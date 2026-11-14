import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencode_app/files/files_controller.dart';
import 'package:opencode_app/format.dart';
import 'package:opencode_app/pro/billing_gateway.dart';
import 'package:opencode_app/pro/pro_controller.dart';
import 'package:opencode_app/settings/settings_store.dart';
import 'package:opencode_app/storage/storage_page.dart';
import 'package:opencode_runtime/opencode_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  late FakeRuntime rt;

  const owned = BillingPurchase(
    productId: proProductId,
    purchaseToken: 'tok',
    status: BillingPurchaseStatus.purchased,
    pendingCompletePurchase: false,
  );

  setUp(() {
    rt = FakeRuntime()
      ..storage = const StorageInfo(
        npmBytes: 3 * 1024 * 1024,
        pythonBytes: 2048,
        projects: [
          ProjectSize(
            name: 'web',
            path: '/root/projects/web',
            bytes: 250 * 1024 * 1024,
          ),
          ProjectSize(
            name: 'script',
            path: '/root/projects/script',
            bytes: 900,
          ),
        ],
      );
  });

  Future<(ProController, FakeBillingGateway)> pump(
    WidgetTester tester, {
    bool isPro = true,
    FakeBillingGateway? gateway,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsStore(await SharedPreferences.getInstance());
    final g = gateway ?? FakeBillingGateway();
    if (isPro) g.purchases = const [owned];
    final pro = ProController(g, settings);
    await pro.initialize();
    addTearDown(pro.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StoragePage(runtime: rt, pro: pro),
      ),
    );
    return (pro, g);
  }

  testWidgets(
    'shows a spinner while sizes are being calculated, then the sizes',
    (tester) async {
      rt.storageGate = Completer<void>();
      await pump(tester);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Calculating storage…'), findsOneWidget);
      expect(find.text('npm cache'), findsNothing);

      rt.storageGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('3.0 MB'), findsOneWidget);
      expect(find.text('2.0 KB'), findsOneWidget);
      expect(find.text('web'), findsOneWidget);
      expect(find.text('250 MB'), findsOneWidget);
      expect(find.text('900 B'), findsOneWidget);
    },
  );

  testWidgets(
    'clearing the npm cache calls the runtime and shows the new size',
    (tester) async {
      await pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Clear').first);
      await tester.pumpAndSettle();
      expect(rt.log, contains('clearCache npm'));
      expect(rt.log, isNot(contains('clearCache python')));
      expect(find.text('Freed 3.0 MB'), findsOneWidget);
      expect(find.text('0 B'), findsOneWidget);
    },
  );

  testWidgets('Clear all caches clears both', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all caches'));
    await tester.pumpAndSettle();
    expect(rt.log.where((l) => l.startsWith('clearCache')), [
      'clearCache npm',
      'clearCache python',
    ]);
  });

  testWidgets('free shows the project lock but keeps caches usable', (
    tester,
  ) async {
    await pump(tester, isPro: false);
    await tester.pumpAndSettle();
    expect(
      find.text('Project size breakdown is a Pro feature'),
      findsOneWidget,
    );
    expect(find.text('web'), findsNothing);
    expect(find.text('250 MB'), findsNothing);
    expect(find.text('npm cache'), findsOneWidget);
    expect(find.text('3.0 MB'), findsOneWidget);
    await tester.ensureVisible(find.text('Unlock Pro'));
    await tester.tap(find.text('Unlock Pro'));
    await tester.pumpAndSettle();
    expect(find.text('Get OpenCode Pocket Pro'), findsOneWidget);
  });

  testWidgets('project sizes appear when pro is granted', (tester) async {
    final (pro, g) = await pump(tester, isPro: false);
    await tester.pumpAndSettle();
    expect(find.text('web'), findsNothing);
    g.purchases = const [owned];
    await pro.refresh();
    await tester.pumpAndSettle();
    expect(find.text('web'), findsOneWidget);
    expect(find.text('250 MB'), findsOneWidget);
  });

  test('formatBytes', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(12 * 1024 * 1024), '12 MB');
    expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
  });

  group('download from Files', () {
    late FilesController c;

    setUp(() async {
      rt.listings = {
        '/root': [
          file('report.pdf'),
          file('notes.txt'),
          file('src', isDir: true),
        ],
      };
      c = FilesController(rt);
      await c.open('/root');
    });

    test('saves each selected file to Downloads', () async {
      c.toggle('/root/report.pdf');
      c.toggle('/root/notes.txt');
      expect(c.selectionDownloadable, isTrue);
      final saved = await c.downloadSelection();
      expect(saved, 2);
      expect(rt.log.where((l) => l.startsWith('download')), [
        'download /root/report.pdf',
        'download /root/notes.txt',
      ]);
      expect(c.selection, isEmpty);
      expect(c.error, isNull);
    });

    test('folders cannot be downloaded', () {
      c.toggle('/root/src');
      expect(c.selectionDownloadable, isFalse);
      c.toggle('/root/report.pdf');
      expect(c.selectionDownloadable, isFalse);
    });

    test(
      'a failure is shown and the count only includes files saved before it',
      () async {
        rt.fileError = PlatformException(
          code: 'state',
          message: 'Saving to Downloads needs Android 10 or newer',
        );
        c.toggle('/root/report.pdf');
        final saved = await c.downloadSelection();
        expect(saved, 0);
        expect(c.error, 'Saving to Downloads needs Android 10 or newer');
      },
    );
  });
}
