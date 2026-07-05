// qr_scanner_page.dart
// 二维码扫描页面 — 扫描桌面端 QR 码自动填充 IP
//
// 使用 mobile_scanner 包实现相机扫码，支持：
//   - clipboardsync://ip:port 格式（桌面端生成）
//   - http://ip:port 格式
//   - 裸 IP 地址
//   - 手电筒开关 / 摄像头翻转
//   - 霓虹暗色风格

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null) return;
    final rawValue = barcode.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    String? ip;

    // 尝试解析 URI 格式
    try {
      final uri = Uri.parse(rawValue);
      if (uri.scheme == 'clipboardsync' || uri.scheme == 'http') {
        ip = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
      }
    } catch (_) {
      // URI 解析失败，继续尝试裸 IP
    }

    // 尝试匹配裸 IP 地址
    if (ip == null || ip.isEmpty) {
      final ipMatch = RegExp(
        r'\b(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(?::(\d{1,5}))?\b',
      ).firstMatch(rawValue);
      if (ipMatch != null) {
        final port = ipMatch.group(2);
        ip = port == null ? ipMatch.group(1) : '${ipMatch.group(1)}:$port';
      }
    }

    if (ip != null && ip.isNotEmpty) {
      Navigator.pop(context, ip);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          '扫描二维码',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _torchOn ? Icons.flash_on : Icons.flash_off,
              color: Colors.white.withOpacity(0.8),
            ),
            tooltip: '手电筒',
            onPressed: () {
              setState(() => _torchOn = !_torchOn);
              _controller.toggleTorch();
            },
          ),
          IconButton(
            icon: Icon(
              Icons.flip_camera_android,
              color: Colors.white.withOpacity(0.8),
            ),
            tooltip: '切换摄像头',
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 相机预览
          MobileScanner(controller: _controller, onDetect: _onDetect),

          // 扫描框覆盖层
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFF00E5FF).withOpacity(0.6),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withOpacity(0.08),
                    blurRadius: 30,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // 四角装饰
                  _cornerMarker(Alignment.topLeft),
                  _cornerMarker(Alignment.topRight),
                  _cornerMarker(Alignment.bottomLeft),
                  _cornerMarker(Alignment.bottomRight),
                ],
              ),
            ),
          ),

          // 底部提示
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Colors.white.withOpacity(0.3),
                  size: 28,
                ),
                const SizedBox(height: 8),
                Text(
                  '将桌面端二维码放入框内自动扫描',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cornerMarker(Alignment alignment) {
    double startX, startY, endX, endY;
    const length = 24.0;
    const thickness = 3.0;
    const color = Color(0xFF00E5FF);

    if (alignment == Alignment.topLeft) {
      startX = 0;
      startY = 0;
      endX = length;
      endY = length;
    } else if (alignment == Alignment.topRight) {
      startX = -length;
      startY = 0;
      endX = 0;
      endY = length;
    } else if (alignment == Alignment.bottomLeft) {
      startX = 0;
      startY = -length;
      endX = length;
      endY = 0;
    } else {
      startX = -length;
      startY = -length;
      endX = 0;
      endY = 0;
    }

    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: CustomPaint(
          size: const Size(length, length),
          painter: _CornerPainter(
            color: color,
            thickness: thickness,
            startX: startX,
            startY: startY,
            endX: endX,
            endY: endY,
          ),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final double startX, startY, endX, endY;

  _CornerPainter({
    required this.color,
    required this.thickness,
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    final x0 = startX == 0 ? 0.0 : size.width + startX;
    final y0 = startY == 0 ? 0.0 : size.height + startY;
    final x1 = endX == 0 ? 0.0 : size.width + endX;
    final y1 = endY == 0 ? 0.0 : size.height + endY;

    // 水平线
    canvas.drawLine(Offset(x0, y0), Offset(x1, y0), paint);
    // 垂直线
    canvas.drawLine(Offset(x0, y0), Offset(x0, y1), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) =>
      old.color != color || old.thickness != thickness;
}
