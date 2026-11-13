const proProductId = 'pro_lifetime';

class BillingProduct {
  const BillingProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.rawPrice,
    required this.currencyCode,
  });
  final String id;
  final String title;
  final String description;
  final String price; // Play's localized, formatted price, e.g. "₹999.00"
  final double rawPrice;
  final String currencyCode;
}

enum BillingPurchaseStatus { purchased, pending, restored, canceled, error }

class BillingPurchase {
  const BillingPurchase({
    required this.productId,
    required this.purchaseToken,
    required this.status,
    required this.pendingCompletePurchase,
    this.error,
  });
  final String productId;
  final String purchaseToken;
  final BillingPurchaseStatus status;
  final bool pendingCompletePurchase;
  final String? error;
}

class BillingException implements Exception {
  const BillingException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class BillingGateway {
  Future<bool> isAvailable();
  Stream<BillingPurchase> get purchaseStream;
  Future<List<BillingProduct>> queryProducts(Set<String> productIds);
  Future<List<BillingPurchase>> queryPurchases();
  Future<void> buy(String productId);
  Future<void> acknowledge(String purchaseToken);
  Future<void> restore();
  Future<void> dispose();
}
