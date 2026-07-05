// clipboard_sync_provider.dart
// PC ↔ App 剪贴板同步 — Riverpod 状态管理
//
// 架构：
//   桌面端：监控本机剪贴板变化 → 通过 WebSocket 广播给所有客户端
//   移动端：通过 WebSocket 接收实时推送 → 立即写入系统剪贴板
//   双向：手机剪贴板内容 → WebSocket → 桌面端
//   文件传输：HTTP 上传/下载/列表/删除

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'background_service.dart';
import 'clipboard_sync_service.dart';

const _unset = Object();

@immutable
class ClipboardSyncState {
  /// 桌面端服务是否运行中
  final bool isServerRunning;

  /// 桌面端服务 IP 地址
  final String? serverAddress;

  /// 桌面端服务端口
  final int serverPort;

  /// 本地剪贴板内容（桌面端实时监控）
  final String? localClipboard;

  /// 是否正在加载
  final bool isLoading;

  /// 错误信息
  final String? error;

  /// 已连接的桌面端主机地址
  final String? connectedHost;

  /// 已连接的桌面端端口
  final int connectedPort;

  /// 远程（桌面端）剪贴板内容
  final String? remoteClipboard;

  /// WebSocket 是否已连接
  final bool isWsConnected;

  /// 手机端推送到 PC 的剪贴板内容
  final String? phoneClipboard;

  /// 已传输的文件列表
  final List<FileInfo> transferredFiles;

  /// 上传进度 0.0~1.0
  final double uploadProgress;

  /// 是否正在上传
  final bool isUploading;

  /// 正在下载的文件名
  final String? downloadingFile;

  /// 手机端是否在监控剪贴板
  final bool isMobileMonitoring;

  const ClipboardSyncState({
    this.isServerRunning = false,
    this.serverAddress,
    this.serverPort = ClipboardSyncService.defaultPort,
    this.localClipboard,
    this.isLoading = false,
    this.error,
    this.connectedHost,
    this.connectedPort = ClipboardSyncService.defaultPort,
    this.remoteClipboard,
    this.isWsConnected = false,
    this.phoneClipboard,
    this.transferredFiles = const [],
    this.uploadProgress = 0.0,
    this.isUploading = false,
    this.downloadingFile,
    this.isMobileMonitoring = false,
  });

  ClipboardSyncState copyWith({
    bool? isServerRunning,
    Object? serverAddress = _unset,
    int? serverPort,
    Object? localClipboard = _unset,
    bool? isLoading,
    Object? error = _unset,
    Object? connectedHost = _unset,
    int? connectedPort,
    Object? remoteClipboard = _unset,
    bool? isWsConnected,
    Object? phoneClipboard = _unset,
    List<FileInfo>? transferredFiles,
    double? uploadProgress,
    bool? isUploading,
    Object? downloadingFile = _unset,
    bool? isMobileMonitoring,
  }) {
    return ClipboardSyncState(
      isServerRunning: isServerRunning ?? this.isServerRunning,
      serverAddress: serverAddress == _unset
          ? this.serverAddress
          : serverAddress as String?,
      serverPort: serverPort ?? this.serverPort,
      localClipboard: localClipboard == _unset
          ? this.localClipboard
          : localClipboard as String?,
      isLoading: isLoading ?? this.isLoading,
      error: error == _unset ? this.error : error as String?,
      connectedHost: connectedHost == _unset
          ? this.connectedHost
          : connectedHost as String?,
      connectedPort: connectedPort ?? this.connectedPort,
      remoteClipboard: remoteClipboard == _unset
          ? this.remoteClipboard
          : remoteClipboard as String?,
      isWsConnected: isWsConnected ?? this.isWsConnected,
      phoneClipboard: phoneClipboard == _unset
          ? this.phoneClipboard
          : phoneClipboard as String?,
      transferredFiles: transferredFiles ?? this.transferredFiles,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      isUploading: isUploading ?? this.isUploading,
      downloadingFile: downloadingFile == _unset
          ? this.downloadingFile
          : downloadingFile as String?,
      isMobileMonitoring: isMobileMonitoring ?? this.isMobileMonitoring,
    );
  }
}

class ClipboardSyncNotifier extends StateNotifier<ClipboardSyncState> {
  final ClipboardSyncService _service;
  Timer? _clipboardMonitor;
  Timer? _mobileClipboardMonitor;
  String? _lastPushedClipboard;
  String? _desktopClipboardWriteFromMobile;

