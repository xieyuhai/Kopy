// mirror_service.dart
// 屏幕投屏 — 相机帧捕获 & WebSocket 流媒体服务
//
// 架构：
//   手机端：Camera → 定时 capture JPEG → WebSocket 发往桌面端
//   桌面端：/ws/mirror 接收帧 → 广播给所有 viewer → 浏览器 HTML 页面渲染
//
// WebSocket 协议：
//   handshake: {"type":"handshake","role":"producer"|"viewer"}
//   生产者: 发送二进制消息（JPEG 帧）
//   消费者: 接收二进制消息（JPEG 帧）
//   服务端: 定期发送 {"type":"stats","fps":N,"viewers":N}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 平台判断（复用 ClipboardSyncService 逻辑）
bool get isDesktopPlatform {
  try {
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  } catch (_) {
    return false;
  }
}

bool get isMobilePlatform {
  try {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  } catch (_) {
    return false;
  }
}

/// 屏幕投屏状态
class ScreenMirrorState {
  /// 是否正在推流
  final bool isStreaming;

  /// 是否已连接到桌面端
  final bool isConnected;

  /// 目标主机地址
  final String? connectedHost;

  /// 连接端口
  final int port;

  /// 错误信息
  final String? error;

  /// 当前帧率
  final int currentFps;

  /// 目标帧率
  final int targetFps;

  /// 已传输帧数
  final int totalFrames;

  /// 已传输数据量（字节）
  final int totalBytes;

  /// 观看者数量（桌面端显示）
  final int viewerCount;

  /// 是否正在加载（相机初始化等）
  final bool isLoading;

  /// 相机是否就绪
  final bool cameraReady;

  /// 选的的分辨率预设
  final String resolutionLabel;

  const ScreenMirrorState({
    this.isStreaming = false,
    this.isConnected = false,
    this.connectedHost,
    this.port = 9876,
    this.error,
    this.currentFps = 0,
    this.targetFps = 15,
    this.totalFrames = 0,
    this.totalBytes = 0,
    this.viewerCount = 0,
    this.isLoading = false,
    this.cameraReady = false,
    this.resolutionLabel = '中等',
  });

  ScreenMirrorState copyWith({
    bool? isStreaming,
    bool? isConnected,
    String? connectedHost,
    int? port,
    String? error,
    int? currentFps,
    int? targetFps,
    int? totalFrames,
    int? totalBytes,
    int? viewerCount,
    bool? isLoading,
    bool? cameraReady,
    String? resolutionLabel,
  }) {
    return ScreenMirrorState(
      isStreaming: isStreaming ?? this.isStreaming,
      isConnected: isConnected ?? this.isConnected,
      connectedHost: connectedHost ?? this.connectedHost,
      port: port ?? this.port,
      error: error ?? this.error,
      currentFps: currentFps ?? this.currentFps,
      targetFps: targetFps ?? this.targetFps,
      totalFrames: totalFrames ?? this.totalFrames,
      totalBytes: totalBytes ?? this.totalBytes,
      viewerCount: viewerCount ?? this.viewerCount,
      isLoading: isLoading ?? this.isLoading,
      cameraReady: cameraReady ?? this.cameraReady,
      resolutionLabel: resolutionLabel ?? this.resolutionLabel,
    );
  }

