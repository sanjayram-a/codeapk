import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:opencode_app/pro/billing_gateway.dart';
import 'package:opencode_app/pro/pro_controller.dart';
import 'package:opencode_app/settings/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SettingsStore> settings() async =>
      SettingsStore(await SharedPreferences.getInstance());

  const owned = BillingPurchase(
    productId: proProductId,
    purchaseToken: 'tok-1',
    status: BillingPurchaseStatus.purchased,
    pendingCompletePurchase: true,
  );

  test('starts loading and loads the price after initialize', () async {
    final pro = ProController(FakeBillingGateway(), await settings());
    expect(pro.status, ProStatus.loading);
    expect(pro.product, isNull);
    await pro.initialize();
    expect(pro.status, ProStatus.free);
    expect(pro.product?.price, '₹999');
  });

  test('no purchase -> free and the price is loaded', () async {
    final g = FakeBillingGateway();
    final pro = ProController(g, await settings());
    await pro.initialize();
    expect(pro.isPro, isFalse);
    expect(pro.status, ProStatus.free);
    expect(pro.product?.price, '₹999');
    expect(g.queryProductCalls, 1);
  });

  test('cached pro survives a failed query inside the grace period', () async {
    SharedPreferences.setMockInitialValues({
      'pro_owned': true,
      'pro_last_verified_at': DateTime.now()
          .subtract(const Duration(days: 2))
          .millisecondsSinceEpoch,
    });
    final g = FakeBillingGateway()
      ..queryError = const BillingException('offline');
    final pro = ProController(g, await settings());
    await pro.initialize();
    expect(pro.isPro, isTrue);
    expect(pro.status, ProStatus.pro);
    expect(pro.error, 'offline');
  });

  test('a successful empty query revokes cached pro', () async {
    SharedPreferences.setMockInitialValues({
      'pro_owned': true,
      'pro_last_verified_at': DateTime.now().millisecondsSinceEpoch,
    });
    final pro = ProController(FakeBillingGateway(), await settings());
    await pro.initialize();
    expect(pro.isPro, isFalse);
    expect(pro.status, ProStatus.free);
  });

  test('after seven days offline, cached pro is dropped', () async {
    SharedPreferences.setMockInitialValues({
      'pro_owned': true,
      'pro_last_verified_at': DateTime.now()
          .subtract(const Duration(days: 8))
          .millisecondsSinceEpoch,
    });
    final g = FakeBillingGateway()
      ..queryError = const BillingException('offline');
    final pro = ProController(g, await settings());
    await pro.initialize();
    expect(pro.isPro, isFalse);
    expect(pro.status, ProStatus.error);
  });

  test('purchased grants pro and acknowledges', () async {
    final g = FakeBillingGateway();
    final pro = ProController(g, await settings());
    await pro.initialize();
    g.emit(owned);
    await pumpEventQueue();
    expect(pro.isPro, isTrue);
    expect(pro.status, ProStatus.pro);
    expect(g.acknowledged, ['tok-1']);
  });

  test('pending does not grant pro', () async {
    final g = FakeBillingGateway();
    final pro = ProController(g, await settings());
    await pro.initialize();
    g.emit(const BillingPurchase(
      productId: proProductId,
      purchaseToken: 'tok-2',
      status: BillingPurchaseStatus.pending,
      pendingCompletePurchase: false,
    ));
    await pumpEventQueue();
    expect(pro.isPro, isFalse);
    expect(pro.status, ProStatus.pending);
  });

  test('a purchase during a slow query is not revoked', () async {
    final g = FakeBillingGateway()..purchasesGate = Completer<void>();
    final pro = ProController(g, await settings());
    final init = pro.initialize();
    await pumpEventQueue(); // let the slow purchase query start
    g.emit(owned);
    await pumpEventQueue();
    g.purchasesGate!.complete();
    await init;
    expect(pro.isPro, isTrue);
    expect(pro.status, ProStatus.pro);
  });

  test('restore adopts an owned purchase', () async {
    final g = FakeBillingGateway();
    final pro = ProController(g, await settings());
    await pro.initialize();
    expect(pro.isPro, isFalse);
    g.purchases = [owned];
    await pro.restore();
    expect(pro.isPro, isTrue);
    expect(g.restoreCalls, 1);
  });

  test('buy without a product is a clear error', () async {
    final g = FakeBillingGateway()..product = null;
    final pro = ProController(g, await settings());
    await pro.initialize();
    await pro.buy();
    expect(pro.status, ProStatus.error);
    expect(pro.error, "Pro isn't available right now.");
  });

  test('buy forwards the product id', () async {
    final g = FakeBillingGateway();
    final pro = ProController(g, await settings());
    await pro.initialize();
    await pro.buy();
    expect(g.bought, [proProductId]);
  });

  test('billing unavailable keeps cached pro inside grace', () async {
    SharedPreferences.setMockInitialValues({
      'pro_owned': true,
      'pro_last_verified_at': DateTime.now().millisecondsSinceEpoch,
    });
    final g = FakeBillingGateway()..available = false;
    final pro = ProController(g, await settings());
    await pro.initialize();
    expect(pro.isPro, isTrue);
    expect(pro.status, ProStatus.pro);
  });

  test('a canceled purchase returns to free', () async {
    final g = FakeBillingGateway();
    final pro = ProController(g, await settings());
    await pro.initialize();
    g.emit(const BillingPurchase(
      productId: proProductId,
      purchaseToken: 'tok-3',
      status: BillingPurchaseStatus.canceled,
      pendingCompletePurchase: false,
    ));
    await pumpEventQueue();
    expect(pro.isPro, isFalse);
    expect(pro.status, ProStatus.free);
  });

  test('a purchase error surfaces and does not grant', () async {
    final g = FakeBillingGateway();
    final pro = ProController(g, await settings());
    await pro.initialize();
    g.emit(const BillingPurchase(
      productId: proProductId,
      purchaseToken: 'tok-4',
      status: BillingPurchaseStatus.error,
      pendingCompletePurchase: false,
      error: 'declined',
    ));
    await pumpEventQueue();
    expect(pro.isPro, isFalse);
    expect(pro.status, ProStatus.error);
    expect(pro.error, 'declined');
  });

  test('a purchase for another product is ignored', () async {
    final g = FakeBillingGateway();
    final pro = ProController(g, await settings());
    await pro.initialize();
    g.emit(const BillingPurchase(
      productId: 'other',
      purchaseToken: 'tok-5',
      status: BillingPurchaseStatus.purchased,
      pendingCompletePurchase: true,
    ));
    await pumpEventQueue();
    expect(pro.isPro, isFalse);
    expect(g.acknowledged, isEmpty);
  });

  test('acknowledgement failure keeps pro and reports an error', () async {
    final g = FakeBillingGateway()
      ..acknowledgeError = const BillingException('ack failed');
    final pro = ProController(g, await settings());
    await pro.initialize();
    g.emit(owned);
    await pumpEventQueue();
    expect(pro.isPro, isTrue);
    expect(pro.status, ProStatus.pro);
    expect(pro.error, 'ack failed');
  });

  test('a stream error clears the purchasing lockout', () async {
    final g = FakeBillingGateway();
    final pro = ProController(g, await settings());
    await pro.initialize();
    await pro.buy();
    expect(pro.isPurchasing, isTrue);
    expect(g.buyCalls, 1);

    g.emitError(const BillingException('stream failed'));
    await pumpEventQueue();

    expect(pro.isPurchasing, isFalse);
    expect(pro.isPro, isFalse);
    expect(pro.error, 'stream failed');
    await pro.buy();
    expect(g.buyCalls, 2);
  });

  test('a stream error does not revoke cached pro', () async {
    SharedPreferences.setMockInitialValues({
      'pro_owned': true,
      'pro_last_verified_at': DateTime.now().millisecondsSinceEpoch,
    });
    final g = FakeBillingGateway()..available = false;
    final pro = ProController(g, await settings());
    await pro.initialize();
    expect(pro.isPro, isTrue);

    g.emitError(const BillingException('stream failed'));
    await pumpEventQueue();

    expect(pro.isPro, isTrue);
    expect(pro.error, 'stream failed');
  });
}
