import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'clipboard_sync/background_service.dart';
import 'clipboard_sync/clipboard_sync_provider.dart';
import 'home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 沉浸式状态栏（Android）
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF060B24),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // 初始化前台服务（移动端），保持后台 WebSocket 连接不中断
  if (!kIsWeb) {
    try {
      await initClipboardBackgroundService();
    } catch (_) {}
  }

  runApp(const ProviderScope(child: KopyApp()));
}

class KopyApp extends ConsumerStatefulWidget {
  const KopyApp({super.key});

  @override
  ConsumerState<KopyApp> createState() => _KopyAppState();
}

class _KopyAppState extends ConsumerState<KopyApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(clipboardSyncProvider.notifier).onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kopy',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF060B24),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF7C4DFF),
          surface: Color(0xFF0C1035),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const HomePage(),
    );
  }
}
