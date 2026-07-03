// clipboard_sync_service.dart
// PC ↔ App 剪贴板同步 + 文件传输服务
//
// 架构：
//   桌面端：HTTP + WebSocket 服务，提供剪贴板、文件上传/下载/列表
//   移动端：通过 WebSocket 接收实时推送，HTTP 上传/下载文件
//
// HTTP 端点:
//   GET  /ping          — 健康检查
//   GET  /clipboard     — 获取系统剪贴板内容
//   GET  /ws            — WebSocket 升级（实时推送）
//   POST /upload        — 上传文件
//   GET  /files         — 列出已上传文件
//   GET  /files/{name}  — 下载文件
//   DELETE /files/{name}— 删除文件

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../screen_mirror/mirror_service.dart';

/// 已传输文件的信息
class FileInfo {
  final String name;
  final int size;
  final DateTime modified;

  const FileInfo({
    required this.name,
    required this.size,
    required this.modified,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'size': size,
        'modified': modified.millisecondsSinceEpoch,
      };

  factory FileInfo.fromJson(Map<String, dynamic> json) => FileInfo(
        name: json['name'] as String,
        size: json['size'] as int,
        modified:
            DateTime.fromMillisecondsSinceEpoch(json['modified'] as int),
      );
}

class ClipboardSyncService {
  static const int defaultPort = 9876;

  HttpServer? _server;
  String? _serverAddress;
  String? _cachedClipboard;

  // WebSocket 客户端集合（桌面端）
  final Set<WebSocket> _wsClients = {};

  // WebSocket 连接（移动端）
  WebSocket? _ws;
  bool _wsConnected = false;
  bool _explicitDisconnect = false;
  VoidCallback? _onWsClipboard;
  VoidCallback? _onWsClipboardFromMobile;
  VoidCallback? _onWsFileListChanged;
  Timer? _wsReconnectTimer;

  // 文件存储
  Directory? _filesDir;

  /// 屏幕镜像服务（桌面端：转发手机相机帧到浏览器 viewer）
  late final MirrorService mirrorService = MirrorService();

  bool get isServerRunning => _server != null;
  String? get serverAddress => _serverAddress;
  int _actualPort = defaultPort;
  int get port => _actualPort;
  String? get cachedClipboard => _cachedClipboard;
  bool get wsConnected => _wsConnected;

  /// 手机剪贴板内容推送到桌面端后的回调
  VoidCallback? get onClipboardFromMobile => _onWsClipboardFromMobile;
  set onClipboardFromMobile(VoidCallback? cb) => _onWsClipboardFromMobile = cb;

  /// 文件列表变更回调（桌面端：手机上传后触发刷新）
  VoidCallback? onFileListChanged;

  // ═══════════════════════════════════════════════════════════
  //  平台判断
  // ═══════════════════════════════════════════════════════════

  static bool get isDesktopPlatform {
    try {
      return defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux;
    } catch (_) {
      return false;
    }
  }