  /// 已传输数据量的可读格式
  String get totalSizeStr {
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 屏幕投屏服务
///
/// 手机端：初始化相机 → 定时 capture JPEG → WebSocket 发送到桌面端
/// 桌面端：接收帧 → 广播给所有浏览器 viewer
class MirrorService {
  static const int defaultPort = 9876;

  // ── WebSocket（手机端） ──
  WebSocket? _ws;
  bool _wsConnected = false;
  Timer? _reconnectTimer;

  // ── 帧捕获定时器 ──
  Timer? _captureTimer;

  // ── 统计 ──
  int _frameCount = 0;
  int _streamBytes = 0;
  int _lastFpsTime = 0;
  int _lastFpsCount = 0;

  // ── 桌面端：生产者 / 消费者集合 ──
  final Set<WebSocket> _mirrorProducers = {};
  final Set<WebSocket> _mirrorViewers = {};

  // ── 回调 ──
  VoidCallback? onStateChanged;

  // ── 状态 ──
  ScreenMirrorState _state = const ScreenMirrorState();
  ScreenMirrorState get state => _state;

  void updateState(ScreenMirrorState newState) {
    _state = newState;
    onStateChanged?.call();
  }

  // ═══════════════════════════════════════════════════════════
  //  桌面端：WebSocket 镜像端点
  // ═══════════════════════════════════════════════════════════

  /// 处理 /ws/mirror WebSocket 升级请求
  Future<void> handleMirrorConnection(HttpRequest request) async {
    try {
      final ws = await WebSocketTransformer.upgrade(request);
      bool? isProducer;
      String? role;

      // 等待 handshake 消息
      ws.listen(
        (data) {
          // 处理 JSON 控制消息
          if (data is String) {
            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              final type = json['type'] as String?;

              if (type == 'handshake') {
                role = json['role'] as String?;
                if (role == 'producer') {
                  isProducer = true;
                  _mirrorProducers.add(ws);
                  ws.add(jsonEncode({
                    'type': 'handshake_ack',
                    'role': 'producer',
                  }));
                  _broadcastStats();
                } else if (role == 'viewer') {
                  isProducer = false;
                  _mirrorViewers.add(ws);
                  ws.add(jsonEncode({
                    'type': 'handshake_ack',
                    'role': 'viewer',
                    'viewers': _mirrorViewers.length,
                  }));
                  _broadcastStats();
                }
                return;
              }

              // 统计信息
              if (type == 'stats_req') {
                ws.add(jsonEncode({
                  'type': 'stats',
                  'viewers': _mirrorViewers.length,
                  'producers': _mirrorProducers.length,
                }));
                return;
              }
            } catch (_) {}
            return;
          }

          // 二进制数据 = JPEG 帧，仅接受来自 producer 的数据
          if (isProducer == true && data is List<int>) {
            _broadcastFrame(data);
          }
        },
        onDone: () {
          _mirrorProducers.remove(ws);
          _mirrorViewers.remove(ws);
          _broadcastStats();
        },
        onError: (_) {
          _mirrorProducers.remove(ws);
          _mirrorViewers.remove(ws);
          _broadcastStats();
        },
      );
    } catch (_) {}
  }

  /// 向所有 viewer 广播 JPEG 帧
  void _broadcastFrame(List<int> frame) {
    for (final viewer in _mirrorViewers.toList()) {
      try {
        viewer.add(frame);
      } catch (_) {
        _mirrorViewers.remove(viewer);
      }
    }
  }

  /// 广播统计信息给所有 producer 和 viewer
  void _broadcastStats() {
    final stats = jsonEncode({
      'type': 'stats',
      'viewers': _mirrorViewers.length,
      'producers': _mirrorProducers.length,
    });

    for (final p in _mirrorProducers.toList()) {
      try { p.add(stats); } catch (_) { _mirrorProducers.remove(p); }
    }
    for (final v in _mirrorViewers.toList()) {
      try { v.add(stats); } catch (_) { _mirrorViewers.remove(v); }
    }
  }

  /// 桌面端：获取连接统计
  Map<String, int> getMirrorStats() {
    return {
      'producers': _mirrorProducers.length,
      'viewers': _mirrorViewers.length,
    };
  }

  // ═══════════════════════════════════════════════════════════
  //  移动端：相机推流
  // ═══════════════════════════════════════════════════════════

  /// 连接到桌面端并启动推流
  ///
  /// 注意：调用此方法前需要先初始化 CameraController 并准备好帧数据
  /// 这里只处理 WebSocket 连接，相机帧由外部传入
  Future<bool> connectToHost(String host, {int port = defaultPort}) async {
    updateState(_state.copyWith(
      isLoading: true,
      error: null,
      connectedHost: host,
      port: port,
    ));

    try {
      _ws = await WebSocket.connect('ws://$host:$port/ws/mirror');

      // 发送 handshake
      _ws!.add(jsonEncode({
        'type': 'handshake',
        'role': 'producer',
      }));

      final completer = Completer<bool>();

      _ws!.listen(
        (data) {
          if (data is String) {
            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              final type = json['type'] as String?;

              if (type == 'handshake_ack') {
                _wsConnected = true;
                updateState(_state.copyWith(
                  isConnected: true,
                  isLoading: false,
                ));
                if (!completer.isCompleted) completer.complete(true);
              } else if (type == 'stats') {
                final viewers = json['viewers'] as int? ?? 0;
                updateState(_state.copyWith(viewerCount: viewers));
              }
            } catch (_) {}
          }
        },
        onDone: () {
          _wsConnected = false;
          updateState(_state.copyWith(
            isConnected: false,
            isStreaming: false,
          ));
          if (!completer.isCompleted) completer.complete(false);
          _scheduleReconnect(host, port);
        },
        onError: (_) {
          _wsConnected = false;
          updateState(_state.copyWith(
            isConnected: false,
            isStreaming: false,
          ));
          if (!completer.isCompleted) completer.complete(false);
          _scheduleReconnect(host, port);
        },
      );

      // 超时处理
      Future.delayed(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          completer.complete(false);
          updateState(_state.copyWith(
            isLoading: false,
            error: '连接超时',
          ));
          disconnect();
        }
      });

