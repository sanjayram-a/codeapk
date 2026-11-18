import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:opencode_app/pro/billing_gateway.dart';
import 'package:opencode_app/pro/play_billing_gateway.dart';

void main() {
  test('maps every Play purchase status', () {
    expect(
      mapPurchaseStatus(PurchaseStatus.purchased),
      BillingPurchaseStatus.purchased,
    );
    expect(
      mapPurchaseStatus(PurchaseStatus.pending),
      BillingPurchaseStatus.pending,
    );
    expect(
      mapPurchaseStatus(PurchaseStatus.restored),
      BillingPurchaseStatus.restored,
    );
    expect(
      mapPurchaseStatus(PurchaseStatus.canceled),
      BillingPurchaseStatus.canceled,
    );
    expect(
      mapPurchaseStatus(PurchaseStatus.error),
      BillingPurchaseStatus.error,
    );
  });
}