  static bool get isMobilePlatform {
    try {
      return defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  桌面端：HTTP + WebSocket 服务
  // ═══════════════════════════════════════════════════════════

  Future<void> startServer({int? port}) async {
    if (_server != null) return;

    final tryPort = port ?? defaultPort;
    SocketException? lastError;

    // 尝试 3 个端口，避免端口被占用导致启动失败
    for (int offset = 0; offset < 3; offset++) {
      final candidatePort = tryPort + offset;
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, candidatePort);
        _actualPort = candidatePort;
        _serverAddress = await _getLocalIp();
        _filesDir = await _getFilesDir();
        _server!.listen(_handleRequest);
        return;
      } on SocketException catch (e) {
        lastError = e;
        _server = null;
        // 端口被占用 → 尝试下一个
        if (e.osError?.errorCode == 48 || e.osError?.errorCode == 98) {
          continue;
        }
        // 权限问题 → 不再重试
        break;
      }
    }

    // 所有尝试都失败
    String detail = lastError?.message ?? '未知错误';
    if (lastError?.osError != null) {
      detail += ' (OS Error ${lastError!.osError!.errorCode}: ${lastError.osError!.message})';
    }
    throw SocketException('Failed to create server socket: $detail');
  }

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address.isNotEmpty) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  /// 获取文件存储目录
  Future<Directory> _getFilesDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final filesDir = Directory('${dir.path}/clipboard_files');
    if (!await filesDir.exists()) {
      await filesDir.create(recursive: true);
    }
    return filesDir;
  }

  // ── 请求路由 ──

  void _handleRequest(HttpRequest request) {
    final path = request.uri.path;
    final method = request.method;
    final isUpgrade =
        request.headers.value('upgrade')?.toLowerCase() == 'websocket';

    // WebSocket 升级 — 镜像投屏流
    if (path == '/ws/mirror' && isUpgrade) {
      mirrorService.handleMirrorConnection(request);
      return;
    }

    // WebSocket 升级 — 剪贴板推送
    if (path == '/ws' && isUpgrade) {
      _handleWebSocketUpgrade(request);
      return;
    }

    // REST 路由
    if (method == 'GET' && path == '/mirror-viewer') {
      _serveMirrorViewer(request);
    } else if (method == 'GET' && path == '/clipboard') {
      _handleClipboardRequest(request);
    } else if (method == 'GET' && path == '/ping') {
      _writeJson(request.response, 200, {'status': 'ok'});
    } else if (method == 'POST' && path == '/upload') {
      _handleFileUpload(request);
    } else if (method == 'GET' && path == '/files') {
      _handleFileList(request);
    } else if (method == 'GET' && path.startsWith('/files/')) {
      _handleFileDownload(request, path.substring(7));
    } else if (method == 'DELETE' && path.startsWith('/files/')) {
      _handleFileDelete(request, path.substring(7));
    } else {
      request.response.statusCode = 404;
      request.response.write('Not found');
      request.response.close();
    }
  }

  /// 提供投屏查看器 HTML 页面
  void _serveMirrorViewer(HttpRequest request) {
    final html = MirrorService.viewerHtml;
    request.response.statusCode = 200;
    request.response.headers.set('Content-Type', 'text/html; charset=utf-8');
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.write(html);
    request.response.close();
  }

  // ── 辅助：写 JSON 响应 ──

  void _writeJson(HttpResponse response, int status, dynamic data,
      {bool close = true}) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.write(jsonEncode(data));
    if (close) response.close();
  }

  // ── GET /clipboard ──

  Future<void> _handleClipboardRequest(HttpRequest request) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      _cachedClipboard = text;
      _writeJson(request.response, 200, {
        'text': text,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      _writeJson(request.response, 500, {'error': e.toString()});
    }
  }

  // ── WebSocket ──

  Future<void> _handleWebSocketUpgrade(HttpRequest request) async {
    try {
      final ws = await WebSocketTransformer.upgrade(request);
      _wsClients.add(ws);

      // 新连接时推送当前剪贴板
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text ?? '';
        if (text.isNotEmpty) {
          _cachedClipboard = text;
          ws.add(_buildWsMessage('clipboard', text));
        }
      } catch (_) {}

      ws.done.then((_) => _wsClients.remove(ws));
      ws.listen(
        (data) {
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            final type = json['type'] as String?;
            if (type == 'clipboard_from_mobile') {
              final text = json['text'] as String? ?? '';
              if (text.isNotEmpty) {
                _cachedClipboard = text;
                _onWsClipboardFromMobile?.call();
              }
            }
          } catch (_) {}
        },
        onError: (_) => _wsClients.remove(ws),
      );
    } catch (_) {}
  }

  /// 向所有 WebSocket 客户端广播消息
  void broadcastClipboard(String text) {
    _cachedClipboard = text;
    final message = _buildWsMessage('clipboard', text);
    for (final client in _wsClients.toList()) {
      try {
        client.add(message);
      } catch (_) {
        _wsClients.remove(client);
      }
    }
  }

  String _buildWsMessage(String type, String text) {
    return jsonEncode({
      'type': type,
      'text': text,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> stopServer() async {
    for (final client in _wsClients.toList()) {
      try {
        client.close();
      } catch (_) {}
    }
    _wsClients.clear();
    await _server?.close(force: true);
    _server = null;
  }

  // ═══════════════════════════════════════════════════════════
  //  桌面端：文件处理
  // ═══════════════════════════════════════════════════════════

  /// POST /upload — 接收文件上传（multipart/form-data）
  ///
  /// 手动解析 multipart（不使用已移除的 MimeMultipartTransformer）
  Future<void> _handleFileUpload(HttpRequest request) async {
    try {
      final contentType = request.headers.contentType;
      if (contentType == null ||
          contentType.mimeType != 'multipart/form-data' ||
          !contentType.parameters.containsKey('boundary')) {
        _writeJson(request.response, 400, {'error': 'Expected multipart/form-data'});
        return;
      }

      final boundary = contentType.parameters['boundary']!;
      final boundaryBytes = utf8.encode('--$boundary');
      final body = await request.fold<List<int>>(
        <int>[],
        (prev, chunk) => prev..addAll(chunk),
      );

      String? savedName;
      int searchStart = 0;

      while (searchStart < body.length) {
        // 查找 boundary
        final boundaryIndex = _indexOfBytes(body, boundaryBytes, searchStart);
        if (boundaryIndex == -1) break;

        // 检查是否是结束 boundary（--boundary--）
        if (body.length > boundaryIndex + boundaryBytes.length + 1 &&
            body[boundaryIndex + boundaryBytes.length] == 45 && // '-'
            body[boundaryIndex + boundaryBytes.length + 1] == 45) {
          break; // 到达结束标记
        }

        // 跳过 boundary 行末尾的 \r\n
        int pos = boundaryIndex + boundaryBytes.length;
        if (pos < body.length && body[pos] == 13) pos++; // \r
        if (pos < body.length && body[pos] == 10) pos++; // \n

        // 解析头部（直到空行 \r\n\r\n）
        final headersEnd = _indexOfBytes(body, utf8.encode('\r\n\r\n'), pos);
        if (headersEnd == -1) break;

        final headerSection = utf8.decode(body.sublist(pos, headersEnd));
        pos = headersEnd + 4; // 跳过 \r\n\r\n

        // 提取文件名
        final fileNameMatch =
            RegExp(r'filename="?(.*?)"?(\r?\n|")')
                .firstMatch(headerSection);
        final originalName = fileNameMatch?.group(1) ?? 'unnamed';

        // 查找下一个 boundary
        final nextBoundary = _indexOfBytes(body, boundaryBytes, pos);
        if (nextBoundary == -1) break;

        // 提取文件数据（去掉末尾的 \r\n）
        int bodyEnd = nextBoundary;
        if (bodyEnd >= 2 && body[bodyEnd - 2] == 13 && body[bodyEnd - 1] == 10) {
          bodyEnd -= 2;
        }

        final fileData = body.sublist(pos, bodyEnd);

        // 重名处理：添加时间戳
        final dir = _filesDir ?? await _getFilesDir();
        final dotIndex = originalName.lastIndexOf('.');
        final nameBody = dotIndex > 0 ? originalName.substring(0, dotIndex) : originalName;
        final ext = dotIndex > 0 ? originalName.substring(dotIndex) : '';
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        savedName = '${nameBody}_$timestamp$ext';
        final saveFile = File('${dir.path}/$savedName');
        await saveFile.writeAsBytes(fileData);

        searchStart = nextBoundary;
      }

      if (savedName != null) {
        _writeJson(request.response, 200, {
          'status': 'ok',
          'filename': savedName,
        });
        // 通知所有 WebSocket 客户端刷新文件列表
        _broadcastFileListChanged();
      } else {
        _writeJson(request.response, 400, {'error': 'No file received'});
      }
    } catch (e) {
      _writeJson(request.response, 500, {'error': e.toString()});
    }
  }

  /// 广播文件列表变更通知给所有 WebSocket 客户端，并通知桌面端 UI
  void _broadcastFileListChanged() {
    final msg = jsonEncode({'type': 'file_list_changed'});
    for (final client in _wsClients) {
      try {
        client.add(msg);
      } catch (_) {}
    }
    // 桌面端直接回调刷新
    onFileListChanged?.call();
  }

  /// 在字节数组中查找子数组位置（替代已移除的 MimeMultipartTransformer）
  int _indexOfBytes(List<int> haystack, List<int> needle, int start) {
    if (needle.isEmpty) return start;
    for (int i = start; i <= haystack.length - needle.length; i++) {
      bool found = true;
      for (int j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          found = false;
          break;
        }
      }
      if (found) return i;
    }
    return -1;
  }

  /// 获取本地文件列表（HTTP / 直接调用共用）
  Future<List<FileInfo>> _listLocalFiles() async {
    final dir = _filesDir ?? await _getFilesDir();
    final entities = await dir.list().toList();
    final files = <FileInfo>[];

    for (final entity in entities) {
      if (entity is File) {
        final stat = await entity.stat();
        files.add(FileInfo(
          name: entity.uri.pathSegments.last,
          size: stat.size,
          modified: stat.modified,
        ));
      }
    }

    // 按修改时间倒序
    files.sort((a, b) => b.modified.compareTo(a.modified));
    return files;
  }

  /// GET /files — 列出已上传文件（HTTP）
  Future<void> _handleFileList(HttpRequest request) async {
    try {
      final files = await _listLocalFiles();
      _writeJson(request.response, 200, {
        'files': files.map((f) => f.toJson()).toList(),
      });
    } catch (e) {
      _writeJson(request.response, 500, {'error': e.toString()});
    }
  }

  /// 桌面端：直接返回本地文件列表（不走 HTTP）
  Future<List<FileInfo>> fetchFileListDirect() async {
    try {
      return await _listLocalFiles();
    } catch (_) {
      return [];
    }
  }

  /// GET /files/{name} — 下载文件
  Future<void> _handleFileDownload(HttpRequest request, String name) async {
    try {
      final dir = _filesDir ?? await _getFilesDir();
      final file = File('${dir.path}/$name');

      if (!await file.exists()) {
        _writeJson(request.response, 404, {'error': 'File not found'});
        return;
      }

      final stat = await file.stat();
      request.response.statusCode = 200;
      request.response.headers.set('Content-Type', 'application/octet-stream');
      request.response.headers.set(
        'Content-Disposition',
        'attachment; filename="$name"',
      );
      request.response.headers.set('Content-Length', stat.size.toString());
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      await request.response.addStream(file.openRead());
      await request.response.close();
    } catch (e) {
      try {
        _writeJson(request.response, 500, {'error': e.toString()});
      } catch (_) {}
    }
  }

  /// DELETE /files/{name} — 删除文件
  Future<void> _handleFileDelete(HttpRequest request, String name) async {
    try {
      final dir = _filesDir ?? await _getFilesDir();
      final file = File('${dir.path}/$name');

      if (!await file.exists()) {
        _writeJson(request.response, 404, {'error': 'File not found'});
        return;
      }

      await file.delete();
      _writeJson(request.response, 200, {'status': 'deleted'});
    } catch (e) {
      _writeJson(request.response, 500, {'error': e.toString()});
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  移动端：WebSocket 客户端
  // ═══════════════════════════════════════════════════════════

  Future<bool> connectWs(String host,
      {int port = defaultPort, VoidCallback? onClipboard,
      VoidCallback? onFileListChanged}) async {
    _explicitDisconnect = false;
    _onWsClipboard = onClipboard;
    _onWsFileListChanged = onFileListChanged;

    try {
      _ws = await WebSocket.connect('ws://$host:$port/ws');
      _wsConnected = true;

      _ws!.listen(
        (data) {
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            final type = json['type'] as String?;
            final text = json['text'] as String? ?? '';
            if (type == 'clipboard' && text.isNotEmpty) {
              _cachedClipboard = text;
              _onWsClipboard?.call();
            } else if (type == 'file_list_changed') {
              _onWsFileListChanged?.call();
            }
          } catch (_) {}
        },
        onDone: () {
          _wsConnected = false;
          _scheduleWsReconnect(host, port);
        },
        onError: (_) {
          _wsConnected = false;
          _scheduleWsReconnect(host, port);
        },
      );
      return true;
    } catch (_) {
      _wsConnected = false;
      _scheduleWsReconnect(host, port);
      return false;
    }
  }

  void _scheduleWsReconnect(String host, int port) {
    if (_explicitDisconnect) return;
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = Timer(const Duration(seconds: 5), () {
      connectWs(host, port: port,
        onClipboard: _onWsClipboard,
        onFileListChanged: _onWsFileListChanged);
    });
  }

  /// 移动端：通过 WebSocket 推送剪贴板内容到桌面端
  void sendClipboardToDesktop(String text) {
    try {
      _ws?.add(_buildWsMessage('clipboard_from_mobile', text));
    } catch (_) {}
  }

  /// 断开 WebSocket 连接
  void disconnectWs() {
    _explicitDisconnect = true;
    _wsReconnectTimer?.cancel();
    _ws?.close();
    _ws = null;
    _wsConnected = false;
  }

  // ═══════════════════════════════════════════════════════════
  //  HTTP 客户端
  // ═══════════════════════════════════════════════════════════

  Future<String?> fetchClipboard(String host, {int port = defaultPort}) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(
        Uri.parse('http://$host:$port/clipboard'),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode != 200) return null;
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['text'] as String?;
    } catch (e) {
      return null;
    }
  }

  Future<bool> ping(String host, {int port = defaultPort}) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      final request = await client.getUrl(
        Uri.parse('http://$host:$port/ping'),
      );
      final response = await request.close();
      client.close();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// HTTP GET /files — 获取文件列表
  Future<List<FileInfo>> fetchFileList(String host,
      {int port = defaultPort}) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(
        Uri.parse('http://$host:$port/files'),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode != 200) return [];
      final json = jsonDecode(body) as Map<String, dynamic>;
      final filesJson = json['files'] as List<dynamic>;
      return filesJson
          .map((f) => FileInfo.fromJson(f as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 上传文件到桌面端
  Future<bool> uploadFile(File file, String host,
      {int port = defaultPort}) async {
    final client = HttpClient();
    final boundary = 'boundary-${DateTime.now().millisecondsSinceEpoch}';

    try {
      final uri = Uri.parse('http://$host:$port/upload');
      final request = await client.postUrl(uri);
      request.headers.set(
        'Content-Type',
        'multipart/form-data; boundary=$boundary',
      );

      final fileName = file.path.split('/').last;
      final header = utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="$fileName"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n',
      );
      final footer = utf8.encode('\r\n--$boundary--\r\n');

      final bytes = await file.readAsBytes();
      request.contentLength = header.length + bytes.length + footer.length;

      request.add(header);
      request.add(bytes);
      request.add(footer);

      final response = await request.close();
      await response.drain();
      client.close();
      return response.statusCode == 200;
    } catch (e) {
      client.close();
      return false;
    }
  }

  /// 下载文件到本地
  Future<String?> downloadFile(String name, String host,
      {int port = defaultPort}) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      final encodedName = Uri.encodeComponent(name);
      final request = await client.getUrl(
        Uri.parse('http://$host:$port/files/$encodedName'),
      );
      final response = await request.close();

      if (response.statusCode != 200) {
        client.close();
        return null;
      }

      final dir = await getApplicationDocumentsDirectory();
      final saveFile = File('${dir.path}/$name');
      await response
          .pipe(saveFile.openWrite())
          .timeout(const Duration(seconds: 120));
      client.close();
      return saveFile.path;
    } catch (e) {
      return null;
    }
  }

  /// 桌面端：直接从本地目录复制文件（不走 HTTP，避免自连接问题）
  Future<String?> downloadFileDirect(String name) async {
    try {
      final dir = _filesDir ?? await _getFilesDir();
      final sourceFile = File('${dir.path}/$name');
      if (!await sourceFile.exists()) return null;

      final downloadDir = await getApplicationDocumentsDirectory();
      String destPath = '${downloadDir.path}/$name';

      // 如果目标文件已存在，添加时间戳避免覆盖
      if (await File(destPath).exists()) {
        final dotIndex = name.lastIndexOf('.');
        final nameBody = dotIndex > 0 ? name.substring(0, dotIndex) : name;
        final ext = dotIndex > 0 ? name.substring(dotIndex) : '';
        final ts = DateTime.now().millisecondsSinceEpoch;
        destPath = '${downloadDir.path}/${nameBody}_$ts$ext';
      }

      await sourceFile.copy(destPath);
      return destPath;
    } catch (_) {
      return null;
    }
  }

  /// 上次上传错误信息（供 UI 展示）
  String? lastUploadError;

  /// 桌面端：直接复制文件到剪贴板目录（不走 HTTP，避免自连接问题）
  Future<bool> uploadFileDirect(String filePath) async {
    lastUploadError = null;
    try {
      final sourceFile = File(filePath);
      if (!await sourceFile.exists()) {
        lastUploadError = '文件不存在';
        return false;
      }

      final dir = _filesDir ?? await _getFilesDir();
      final name = p.basename(filePath);
      if (name.isEmpty) {
        lastUploadError = '无法解析文件名';
        return false;
      }

      // 重名处理：添加时间戳
      final dotIndex = name.lastIndexOf('.');
      final nameBody = dotIndex > 0 ? name.substring(0, dotIndex) : name;
      final ext = dotIndex > 0 ? name.substring(dotIndex) : '';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final savedName = '${nameBody}_$timestamp$ext';

      await sourceFile.copy('${dir.path}/$savedName');
      _broadcastFileListChanged();
      return true;
    } catch (e) {
      lastUploadError = e.toString();
      return false;
    }
  }

  /// 桌面端：直接删除本地文件（不走 HTTP）
  Future<bool> deleteFileDirect(String name) async {
    try {
      final dir = _filesDir ?? await _getFilesDir();
      final file = File('${dir.path}/$name');
      if (!await file.exists()) return false;
      await file.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 删除桌面端文件（HTTP）
  Future<bool> deleteFile(String name, String host,
      {int port = defaultPort}) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final encodedName = Uri.encodeComponent(name);
      final request = await client.deleteUrl(
        Uri.parse('http://$host:$port/files/$encodedName'),
      );
      final response = await request.close();
      await response.drain();
      client.close();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  IP 地址持久化
  // ═══════════════════════════════════════════════════════════

  Future<File> get _ipFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/clipboard_last_ip.txt');
  }

  Future<void> saveLastIp(String ip) async {
    try {
      final file = await _ipFile;
      await file.writeAsString(ip);
    } catch (_) {}
  }

  Future<String?> loadLastIp() async {
    try {
      final file = await _ipFile;
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    disconnectWs();
    stopServer();
    _wsReconnectTimer?.cancel();
    mirrorService.dispose();
  }
}
