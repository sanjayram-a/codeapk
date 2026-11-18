import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencode_app/pro/billing_gateway.dart';
import 'package:opencode_app/pro/paywall_page.dart';
import 'package:opencode_app/pro/pro_controller.dart';
import 'package:opencode_app/pro/pro_feature.dart';
import 'package:opencode_app/settings/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const _product = BillingProduct(
  id: proProductId,
  title: 'OpenCode Pocket Pro',
  description: 'Lifetime Pro',
  price: '₹999',
  rawPrice: 999,
  currencyCode: 'INR',
);

const _owned = BillingPurchase(
  productId: proProductId,
  purchaseToken: 'tok-1',
  status: BillingPurchaseStatus.purchased,
  pendingCompletePurchase: true,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(ProController, FakeBillingGateway)> make({
    bool owned = false,
    BillingProduct? product = _product,
  }) async {
    final g = FakeBillingGateway()..product = product;
    if (owned) g.purchases = [_owned];
    final pro = ProController(
      g,
      SettingsStore(await SharedPreferences.getInstance()),
    );
    await pro.initialize();
    return (pro, g);
  }

  Widget host(ProController pro) => MaterialApp(
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF3F6BE0),
      useMaterial3: true,
    ),
    home: PaywallPage(pro: pro, feature: ProFeature.terminal),
  );

  testWidgets('free paywall shows the reference layout', (tester) async {
    final (pro, _) = await make();
    await tester.pumpWidget(host(pro));
    await tester.pumpAndSettle();
    expect(find.text('Get OpenCode Pocket Pro'), findsOneWidget);
    expect(find.text('Terminal is a Pro feature.'), findsOneWidget);
    expect(find.text('Founder price'), findsOneWidget);
    expect(find.text('50% OFF'), findsOneWidget);
    expect(find.text('₹999'), findsOneWidget);
    expect(find.text('Lifetime'), findsOneWidget);
    expect(find.text('Unlock Pro'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);
    expect(find.text('Chat, files and editor'), findsOneWidget);
    expect(find.text('Build tools and cache clearing'), findsOneWidget);
  });

  testWidgets('fits small phones without scrolling', (tester) async {
    addTearDown(tester.view.reset);
    final (pro, _) = await make();
    for (final size in [const Size(360, 640), const Size(320, 568)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(host(pro));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.text('Get OpenCode Pocket Pro'), findsOneWidget);
      expect(find.text('Unlock Pro'), findsOneWidget);
      expect(
        find.text('One-time purchase. No subscription. Restore anytime.'),
        findsOneWidget,
      );
      expect(
        tester.getBottomLeft(find.text('Unlock Pro')).dy,
        greaterThan(size.height * 0.75),
      );
      expect(
        tester.getTopLeft(find.text('₹999')).dy,
        greaterThan(size.height * 0.5),
      );
    }
  });

  testWidgets('buy forwards the product id', (tester) async {
    final (pro, g) = await make();
    await tester.pumpWidget(host(pro));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Unlock Pro'));
    await tester.tap(find.text('Unlock Pro'));
    await tester.pump();
    expect(g.bought, [proProductId]);
  });

  testWidgets('loading price disables the button', (tester) async {
    final pro = ProController(
      FakeBillingGateway(),
      SettingsStore(await SharedPreferences.getInstance()),
    );
    await tester.pumpWidget(host(pro));
    await tester.pump();
    expect(find.text('Loading price…'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Unlock Pro'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('missing price is explicit, never a fake amount', (tester) async {
    final (pro, _) = await make(product: null);
    await tester.pumpWidget(host(pro));
    await tester.pumpAndSettle();
    expect(find.text("Pro isn't available right now."), findsOneWidget);
    expect(find.text('₹999'), findsNothing);
  });

  testWidgets('pending shows the pending banner', (tester) async {
    final (pro, g) = await make();
    await tester.pumpWidget(host(pro));
    await tester.pumpAndSettle();
    g.emit(
      const BillingPurchase(
        productId: proProductId,
        purchaseToken: 'p',
        status: BillingPurchaseStatus.pending,
        pendingCompletePurchase: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Payment pending'), findsOneWidget);
  });

  testWidgets('a purchase pops the paywall with true', (tester) async {
    final (pro, g) = await make();
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF3F6BE0),
          useMaterial3: true,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showPaywall(context, pro, ProFeature.generic);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    g.emit(_owned);
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.text('Get OpenCode Pocket Pro'), findsNothing);
  });

  testWidgets('already pro shows the owned state', (tester) async {
    final (pro, _) = await make(owned: true);
    await tester.pumpWidget(host(pro));
    await tester.pumpAndSettle();
    expect(find.text('You own Pro'), findsOneWidget);
    expect(find.text('Unlock Pro'), findsNothing);
    expect(find.text('Restore'), findsNothing);
  });

  testWidgets('revoking while open shows the free body', (tester) async {
    final (pro, g) = await make(owned: true);
    await tester.pumpWidget(host(pro));
    await tester.pumpAndSettle();
    expect(find.text('You own Pro'), findsOneWidget);
    g.purchases = const [];
    await pro.refresh();
    await tester.pumpAndSettle();
    expect(find.text('You own Pro'), findsNothing);
    expect(find.text('Get OpenCode Pocket Pro'), findsOneWidget);
  });

  testWidgets('restore calls the gateway', (tester) async {
    final (pro, g) = await make();
    await tester.pumpWidget(host(pro));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(g.restoreCalls, 1);
  });
}