      return await completer.future;
    } catch (e) {
      updateState(_state.copyWith(
        isLoading: false,
        error: '连接失败：$e',
      ));
      return false;
    }
  }

  void _scheduleReconnect(String host, int port) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_wsConnected) {
        connectToHost(host, port: port);
      }
    });
  }

  /// 发送一帧 JPEG 数据
  void sendFrame(List<int> jpegData) {
    if (!_wsConnected || _ws == null) return;
    try {
      _ws!.add(jpegData);
      _frameCount++;
      _streamBytes += jpegData.length;

      // 计算 FPS
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_lastFpsTime == 0) {
        _lastFpsTime = now;
        _lastFpsCount = _frameCount;
      } else if (now - _lastFpsTime >= 1000) {
        final fps = _frameCount - _lastFpsCount;
        _lastFpsCount = _frameCount;
        _lastFpsTime = now;
        updateState(_state.copyWith(
          currentFps: fps,
          totalFrames: _frameCount,
          totalBytes: _streamBytes,
        ));
      }
    } catch (_) {}
  }

  // ── 帧定时捕获（用于非 camera 包的回退方案） ──

  /// 开始定时捕获（由外部提供捕获函数）
  void startPeriodicCapture(Future<List<int>?> Function() captureFn) {
    if (_captureTimer != null) return;

    _frameCount = 0;
    _streamBytes = 0;
    _lastFpsTime = DateTime.now().millisecondsSinceEpoch;
    _lastFpsCount = 0;

    updateState(_state.copyWith(
      isStreaming: true,
      totalFrames: 0,
      currentFps: 0,
    ));

    final interval = (1000 / _state.targetFps).round();
    _captureTimer = Timer.periodic(Duration(milliseconds: interval), (_) async {
      if (!_state.isStreaming) return;
      try {
        final jpeg = await captureFn();
        if (jpeg != null && jpeg.isNotEmpty) {
          sendFrame(jpeg);
        }
      } catch (_) {}
    });
  }

  void stopPeriodicCapture() {
    _captureTimer?.cancel();
    _captureTimer = null;
    updateState(_state.copyWith(isStreaming: false));
  }

  // ═══════════════════════════════════════════════════════════
  //  通用
  // ═══════════════════════════════════════════════════════════

  void setTargetFps(int fps) {
    updateState(_state.copyWith(targetFps: fps.clamp(5, 30)));
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _captureTimer?.cancel();
    _ws?.close();
    _ws = null;
    _wsConnected = false;
    _frameCount = 0;
    _streamBytes = 0;
    _lastFpsTime = 0;
    _lastFpsCount = 0;
    updateState(const ScreenMirrorState());
  }

  void clearError() {
    updateState(_state.copyWith(error: null));
  }

  void dispose() {
    disconnect();
    // 清理桌面端连接
    for (final ws in {..._mirrorProducers}) {
      try { ws.close(); } catch (_) {}
    }
    for (final ws in {..._mirrorViewers}) {
      try { ws.close(); } catch (_) {}
    }
    _mirrorProducers.clear();
    _mirrorViewers.clear();
  }

  // ═══════════════════════════════════════════════════════════
  //  HTML 查看器页面
  // ═══════════════════════════════════════════════════════════

  /// 返回内嵌的 HTML 查看器页面内容
  static String get viewerHtml => _viewerHtmlContent;

  static const String _viewerHtmlContent = r'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>屏幕投屏查看器</title>
