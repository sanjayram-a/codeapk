import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencode_app/app_deps.dart';
import 'package:opencode_app/files/file_editor_page.dart';
import 'package:opencode_app/files/files_controller.dart';
import 'package:opencode_app/files/files_tab.dart';
import 'package:opencode_app/pro/billing_gateway.dart';
import 'package:opencode_app/pro/pro_controller.dart';
import 'package:opencode_app/settings/settings_store.dart';
import 'package:opencode_app/shell/home_shell.dart';
import 'package:opencode_app/shell/shell_controller.dart';
import 'package:opencode_app/terminal/terminal_tab.dart';
import 'package:opencode_runtime/opencode_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  Future<(FakeRuntime, ProController, FakeBillingGateway)> makePro({
    bool owned = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsStore(await SharedPreferences.getInstance());
    final g = FakeBillingGateway();
    if (owned) {
      g.purchases = const [
        BillingPurchase(
          productId: proProductId,
          purchaseToken: 'tok',
          status: BillingPurchaseStatus.purchased,
          pendingCompletePurchase: false,
        ),
      ];
    }
    final pro = ProController(g, settings);
    await pro.initialize();
    return (FakeRuntime(), pro, g);
  }

  testWidgets('revoking while a PTY starts closes the new session', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsStore(await SharedPreferences.getInstance());
    final g = FakeBillingGateway()
      ..purchases = const [
        BillingPurchase(
          productId: proProductId,
          purchaseToken: 'tok',
          status: BillingPurchaseStatus.purchased,
          pendingCompletePurchase: false,
        ),
      ];
    final pro = ProController(g, settings);
    await pro.initialize();
    final rt = _GatedOpenRuntime();
    final shell = ShellController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalTab(runtime: rt, shell: shell, visible: true, pro: pro),
        ),
      ),
    );
    await tester.pump();
    // The PTY has not been created yet; revoke Pro, then let it finish.
    g.purchases = const [];
    await pro.refresh();
    expect(pro.isPro, isFalse);
    rt.gate.complete();
    await tester.pumpAndSettle();
    expect(rt.terminals, hasLength(1));
    expect(rt.terminals.single.closed, isTrue);
    expect(find.text('Terminal is a Pro feature'), findsOneWidget);
  });

  testWidgets('free terminal shows the lock and starts no PTY', (tester) async {
    final (rt, pro, _) = await makePro();
    final shell = ShellController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalTab(runtime: rt, shell: shell, visible: true, pro: pro),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Terminal is a Pro feature'), findsOneWidget);
    expect(rt.log.where((l) => l.startsWith('openTerminal')), isEmpty);
  });

  testWidgets('pro terminal opens a PTY and revoking closes it', (
    tester,
  ) async {
    final (rt, pro, g) = await makePro(owned: true);
    final shell = ShellController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalTab(runtime: rt, shell: shell, visible: true, pro: pro),
        ),
      ),
    );
    // `TerminalView` blinks its cursor, so do not use pumpAndSettle while it is mounted.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(rt.terminals, hasLength(1));
    final terminal = rt.terminals.single;

    g.purchases = const [];
    await pro.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Terminal is a Pro feature'), findsOneWidget);
    expect(terminal.closed, isTrue);
  });

  testWidgets('tapping terminal free opens the shared paywall', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsStore(await SharedPreferences.getInstance());
    final rt = FakeRuntime();
    final pro = ProController(FakeBillingGateway(), settings);
    await pro.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          deps: AppDeps(
            runtime: rt,
            settings: settings,
            pro: pro,
            apiFactory: (_, _) => FakeOpencodeApi(),
          ),
          onResetDone: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terminal'));
    await tester.pumpAndSettle();
    expect(find.text('Get OpenCode Pocket Pro'), findsOneWidget);
    expect(rt.log.where((l) => l.startsWith('openTerminal')), isEmpty);
  });

  final file = FileEntry(
    name: 'report.pdf',
    path: '/root/report.pdf',
    isDir: false,
    size: 10,
    modified: DateTime(2026),
  );

  testWidgets('free files download opens the paywall and saves nothing', (
    tester,
  ) async {
    final (rt, pro, _) = await makePro();
    rt.listings = {
      FilesController.root: [file],
    };
    final shell = ShellController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilesTab(runtime: rt, shell: shell, visible: true, pro: pro),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('report.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save to Downloads'));
    await tester.pumpAndSettle();
    expect(find.text('Get OpenCode Pocket Pro'), findsOneWidget);
    expect(rt.log, isNot(contains('download /root/report.pdf')));
  });

  testWidgets('pro files download saves the file', (tester) async {
    final (rt, pro, _) = await makePro(owned: true);
    rt.listings = {
      FilesController.root: [file],
    };
    final shell = ShellController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilesTab(runtime: rt, shell: shell, visible: true, pro: pro),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('report.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save to Downloads'));
    await tester.pumpAndSettle();
    expect(rt.log, contains('download /root/report.pdf'));
    expect(find.text('Get OpenCode Pocket Pro'), findsNothing);
  });

  testWidgets('free editor download opens the paywall', (tester) async {
    final (_, pro, _) = await makePro();
    final invalid = _InvalidReadRuntime();
    await tester.pumpWidget(
      MaterialApp(
        home: FileEditorPage(runtime: invalid, path: '/root/big.bin', pro: pro),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to Downloads'));
    await tester.pumpAndSettle();
    expect(find.text('Get OpenCode Pocket Pro'), findsOneWidget);
    expect(invalid.log, isEmpty);
  });

  testWidgets('pro editor download saves the file', (tester) async {
    final (_, pro, _) = await makePro(owned: true);
    final invalid = _InvalidReadRuntime();
    await tester.pumpWidget(
      MaterialApp(
        home: FileEditorPage(runtime: invalid, path: '/root/big.bin', pro: pro),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to Downloads'));
    await tester.pumpAndSettle();
    expect(invalid.log, contains('download /root/big.bin'));
  });
}

class _InvalidReadRuntime extends FakeRuntime {
  @override
  Future<String> readText(String path) async {
    throw PlatformException(code: 'invalid');
  }
}

class _GatedOpenRuntime extends FakeRuntime {
  final gate = Completer<void>();

  @override
  Future<TerminalSession> openTerminal({
    required int rows,
    required int cols,
    List<String>? command,
  }) async {
    await gate.future;
    return super.openTerminal(rows: rows, cols: cols, command: command);
  }
}
