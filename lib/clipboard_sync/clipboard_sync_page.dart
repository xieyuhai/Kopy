// clipboard_sync_page.dart
// PC ↔ App 剪贴板同步 — Neon Glass 重构版 UI
//
// 设计理念：深色霓虹玻璃主义
//   - 午夜渐变背景 + 动态流光
//   - 毛玻璃卡片（BackdropFilter blur）
//   - 霓虹青 + 紫外光点缀
//   - 脉冲发光状态指示器
//   - 渐变按钮 + 阴影辉光
//
// Tab 布局：
//   同步 — 剪贴板双向同步 + QR 码连接
//   文件 — 局域网文件互传

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'clipboard_sync_provider.dart';
import 'clipboard_sync_service.dart';
import 'qr_scanner_page.dart';

// ═══════════════════════════════════════════════════════════════
//  设计令牌
// ═══════════════════════════════════════════════════════════════

abstract class _Theme {
  // 背景
  static const bgStart = Color(0xFF0A0E27);
  static const bgEnd = Color(0xFF1A1040);
  static const bgCard = Color(0x1AFFFFFF);
  static const bgCardHover = Color(0x28FFFFFF);

  // 霓虹
  static const neonCyan = Color(0xFF00E5FF);
  static const neonPurple = Color(0xFF7C4DFF);
  static const neonAmber = Color(0xFFFFB300);
  static const neonRose = Color(0xFFFF4081);
  static const neonGreen = Color(0xFF00E676);

  // 文字
  static const textPrimary = Color(0xFFF0F0FF);
  static const textSecondary = Color(0xFFB0B0DD);
  static const textMuted = Color(0xFF8888BB);