<style>
  *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }

  :root {
    --bg: #0A0E27;
    --surface: rgba(255,255,255,0.05);
    --border: rgba(255,255,255,0.08);
    --cyan: #00E5FF;
    --green: #00E676;
    --amber: #FFB300;
    --rose: #FF4081;
    --text: #F0F0FF;
    --text-sec: #9090BB;
    --text-muted: #606090;
    --radius: 12px;
  }

  body {
    font-family: -apple-system, 'SF Mono', 'Cascadia Code', 'JetBrains Mono', monospace;
    background: var(--bg);
    color: var(--text);
    height: 100vh;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  /* 顶部状态栏 */
  .status-bar {
    padding: 12px 20px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    border-bottom: 1px solid var(--border);
    backdrop-filter: blur(12px);
    background: rgba(10,14,39,0.8);
    flex-shrink: 0;
  }

  .status-left {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .dot {
    width: 10px; height: 10px;
    border-radius: 50%;
    transition: all 0.3s;
  }
  .dot.connected { background: var(--green); box-shadow: 0 0 12px var(--green); }
  .dot.connecting { background: var(--amber); box-shadow: 0 0 12px var(--amber); animation: pulse 1s infinite; }
  .dot.disconnected { background: var(--rose); }

  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.4; }
  }

  .status-text {
    font-size: 13px;
    font-weight: 500;
    letter-spacing: 0.3px;
  }
  .status-text.connected { color: var(--green); }
  .status-text.connecting { color: var(--amber); }
  .status-text.disconnected { color: var(--rose); }

  .status-right {
    display: flex;
    align-items: center;
    gap: 16px;
    font-size: 12px;
    color: var(--text-muted);
  }
  .status-right span {
    display: flex;
    align-items: center;
    gap: 4px;
  }

  /* 查看器主体 */
  .viewer {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 16px;
    position: relative;
    overflow: hidden;
  }

  .viewer::before {
    content: '';
    position: absolute;
    width: 300px; height: 300px;
    border-radius: 50%;
    background: radial-gradient(circle, rgba(0,229,255,0.03) 0%, transparent 70%);
    top: 50%; left: 50%;
    transform: translate(-50%, -50%);
    pointer-events: none;
  }

  #streamCanvas {
    max-width: 100%;
    max-height: 100%;
    border-radius: var(--radius);
    box-shadow: 0 0 40px rgba(0,229,255,0.08), 0 0 80px rgba(0,229,255,0.04);
    object-fit: contain;
    background: #000;
    display: none;
  }

  .placeholder {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 16px;
    color: var(--text-muted);
    text-align: center;
  }
  .placeholder svg { width: 64px; height: 64px; opacity: 0.3; }
  .placeholder h2 {
    font-size: 16px;
    font-weight: 500;
    color: var(--text-sec);
    letter-spacing: 0.5px;
  }
  .placeholder p {
    font-size: 13px;
    max-width: 280px;
    line-height: 1.6;
  }

  /* 底部信息 */
  .footer {
    padding: 10px 20px;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 20px;
    border-top: 1px solid var(--border);
    font-size: 11px;
    color: var(--text-muted);
    flex-shrink: 0;
  }
  .footer span { display: flex; align-items: center; gap: 4px; }

  /* 标题 */
  .title {
    font-size: 14px;
    font-weight: 600;
    background: linear-gradient(135deg, var(--cyan), #7C4DFF);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
  }
</style>
</head>
<body>
  <div class="status-bar">
    <div class="status-left">
      <div class="dot disconnected" id="statusDot"></div>
      <span class="status-text disconnected" id="statusText">未连接</span>
    </div>
    <div class="title">屏幕投屏</div>
    <div class="status-right">
      <span id="fpsDisplay">📷 0 FPS</span>
      <span id="sizeDisplay">📦 0 KB</span>
    </div>
  </div>

  <div class="viewer" id="viewerContainer">
    <div class="placeholder" id="placeholder">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
        <path d="M23 7l-7 5 7 5V7z"/>
        <rect x="1" y="5" width="15" height="14" rx="2" stroke-width="1.5"/>
      </svg>
      <h2>等待投屏信号…</h2>
      <p>请在手机上打开「屏幕投屏」功能，<br>连接到本机 IP 即可看到画面</p>
    </div>
    <canvas id="streamCanvas"></canvas>
  </div>

  <div class="footer">
    <span>📡 <span id="signalStatus">等待连接</span></span>
    <span>🖥 <span id="viewerCount">-</span></span>
    <span id="latencyDisplay">⏱ 0 ms</span>
  </div>

<script>
(function() {
  'use strict';

  const canvas = document.getElementById('streamCanvas');
  const ctx = canvas.getContext('2d');
  const placeholder = document.getElementById('placeholder');
  const statusDot = document.getElementById('statusDot');
  const statusText = document.getElementById('statusText');
  const fpsDisplay = document.getElementById('fpsDisplay');
  const sizeDisplay = document.getElementById('sizeDisplay');
  const signalStatus = document.getElementById('signalStatus');
  const viewerCount = document.getElementById('viewerCount');
  const latencyDisplay = document.getElementById('latencyDisplay');

  let ws = null;
  let reconnectTimer = null;
  let frameCount = 0;
  let byteCount = 0;
  let lastFpsTime = 0;
  let currentFps = 0;
  let imgBuffer = null;
  let pendingFrame = false;
  let lastRenderTime = 0;

  // 从当前页面 URL 推导 WebSocket URL
  function getWsUrl() {
    const loc = window.location;
    const host = loc.hostname;
    const port = loc.port || '9876';
    return 'ws://' + host + ':' + port + '/ws/mirror';
  }

  function setStatus(state, text) {
    statusDot.className = 'dot ' + state;
    statusText.className = 'status-text ' + state;
    statusText.textContent = text;
    signalStatus.textContent = text;
  }

  function connect() {
    if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) return;

    setStatus('connecting', '连接中…');

    try {
      ws = new WebSocket(getWsUrl());

      ws.onopen = function() {
        // 发送 handshake
        ws.send(JSON.stringify({ type: 'handshake', role: 'viewer' }));
        setStatus('connected', '已连接');
        if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }
        lastFpsTime = Date.now();
        frameCount = 0;
        currentFps = 0;
      };

      ws.onmessage = function(e) {
        if (typeof e.data === 'string') {
          try {
            const json = JSON.parse(e.data);
            if (json.type === 'handshake_ack') {
              viewerCount.textContent = json.viewers || '-';
            } else if (json.type === 'stats') {
              viewerCount.textContent = json.viewers || '-';
            }
          } catch(_) {}
          return;
        }

        // 二进制消息 = JPEG 帧
        if (e.data instanceof Blob) {
          const now = Date.now();

          // FPS 计算
          frameCount++;
          if (now - lastFpsTime >= 1000) {
            currentFps = frameCount;
            frameCount = 0;
            lastFpsTime = now;
          }

          // 统计显示
          fpsDisplay.textContent = '📷 ' + currentFps + ' FPS';
          byteCount += e.data.size;
          const kb = (byteCount / 1024).toFixed(0);
          sizeDisplay.textContent = '📦 ' + kb + ' KB';

          // 延迟计算
          if (lastRenderTime > 0) {
            latencyDisplay.textContent = '⏱ ' + (now - lastRenderTime) + ' ms';
          }

          // 将 Blob 转为 ImageBitmap 在 canvas 上渲染
          const blob = e.data;
          createImageBitmap(blob).then(function(bitmap) {
            canvas.width = bitmap.width;
            canvas.height = bitmap.height;
            ctx.drawImage(bitmap, 0, 0);
            bitmap.close();

            canvas.style.display = 'block';
            placeholder.style.display = 'none';
            lastRenderTime = Date.now();
            pendingFrame = false;
          }).catch(function() {
            // fallback: 使用 Image 对象
            const url = URL.createObjectURL(blob);
            const img = new Image();
            img.onload = function() {
              canvas.width = img.naturalWidth;
              canvas.height = img.naturalHeight;
              ctx.drawImage(img, 0, 0);
              URL.revokeObjectURL(url);
              canvas.style.display = 'block';
              placeholder.style.display = 'none';
              lastRenderTime = Date.now();
              pendingFrame = false;
            };
            img.onerror = function() { URL.revokeObjectURL(url); pendingFrame = false; };
            img.src = url;
          });
        }
      };

      ws.onclose = function() {
        setStatus('disconnected', '已断开');
        ws = null;
        scheduleReconnect();
      };

      ws.onerror = function() {
        if (ws) ws.close();
      };
    } catch(e) {
      setStatus('disconnected', '连接失败');
      scheduleReconnect();
    }
  }

  function scheduleReconnect() {
    if (reconnectTimer) return;
    reconnectTimer = setTimeout(function() {
      reconnectTimer = null;
      connect();
    }, 3000);
  }

  // 自动连接
  connect();

  // 每 3 秒请求一次统计信息
  setInterval(function() {
    if (ws && ws.readyState === WebSocket.OPEN) {
      try { ws.send(JSON.stringify({ type: 'stats_req' })); } catch(_) {}
    }
  }, 3000);
})();
</script>
</body>
</html>''';
}
