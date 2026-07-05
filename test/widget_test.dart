import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kopy/clipboard_sync/clipboard_sync_provider.dart';
import 'package:kopy/clipboard_sync/clipboard_sync_service.dart';
import 'package:kopy/main.dart';

void main() {
  testWidgets('Kopy home renders feature entries', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clipboardSyncProvider.overrideWith(
            (ref) => ClipboardSyncNotifier(
              ClipboardSyncService(),
              autoStartServer: false,
            ),
          ),
        ],
        child: const KopyApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Kopy'), findsOneWidget);
    expect(find.text('剪贴板同步'), findsOneWidget);
    expect(find.text('文件互传'), findsOneWidget);
  });
}