  // 渐变
  static const gradientCyan = LinearGradient(
    colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
  static const gradientGreen = LinearGradient(
    colors: [Color(0xFF00E676), Color(0xFF00BCD4)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
  static const gradientRose = LinearGradient(
    colors: [Color(0xFFFF4081), Color(0xFFFF6E40)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
  static const gradientAmber = LinearGradient(
    colors: [Color(0xFFFFB300), Color(0xFFFF6E40)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const radiusSm = 8.0;
  static const radiusMd = 16.0;
  static const radiusLg = 24.0;
}

// ═══════════════════════════════════════════════════════════════
//  页面
// ═══════════════════════════════════════════════════════════════

class ClipboardSyncPage extends ConsumerStatefulWidget {
  final int initialTab;

  const ClipboardSyncPage({super.key, this.initialTab = 0});

  @override
  ConsumerState<ClipboardSyncPage> createState() => _ClipboardSyncPageState();
}

class _ClipboardSyncPageState extends ConsumerState<ClipboardSyncPage>
    with TickerProviderStateMixin {
  final _ipController = TextEditingController();
  bool _showPasted = false;

  late AnimationController _pulseCtrl;
  late AnimationController _shimmerCtrl;
  late AnimationController _slideCtrl;

  @override
  void initState() {
    super.initState();
    _loadLastIp();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _slideCtrl.forward();
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    _pulseCtrl.dispose();
    _shimmerCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  void _loadLastIp() async {
    final ip = await ref.read(clipboardSyncProvider.notifier).loadLastIp();
    if (ip != null && ip.isNotEmpty && mounted) {
      _ipController.text = ip;
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clipboardSyncProvider);
    final notifier = ref.read(clipboardSyncProvider.notifier);
    final isDesktop = ClipboardSyncService.isDesktopPlatform;
    final isMobile = ClipboardSyncService.isMobilePlatform;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: _buildAppBar(isDesktop),
        body: _AnimatedBg(
          shimmerCtrl: _shimmerCtrl,
          child: SafeArea(
            child: TabBarView(
              children: [
                _buildSyncTab(state, notifier, isDesktop, isMobile),
                _buildFilesTab(state, notifier, isDesktop, isMobile),
              ],
            ),
          ),
        ),
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
        final offset = Offset(0, 24 * (1.0 - t));
        return Opacity(
          opacity: opacity,
          child: Transform.translate(offset: offset, child: child),
        );
      },
      child: child,
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  AppBar
  // ═══════════════════════════════════════════════════════════

  PreferredSizeWidget _buildAppBar(bool isDesktop) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          colors: [_Theme.neonCyan, _Theme.neonPurple],
        ).createShader(bounds),
        child: const Text(
          '剪贴板同步',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: Colors.white,
          ),
        ),
      ),
      bottom: const TabBar(
        tabs: [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sync_rounded, size: 18),
                SizedBox(width: 6),
                Text('同步'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder_rounded, size: 18),
                SizedBox(width: 6),
                Text('文件'),
              ],
            ),
          ),
        ],
        indicatorColor: _Theme.neonCyan,
        indicatorSize: TabBarIndicatorSize.tab,
        unselectedLabelColor: _Theme.textMuted,
        labelColor: _Theme.neonCyan,
        labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: _GlassIconButton(
            icon: Icons.info_outline,
            onPressed: () => _showHelp(context, isDesktop),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  同步 Tab
  // ═══════════════════════════════════════════════════════════

  Widget _buildSyncTab(
    ClipboardSyncState state,
    ClipboardSyncNotifier notifier,
    bool isDesktop,
    bool isMobile,
  ) {
    return RefreshIndicator(
      color: _Theme.neonCyan,
      backgroundColor: const Color(0xFF1A1A2E),
      onRefresh: () => notifier.fetchFileList(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _slideIn(
            child: _buildPlatformBadge(isDesktop, isMobile),
          ),
        const SizedBox(height: 20),
        if (isDesktop) ...[
          _slideIn(child: _buildServerSection(state, notifier), delay: 0.08),
          if (state.isServerRunning)
            _slideIn(child: _buildQrSection(state, notifier), delay: 0.10),
        ],
        if (isMobile)
          _slideIn(child: _buildConnectionSection(state, notifier), delay: 0.08),
        if (state.error != null)
          _slideIn(child: _buildErrorCard(state, notifier), delay: 0.12),
        const SizedBox(height: 4),
        // 手机剪贴板展示（桌面端）
        if (isDesktop && state.phoneClipboard != null)
          _slideIn(child: _buildPhoneClipboardCard(state, notifier), delay: 0.14),
        // 手机端操作（推送到 PC + 自动监控）
        if (isMobile && state.connectedHost != null)
          _slideIn(child: _buildMobileActions(state, notifier), delay: 0.14),
        // 剪贴板内容展示
        _slideIn(
          child: _buildClipboardDisplay(state, notifier, isDesktop, isMobile),
          delay: 0.16,
        ),
        const SizedBox(height: 4),
        if (state.connectedHost != null)
          _slideIn(child: _buildConnectedInfo(state, notifier, isMobile), delay: 0.20),
        if (isMobile && state.connectedHost == null && state.error == null)
          _slideIn(child: _buildHelpCard(), delay: 0.24),
      ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  文件 Tab
  // ═══════════════════════════════════════════════════════════

  Widget _buildFilesTab(
    ClipboardSyncState state,
    ClipboardSyncNotifier notifier,
    bool isDesktop,
    bool isMobile,
  ) {
    final canAccessFiles =
        isDesktop ||
        (isMobile && state.connectedHost != null);

    if (!canAccessFiles) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NeonIcon(
                icon: Icons.folder_open_rounded,
                size: 56,
                color: _Theme.textMuted,
                opacity: 0.5,
              ),
              const SizedBox(height: 16),
              Text(
                isDesktop ? '文件管理' : '请先连接到桌面端',
                style: const TextStyle(
                  fontSize: 15,
                  color: _Theme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isDesktop
                    ? '选择文件上传或管理已传输的文件'
                    : '连接后可在手机和电脑之间传输文件',
                style: const TextStyle(
                  fontSize: 12,
                  color: _Theme.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _Theme.neonCyan,
      backgroundColor: const Color(0xFF1A1A2E),
      onRefresh: () => notifier.fetchFileList(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _slideIn(child: _buildFileActions(state, notifier), delay: 0),
          if (state.isUploading)
            _slideIn(child: _buildUploadProgress(state), delay: 0.04),
          const SizedBox(height: 4),
          _slideIn(child: _buildFileList(state, notifier), delay: 0.08),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  平台徽章
  // ═══════════════════════════════════════════════════════════

  Widget _buildPlatformBadge(bool isDesktop, bool isMobile) {
    IconData icon;
    String label;
    String sublabel;

    if (isDesktop) {
      icon = Icons.dns;
      label = '桌面端服务';
      sublabel = '本机作为剪贴板服务端 · 局域网共享';
    } else if (isMobile) {
      icon = Icons.phone_android;
      label = '移动端客户端';
      sublabel = 'WebSocket 实时同步 · 双向剪贴板 · 文件互传';
    } else {
      icon = Icons.warning_amber_rounded;
      label = '不支持的平台';
      sublabel = '当前平台不支持剪贴板同步';
    }

    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      borderColor: isDesktop
          ? _Theme.neonCyan.withOpacity(0.25)
          : _Theme.neonPurple.withOpacity(0.25),
      child: Row(
        children: [
          _NeonIcon(icon: icon, size: 28, color: isDesktop ? _Theme.neonCyan : _Theme.neonPurple),
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
  //  桌面端：服务控制
  // ═══════════════════════════════════════════════════════════

  Widget _buildServerSection(
    ClipboardSyncState state,
    ClipboardSyncNotifier notifier,
  ) {
    return _GlassCard(
      borderColor: state.isServerRunning
          ? _Theme.neonGreen.withOpacity(0.25)
          : _Theme.neonRose.withOpacity(0.25),
      glowColor: state.isServerRunning ? _Theme.neonGreen.withOpacity(0.08) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PulseDot(
                active: state.isServerRunning,
                activeColor: _Theme.neonGreen,
                inactiveColor: _Theme.neonRose,
                pulseCtrl: state.isServerRunning ? _pulseCtrl : null,
              ),
              const SizedBox(width: 12),
              Text(
                state.isServerRunning ? '服务运行中' : '服务未启动',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: state.isServerRunning ? _Theme.neonGreen : _Theme.neonRose,
                ),
              ),
              const Spacer(),
              if (state.isLoading)
                _NeonSpinner(),
            ],
          ),

          if (state.isServerRunning && state.serverAddress != null) ...[
            const SizedBox(height: 16),
            _AddressChip(
              address:
                  'http://${state.serverAddress}:${ClipboardSyncService.defaultPort}',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.bolt, size: 14, color: _Theme.neonAmber.withOpacity(0.8)),
                const SizedBox(width: 6),
                const Text(
                  'WebSocket 实时推送 · 复制即同步',
                  style: TextStyle(
                    fontSize: 12,
                    color: _Theme.neonAmber,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 18),

          _GradientButton(
            gradient: state.isServerRunning ? _Theme.gradientRose : _Theme.gradientCyan,
            icon: state.isServerRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
            label: state.isServerRunning ? '停止服务' : '启动服务',
            onPressed: () async {
              if (state.isServerRunning) {
                await notifier.stopServer();
              } else {
                await notifier.startServer();
              }
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  桌面端：QR 码
  // ═══════════════════════════════════════════════════════════

  Widget _buildQrSection(
    ClipboardSyncState state,
    ClipboardSyncNotifier notifier,
  ) {
    return _GlassCard(
      borderColor: _Theme.neonCyan.withOpacity(0.2),
      child: Column(
        children: [
          Row(
            children: [
              _NeonIcon(icon: Icons.qr_code_2_rounded, size: 20, color: _Theme.neonCyan),
              const SizedBox(width: 10),
              const Text(
                '手机扫码连接',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _Theme.textPrimary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // QR 码
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _Theme.neonCyan.withOpacity(0.15),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: QrImageView(
              data: notifier.getQrData(),
              version: QrVersions.auto,
              size: 180,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF0A0E27),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF0A0E27),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '用手机扫描上方二维码即可自动连接',
            style: TextStyle(
              color: _Theme.textMuted,
              fontSize: 12,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '支持 手机→PC 剪贴板推送 · 文件互传',
            style: TextStyle(
              color: _Theme.textMuted.withOpacity(0.6),
              fontSize: 11,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  桌面端：来自手机的剪贴板
  // ═══════════════════════════════════════════════════════════

  Widget _buildPhoneClipboardCard(
    ClipboardSyncState state,
    ClipboardSyncNotifier notifier,
  ) {
    return _GlassCard(
      borderColor: _Theme.neonAmber.withOpacity(0.25),
      glowColor: _Theme.neonAmber.withOpacity(0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _NeonIcon(icon: Icons.phone_iphone_rounded, size: 20, color: _Theme.neonAmber),
              const SizedBox(width: 10),
              const Text(
                '来自手机',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _Theme.neonAmber,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Icon(Icons.access_time_rounded,
                      size: 12, color: _Theme.textMuted),
                  const SizedBox(width: 4),
                  const Text(
                    '刚刚推送',
                    style: TextStyle(
                      fontSize: 11,
                      color: _Theme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              _GlassIconButton(
                icon: Icons.close_rounded,
                size: 16,
                onPressed: () => notifier.clearPhoneClipboard(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 150),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x0DFFFFFF),
              borderRadius: BorderRadius.circular(_Theme.radiusSm),
              border: Border.all(
                color: _Theme.neonAmber.withOpacity(0.15),
              ),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                state.phoneClipboard!,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: _Theme.textPrimary,
                  fontFamily: 'monospace',
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _OutlineNeonButton(
                icon: Icons.copy_rounded,
                label: '复制',
                color: _Theme.neonCyan,
                onPressed: () {
                  notifier.copyToClipboard(state.phoneClipboard!);
                  _showSnack('已复制到本机剪贴板');
                },
              ),
              const SizedBox(width: 10),
              _OutlineNeonButton(
                icon: Icons.content_paste_rounded,
                label: '粘贴到输入框',
                color: _Theme.neonAmber,
                onPressed: () => _showPasteDialog(state.phoneClipboard!),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  移动端：连接表单
  // ═══════════════════════════════════════════════════════════

  Widget _buildConnectionSection(
    ClipboardSyncState state,
    ClipboardSyncNotifier notifier,
  ) {
    return _GlassCard(
      borderColor: state.connectedHost != null
          ? _Theme.neonGreen.withOpacity(0.25)
          : _Theme.neonPurple.withOpacity(0.25),
      glowColor: state.connectedHost != null ? _Theme.neonGreen.withOpacity(0.06) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _NeonIcon(icon: Icons.lan, size: 22, color: _Theme.neonPurple),
              const SizedBox(width: 10),
              const Text(
                '连接桌面端',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: _Theme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '输入桌面端显示的 IP 地址或扫码连接',
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
                  enabled: state.connectedHost == null,
                ),
              ),
              if (state.connectedHost == null) ...[
                const SizedBox(width: 8),
                // 扫码按钮
                _GlassIconButton(
                  icon: Icons.qr_code_scanner_rounded,
                  size: 22,
                  onPressed: () => _scanQrCode(notifier),
                ),
                const SizedBox(width: 8),
                _GradientButton(
                  gradient: _Theme.gradientCyan,
                  icon: state.isLoading
                      ? null
                      : Icons.link_rounded,
                  label: state.isLoading ? '连接中' : '连接',
                  compact: true,
                  loading: state.isLoading,
                  onPressed: state.isLoading
                      ? null
                      : () => _connect(notifier),
                ),
              ] else
                _GradientButton(
                  gradient: _Theme.gradientRose,
                  icon: Icons.link_off_rounded,
                  label: '断开',
                  compact: true,
                  onPressed: () => notifier.disconnect(),
                ),
            ],
          ),

          if (state.connectedHost != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _Theme.neonGreen.withOpacity(0.08),
                borderRadius: BorderRadius.circular(_Theme.radiusSm),
                border: Border.all(
                  color: _Theme.neonGreen.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  const _PulseDot(
                    active: true,
                    activeColor: _Theme.neonGreen,
                    inactiveColor: _Theme.neonRose,
                    size: 8,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '已连接到 ${state.connectedHost}',
                    style: const TextStyle(
                      color: _Theme.neonGreen,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _SignalIndicator(
                  connected: state.isWsConnected,
                  pulseCtrl: state.isWsConnected ? _pulseCtrl : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.isWsConnected ? '实时推送已连接' : '实时推送断开 · 自动重连中',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: state.isWsConnected
                              ? _Theme.neonCyan
                              : _Theme.neonAmber,
                          letterSpacing: 0.3,
                        ),
                      ),
                      if (state.isWsConnected) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.notifications_active,
                                size: 12, color: _Theme.textMuted),
                            const SizedBox(width: 4),
                            const Text(
                              '后台同步 · 退到桌面仍可接收',
                              style: TextStyle(
                                fontSize: 11,
                                color: _Theme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                _GlassIconButton(
                  icon: Icons.refresh_rounded,
                  size: 18,
                  onPressed: () => notifier.refreshClipboard(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  移动端：剪贴板推送 + 自动监控
  // ═══════════════════════════════════════════════════════════

  Widget _buildMobileActions(
    ClipboardSyncState state,
    ClipboardSyncNotifier notifier,
  ) {
    return _GlassCard(
      borderColor: _Theme.neonCyan.withOpacity(0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _NeonIcon(icon: Icons.send_rounded, size: 20, color: _Theme.neonCyan),
              const SizedBox(width: 10),
              const Text(
                '手机剪贴板 → PC',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: _Theme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _GradientButton(
            gradient: _Theme.gradientCyan,
            icon: Icons.send_rounded,
            label: '推送本机剪贴板到 PC',
            onPressed: () {
              notifier.pushClipboardToDesktop();
              _showSnack('已推送到桌面端');
            },
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x0DFFFFFF),
              borderRadius: BorderRadius.circular(_Theme.radiusSm),
              border: Border.all(
                color: state.isMobileMonitoring
                    ? _Theme.neonGreen.withOpacity(0.2)
                    : Colors.white.withOpacity(0.06),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  height: 28,
                  child: Switch.adaptive(
                    value: state.isMobileMonitoring,
                    activeColor: _Theme.neonCyan,
                    activeTrackColor: _Theme.neonCyan.withOpacity(0.3),
                    onChanged: (_) => notifier.toggleMobileClipboardMonitor(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.isMobileMonitoring ? '自动推送已开启' : '自动推送已关闭',
                        style: TextStyle(
                          fontSize: 13,
                          color: state.isMobileMonitoring
                              ? _Theme.neonGreen
                              : _Theme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        state.isMobileMonitoring
                            ? '每 2 秒检测剪贴板变化，自动发送到 PC'
                            : '开启后，手机复制内容自动发送到电脑',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _Theme.textMuted,
                        ),
                      ),
                    ],
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
  //  错误提示
  // ═══════════════════════════════════════════════════════════

  Widget _buildErrorCard(
    ClipboardSyncState state,
    ClipboardSyncNotifier notifier,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _Theme.neonRose.withOpacity(0.15),
            _Theme.neonRose.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(_Theme.radiusMd),
        border: Border.all(color: _Theme.neonRose.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              color: _Theme.neonRose.withOpacity(0.9), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              state.error!,
              style: TextStyle(
                color: _Theme.neonRose.withOpacity(0.9),
                fontSize: 13,
                letterSpacing: 0.3,
              ),
            ),
          ),
          InkWell(
            onTap: () => notifier.clearError(),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close_rounded,
                  color: _Theme.neonRose.withOpacity(0.6), size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  剪贴板内容展示
  // ═══════════════════════════════════════════════════════════

  Widget _buildClipboardDisplay(
    ClipboardSyncState state,
    ClipboardSyncNotifier notifier,
    bool isDesktop,
    bool isMobile,
  ) {
    final content = isDesktop ? state.localClipboard : state.remoteClipboard;
    final isEmpty = content == null || content.isEmpty;
    final title = isDesktop ? '本机剪贴板' : 'PC 剪贴板内容';
    final accentColor = isDesktop ? _Theme.neonCyan : _Theme.neonPurple;

    return _GlassCard(
      borderColor: isEmpty
          ? _Theme.textMuted.withOpacity(0.15)
          : accentColor.withOpacity(0.25),
      glowColor: !isEmpty ? accentColor.withOpacity(0.06) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _NeonIcon(
                icon: isDesktop ? Icons.content_paste_rounded : Icons.content_paste_go_rounded,
                size: 20,
                color: accentColor,
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: accentColor,
                ),
              ),
              const Spacer(),
              if (state.isLoading && isMobile)
                _NeonSpinner(size: 16),
              if (isMobile && state.connectedHost != null)
                _GlassIconButton(
                  icon: Icons.refresh_rounded,
                  size: 18,
                  onPressed: () => notifier.refreshClipboard(),
                ),
            ],
          ),
          const SizedBox(height: 14),

          if (isEmpty)
            _buildEmptyState(
              isDesktop
                  ? Icons.content_copy_rounded
                  : state.connectedHost == null
                      ? Icons.link_off_rounded
                      : Icons.hourglass_empty_rounded,
              isDesktop
                  ? '暂未检测到剪贴板内容'
                  : state.connectedHost == null
                      ? '未连接到桌面端'
                      : '等待中',
              isDesktop
                  ? '在电脑上复制文本后将自动显示在这里'
                  : state.connectedHost == null
                      ? '连接后 PC 剪贴板内容将自动显示'
                      : 'PC 剪贴板为空，复制内容后将自动同步',
              accentColor,
            )
          else ...[
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0x0DFFFFFF),
                borderRadius: BorderRadius.circular(_Theme.radiusSm),
                border: Border.all(
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  content,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: _Theme.textPrimary,
                    fontFamily: 'monospace',
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                _OutlineNeonButton(
                  icon: Icons.copy_rounded,
                  label: '复制',
                  color: _Theme.neonCyan,
                  onPressed: () {
                    notifier.copyToClipboard(content);
                    setState(() => _showPasted = true);
                    _showSnack('已复制到本地剪贴板');
                  },
                ),
                if (isMobile && state.connectedHost != null) ...[
                  const SizedBox(width: 10),
                  _OutlineNeonButton(
                    icon: Icons.paste_rounded,
                    label: '粘贴到输入框',
                    color: _Theme.neonPurple,
                    onPressed: () => _showPasteDialog(content),
                  ),
                ],
              ],
            ),

            if (_showPasted)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 14, color: _Theme.neonGreen),
                    const SizedBox(width: 6),
                    const Text(
                      '内容已复制到系统剪贴板，长按输入框即可粘贴',
                      style: TextStyle(
                        fontSize: 12,
                        color: _Theme.neonGreen,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(
      IconData icon, String title, String subtitle, Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          _NeonIcon(icon: icon, size: 44, color: _Theme.textMuted, opacity: 0.5),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _Theme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: _Theme.textMuted,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  连接状态信息
  // ═══════════════════════════════════════════════════════════

  Widget _buildConnectedInfo(
    ClipboardSyncState state,
    ClipboardSyncNotifier notifier,
    bool isMobile,
  ) {
    return _GlassCard(
      borderColor: state.isWsConnected
          ? _Theme.neonGreen.withOpacity(0.25)
          : _Theme.neonAmber.withOpacity(0.25),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PulseDot(
                active: state.isWsConnected,
                activeColor: _Theme.neonGreen,
                inactiveColor: _Theme.neonAmber,
                pulseCtrl: state.isWsConnected ? _pulseCtrl : null,
                size: 10,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  state.isWsConnected
                      ? 'WebSocket 实时推送中'
                      : 'HTTP 降级模式',
                  style: TextStyle(
                    color: state.isWsConnected ? _Theme.neonGreen : _Theme.neonAmber,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          if (isMobile && state.isWsConnected) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.sync_rounded,
                    size: 14, color: _Theme.neonGreen.withOpacity(0.7)),
                const SizedBox(width: 6),
                const Text(
                  'PC 复制后即时同步到手机 · 无需手动刷新',
                  style: TextStyle(
                    fontSize: 12,
                    color: _Theme.textMuted,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  文件操作
  // ═══════════════════════════════════════════════════════════

  Widget _buildFileActions(
    ClipboardSyncState state,
    ClipboardSyncNotifier notifier,
  ) {
    return _GlassCard(
      borderColor: _Theme.neonCyan.withOpacity(0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _NeonIcon(icon: Icons.upload_file_rounded, size: 20, color: _Theme.neonCyan),
              const SizedBox(width: 10),
              const Text(
                '文件传输',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: _Theme.textPrimary,
                ),
              ),
              const Spacer(),
              _GlassIconButton(
                icon: Icons.refresh_rounded,
                size: 18,
                onPressed: () async {
                  await notifier.fetchFileList();
                  _showSnack('已刷新文件列表');
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          _GradientButton(
            gradient: _Theme.gradientCyan,
            icon: Icons.file_upload_rounded,
            label: '选择并上传文件',
            onPressed: () async {
              final ok = await notifier.pickAndUploadFile();
              if (ok == true) {
                final count = ref.read(clipboardSyncProvider).transferredFiles.length;
                _showSnack('文件上传成功，共 $count 个文件');
              } else if (ok == false) {
                final err = ref.read(clipboardSyncProvider).error;
                _showSnack(err ?? '上传失败，请检查文件权限');
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildUploadProgress(ClipboardSyncState state) {
    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderColor: _Theme.neonCyan.withOpacity(0.3),
      child: Row(
        children: [
          _NeonSpinner(size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '正在上传…',
                  style: TextStyle(
                    fontSize: 13,
                    color: _Theme.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: state.uploadProgress > 0 ? state.uploadProgress : null,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(_Theme.neonCyan),
                    minHeight: 3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList(
    ClipboardSyncState state,
    ClipboardSyncNotifier notifier,
  ) {
    if (state.transferredFiles.isEmpty) {
      return _GlassCard(
        borderColor: _Theme.textMuted.withOpacity(0.1),
        child: _buildEmptyState(
          Icons.folder_off_rounded,
          '暂无文件',
          '点击上方按钮选择文件上传',
          _Theme.textMuted,
        ),
      );
    }

    return _GlassCard(
      borderColor: _Theme.neonPurple.withOpacity(0.15),
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Icon(Icons.description_rounded,
                    size: 16, color: _Theme.neonPurple.withOpacity(0.7)),
                const SizedBox(width: 8),
                Text(
                  '共 ${state.transferredFiles.length} 个文件',
                  style: TextStyle(
                    fontSize: 13,
                    color: _Theme.textMuted.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // 文件列表
          ...state.transferredFiles.map(
            (file) => _buildFileItem(file, state, notifier),
          ),
        ],
      ),
    );
  }

  Widget _buildFileItem(
    FileInfo file,
    ClipboardSyncState state,
    ClipboardSyncNotifier notifier,
  ) {
    final isDownloading = state.downloadingFile == file.name;
    final sizeStr = _formatFileSize(file.size);
    final dateStr = _formatDate(file.modified);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.04)),
        ),
      ),
      child: Row(
        children: [
          // 图标
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _Theme.neonPurple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getFileIcon(file.name),
              size: 20,
              color: _Theme.neonCyan.withOpacity(0.7),
            ),
          ),
          const SizedBox(width: 12),
          // 文件名 + 元数据
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _Theme.textPrimary,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      sizeStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: _Theme.textMuted.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: _Theme.textMuted.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 操作按钮
          if (isDownloading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(_Theme.neonCyan),
              ),
            )
          else ...[
            _GlassIconButton(
              icon: Icons.download_rounded,
              size: 18,
              onPressed: () async {
                final path = await notifier.downloadFile(file.name);
                if (path != null) {
                  _showSnack('已保存到：$path');
                } else {
                  _showSnack('下载失败，请检查连接');
                }
              },
            ),
            const SizedBox(width: 4),
            _GlassIconButton(
              icon: Icons.delete_outline_rounded,
              size: 18,
              onPressed: () => _confirmDeleteFile(file, notifier),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getFileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
        return Icons.image_rounded;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
        return Icons.videocam_rounded;
      case 'mp3':
      case 'wav':
      case 'aac':
      case 'flac':
        return Icons.audiotrack_rounded;
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${date.month}/${date.day}';
  }

  void _confirmDeleteFile(FileInfo file, ClipboardSyncNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141038),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_Theme.radiusMd),
          side: BorderSide(color: _Theme.neonRose.withOpacity(0.2)),
        ),
        title: const Text(
          '确认删除',
          style: TextStyle(color: _Theme.textPrimary, letterSpacing: 0.5),
        ),
        content: Text(
          '确定要删除 "${file.name}" 吗？',
          style: const TextStyle(color: _Theme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: _Theme.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.deleteFile(file.name);
            },
            child: const Text('删除',
                style: TextStyle(color: _Theme.neonRose)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  帮助卡片
  // ═══════════════════════════════════════════════════════════

  Widget _buildHelpCard() {
    return _GlassCard(
      padding: const EdgeInsets.all(16),
      borderColor: _Theme.neonAmber.withOpacity(0.15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _NeonIcon(
                icon: Icons.tips_and_updates_rounded,
                size: 22,
                color: _Theme.neonAmber,
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
          _buildStep(
            1,
            '在电脑上打开本应用 → 自动启动剪贴板服务',
            _Theme.neonCyan,
          ),
          _buildStep(
            2,
            '记下显示的 IP 地址或扫描 QR 码',
            _Theme.neonCyan,
          ),
          _buildStep(
            3,
            '在手机上输入上方 IP 并点击"连接"，或扫码自动连接',
            _Theme.neonPurple,
          ),
          _buildStep(
            4,
            '在电脑上复制 → 手机实时收到 → 直接粘贴',
            _Theme.neonGreen,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _Theme.neonAmber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(_Theme.radiusSm),
              border: Border.all(color: _Theme.neonAmber.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                Icon(Icons.wifi_rounded, size: 16, color: _Theme.neonAmber.withOpacity(0.8)),
                const SizedBox(width: 8),
                const Text(
                  '请确保手机和电脑在同一个局域网内',
                  style: TextStyle(
                    fontSize: 12,
                    color: _Theme.neonAmber,
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

  void _connect(ClipboardSyncNotifier notifier) async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      _showSnack('请输入 IP 地址');
      return;
    }
    final ok = await notifier.connectToHost(ip);
    if (ok) {
      notifier.saveLastIp(ip);
      _showSnack('已连接到 $ip');
    }
  }

  Future<void> _scanQrCode(ClipboardSyncNotifier notifier) async {
    final ip = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );
    if (ip != null && ip.isNotEmpty) {
      _ipController.text = ip;
      _connect(notifier);
    }
  }

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
          side: BorderSide(color: _Theme.neonCyan.withOpacity(0.4)),
        ),
      ),
    );
  }

  void _showPasteDialog(String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141038),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_Theme.radiusMd),
          side: BorderSide(color: _Theme.neonCyan.withOpacity(0.2)),
        ),
        title: const Text(
          '粘贴内容',
          style: TextStyle(color: _Theme.textPrimary, letterSpacing: 0.5),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: TextEditingController(text: content),
            maxLines: 8,
            minLines: 3,
            style: const TextStyle(color: _Theme.textPrimary),
            decoration: InputDecoration(
              hintText: '内容已自动填入，可在此编辑',
              hintStyle: TextStyle(color: _Theme.textMuted),
              filled: true,
              fillColor: const Color(0x0DFFFFFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(_Theme.radiusSm),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(_Theme.radiusSm),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              '关闭',
              style: TextStyle(color: _Theme.neonCyan),
            ),
          ),
        ],
      ),
    );
  }

  void _showHelp(BuildContext context, bool isDesktop) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141038),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_Theme.radiusMd),
          side: BorderSide(color: _Theme.neonPurple.withOpacity(0.2)),
        ),
        title: ShaderMask(
          shaderCallback: (b) => _Theme.gradientCyan.createShader(b),
          child: const Text(
            '剪贴板同步说明',
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
                '通过局域网实现 PC 和 App 之间的剪贴板同步与文件传输。',
                style: TextStyle(color: _Theme.textSecondary, fontSize: 13),
              ),
              SizedBox(height: 16),
              _HelpSection(
                title: '桌面端（服务端）',
                items: [
                  '进入此页面后自动启动剪贴板服务',
                  '本机剪贴板内容通过 HTTP + WebSocket 提供',
                  '生成 QR 码供手机扫码自动连接',
                  '接收手机推送的剪贴板内容',
                  '接收手机上传的文件，提供下载',
                ],
              ),
              SizedBox(height: 14),
              _HelpSection(
                title: '移动端（客户端）',
                items: [
                  '输入 IP 地址或扫码连接桌面端',
                  '通过 WebSocket 实时接收 PC 剪贴板更新',
                  '支持将手机剪贴板推送到 PC（手动或自动）',
                  '文件传输：上传手机文件到 PC，也可下载',
                  'Android 退到后台仍可继续同步',
                ],
              ),
              SizedBox(height: 14),
              _HelpSection(
                title: '注意事项',
                items: [
                  '手机和电脑需要在同一个 WiFi 网络',
                  '剪贴板仅支持纯文本内容',
                  '文件传输通过 HTTP，适合局域网内小文件',
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
              style: TextStyle(color: _Theme.neonCyan, letterSpacing: 0.5),
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
            color: _Theme.neonCyan,
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
                Text('•  ', style: TextStyle(color: _Theme.neonPurple.withOpacity(0.6))),
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
    this.borderColor = const Color(0x1AFFFFFF),
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
              color: const Color(0x14FFFFFF),
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
    this.color = _Theme.neonCyan,
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

class _SignalIndicator extends StatelessWidget {
  final bool connected;
  final AnimationController? pulseCtrl;

  const _SignalIndicator({required this.connected, this.pulseCtrl});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 20,
      child: CustomPaint(
        painter: _SignalPainter(
          connected: connected,
          pulseCtrl: pulseCtrl,
        ),
      ),
    );
  }
}

class _SignalPainter extends CustomPainter {
  final bool connected;
  final AnimationController? pulseCtrl;

  _SignalPainter({required this.connected, this.pulseCtrl});

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
      final barHeight = size.height * (0.25 + 0.2 * i);
      final x = i * (barWidth + gap);

      Color color;
      if (!connected) {
        color = _Theme.neonRose.withOpacity(0.3);
      } else if (i == 0) {
        color = _Theme.neonCyan.withOpacity(0.4);
      } else {
        color = _Theme.neonCyan.withOpacity(0.4 + 0.15 * i);
      }

      if (connected && pulseCtrl != null && pulseCtrl!.isAnimating) {
        if (i == barCount - 1) {
          color = Color.lerp(
            _Theme.neonCyan.withOpacity(0.5),
            _Theme.neonCyan,
            pulseCtrl!.value,
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
  bool shouldRepaint(_SignalPainter old) => true;
}

// ── 霓虹文本输入框 ──

class _NeonTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool enabled;

  const _NeonTextField({
    required this.controller,
    required this.hintText,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
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
            size: 18, color: _Theme.neonPurple.withOpacity(0.7)),
        filled: true,
        fillColor: enabled
            ? const Color(0x10FFFFFF)
            : const Color(0x08FFFFFF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_Theme.radiusSm),
          borderSide: BorderSide(
            color: _Theme.neonPurple.withOpacity(0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_Theme.radiusSm),
          borderSide: BorderSide(
            color: _Theme.neonPurple.withOpacity(0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_Theme.radiusSm),
          borderSide: BorderSide(
            color: _Theme.neonCyan.withOpacity(0.5),
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_Theme.radiusSm),
          borderSide: BorderSide(
            color: Colors.white.withOpacity(0.05),
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
              color: (gradient as LinearGradient).colors.first.withOpacity(0.3),
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
          mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.center,
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

// ── 描边霓虹按钮 ──

class _OutlineNeonButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _OutlineNeonButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_Theme.radiusSm),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
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
        valueColor: const AlwaysStoppedAnimation<Color>(_Theme.neonCyan),
      ),
    );
  }
}

// ── 地址芯片 ──

class _AddressChip extends StatelessWidget {
  final String address;

  const _AddressChip({required this.address});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _Theme.neonCyan.withOpacity(0.06),
        borderRadius: BorderRadius.circular(_Theme.radiusSm),
        border: Border.all(color: _Theme.neonCyan.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link_rounded, size: 16, color: _Theme.neonCyan.withOpacity(0.8)),
          const SizedBox(width: 8),
          SelectableText(
            address,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: _Theme.neonCyan,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

// ── 动画背景 ──

class _AnimatedBg extends StatelessWidget {
  final AnimationController shimmerCtrl;
  final Widget child;

  const _AnimatedBg({
    required this.shimmerCtrl,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shimmerCtrl,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(
                  _Theme.bgStart,
                  const Color(0xFF1A1A40),
                  (shimmerCtrl.value * 0.5).clamp(0.0, 1.0),
                )!,
                Color.lerp(
                  _Theme.bgEnd,
                  const Color(0xFF0D1040),
                  (shimmerCtrl.value * 0.5).clamp(0.0, 1.0),
                )!,
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -80,
                right: -80,
                child: _buildGlow(
                  _Theme.neonCyan.withOpacity(0.04),
                  200,
                  Offset(
                    math.sin(shimmerCtrl.value * math.pi * 2) * 40,
                    math.cos(shimmerCtrl.value * math.pi * 2) * 20,
                  ),
                ),
              ),
              Positioned(
                bottom: -60,
                left: -60,
                child: _buildGlow(
                  _Theme.neonPurple.withOpacity(0.04),
                  180,
                  Offset(
                    math.cos(shimmerCtrl.value * math.pi * 2) * 30,
                    math.sin(shimmerCtrl.value * math.pi * 2) * 40,
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _GridPainter(
                    phase: shimmerCtrl.value * 0.1,
                  ),
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

  Widget _buildGlow(Color color, double size, Offset offset) {
    return Transform.translate(
      offset: offset,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: size * 2,
              spreadRadius: size * 0.5,
            ),
          ],
        ),
      ),
    );
  }
}

// ── 网格背景绘制器 ──

class _GridPainter extends CustomPainter {
  final double phase;

  _GridPainter({this.phase = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.015)
      ..strokeWidth = 0.5;

    const spacing = 48.0;
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
