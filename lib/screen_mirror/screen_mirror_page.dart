// screen_mirror_page.dart
// 屏幕投屏页面 — 手机实时投屏到电脑
//
// 设计理念：Cosmic Broadcast
//   - 深空渐变背景 + 浮动光晕粒子
//   - 相机预览区像 CRT 监视器
//   - 广播信号风格的状态指示
//   - 简洁直观的控制面板
//   - 毛玻璃卡片 + 霓虹点缀

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'mirror_service.dart';
import '../clipboard_sync/qr_scanner_page.dart';

// ═══════════════════════════════════════════════════════════════
//  设计令牌 — Cosmic Broadcast
// ═══════════════════════════════════════════════════════════════

abstract class _Theme {
  // 背景 — 深邃宇宙
  static const bgStart = Color(0xFF05051A);
  static const bgMid = Color(0xFF0A0A2E);
  static const bgEnd = Color(0xFF0F0528);

  // 毛玻璃
  static const glassBorder = Color(0x18FFFFFF);

  // 霓虹
  static const signalCyan = Color(0xFF00E5FF);
  static const signalBlue = Color(0xFF2979FF);
  static const signalPurple = Color(0xFF7C4DFF);
  static const signalGreen = Color(0xFF00E676);
  static const signalAmber = Color(0xFFFFB300);
  static const signalRose = Color(0xFFFF1744);

  // 文字
  static const textPrimary = Color(0xFFF0F0FF);
  static const textSecondary = Color(0xFFB0B0DD);
  static const textMuted = Color(0xFF8888BB);

