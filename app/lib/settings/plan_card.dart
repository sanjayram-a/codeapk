import 'dart:async';

import 'package:flutter/material.dart';

import '../pro/paywall_page.dart';
import '../pro/pro_controller.dart';
import '../pro/pro_feature.dart';

/// Settings card that shows the current plan and the one-time unlock.
class PlanCard extends StatelessWidget {
  const PlanCard({super.key, required this.pro});

  final ProController pro;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pro,
      builder: (context, _) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final isPro = pro.isPro;
        final title = isPro
            ? 'Pro — lifetime'
            : switch (pro.status) {
                ProStatus.free => 'Free plan',
                ProStatus.pending => 'Payment pending',
                ProStatus.loading => 'Checking your purchase…',
                ProStatus.pro => 'Pro — lifetime',
                ProStatus.error => 'Could not check your purchase',
              };
        final subtitle = isPro
            ? 'All features unlocked. Purchased on this Google account.'
            : switch (pro.status) {
                ProStatus.free =>
                  '5-minute background idle run. Terminal, save/export and '
                      'project sizes are Pro.',
                ProStatus.pending =>
                  'Google will confirm shortly. Pro unlocks automatically.',
                ProStatus.error => 'Check your connection and try again.',
                ProStatus.loading || ProStatus.pro => '',
              };

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPro ? Icons.verified : Icons.workspace_premium,
                        size: 22,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'OpenCode Pocket Pro',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            if (!isPro && pro.status == ProStatus.free) ...[
                              const SizedBox(height: 4),
                              Text(
                                'One-time purchase. No subscription.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (!isPro && pro.status == ProStatus.free) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Founder price',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        pro.product == null
                            ? 'Price unavailable'
                            : '${pro.product!.price} · one-time',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                if (isPro)
                  TextButton(
                    onPressed: pro.isPurchasing
                        ? null
                        : () => unawaited(pro.restore()),
                    child: const Text('Restore purchases'),
                  )
                else if (pro.status == ProStatus.pending)
                  TextButton(
                    onPressed: () => unawaited(pro.refresh()),
                    child: const Text('Refresh status'),
                  )
                else if (pro.status == ProStatus.loading ||
                    pro.status == ProStatus.error)
                  TextButton(
                    onPressed: () => unawaited(pro.refresh()),
                    child: const Text('Retry'),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: () => unawaited(
                        showPaywall(context, pro, ProFeature.generic),
                      ),
                      child: const Text('Unlock lifetime Pro'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
