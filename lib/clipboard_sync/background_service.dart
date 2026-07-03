// background_service.dart
// 前台服务 — 保持 WebSocket 连接在 app 退到后台时仍然存活
//
//   Android：通过 MethodChannel 调用原生 ClipboardForegroundService，
//           前台服务 + 持续通知 → 阻止 OS 杀掉 Dart isolate，WebSocket 持续接收
//   iOS：    不支持任意后台网络连接，fallback 到 onAppResumed() HTTP 拉取
//
// 架构：
//   连接到桌面端时 startClipboardSyncService() → 断开时 stopClipboardSyncService()
//   原生 Service 仅负责生命周期管理，不运行 Dart isolate

import 'package:flutter/foundation.dart';
import 'foreground_service_bridge.dart';

/// 初始化（仅占位，无需额外配置）
Future<void> initClipboardBackgroundService() async {
  // Android 前台服务由 MethodChannel 在连接时动态启动
  // 无需预先配置
}

/// 启动前台服务 — 在 WebSocket 连接成功后调用
Future<void> startClipboardSyncService() async {
  if (_isAndroid) {
    await startForegroundService();
  }
}

/// 停止前台服务 — 在断开连接时调用
Future<void> stopClipboardSyncService() async {
  if (_isAndroid) {
    await stopForegroundService();
  }
}

/// 安全判断是否为 Android 平台（defaultTargetPlatform 在 Web 上会抛异常）
bool get _isAndroid {
  try {
    return defaultTargetPlatform == TargetPlatform.android;
  } catch (_) {
    return false;
  }
}
