import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'billing_gateway.dart';

/// Play Billing implementation of [BillingGateway].
///
/// This is the only production file that imports `in_app_purchase` or
/// `in_app_purchase_android`.
class PlayBillingGateway implements BillingGateway {
  final InAppPurchase _iap = InAppPurchase.instance;
  final Map<String, ProductDetails> _products = {};
  final Map<String, PurchaseDetails> _purchases = {};

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Stream<BillingPurchase> get purchaseStream =>
      _iap.purchaseStream.expand((purchases) => purchases).map((purchase) {
        _purchases[_purchaseKey(purchase)] = purchase;
        return _mapPurchase(purchase);
      });

  @override
  Future<List<BillingProduct>> queryProducts(Set<String> productIds) async {
    final response = await _iap.queryProductDetails(productIds);
    final error = response.error;
    if (error != null) {
      throw BillingException(error.message);
    }
    for (final product in response.productDetails) {
      _products[product.id] = product;
    }
    return [
      for (final product in response.productDetails) _mapProduct(product),
    ];
  }

  @override
  Future<List<BillingPurchase>> queryPurchases() async {
    // The Android addition reports owned one-time products, which excludes
    // refunded purchases. It is null when Play Billing is unavailable.
    final addition = _iap
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition?>();
    if (addition == null) {
      throw const BillingException(
        'Google Play is not available on this device.',
      );
    }
    final response = await addition.queryPastPurchases();
    final error = response.error;
    if (error != null) {
      throw BillingException(error.message);
    }
    for (final purchase in response.pastPurchases) {
      _purchases[_purchaseKey(purchase)] = purchase;
    }
    return [
      for (final purchase in response.pastPurchases) _mapPurchase(purchase),
    ];
  }

  @override
  Future<void> buy(String productId) async {
    var product = _products[productId];
    if (product == null) {
      // The controller normally loads the product first; re-query so a cold
      // buy still opens Play instead of failing on a missing cache entry.
      await queryProducts({productId});
      product = _products[productId];
    }
    if (product == null) {
      throw const BillingException('Product not found');
    }
    final started = await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
    if (!started) {
      throw const BillingException('Could not open Google Play');
    }
  }

  @override
  Future<void> acknowledge(String purchaseToken) async {
    final purchase = _purchases[purchaseToken];
    if (purchase == null) {
      throw const BillingException('Purchase not found');
    }
    try {
      // `completePurchase` returns void and throws when the purchase cannot be
      // finished; the controller only needs to know whether it worked.
      await _iap.completePurchase(purchase);
    } on Exception {
      throw const BillingException('Could not acknowledge purchase');
    }
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  Future<void> dispose() async {
    _products.clear();
    _purchases.clear();
  }

  String _purchaseKey(PurchaseDetails purchase) =>
      purchase.purchaseID ?? purchase.productID;

  BillingProduct _mapProduct(ProductDetails product) => BillingProduct(
    id: product.id,
    title: product.title,
    description: product.description,
    price: product.price,
    rawPrice: product.rawPrice,
    currencyCode: product.currencyCode,
  );

  BillingPurchase _mapPurchase(PurchaseDetails purchase) => BillingPurchase(
    productId: purchase.productID,
    purchaseToken: _purchaseKey(purchase),
    status: mapPurchaseStatus(purchase.status),
    pendingCompletePurchase: purchase.pendingCompletePurchase,
    error: purchase.error?.message,
  );
}

/// Maps Play's [PurchaseStatus] onto the app's [BillingPurchaseStatus].
///
/// The switch is exhaustive on purpose: a new Play status must fail to
/// compile here rather than silently lose an entitlement transition.
@visibleForTesting
BillingPurchaseStatus mapPurchaseStatus(PurchaseStatus status) =>
    switch (status) {
      PurchaseStatus.purchased => BillingPurchaseStatus.purchased,
      PurchaseStatus.pending => BillingPurchaseStatus.pending,
      PurchaseStatus.restored => BillingPurchaseStatus.restored,
      PurchaseStatus.canceled => BillingPurchaseStatus.canceled,
      PurchaseStatus.error => BillingPurchaseStatus.error,
    };
