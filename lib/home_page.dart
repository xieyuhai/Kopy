// home_page.dart
// Kopy 首页 — 深空霓虹仪表盘
//
// 设计理念：Cosmic Dashboard
//   - 深空渐变背景 + 动态光晕粒子
//   - 毛玻璃功能卡片 + 微光边框
//   - 霓虹青/紫外光点缀
//   - 脉冲状态指示器
//   - 渐进式入场动画
//
// 三大功能模块：
//   📋 剪贴板同步 — PC ↔ App 实时同步
//   📁 文件互传 — 局域网文件传输
//   📡 屏幕投屏 — 手机 → 电脑实时投屏

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'clipboard_sync/clipboard_sync_page.dart';
import 'clipboard_sync/clipboard_sync_provider.dart';
import 'clipboard_sync/clipboard_sync_service.dart';
import 'screen_mirror/screen_mirror_page.dart';

// ═══════════════════════════════════════════════════════════════
//  设计令牌 — Cosmic Dashboard
// ═══════════════════════════════════════════════════════════════

abstract class _Theme {
  static const bgStart = Color(0xFF060B24);
  static const bgMid = Color(0xFF0C1035);
  static const bgEnd = Color(0xFF120A30);

  static const neonCyan = Color(0xFF00E5FF);
  static const neonPurple = Color(0xFF7C4DFF);
  static const neonGreen = Color(0xFF00E676);
  static const neonAmber = Color(0xFFFFB300);
  static const neonRose = Color(0xFFFF4081);

  static const textPrimary = Color(0xFFF0F0FF);
  static const textSecondary = Color(0xFFB0B0DD);
  static const textMuted = Color(0xFF8888BB);

  static const glassBorder = Color(0x15FFFFFF);
  static const glassBg = Color(0x0AFFFFFF);
  static const glassHover = Color(0x14FFFFFF);

  static const radiusMd = 20.0;
  static const radiusLg = 28.0;
}

