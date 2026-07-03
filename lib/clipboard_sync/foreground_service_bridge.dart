// foreground_service_bridge.dart
// 原生 Android 前台服务的 Dart 桥接层
//
// 通过 MethodChannel 与 ClipboardForegroundService (Kotlin) 通信，
// 在 app 退到后台时保持 Android 进程存活，使 WebSocket 持续接收数据。

import 'package:flutter/services.dart';

/// MethodChannel 名称，需与 MainActivity.kt 中的 CHANNEL 常量一致
const _channelName = 'com.xyh.kopy/clipboard_service';

final MethodChannel _channel = MethodChannel(_channelName);

/// 启动前台服务（Android 通知栏会出现常驻通知）
Future<void> startForegroundService() async {
  try {
    await _channel.invokeMethod<void>('startService');
  } catch (_) {
    // 非 Android 平台或服务未注册时静默处理
  }
}

/// 停止前台服务（移除通知栏常驻通知）
Future<void> stopForegroundService() async {
  try {
    await _channel.invokeMethod<void>('stopService');
  } catch (_) {
    // 非 Android 平台或服务未注册时静默处理
  }
}