  // 渐变
  static const gradCyan = LinearGradient(
    colors: [signalCyan, signalBlue],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
  static const gradGreen = LinearGradient(
    colors: [signalGreen, Color(0xFF00BCD4)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
  static const gradRose = LinearGradient(
    colors: [signalRose, Color(0xFFFF6E40)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
  static const gradSignal = LinearGradient(
    colors: [signalCyan, signalPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // 圆角
  static const radiusSm = 8.0;
  static const radiusMd = 16.0;
}

// ═══════════════════════════════════════════════════════════════
//  页面
// ═══════════════════════════════════════════════════════════════

class ScreenMirrorPage extends StatefulWidget {
  const ScreenMirrorPage({super.key});

  @override
  State<ScreenMirrorPage> createState() => _ScreenMirrorPageState();
}

class _ScreenMirrorPageState extends State<ScreenMirrorPage>
    with TickerProviderStateMixin {
  final _ipController = TextEditingController();
  final _mirrorService = MirrorService();
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;

  // 动画
  late AnimationController _pulseCtrl;
  late AnimationController _driftCtrl;
  late AnimationController _slideCtrl;
  late AnimationController _scanlineCtrl;

  // 帧捕获定时器
  Timer? _captureTimer;
  bool _cameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _loadLastIp();
    _initCameras();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _driftCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _slideCtrl.forward();
    });

    _scanlineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    // 监听服务状态变化
    _mirrorService.onStateChanged = () {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
    };
  }

  @override
  void dispose() {
    _ipController.dispose();
    _pulseCtrl.dispose();
    _driftCtrl.dispose();
    _slideCtrl.dispose();
    _scanlineCtrl.dispose();
    _captureTimer?.cancel();
    _cameraController?.dispose();
    _mirrorService.dispose();
    super.dispose();
  }

  Future<void> _loadLastIp() async {
    try {
      final dir = await _getDocDir();
      final file = File('${dir.path}/mirror_last_ip.txt');
      if (await file.exists()) {
        final ip = await file.readAsString();
        if (ip.isNotEmpty && mounted) {
          _ipController.text = ip;
        }
      }
    } catch (_) {}
  }

  Future<void> _saveLastIp(String ip) async {
    try {
      final dir = await _getDocDir();
      final file = File('${dir.path}/mirror_last_ip.txt');
      await file.writeAsString(ip);
    } catch (_) {}
  }

  Future<Directory> _getDocDir() async {
    return await getApplicationDocumentsDirectory();
  }

  // ═══════════════════════════════════════════════════════════
  //  相机初始化
  // ═══════════════════════════════════════════════════════════

  Future<void> _initCameras() async {
    if (!isMobilePlatform) return;
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty && mounted) {
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _initCamera() async {
    if (_cameraController != null) return;
    if (_cameras == null || _cameras!.isEmpty) return;

    try {
      final ctrl = CameraController(
        _cameras![0],
        _getResolutionPreset(),
      );
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      _cameraController = ctrl;
      _cameraInitialized = true;
      setState(() {});
    } catch (e) {
      _mirrorService.updateState(
        _mirrorService.state.copyWith(error: '相机启动失败：$e'),
      );
    }
  }

  ResolutionPreset _getResolutionPreset() {
    switch (_mirrorService.state.resolutionLabel) {
      case '低':
        return ResolutionPreset.low;
      case '高':
        return ResolutionPreset.high;
      case '很高':
        return ResolutionPreset.veryHigh;
      default:
        return ResolutionPreset.medium;
    }
  }

  Future<void> _disposeCamera() async {
    _captureTimer?.cancel();
    _captureTimer = null;
    _cameraInitialized = false;
    await _cameraController?.dispose();
    _cameraController = null;
  }

  // ═══════════════════════════════════════════════════════════
  //  帧捕获
  // ═══════════════════════════════════════════════════════════

  void _startFrameCapture() {
    if (_captureTimer != null) return;
    if (_cameraController == null || !_cameraInitialized) return;

    _mirrorService.updateState(_mirrorService.state.copyWith(
      isStreaming: true,
      totalFrames: 0,
      currentFps: 0,
    ));

    final interval = (1000 / _mirrorService.state.targetFps).round();
    _captureTimer = Timer.periodic(Duration(milliseconds: interval), (_) async {
      if (!_mirrorService.state.isStreaming) return;
      if (_cameraController == null || !_cameraInitialized) return;
      try {
        final xfile = await _cameraController!.takePicture();
        final bytes = await xfile.readAsBytes();
        _mirrorService.sendFrame(bytes);
      } catch (_) {}
    });
  }

  void _stopFrameCapture() {
    _captureTimer?.cancel();
    _captureTimer = null;
    _mirrorService.updateState(_mirrorService.state.copyWith(
      isStreaming: false,
    ));
  }

  // ═══════════════════════════════════════════════════════════
  //  连接 / 断开
  // ═══════════════════════════════════════════════════════════

  Future<void> _connect() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      _showSnack('请输入 IP 地址');
      return;
    }

    await _initCamera();
    final ok = await _mirrorService.connectToHost(ip);
    if (ok) {
      _saveLastIp(ip);
      _showSnack('已连接到 $ip');
    }
  }

  void _disconnect() {
    _stopFrameCapture();
    _disposeCamera();
    _mirrorService.disconnect();
    _showSnack('已断开连接');
  }

  void _toggleStreaming() {
    if (_mirrorService.state.isStreaming) {
      _stopFrameCapture();
    } else {
      _startFrameCapture();
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  QR 扫码
  // ═══════════════════════════════════════════════════════════

  Future<void> _scanQrCode() async {
    final ip = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );
    if (ip != null && ip.isNotEmpty) {
      _ipController.text = ip;
      _connect();
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  构建
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final state = _mirrorService.state;
    final isMobile = isMobilePlatform;
    final isDesktop = isDesktopPlatform;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(state),
      body: _CosmicBg(
        driftCtrl: _driftCtrl,
        pulseCtrl: _pulseCtrl,
        child: SafeArea(
          child: _buildContent(state, isMobile, isDesktop),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ScreenMirrorState state) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: ShaderMask(
        shaderCallback: (bounds) => _Theme.gradSignal.createShader(bounds),
        child: const Text(
          '屏幕投屏',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
            color: Colors.white,
          ),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: _GlassIconButton(
            icon: Icons.info_outline,
            onPressed: () => _showHelp(context),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  内容主体
  // ═══════════════════════════════════════════════════════════

  Widget _buildContent(
    ScreenMirrorState state,
    bool isMobile,
    bool isDesktop,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        children: [
          _slideIn(
            child: _buildPlatformBadge(isDesktop, isMobile, state),
            delay: 0,
          ),
          const SizedBox(height: 16),
          // 预览区
          _slideIn(
            child: _buildPreviewArea(state, isMobile),
            delay: 0.06,
          ),
          const SizedBox(height: 4),
          // 状态区
          if (state.isConnected || state.isLoading)
            _slideIn(
              child: _buildStatusPanel(state),
              delay: 0.10,
            ),
          const SizedBox(height: 4),
          // 错误
          if (state.error != null)
            _slideIn(child: _buildErrorCard(state), delay: 0.10),
          const SizedBox(height: 4),
          // 控制区
          _slideIn(
            child: isDesktop
                ? _buildDesktopInfo(state)
                : _buildMobileControls(state),
            delay: 0.14,
          ),
          const SizedBox(height: 4),
          // 提示
          if (state.connectedHost == null && !state.isLoading && state.error == null)
            _slideIn(
              child: isDesktop
                  ? _buildDesktopHelp()
                  : _buildMobileHelp(),
              delay: 0.18,
            ),
        ],
      ),
    );
  }

  Widget _slideIn({required Widget child, double delay = 0}) {
    return AnimatedBuilder(
      animation: _slideCtrl,
      builder: (context, child) {
        final elapsed = _slideCtrl.value - delay;
        final t = elapsed.clamp(0.0, 1.0);
        final opacity = 1.0 - (1.0 - t) * (1.0 - t);
        final offset = Offset(0, 20 * (1.0 - t));
        return Opacity(
          opacity: opacity,
          child: Transform.translate(offset: offset, child: child),
        );
      },
      child: child,
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  平台徽章
  // ═══════════════════════════════════════════════════════════

  Widget _buildPlatformBadge(
    bool isDesktop,
    bool isMobile,
    ScreenMirrorState state,
  ) {
    IconData icon;
    String label;
    String sublabel;

    if (isDesktop) {
      icon = Icons.monitor_heart_rounded;
      label = '投屏接收端';
      sublabel = '浏览器打开地址观看手机投屏';
    } else if (isMobile) {
      icon = Icons.cast_rounded;
      label = '投屏发送端';
      sublabel = '将手机相机画面实时发送到电脑';
    } else {
      icon = Icons.warning_amber_rounded;
      label = '不支持的平台';
      sublabel = '请使用 Android 或桌面端';
    }

    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      borderColor: isDesktop
          ? _Theme.signalGreen.withOpacity(0.25)
          : _Theme.signalCyan.withOpacity(0.25),
      child: Row(
        children: [
          _NeonIcon(
            icon: icon,
            size: 28,
            color: isDesktop ? _Theme.signalGreen : _Theme.signalCyan,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _Theme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sublabel,
                  style: const TextStyle(
                    color: _Theme.textSecondary,
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  预览区
  // ═══════════════════════════════════════════════════════════

  Widget _buildPreviewArea(ScreenMirrorState state, bool isMobile) {
    // 桌面端：不显示预览
    if (isDesktopPlatform) {
      return _buildDesktopPreview();
    }

    // 移动端：显示相机预览或占位
    final hasCamera = _cameraController != null && _cameraInitialized;
    final isViewerMode = state.isConnected || state.isLoading;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: _GlassCard(
        padding: EdgeInsets.zero,
        borderColor: state.isStreaming
            ? _Theme.signalGreen.withOpacity(0.4)
            : isViewerMode
                ? _Theme.signalCyan.withOpacity(0.25)
                : _Theme.glassBorder,
        glowColor: state.isStreaming
            ? _Theme.signalGreen.withOpacity(0.08)
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_Theme.radiusMd),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 相机预览或占位
              if (hasCamera)
                _buildCameraPreview(state)
              else
                _buildCameraPlaceholder(isViewerMode, state),

              // 扫描线覆盖层（流式状态时显示）
              if (state.isStreaming)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _scanlineCtrl,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _ScanlinePainter(
                          phase: _scanlineCtrl.value,
                          color: _Theme.signalCyan.withOpacity(0.04),
                        ),
                      );
                    },
                  ),
                ),

              // 录制指示器
              if (state.isStreaming)
                Positioned(
                  top: 12,
                  left: 12,
                  child: _buildRecordingIndicator(),
                ),

              // 分辨率标签
              if (hasCamera && state.isConnected)
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: _buildResolutionLabel(state),
                ),

              // 黑暗状态 — 连接但无相机
              if (isViewerMode && !hasCamera)
                _buildConnectingOverlay(state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview(ScreenMirrorState state) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_Theme.radiusMd - 1),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_cameraController!),
          // 画面边缘微光
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_Theme.radiusMd - 1),
                  boxShadow: [
                    BoxShadow(
                      color: _Theme.signalCyan.withOpacity(0.06),
                      blurRadius: 20,
                      spreadRadius: 0,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPlaceholder(bool isViewerMode, ScreenMirrorState state) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _Theme.bgStart.withOpacity(0.6),
            _Theme.bgMid.withOpacity(0.4),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NeonIcon(
              icon: isViewerMode
                  ? Icons.camera_alt_outlined
                  : Icons.cast_connected_rounded,
              size: 48,
              color: isViewerMode ? _Theme.signalAmber : _Theme.textMuted,
              opacity: 0.5,
            ),
            const SizedBox(height: 12),
            Text(
              isViewerMode ? '正在启动相机…' : '准备好投屏',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: isViewerMode ? _Theme.signalAmber : _Theme.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            if (!isViewerMode) ...[
              const SizedBox(height: 4),
              Text(
                '连接后相机会自动启动',
                style: TextStyle(
                  fontSize: 12,
                  color: _Theme.textMuted.withOpacity(0.7),
                  letterSpacing: 0.3,
                ),
              ),
            ],
            if (isViewerMode) ...[
              const SizedBox(height: 12),
              _NeonSpinner(size: 24),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectingOverlay(ScreenMirrorState state) {
    return Container(
      color: const Color(0x80000000),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NeonSpinner(size: 28),
            SizedBox(height: 12),
            Text(
              '等待相机…',
              style: TextStyle(
                fontSize: 14,
                color: _Theme.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingIndicator() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _Theme.signalRose.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _Theme.signalRose.withOpacity(0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: _Theme.signalRose.withOpacity(0.15 * _pulseCtrl.value),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _Theme.signalRose,
                  boxShadow: [
                    BoxShadow(
                      color: _Theme.signalRose.withOpacity(0.3 + 0.4 * _pulseCtrl.value),
                      blurRadius: 4 + 4 * _pulseCtrl.value,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${_mirrorService.state.currentFps} FPS',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _Theme.signalRose,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResolutionLabel(ScreenMirrorState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xAA000000),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        state.resolutionLabel,
        style: const TextStyle(
          fontSize: 10,
          color: _Theme.textMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  桌面端预览（提示打开浏览器）
  // ═══════════════════════════════════════════════════════════

  Widget _buildDesktopPreview() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: _GlassCard(
        padding: EdgeInsets.zero,
        borderColor: _Theme.signalGreen.withOpacity(0.2),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_Theme.radiusMd),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _Theme.bgStart.withOpacity(0.5),
                  _Theme.bgMid.withOpacity(0.3),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _NeonIcon(
                    icon: Icons.tv_rounded,
                    size: 48,
                    color: _Theme.signalGreen,
                    opacity: 0.6,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '投屏查看器',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _Theme.textPrimary,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '在浏览器中打开下方地址\n即可观看手机投屏画面',
                    style: TextStyle(
                      fontSize: 13,
                      color: _Theme.textMuted.withOpacity(0.8),
                      letterSpacing: 0.3,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  // 在桌面端，我们直接显示地址
                  _buildViewerUrl(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewerUrl() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _Theme.signalGreen.withOpacity(0.06),
        borderRadius: BorderRadius.circular(_Theme.radiusSm),
        border: Border.all(color: _Theme.signalGreen.withOpacity(0.15)),
      ),
      child: SelectableText(
        'http://127.0.0.1:9876/mirror-viewer',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: _Theme.signalGreen,
          fontFamily: 'monospace',
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  状态面板
  // ═══════════════════════════════════════════════════════════

  Widget _buildStatusPanel(ScreenMirrorState state) {
    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      borderColor: state.isConnected
          ? _Theme.signalGreen.withOpacity(0.25)
          : _Theme.signalAmber.withOpacity(0.25),
      glowColor: state.isConnected
          ? _Theme.signalGreen.withOpacity(0.06)
          : null,
      child: Row(
        children: [
          // 信号强度指示
          _SignalBars(
            level: state.isConnected ? (state.isStreaming ? 4 : 3) : 1,
            active: state.isConnected,
            pulseCtrl: state.isStreaming ? _pulseCtrl : null,
          ),
          const SizedBox(width: 14),
          // 状态信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      state.isConnected
                          ? (state.isStreaming ? '正在投屏' : '已连接')
                          : '连接中…',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: state.isConnected
                            ? (state.isStreaming
                                ? _Theme.signalGreen
                                : _Theme.signalCyan)
                            : _Theme.signalAmber,
                      ),
                    ),
                    const Spacer(),
                    if (state.isConnected && state.connectedHost != null)
                      Text(
                        state.connectedHost!,
                        style: TextStyle(
                          fontSize: 11,
                          color: _Theme.textMuted.withOpacity(0.7),
                          fontFamily: 'monospace',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildStatChip(
                      Icons.speed_rounded,
                      '${state.currentFps} FPS',
                      _Theme.signalCyan,
                    ),
                    const SizedBox(width: 10),
                    _buildStatChip(
                      Icons.data_usage_rounded,
                      _formatDataSize(state.totalBytes),
                      _Theme.signalBlue,
                    ),
                    const SizedBox(width: 10),
                    _buildStatChip(
                      Icons.people_outline_rounded,
                      '${state.viewerCount} 人',
                      _Theme.signalPurple,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color.withOpacity(0.8)),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color.withOpacity(0.9),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDataSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ═══════════════════════════════════════════════════════════
  //  错误卡片
  // ═══════════════════════════════════════════════════════════

  Widget _buildErrorCard(ScreenMirrorState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _Theme.signalRose.withOpacity(0.15),
            _Theme.signalRose.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(_Theme.radiusMd),
        border: Border.all(color: _Theme.signalRose.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              color: _Theme.signalRose.withOpacity(0.9), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              state.error!,
              style: TextStyle(
                color: _Theme.signalRose.withOpacity(0.9),
                fontSize: 13,
                letterSpacing: 0.3,
              ),
            ),
          ),
          InkWell(
            onTap: () => _mirrorService.clearError(),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close_rounded,
                  color: _Theme.signalRose.withOpacity(0.6), size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  移动端控制区
  // ═══════════════════════════════════════════════════════════

  Widget _buildMobileControls(ScreenMirrorState state) {
    // 已连接状态
    if (state.isConnected) {
      return _GlassCard(
        borderColor: state.isStreaming
            ? _Theme.signalGreen.withOpacity(0.3)
            : _Theme.signalCyan.withOpacity(0.2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 投屏控制
            Row(
              children: [
                _NeonIcon(
                  icon: state.isStreaming
                      ? Icons.videocam_rounded
                      : Icons.videocam_outlined,
                  size: 20,
                  color:
                      state.isStreaming ? _Theme.signalGreen : _Theme.signalCyan,
                ),
                const SizedBox(width: 10),
                const Text(
                  '投屏控制',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _Theme.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                _GlassIconButton(
                  icon: Icons.link_off_rounded,
                  size: 18,
                  onPressed: _disconnect,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 开始/停止投屏按钮
            SizedBox(
              width: double.infinity,
              child: _GradientButton(
                gradient:
                    state.isStreaming ? _Theme.gradRose : _Theme.gradGreen,
                icon: state.isStreaming
                    ? Icons.stop_rounded
                    : Icons.play_arrow_rounded,
                label: state.isStreaming ? '停止投屏' : '开始投屏',
                onPressed: _toggleStreaming,
              ),
            ),

            if (!state.isStreaming) ...[
              const SizedBox(height: 14),
              // 帧率选择
              Row(
                children: [
                  Icon(Icons.tune_rounded, size: 16, color: _Theme.textMuted),
                  const SizedBox(width: 8),
                  const Text(
                    '帧率',
                    style: TextStyle(
                      fontSize: 13,
                      color: _Theme.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildFpsChip(10),
                  const SizedBox(width: 6),
                  _buildFpsChip(15),
                  const SizedBox(width: 6),
                  _buildFpsChip(20),
                  const SizedBox(width: 6),
                  _buildFpsChip(30),
                ],
              ),
              const SizedBox(height: 10),
              // 分辨率选择
              Row(
                children: [
                  Icon(Icons.high_quality_rounded,
                      size: 16, color: _Theme.textMuted),
                  const SizedBox(width: 8),
                  const Text(
                    '画质',
                    style: TextStyle(
                      fontSize: 13,
                      color: _Theme.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildResChip('低'),
                  const SizedBox(width: 6),
                  _buildResChip('中等'),
                  const SizedBox(width: 6),
                  _buildResChip('高'),
                ],
              ),
            ],
          ],
        ),
      );
    }

    // 未连接：连接表单
    return _GlassCard(
      borderColor: _Theme.signalCyan.withOpacity(0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _NeonIcon(icon: Icons.cast_rounded, size: 20, color: _Theme.signalCyan),
              const SizedBox(width: 10),
              const Text(
                '连接到电脑',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _Theme.textPrimary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '输入电脑端显示的 IP 地址或扫码连接',
            style: TextStyle(
              fontSize: 13,
              color: _Theme.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _NeonTextField(
                  controller: _ipController,
                  hintText: '192.168.1.100',
                ),
              ),
              const SizedBox(width: 8),
              _GlassIconButton(
                icon: Icons.qr_code_scanner_rounded,
                size: 22,
                onPressed: _scanQrCode,
              ),
              const SizedBox(width: 8),
              _GradientButton(
                gradient: _Theme.gradCyan,
                icon: state.isLoading ? null : Icons.link_rounded,
                label: state.isLoading ? '连接中' : '连接',
                compact: true,
                loading: state.isLoading,
                onPressed: state.isLoading ? null : _connect,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFpsChip(int fps) {
    final isSelected = _mirrorService.state.targetFps == fps;
    return GestureDetector(
      onTap: () {
        if (!_mirrorService.state.isStreaming) {
          _mirrorService.setTargetFps(fps);
          setState(() {});
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? _Theme.signalCyan.withOpacity(0.15)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? _Theme.signalCyan.withOpacity(0.4)
                : Colors.white.withOpacity(0.06),
          ),
        ),
        child: Text(
          '$fps',
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? _Theme.signalCyan : _Theme.textMuted,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _buildResChip(String label) {
    final isSelected = _mirrorService.state.resolutionLabel == label;
    return GestureDetector(
      onTap: () {
        if (!_mirrorService.state.isStreaming) {
          _mirrorService.updateState(
            _mirrorService.state.copyWith(resolutionLabel: label),
          );
          setState(() {});
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? _Theme.signalBlue.withOpacity(0.15)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? _Theme.signalBlue.withOpacity(0.4)
                : Colors.white.withOpacity(0.06),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? _Theme.signalBlue : _Theme.textMuted,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  桌面端信息
  // ═══════════════════════════════════════════════════════════

  Widget _buildDesktopInfo(ScreenMirrorState state) {
    return _GlassCard(
      borderColor: _Theme.signalGreen.withOpacity(0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _NeonIcon(
                icon: Icons.wifi_tethering_rounded,
                size: 20,
                color: _Theme.signalGreen,
              ),
              const SizedBox(width: 10),
              const Text(
                '查看器地址',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _Theme.textPrimary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _Theme.signalGreen.withOpacity(0.06),
              borderRadius: BorderRadius.circular(_Theme.radiusSm),
              border: Border.all(
                color: _Theme.signalGreen.withOpacity(0.15),
              ),
            ),
            child: Column(
              children: [
                const Icon(Icons.language_rounded,
                    size: 20, color: _Theme.signalGreen),
                const SizedBox(height: 8),
                SelectableText(
                  'http://127.0.0.1:9876/mirror-viewer',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _Theme.signalGreen,
                    fontFamily: 'monospace',
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '在同一局域网内的任何设备上打开此地址\n即可观看手机投屏画面',
                  style: TextStyle(
                    fontSize: 12,
                    color: _Theme.textMuted.withOpacity(0.8),
                    letterSpacing: 0.3,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 连接状态
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _Theme.signalGreen.withOpacity(0.08),
              borderRadius: BorderRadius.circular(_Theme.radiusSm),
            ),
            child: Row(
              children: [
                _PulseDot(
                  active: state.viewerCount > 0,
                  activeColor: _Theme.signalGreen,
                  inactiveColor: _Theme.textMuted,
                  pulseCtrl: state.viewerCount > 0 ? _pulseCtrl : null,
                  size: 8,
                ),
                const SizedBox(width: 8),
                Text(
                  state.viewerCount > 0
                      ? '有 ${state.viewerCount} 个设备正在观看'
                      : '等待投屏连接…',
                  style: TextStyle(
                    fontSize: 13,
                    color: state.viewerCount > 0
                        ? _Theme.signalGreen
                        : _Theme.textMuted,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  帮助卡片
  // ═══════════════════════════════════════════════════════════

  Widget _buildMobileHelp() {
    return _GlassCard(
      padding: const EdgeInsets.all(16),
      borderColor: _Theme.signalCyan.withOpacity(0.15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _NeonIcon(
                icon: Icons.tips_and_updates_rounded,
                size: 22,
                color: _Theme.signalAmber,
              ),
              const SizedBox(width: 10),
              const Text(
                '使用步骤',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: _Theme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildStep(1, '在电脑上打开本应用 → 查看器会自动启动', _Theme.signalCyan),
          _buildStep(2, '记下投屏查看器地址中的 IP', _Theme.signalCyan),
          _buildStep(3, '在手机上输入 IP 并点击"连接"', _Theme.signalBlue),
          _buildStep(4, '连接成功后点击"开始投屏"', _Theme.signalGreen),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _Theme.signalAmber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(_Theme.radiusSm),
              border: Border.all(color: _Theme.signalAmber.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                Icon(Icons.wifi_rounded,
                    size: 16, color: _Theme.signalAmber.withOpacity(0.8)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '请确保手机和电脑在同一个局域网内',
                    style: TextStyle(
                      fontSize: 12,
                      color: _Theme.signalAmber,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopHelp() {
    return _GlassCard(
      padding: const EdgeInsets.all(16),
      borderColor: _Theme.signalGreen.withOpacity(0.15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _NeonIcon(
                icon: Icons.info_outline_rounded,
                size: 22,
                color: _Theme.signalGreen,
              ),
              const SizedBox(width: 10),
              const Text(
                '使用说明',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: _Theme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildStep(
            1,
            '将上面的地址发给手机端（局域网内可用）',
            _Theme.signalGreen,
          ),
          _buildStep(
            2,
            '手机端扫码或输入 IP 并连接',
            _Theme.signalGreen,
          ),
          _buildStep(
            3,
            '手机开始投屏后，画面将实时显示在浏览器中',
            _Theme.signalGreen,
          ),
        ],
      ),
    );
  }

  Widget _buildStep(int number, String text, Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent, accent.withOpacity(0.6)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  color: _Theme.textSecondary,
                  letterSpacing: 0.3,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  辅助方法
  // ═══════════════════════════════════════════════════════════

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        backgroundColor: const Color(0xFF1A1050),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _Theme.signalCyan.withOpacity(0.4)),
        ),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_Theme.radiusMd),
          side: BorderSide(color: _Theme.signalPurple.withOpacity(0.2)),
        ),
        title: ShaderMask(
          shaderCallback: (b) => _Theme.gradSignal.createShader(b),
          child: const Text(
            '屏幕投屏说明',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '通过局域网将手机相机画面实时投屏到电脑浏览器。',
                style: TextStyle(color: _Theme.textSecondary, fontSize: 13),
              ),
              SizedBox(height: 16),
              _HelpSection(
                title: '手机端',
                items: [
                  '输入电脑 IP 地址或扫码自动连接',
                  '连接后自动打开相机',
                  '点击"开始投屏"将画面实时传送到电脑',
                  '可调节帧率（10~30 FPS）和画质',
                ],
              ),
              SizedBox(height: 14),
              _HelpSection(
                title: '电脑端',
                items: [
                  '在浏览器打开投屏查看器地址',
                  '手机开始投屏后自动显示画面',
                  '支持同一局域网内多设备观看',
                ],
              ),
              SizedBox(height: 14),
              _HelpSection(
                title: '注意事项',
                items: [
                  '手机和电脑需在同一 WiFi 网络',
                  '投屏延迟约 100~300ms，适合演示和展示',
                  '帧率越高，网络带宽消耗越大',
                  '建议使用 15 FPS + 中等画质获得最佳体验',
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              '知道了',
              style: TextStyle(
                color: _Theme.signalCyan,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  帮助对话框子组件
// ═══════════════════════════════════════════════════════════════

class _HelpSection extends StatelessWidget {
  final String title;
  final List<String> items;

  const _HelpSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: _Theme.signalCyan,
            fontSize: 14,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(left: 8, top: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: TextStyle(color: _Theme.signalPurple.withOpacity(0.6))),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      color: _Theme.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  可复用组件
// ═══════════════════════════════════════════════════════════════

// ── 毛玻璃卡片 ──

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color borderColor;
  final Color? glowColor;

  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor = const Color(0x18FFFFFF),
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_Theme.radiusMd),
        boxShadow: [
          if (glowColor != null)
            BoxShadow(
              color: glowColor!,
              blurRadius: 24,
              spreadRadius: 0,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_Theme.radiusMd),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: const Color(0x12FFFFFF),
              borderRadius: BorderRadius.circular(_Theme.radiusMd),
              border: Border.all(color: borderColor),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ── 脉冲指示点 ──

class _PulseDot extends StatelessWidget {
  final bool active;
  final Color activeColor;
  final Color inactiveColor;
  final AnimationController? pulseCtrl;
  final double size;

  const _PulseDot({
    required this.active,
    required this.activeColor,
    required this.inactiveColor,
    this.pulseCtrl,
    this.size = 12,
  });

  @override
  Widget build(BuildContext context) {
    if (!active || pulseCtrl == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: active ? activeColor : inactiveColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: (active ? activeColor : inactiveColor).withOpacity(0.4),
              blurRadius: 6,
            ),
          ],
        ),
      );
    }

    return AnimatedBuilder(
      animation: pulseCtrl!,
      builder: (context, _) {
        final t = pulseCtrl!.value;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: activeColor.withOpacity(0.2 * (1 - t) + 0.5 * t),
                blurRadius: 2 + 8 * t,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Container(
            decoration: BoxDecoration(
              color: activeColor.withOpacity(0.8 + 0.2 * t),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

// ── 霓虹图标 ──

class _NeonIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  final double opacity;

  const _NeonIcon({
    required this.icon,
    this.size = 24,
    this.color = _Theme.signalCyan,
    this.opacity = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size + 8,
      height: size + 8,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1 * opacity),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15 * opacity),
            blurRadius: 12,
          ),
        ],
      ),
      child: Icon(icon, size: size, color: color.withOpacity(opacity)),
    );
  }
}

// ── 信号强度指示器 ──

class _SignalBars extends StatelessWidget {
  final int level;
  final bool active;
  final AnimationController? pulseCtrl;

  const _SignalBars({
    this.level = 1,
    this.active = false,
    this.pulseCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 20,
      child: CustomPaint(
        painter: _SignalBarsPainter(
          level: level,
          active: active,
          pulseCtrl: pulseCtrl,
        ),
      ),
    );
  }
}

class _SignalBarsPainter extends CustomPainter {
  final int level;
  final bool active;
  final AnimationController? pulseCtrl;

  _SignalBarsPainter({
    required this.level,
    required this.active,
    this.pulseCtrl,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    const barCount = 4;
    final barWidth = size.width / (barCount * 1.6);
    final gap = barWidth * 0.6;
    final baseY = size.height;

    for (int i = 0; i < barCount; i++) {
      final barHeight = size.height * (0.2 + 0.2 * i);
      final x = i * (barWidth + gap);

      Color color;
      if (!active) {
        color = _Theme.signalRose.withOpacity(0.25);
      } else if (i < level) {
        color = i == 0
            ? _Theme.signalGreen.withOpacity(0.5)
            : i == 1
                ? _Theme.signalCyan.withOpacity(0.6)
                : i == 2
                    ? _Theme.signalBlue.withOpacity(0.7)
                    : _Theme.signalPurple.withOpacity(0.8);
      } else {
        color = _Theme.textMuted.withOpacity(0.15);
      }

      // 全高时脉冲发光
      if (active && pulseCtrl != null && pulseCtrl!.isAnimating) {
        if (i == level - 1 && i == barCount - 1) {
          color = Color.lerp(
            color,
            _Theme.signalGreen,
            pulseCtrl!.value * 0.5,
          )!;
        }
      }

      paint.color = color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, baseY - barHeight, barWidth, barHeight),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SignalBarsPainter old) =>
      old.level != level || old.active != active;
}

// ── 扫描线效果绘制器 ──

class _ScanlinePainter extends CustomPainter {
  final double phase;
  final Color color;

  _ScanlinePainter({required this.phase, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;

    const spacing = 3.0;
    final offset = (phase * spacing * 4) % spacing;

    for (double y = offset; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => old.phase != phase;
}

// ── 霓虹文本输入框 ──

class _NeonTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;

  const _NeonTextField({
    required this.controller,
    required this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.url,
      style: const TextStyle(
        color: _Theme.textPrimary,
        fontSize: 14,
        letterSpacing: 0.5,
        fontFamily: 'monospace',
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          color: _Theme.textMuted.withOpacity(0.85),
          fontSize: 14,
          fontFamily: 'monospace',
        ),
        prefixIcon: Icon(Icons.language_rounded,
            size: 18, color: _Theme.signalCyan.withOpacity(0.7)),
        filled: true,
        fillColor: const Color(0x10FFFFFF),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_Theme.radiusSm),
          borderSide: BorderSide(
            color: _Theme.signalCyan.withOpacity(0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_Theme.radiusSm),
          borderSide: BorderSide(
            color: _Theme.signalCyan.withOpacity(0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_Theme.radiusSm),
          borderSide: BorderSide(
            color: _Theme.signalCyan.withOpacity(0.5),
          ),
        ),
      ),
    );
  }
}

// ── 渐变按钮 ──

class _GradientButton extends StatelessWidget {
  final Gradient gradient;
  final IconData? icon;
  final String label;
  final VoidCallback? onPressed;
  final bool compact;
  final bool loading;

  const _GradientButton({
    required this.gradient,
    this.icon,
    required this.label,
    this.onPressed,
    this.compact = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 18, vertical: 12)
          : const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_Theme.radiusSm),
      ),
      backgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_Theme.radiusSm),
        gradient: onPressed != null ? gradient : null,
        boxShadow: [
          if (onPressed != null)
            BoxShadow(
              color:
                  (gradient as LinearGradient).colors.first.withOpacity(0.3),
              blurRadius: 12,
              spreadRadius: 0,
            ),
        ],
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: style,
        child: Row(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else ...[
              if (icon != null) ...[
                Icon(icon, size: compact ? 18 : 20),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: compact ? 14 : 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 玻璃图标按钮 ──

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback? onPressed;

  const _GlassIconButton({
    required this.icon,
    this.size = 20,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: IconButton(
        icon: Icon(icon, size: size),
        color: _Theme.textSecondary,
        onPressed: onPressed,
        splashRadius: 18,
        padding: EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      ),
    );
  }
}

// ── 霓虹加载旋转器 ──

class _NeonSpinner extends StatelessWidget {
  final double size;

  const _NeonSpinner({this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: const AlwaysStoppedAnimation<Color>(_Theme.signalCyan),
      ),
    );
  }
}

// ── 宇宙背景 ──

class _CosmicBg extends StatelessWidget {
  final AnimationController driftCtrl;
  final AnimationController pulseCtrl;
  final Widget child;

  const _CosmicBg({
    required this.driftCtrl,
    required this.pulseCtrl,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([driftCtrl, pulseCtrl]),
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(
                  _Theme.bgStart,
                  const Color(0xFF0D0D35),
                  (driftCtrl.value * 0.3).clamp(0.0, 1.0),
                )!,
                Color.lerp(
                  _Theme.bgMid,
                  const Color(0xFF0F0A2A),
                  (driftCtrl.value * 0.3 + 0.2).clamp(0.0, 1.0),
                )!,
                Color.lerp(
                  _Theme.bgEnd,
                  const Color(0xFF150520),
                  (driftCtrl.value * 0.3 + 0.4).clamp(0.0, 1.0),
                )!,
              ],
            ),
          ),
          child: Stack(
            children: [
              // 浮动光晕
              Positioned(
                top: -60 + math.sin(driftCtrl.value * math.pi * 2) * 30,
                right: -40 + math.cos(driftCtrl.value * math.pi * 2) * 20,
                child: _buildOrb(
                  _Theme.signalCyan.withOpacity(0.035),
                  180,
                ),
              ),
              Positioned(
                bottom: -80 + math.cos(driftCtrl.value * math.pi * 2) * 25,
                left: -50 + math.sin(driftCtrl.value * math.pi * 2) * 20,
                child: _buildOrb(
                  _Theme.signalPurple.withOpacity(0.03),
                  160,
                ),
              ),
              Positioned(
                top: 200 + math.sin((driftCtrl.value * math.pi * 2 + 1)) * 40,
                left: -30,
                child: _buildOrb(
                  _Theme.signalBlue.withOpacity(0.02),
                  120,
                ),
              ),
              // 微弱的网格
              Positioned.fill(
                child: CustomPaint(
                  painter: _GridPainter(phase: driftCtrl.value * 0.05),
                ),
              ),
              // 星星
              Positioned.fill(
                child: CustomPaint(
                  painter: _StarPainter(phase: pulseCtrl.value),
                ),
              ),
              child!,
            ],
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildOrb(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: size * 2,
            spreadRadius: size * 0.3,
          ),
        ],
      ),
    );
  }
}

// ── 网格绘制器 ──

class _GridPainter extends CustomPainter {
  final double phase;

  _GridPainter({this.phase = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.008)
      ..strokeWidth = 0.5;

    const spacing = 64.0;
    final offset = spacing * phase;

    for (double x = offset % spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = offset % spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.phase != phase;
}

// ── 星星绘制器 ──

class _StarPainter extends CustomPainter {
  final double phase;

  _StarPainter({this.phase = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42);
    final paint = Paint();

    for (int i = 0; i < 40; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final radius = 0.3 + random.nextDouble() * 0.7;
      final brightness = 0.3 + random.nextDouble() * 0.4;

      paint.color = Colors.white.withOpacity(
        brightness * (0.8 + 0.2 * math.sin(phase * math.pi * 2 + i * 1.7)),
      );
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => true;
}