// ═══════════════════════════════════════════════════════════════
//  首页
// ═══════════════════════════════════════════════════════════════

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with TickerProviderStateMixin {
  late AnimationController _phaseCtrl;
  late AnimationController _entranceCtrl;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();
    _phaseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeIn = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.easeOut,
    );
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.easeOutCubic,
    ));

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _entranceCtrl.forward();
    });
  }

  @override
  void dispose() {
    _phaseCtrl.dispose();
    _entranceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(clipboardSyncProvider);
    final isDesktop = ClipboardSyncService.isDesktopPlatform;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _phaseCtrl,
        builder: (context, _) => _CosmicBg(
          phaseCtrl: _phaseCtrl,
          child: SafeArea(
            child: FadeTransition(
              opacity: _fadeIn,
              child: SlideTransition(
                position: _slideUp,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      _buildHeader(isDesktop, syncState.isServerRunning),
                      const SizedBox(height: 36),
                      _buildSectionTitle('功能模块'),
                      const SizedBox(height: 20),
                      _FeatureCard(
                        icon: Icons.sync_alt_rounded,
                        title: '剪贴板同步',
                        subtitle: 'PC ↔ 手机实时同步',
                        description: '局域网内剪贴板双向实时同步，支持二维码扫码连接',
                        gradient: const LinearGradient(
                          colors: [_Theme.neonCyan, Color(0xFF0091EA)],
                        ),
                        onTap: () => _navigate(const ClipboardSyncPage()),
                        statusIcon: syncState.isWsConnected
                            ? Icons.link_rounded
                            : null,
                        statusLabel: syncState.isWsConnected ? '已连接' : null,
                        statusColor: _Theme.neonGreen,
                        delayMs: 0,
                        entranceCtrl: _entranceCtrl,
                      ),
                      const SizedBox(height: 16),
                      _FeatureCard(
                        icon: Icons.folder_shared_rounded,
                        title: '文件互传',
                        subtitle: '局域网文件传输',
                        description: '支持图片、文档、视频等文件的局域网双向传输',
                        gradient: const LinearGradient(
                          colors: [_Theme.neonPurple, Color(0xFFE040FB)],
                        ),
                        onTap: () => _navigateFileTab(),
                        delayMs: 100,
                        entranceCtrl: _entranceCtrl,
                      ),
                      const SizedBox(height: 16),
                      _FeatureCard(
                        icon: Icons.cast_connected_rounded,
                        title: '屏幕投屏',
                        subtitle: '手机 → 电脑实时投屏',
                        description: '将手机摄像头画面实时传输到电脑浏览器查看',
                        gradient: const LinearGradient(
                          colors: [_Theme.neonAmber, Color(0xFFFF6E40)],
                        ),
                        onTap: () => _navigate(const ScreenMirrorPage()),
                        delayMs: 200,
                        entranceCtrl: _entranceCtrl,
                      ),
                      const SizedBox(height: 36),
                      _buildStatusBar(isDesktop, syncState),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _navigate(Widget page) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _navigateFileTab() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const ClipboardSyncPage(initialTab: 1),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  // ── 顶部 Header ──

  Widget _buildHeader(bool isDesktop, bool isServerRunning) {
    return Row(
      children: [
        // Logo
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [_Theme.neonCyan, _Theme.neonPurple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _Theme.neonCyan.withOpacity(0.25),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'K',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kopy',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: _Theme.textPrimary,
                  letterSpacing: -0.5,
                  height: 1.1,
                ),
              ),
              Text(
                '设备间无缝协作',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: _Theme.textSecondary.withOpacity(0.8),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        // 平台指示器
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _Theme.glassBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _Theme.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDesktop ? Icons.desktop_windows_rounded : Icons.phone_android_rounded,
                size: 14,
                color: _Theme.neonCyan.withOpacity(0.8),
              ),
              const SizedBox(width: 6),
              Text(
                isDesktop ? '桌面端' : '移动端',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _Theme.neonCyan.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: _Theme.textSecondary.withOpacity(0.6),
        letterSpacing: 1.5,
      ),
    );
  }

  // ── 底部状态栏 ──

  Widget _buildStatusBar(bool isDesktop, dynamic syncState) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _Theme.glassBg,
        borderRadius: BorderRadius.circular(_Theme.radiusMd),
        border: Border.all(color: _Theme.glassBorder),
      ),
      child: Row(
        children: [
          // 服务状态
          _StatusDot(
            active: isDesktop
                ? syncState.isServerRunning
                : syncState.isWsConnected,
            color: _Theme.neonGreen,
            label: isDesktop ? '剪贴板服务' : '连接状态',
          ),
          const SizedBox(width: 20),
          _StatusDot(
            active: syncState.isMobileMonitoring,
            color: _Theme.neonAmber,
            label: '手机监控',
          ),
          const Spacer(),
          Text(
            'Kopy v1.0.0',
            style: TextStyle(
              fontSize: 12,
              color: _Theme.textMuted.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 功能卡片 ──

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String description;
  final LinearGradient gradient;
  final VoidCallback onTap;
  final IconData? statusIcon;
  final String? statusLabel;
  final Color? statusColor;
  final int delayMs;
  final AnimationController entranceCtrl;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.gradient,
    required this.onTap,
    this.statusIcon,
    this.statusLabel,
    this.statusColor,
    required this.delayMs,
    required this.entranceCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final delaySeconds = delayMs / 1000.0;
    final anim = CurvedAnimation(
      parent: entranceCtrl,
      curve: Interval(
        (delaySeconds).clamp(0.0, 1.0),
        (delaySeconds + 0.4).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        return Opacity(
          opacity: anim.value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - anim.value)),
            child: _GlassCard(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Row(
                  children: [
                    // 左侧图标
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: gradient,
                        boxShadow: [
                          BoxShadow(
                            color: gradient.colors.first.withOpacity(0.3),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Icon(icon, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 18),
                    // 文字内容
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: _Theme.textPrimary,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              if (statusIcon != null && statusLabel != null) ...[
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (statusColor ?? _Theme.neonGreen)
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: (statusColor ?? _Theme.neonGreen)
                                          .withOpacity(0.2),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        statusIcon,
                                        size: 12,
                                        color: statusColor ?? _Theme.neonGreen,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        statusLabel!,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: statusColor ?? _Theme.neonGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 13,
                              color: _Theme.neonCyan.withOpacity(0.7),
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 12,
                              color: _Theme.textSecondary.withOpacity(0.7),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: _Theme.textMuted.withOpacity(0.5),
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── 毛玻璃卡片 ──

class _GlassCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _GlassCard({required this.child, this.onTap});

  @override
  State<_GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<_GlassCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_Theme.radiusMd),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: _pressed ? _Theme.glassHover : _Theme.glassBg,
                borderRadius: BorderRadius.circular(_Theme.radiusMd),
                border: Border.all(
                  color: _pressed
                      ? Colors.white.withOpacity(0.08)
                      : _Theme.glassBorder,
                ),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

// ── 状态指示灯 ──

class _StatusDot extends StatelessWidget {
  final bool active;
  final Color color;
  final String label;

  const _StatusDot({
    required this.active,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? color : _Theme.textMuted.withOpacity(0.3),
            boxShadow: active
                ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8)]
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: active
                ? _Theme.textSecondary
                : _Theme.textMuted.withOpacity(0.4),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  宇宙背景
// ═══════════════════════════════════════════════════════════════

class _CosmicBg extends StatelessWidget {
  final AnimationController phaseCtrl;
  final Widget child;

  const _CosmicBg({required this.phaseCtrl, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: phaseCtrl,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(
                  _Theme.bgStart,
                  const Color(0xFF0A1030),
                  (phaseCtrl.value * 0.4).clamp(0.0, 1.0),
                )!,
                Color.lerp(
                  _Theme.bgMid,
                  const Color(0xFF101540),
                  (phaseCtrl.value * 0.4 + 0.2).clamp(0.0, 1.0),
                )!,
                Color.lerp(
                  _Theme.bgEnd,
                  const Color(0xFF0A0828),
                  (phaseCtrl.value * 0.4 + 0.4).clamp(0.0, 1.0),
                )!,
              ],
            ),
          ),
          child: Stack(
            children: [
              // 浮动光晕
              Positioned(
                top: -120 + math.sin(phaseCtrl.value * math.pi * 2) * 40,
                right: -80 + math.cos(phaseCtrl.value * math.pi * 2) * 30,
                child: _buildOrb(_Theme.neonCyan.withOpacity(0.025), 260),
              ),
              Positioned(
                bottom: -100 + math.cos(phaseCtrl.value * math.pi * 2) * 35,
                left: -60 + math.sin(phaseCtrl.value * math.pi * 2) * 25,
                child: _buildOrb(_Theme.neonPurple.withOpacity(0.02), 220),
              ),
              Positioned(
                top: 300 + math.sin((phaseCtrl.value * math.pi * 2 + 1.5)) * 50,
                left: -40,
                child: _buildOrb(_Theme.neonAmber.withOpacity(0.015), 160),
              ),
              // 网格
              Positioned.fill(
                child: CustomPaint(
                  painter: _GridPainter(phase: phaseCtrl.value * 0.03),
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

class _GridPainter extends CustomPainter {
  final double phase;
  _GridPainter({this.phase = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.012)
      ..strokeWidth = 0.5;
    const spacing = 56.0;
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
