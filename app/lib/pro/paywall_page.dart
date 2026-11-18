import 'dart:async';

import 'package:flutter/material.dart';

import 'billing_gateway.dart';
import 'pro_controller.dart';
import 'pro_feature.dart';

/// Full-screen lifetime Pro paywall, opened by every Pro gate.
class PaywallPage extends StatefulWidget {
  const PaywallPage({super.key, required this.pro, required this.feature});

  final ProController pro;
  final ProFeature feature;

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  late final bool _wasProOnOpen;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _wasProOnOpen = widget.pro.isPro;
  }

  bool get _owned => _wasProOnOpen && widget.pro.isPro;

  bool get _canBuy =>
      widget.pro.product != null &&
      !widget.pro.isPurchasing &&
      widget.pro.status != ProStatus.pending &&
      widget.pro.status != ProStatus.loading;

  void _close() => Navigator.of(context).pop(widget.pro.isPro);

  Future<void> _restore() async {
    await widget.pro.restore();
    if (!mounted) return;
    if (!widget.pro.isPro && widget.pro.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No purchases found on this account')),
      );
    }
  }

  void _maybeFinish() {
    if (!widget.pro.isPro || _wasProOnOpen || _finishing) return;
    _finishing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pro unlocked')));
      Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.pro,
      builder: (context, _) {
        _maybeFinish();
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _topBar(context),
                Expanded(
                  child: _owned ? _ownedBody(context) : _freeBody(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _topBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
      child: Row(
        children: [
          IconButton.outlined(
            onPressed: _close,
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close),
          ),
          const Spacer(),
          if (!_owned)
            TextButton(
              onPressed: () => unawaited(_restore()),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Restore'),
            ),
        ],
      ),
    );
  }

  Widget _ownedBody(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified, size: 48, color: scheme.primary),
            const SizedBox(height: 12),
            Text(
              'You own Pro',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Lifetime access is active on this Google account.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  /// No scroll view: the top content scales down when needed, while the price
  /// card and Unlock button stay pinned to the bottom of the screen.
  Widget _freeBody(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - 40;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: SizedBox(width: width, child: _freeTop(context)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.55,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(width: width, child: _freeBottom(context)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _freeTop(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              'assets/images/app_icon.png',
              width: 72,
              height: 72,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Get OpenCode Pocket Pro',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          widget.feature.reason,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        _comparisonTable(context),
        const SizedBox(height: 6),
        Text(
          'Background run means the server stays warm after you leave the '
          'app. A running task keeps it alive.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _freeBottom(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final product = widget.pro.product;
    final unavailable =
        widget.pro.status != ProStatus.loading && product == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _priceCard(context, product: product, unavailable: unavailable),
        if (widget.pro.status == ProStatus.pending) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Payment pending — Google will confirm shortly.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
        if (widget.pro.error != null && product != null) ...[
          const SizedBox(height: 8),
          _errorRow(context, widget.pro.error!),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _canBuy ? () => unawaited(widget.pro.buy()) : null,
            child: widget.pro.isPurchasing
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      const Text('Opening Google Play…'),
                    ],
                  )
                : const Text('Unlock Pro'),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'One-time purchase. No subscription. Restore anytime.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _comparisonTable(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      color: muted,
      fontWeight: FontWeight.w600,
    );

    Widget header(String label) => Text(label, style: headerStyle);
    Widget check(Color color) => Icon(Icons.check, size: 15, color: color);
    Widget dash(Color color) => Text('—', style: TextStyle(color: color));
    Widget value(String text) => Text(
      text,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
    );

    Widget row(String label, {required Widget free, required Widget pro}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
              ),
            ),
            Expanded(flex: 1, child: Center(child: free)),
            Expanded(flex: 1, child: Center(child: pro)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(flex: 3, child: header('Features')),
            Expanded(flex: 1, child: Center(child: header('Free'))),
            Expanded(flex: 1, child: Center(child: header('Pro'))),
          ],
        ),
        Divider(height: 8, color: scheme.outlineVariant),
        row(
          'Chat, files and editor',
          free: check(muted),
          pro: check(scheme.primary),
        ),
        row('Terminal', free: dash(muted), pro: check(scheme.primary)),
        row(
          'Save to Downloads / export',
          free: dash(muted),
          pro: check(scheme.primary),
        ),
        row(
          'Project size breakdown',
          free: dash(muted),
          pro: check(scheme.primary),
        ),
        row(
          'Background run (idle)',
          free: value('5 min'),
          pro: value('Up to 60 min'),
        ),
        row(
          'Build tools and cache clearing',
          free: check(muted),
          pro: check(scheme.primary),
        ),
      ],
    );
  }

  Widget _priceCard(
    BuildContext context, {
    required BillingProduct? product,
    required bool unavailable,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.primary, width: 2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: unavailable
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(
                    "Pro isn't available right now.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton(
                    onPressed: () => unawaited(widget.pro.refresh()),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                children: [
                  Text(
                    'Lifetime',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (widget.pro.status == ProStatus.loading)
                    Text(
                      'Loading price…',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else
                    Text(
                      product!.price,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    'one-time',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _founderChip(context),
                      _discountChip(context),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Lifetime access. No subscription.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _founderChip(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        'Founder price',
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _discountChip(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '50% OFF',
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _errorRow(BuildContext context, String message) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: scheme.error, fontSize: 12),
          ),
        ),
        TextButton(
          onPressed: () => unawaited(widget.pro.refresh()),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          child: const Text('Retry'),
        ),
      ],
    );
  }
}

/// Refreshes the entitlement, then opens the paywall.
///
/// Returns `true` when the user owns Pro at close or completes a purchase, and
/// `false` on a free close.
Future<bool> showPaywall(
  BuildContext context,
  ProController pro,
  ProFeature feature,
) async {
  try {
    await pro.initialize();
    await pro.refresh();
  } catch (e) {
    // Billing failures must never block the gate; the page renders the error state.
    debugPrint('Billing refresh failed: $e');
  }
  if (!context.mounted) return false;
  return await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PaywallPage(pro: pro, feature: feature),
        ),
      ) ??
      pro.isPro;
}