  ClipboardSyncNotifier(this._service, {bool autoStartServer = true})
    : super(const ClipboardSyncState()) {
    // 设置手机剪贴板推送回调（桌面端）
    _service.onClipboardFromMobile = _onWsClipboardFromMobile;
    // 文件列表变更回调 → 桌面端自动刷新
    _service.onFileListChanged = () => fetchFileList();

    if (autoStartServer && ClipboardSyncService.isDesktopPlatform) {
      startServer();
    }
  }

  // ════════════════════════════════════════════
  //  桌面端
  // ════════════════════════════════════════════

  Future<void> startServer() async {
    state = state.copyWith(isLoading: true);
    try {
      await _service.startServer();
      state = state.copyWith(
        isServerRunning: true,
        serverAddress: _service.serverAddress,
        serverPort: _service.port,
        isLoading: false,
        error: null,
      );
      _startClipboardMonitor();
      // 获取本地文件列表
      await fetchFileList();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: '启动失败：${e is SocketException ? '端口占用或权限不足 → ' + e.message : e}',
      );
    }
  }

  Future<void> stopServer() async {
    await _service.stopServer();
    _clipboardMonitor?.cancel();
    state = state.copyWith(
      isServerRunning: false,
      serverAddress: null,
      localClipboard: null,
      phoneClipboard: null,
    );
  }

  /// 每秒检查本机剪贴板，有变化时通过 WebSocket 广播给所有客户端
  void _startClipboardMonitor() {
    _readAndBroadcast();
    _clipboardMonitor = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _readAndBroadcast();
    });
  }

  Future<void> _readAndBroadcast() async {
    if (!_service.isServerRunning) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final newText = data?.text ?? '';
      if (newText != (state.localClipboard ?? '')) {
        state = state.copyWith(
          localClipboard: newText.isEmpty ? null : newText,
        );
        if (newText.isNotEmpty && newText == _desktopClipboardWriteFromMobile) {
          _desktopClipboardWriteFromMobile = null;
          return;
        }
        if (newText.isNotEmpty) {
          _service.broadcastClipboard(newText);
        }
      }
    } catch (_) {}
  }

  // ════════════════════════════════════════════
  //  手机剪贴板推送回调（桌面端）
  // ════════════════════════════════════════════

  Future<void> _onWsClipboardFromMobile() async {
    final text = _service.cachedClipboard;
    if (text != null && text.isNotEmpty) {
      _desktopClipboardWriteFromMobile = text;
      state = state.copyWith(phoneClipboard: text, localClipboard: text);
      try {
        await Clipboard.setData(ClipboardData(text: text));
      } catch (_) {}
    }
  }

  /// 清除手机剪贴板展示
  void clearPhoneClipboard() {
    state = state.copyWith(phoneClipboard: null);
  }

  // ════════════════════════════════════════════
  //  移动端
  // ════════════════════════════════════════════

  /// 连接到桌面端 — 通过 WebSocket 接收实时推送
  Future<bool> connectToHost(String host) async {
    final endpoint = _parseEndpoint(host);
    state = state.copyWith(isLoading: true, error: null);

    final pingOk = await _service.ping(endpoint.host, port: endpoint.port);
    if (!pingOk) {
      state = state.copyWith(
        isLoading: false,
        error: '无法连接到 ${endpoint.host}:${endpoint.port}，请确认桌面端已启动服务',
      );
      return false;
    }

    final wsOk = await _service.connectWs(
      endpoint.host,
      port: endpoint.port,
      onClipboard: _onWsClipboardReceived,
      onFileListChanged: () => fetchFileList(),
    );

    final initial = await _service.fetchClipboard(
      endpoint.host,
      port: endpoint.port,
    );
    if (initial != null && initial.isNotEmpty) {
      _applyClipboard(initial);
    }

    state = state.copyWith(
      connectedHost: endpoint.host,
      connectedPort: endpoint.port,
      isWsConnected: wsOk,
      isLoading: false,
    );

    // 获取文件列表
    await fetchFileList();

    // 启动前台服务，保持 WebSocket 在 app 退到后台时不断连
    if (ClipboardSyncService.isMobilePlatform) {
      unawaited(startClipboardSyncService());
    }

    return true;
  }

  void _onWsClipboardReceived() {
    final text = _service.cachedClipboard;
    if (text != null && text.isNotEmpty) {
      _applyClipboard(text);
    }
  }

  void _applyClipboard(String text) {
    if (text == state.remoteClipboard) return;
    state = state.copyWith(remoteClipboard: text);
    Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> refreshClipboard() async {
    if (state.connectedHost == null) return;
    state = state.copyWith(isLoading: true, error: null);
    final text = await _service.fetchClipboard(
      state.connectedHost!,
      port: state.connectedPort,
    );
    if (text != null && text.isNotEmpty) {
      _applyClipboard(text);
    } else if (text == null) {
      state = state.copyWith(
        error: '无法连接到桌面端，请确认桌面端服务正在运行',
        isWsConnected: false,
      );
    }
    state = state.copyWith(isLoading: false);
  }

  void onAppResumed() {
    if (state.connectedHost == null) return;

    // 1. 推送手机当前剪贴板到桌面端（用户可能在后台复制了内容）
    pushClipboardToDesktop();

    // 2. 重连 WebSocket
    final host = state.connectedHost!;
    _service.disconnectWs();
    _service.connectWs(
      host,
      port: state.connectedPort,
      onClipboard: _onWsClipboardReceived,
      onFileListChanged: () => fetchFileList(),
    );

    // 3. 从桌面端拉取最新剪贴板
    refreshClipboard();
    fetchFileList();
  }

  Future<String?> loadLastIp() => _service.loadLastIp();
  Future<void> saveLastIp(String ip) => _service.saveLastIp(ip);

  Future<void> copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {}
  }

  void disconnect() {
    stopMobileClipboardMonitor();
    _service.disconnectWs();
    if (ClipboardSyncService.isMobilePlatform) {
      unawaited(stopClipboardSyncService());
    }
    state = state.copyWith(
      connectedHost: null,
      remoteClipboard: null,
      isWsConnected: false,
      transferredFiles: [],
    );
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  // ════════════════════════════════════════════
  //  QR 连接
  // ════════════════════════════════════════════

  /// 生成 QR 码数据（桌面端）
  String getQrData() {
    final addr = _service.serverAddress;
    if (addr == null) return '';
    return 'clipboardsync://$addr:${_service.port}';
  }

  ({String host, int port}) _parseEndpoint(String input) {
    final value = input.trim();
    try {
      final uri = Uri.parse(value);
      if ((uri.scheme == 'clipboardsync' || uri.scheme == 'http') &&
          uri.host.isNotEmpty) {
        return (
          host: uri.host,
          port: uri.hasPort ? uri.port : ClipboardSyncService.defaultPort,
        );
      }
    } catch (_) {}

    final hostPort = RegExp(r'^([^:]+):(\d{1,5})$').firstMatch(value);
    if (hostPort != null) {
      final parsedPort = int.tryParse(hostPort.group(2)!);
      if (parsedPort != null && parsedPort > 0 && parsedPort <= 65535) {
        return (host: hostPort.group(1)!, port: parsedPort);
      }
    }

    return (host: value, port: ClipboardSyncService.defaultPort);
  }

  // ════════════════════════════════════════════
  //  双向剪贴板
  // ════════════════════════════════════════════

  /// 将手机剪贴板内容推送到桌面端
  Future<void> pushClipboardToDesktop() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.isNotEmpty) {
        _service.sendClipboardToDesktop(text);
        _lastPushedClipboard = text;
        state = state.copyWith(phoneClipboard: text);
      }
    } catch (_) {}
  }

  /// 启动手机剪贴板监控（每 2 秒检查变化并自动推送）
  void startMobileClipboardMonitor() {
    if (_mobileClipboardMonitor != null) return;
    state = state.copyWith(isMobileMonitoring: true);

    _mobileClipboardMonitor = Timer.periodic(const Duration(seconds: 2), (
      _,
    ) async {
      if (state.connectedHost == null) {
        stopMobileClipboardMonitor();
        return;
      }
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text ?? '';
        if (text.isNotEmpty && text != _lastPushedClipboard) {
          _lastPushedClipboard = text;
          _service.sendClipboardToDesktop(text);
          state = state.copyWith(phoneClipboard: text);
        }
      } catch (_) {}
    });
  }

  /// 停止手机剪贴板监控
  void stopMobileClipboardMonitor() {
    _mobileClipboardMonitor?.cancel();
    _mobileClipboardMonitor = null;
    _lastPushedClipboard = null;
    state = state.copyWith(isMobileMonitoring: false);
  }

  /// 切换手机剪贴板监控
  void toggleMobileClipboardMonitor() {
    if (state.isMobileMonitoring) {
      stopMobileClipboardMonitor();
    } else {
      startMobileClipboardMonitor();
    }
  }

  // ════════════════════════════════════════════
  //  文件传输
  // ════════════════════════════════════════════

  /// 解析文件操作的目标主机
  String? _resolveFileHost() {
    if (state.connectedHost != null) return state.connectedHost;
    if (ClipboardSyncService.isDesktopPlatform && _service.isServerRunning) {
      return '127.0.0.1';
    }
    return null;
  }

  int _resolveFilePort() {
    if (state.connectedHost != null) return state.connectedPort;
    return _service.port;
  }

  /// 选择并上传文件
  /// Returns: true=成功, false=失败, null=用户取消
  Future<bool?> pickAndUploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return null;

      final filePath = result.files.single.path;
      if (filePath == null) return false;

      state = state.copyWith(isUploading: true, uploadProgress: 0.0);

      bool ok;
      if (ClipboardSyncService.isDesktopPlatform) {
        // 桌面端：直接复制到本地剪贴板目录（无需 HTTP 服务）
        ok = await _service.uploadFileDirect(filePath);
        if (!ok) {
          state = state.copyWith(
            isUploading: false,
            error:
                '上传失败${_service.lastUploadError != null ? '：${_service.lastUploadError}' : '，请检查文件权限'}',
          );
          return false;
        }
      } else {
        // 移动端：通过 HTTP 上传
        final host = _resolveFileHost();
        if (host == null) {
          state = state.copyWith(isUploading: false);
          return false as bool?;
        }
        final file = File(filePath);
        ok = await _service.uploadFile(file, host, port: _resolveFilePort());
        if (!ok) {
          state = state.copyWith(
            isUploading: false,
            error:
                '上传失败${_service.lastUploadError != null ? '：${_service.lastUploadError}' : '，请检查网络连接'}',
          );
          return false;
        }
      }

      state = state.copyWith(isUploading: false, uploadProgress: 1.0);

      if (ok) {
        await fetchFileList();
      }

      return ok;
    } catch (e) {
      state = state.copyWith(
        isUploading: false,
        uploadProgress: 0.0,
        error: '上传异常：$e',
      );
      return false as bool?;
    }
  }

  /// 获取文件列表
  Future<bool> fetchFileList() async {
    List<FileInfo> files;
    if (ClipboardSyncService.isDesktopPlatform) {
      files = await _service.fetchFileListDirect();
    } else {
      final host = _resolveFileHost();
      if (host == null) {
        state = state.copyWith(transferredFiles: []);
        return false;
      }
      files = await _service.fetchFileList(host, port: _resolveFilePort());
      if (_service.lastFileListError != null) {
        state = state.copyWith(error: '刷新文件列表失败：${_service.lastFileListError}');
        return false;
      }
    }
    state = state.copyWith(transferredFiles: files, error: null);
    return true;
  }

  /// 下载文件到手机
  Future<String?> downloadFile(String name) async {
    state = state.copyWith(downloadingFile: name);

    try {
      String? path;
      if (ClipboardSyncService.isDesktopPlatform) {
        // 桌面端：直接复制本地文件（不走 HTTP）
        path = await _service.downloadFileDirect(name);
      } else {
        // 移动端：通过 HTTP 下载
        final host = _resolveFileHost();
        if (host == null) {
          state = state.copyWith(error: '下载失败：未连接到桌面端');
          return null;
        }
        path = await _service.downloadFile(
          name,
          host,
          port: _resolveFilePort(),
        );
      }

      if (path == null) {
        state = state.copyWith(
          error:
              '下载失败${_service.lastDownloadError != null ? '：${_service.lastDownloadError}' : '，请检查连接'}',
        );
        return null;
      }

      try {
        await OpenFilex.open(path);
      } catch (_) {}
      state = state.copyWith(error: null);
      return path;
    } finally {
      state = state.copyWith(downloadingFile: null);
    }
  }

  /// 删除文件
  Future<bool> deleteFile(String name) async {
    bool ok;
    if (ClipboardSyncService.isDesktopPlatform) {
      ok = await _service.deleteFileDirect(name);
    } else {
      final host = _resolveFileHost();
      if (host == null) return false;
      ok = await _service.deleteFile(name, host, port: _resolveFilePort());
    }
    if (ok) {
      await fetchFileList();
    }
    return ok;
  }

  @override
  void dispose() {
    _clipboardMonitor?.cancel();
    _mobileClipboardMonitor?.cancel();
    _service.dispose();
    super.dispose();
  }
}

final clipboardSyncProvider =
    StateNotifierProvider<ClipboardSyncNotifier, ClipboardSyncState>((ref) {
      final service = ClipboardSyncService();
      return ClipboardSyncNotifier(service);
    });
