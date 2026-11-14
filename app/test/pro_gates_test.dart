import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencode_app/app_deps.dart';
import 'package:opencode_app/pro/billing_gateway.dart';
import 'package:opencode_app/pro/pro_controller.dart';
import 'package:opencode_app/settings/settings_store.dart';
import 'package:opencode_app/shell/home_shell.dart';
import 'package:opencode_app/shell/shell_controller.dart';
import 'package:opencode_app/terminal/terminal_tab.dart';
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
}
