import 'dart:async';

import 'package:flutter/foundation.dart';

import '../settings/settings_store.dart';
import 'billing_gateway.dart';

enum ProStatus { loading, free, pro, pending, error }

/// Local entitlement state machine for the one-time lifetime Pro purchase.
///
/// Entitlement is cached in [SettingsStore] (`pro_owned` plus
/// `pro_last_verified_at`) and treated as valid for seven days offline.
class ProController extends ChangeNotifier {
  ProController(BillingGateway gateway, SettingsStore settings)
      : _gateway = gateway,
        _settings = settings,
        _lastVerifiedAt = settings.proLastVerifiedAt {
    _owned = settings.proOwned && _withinGrace();
    _status = _owned ? ProStatus.pro : ProStatus.loading;
  }

  final BillingGateway _gateway;
  final SettingsStore _settings;

  StreamSubscription<BillingPurchase>? _subscription;
  Future<void>? _initFuture;
  Future<void>? _refreshFuture;

  bool _owned = false;
  ProStatus _status = ProStatus.loading;
  BillingProduct? _product;
  String? _error;
  bool _purchasing = false;
  DateTime? _lastVerifiedAt;
  int _generation = 0;
  bool _disposed = false;

  bool get isPro => _owned;
  ProStatus get status => _status;
  BillingProduct? get product => _product;
  String? get error => _error;
  bool get isPurchasing => _purchasing;

  Future<void> initialize() => _initFuture ??= _initialize();

  Future<void> _initialize() async {
    // Subscribe before the first await so a purchase emitted right after
    // construction is not lost.
    _subscription = _gateway.purchaseStream.listen(
      _onPurchase,
      onError: _onPurchaseStreamError,
    );

    try {
      final available = await _gateway.isAvailable();
      if (!available) {
        _error = 'Google Play is not available on this device.';
        if (_owned && _withinGrace()) {
          _status = ProStatus.pro;
        } else {
          _owned = false;
          _status = ProStatus.error;
        }
        _notify();
        return;
      }
    } catch (e) {
      _error = _message(e);
      if (_owned && _withinGrace()) {
        _status = ProStatus.pro;
      } else {
        _owned = false;
        _status = ProStatus.error;
      }
      _notify();
      return;
    }

    await refresh();
  }

  /// Single-flight while a refresh is in progress, but never cached after it
  /// finishes, so later resume/Settings/paywall refreshes query again.
  Future<void> refresh() {
    final inFlight = _refreshFuture;
    if (inFlight != null) return inFlight;
    return _refreshFuture = _refresh().whenComplete(() {
      _refreshFuture = null;
    });
  }

  Future<void> _refresh() async {
    final generation = _generation;

    BillingProduct? product;
    String? productError;
    try {
      final products = await _gateway.queryProducts({proProductId});
      product = products.isEmpty ? null : products.first;
    } catch (e) {
      productError = _message(e);
    }

    List<BillingPurchase> purchases;
    try {
      purchases = await _gateway.queryPurchases();
    } catch (e) {
      if (_generation != generation) return;
      _product = product;
      _error = _message(e);
      if (_owned && _withinGrace()) {
        _status = ProStatus.pro;
      } else {
        _owned = false;
        _status = ProStatus.error;
      }
      _notify();
      return;
    }

    // A purchase event during either query owns the state now.
    if (_generation != generation) return;

    _product = product;
    _stampVerified(DateTime.now());

    final purchased = purchases.any(
      (p) =>
          p.productId == proProductId &&
          (p.status == BillingPurchaseStatus.purchased ||
              p.status == BillingPurchaseStatus.restored),
    );
    final pending = purchases.any(
      (p) =>
          p.productId == proProductId &&
          p.status == BillingPurchaseStatus.pending,
    );

    _setOwned(purchased);
    if (purchased) {
      _status = ProStatus.pro;
    } else if (pending) {
      _status = ProStatus.pending;
    } else {
      _status = ProStatus.free;
    }

    String? acknowledgeError;
    for (final purchase in purchases) {
      if (purchase.productId != proProductId) continue;
      if (purchase.status != BillingPurchaseStatus.purchased &&
          purchase.status != BillingPurchaseStatus.restored) {
        continue;
      }
      if (!purchase.pendingCompletePurchase) continue;
      try {
        await _gateway.acknowledge(purchase.purchaseToken);
      } catch (e) {
        acknowledgeError = _message(e);
      }
    }

    if (_generation != generation) return;
    _error = productError ?? acknowledgeError;
    _notify();
  }

  void _onPurchase(BillingPurchase purchase) {
    if (purchase.productId != proProductId) return;
    _generation++;
    _purchasing = false;

    switch (purchase.status) {
      case BillingPurchaseStatus.purchased:
      case BillingPurchaseStatus.restored:
        _setOwned(true);
        final now = DateTime.now();
        _stampVerified(now);
        _error = null;
        _status = ProStatus.pro;
        _notify();
        if (purchase.pendingCompletePurchase) {
          unawaited(_acknowledge(purchase.purchaseToken));
        }
      case BillingPurchaseStatus.pending:
        _error = null;
        _status = ProStatus.pending;
        _notify();
      case BillingPurchaseStatus.canceled:
        _error = null;
        _status = _owned ? ProStatus.pro : ProStatus.free;
        _notify();
      case BillingPurchaseStatus.error:
        _error = purchase.error ?? 'Purchase failed.';
        _status = _owned ? ProStatus.pro : ProStatus.error;
        _notify();
    }
  }

  Future<void> _acknowledge(String purchaseToken) async {
    try {
      await _gateway.acknowledge(purchaseToken);
    } catch (e) {
      _error = _message(e);
      _notify();
    }
  }

  void _onPurchaseStreamError(Object error) {
    _error = _message(error);
    if (!_owned) {
      _status = ProStatus.error;
    }
    _notify();
  }

  Future<void> buy() async {
    if (_owned || _purchasing) return;
    final product = _product;
    if (product == null) {
      _error = "Pro isn't available right now.";
      _status = ProStatus.error;
      _notify();
      return;
    }

    _purchasing = true;
    _notify();
    try {
      await _gateway.buy(product.id);
    } catch (e) {
      _error = _message(e);
      if (!_owned) {
        _status = ProStatus.error;
      }
      _purchasing = false;
      _notify();
    }
  }

  Future<void> restore() async {
    if (_purchasing) return;
    _purchasing = true;
    _notify();
    try {
      await _gateway.restore();
      await refresh();
    } catch (e) {
      _error = _message(e);
      if (!_owned) {
        _status = ProStatus.error;
      }
    } finally {
      _purchasing = false;
      _notify();
    }
  }

  bool _withinGrace() {
    final last = _lastVerifiedAt;
    if (last == null) return false;
    return DateTime.now().difference(last) <= const Duration(days: 7);
  }

  void _setOwned(bool value) {
    _owned = value;
    unawaited(_settings.setProOwned(value));
  }

  void _stampVerified(DateTime value) {
    _lastVerifiedAt = value;
    unawaited(_settings.setProLastVerifiedAt(value));
  }

  String _message(Object error) => error.toString();

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_subscription?.cancel());
    unawaited(_gateway.dispose());
    super.dispose();
  }
}
