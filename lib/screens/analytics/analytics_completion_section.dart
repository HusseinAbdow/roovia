import 'package:flutter/material.dart';

import '../../models/financial_analytics.dart';
import 'analytics_shared.dart';

class AnalyticsCompletionSection extends StatelessWidget {
  final CompletionStats stats;
  final String Function(double) formatPercent;

  const AnalyticsCompletionSection({super.key, required this.stats, required this.formatPercent});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProgressRow(
          label: 'Bill completion',
          value: formatPercent(stats.completionRate * 100),
          progress: stats.completionRate,
        ),
        const SizedBox(height: 10),
        _ProgressRow(
          label: 'Participant payments confirmed',
          value: formatPercent(stats.participantPaymentRate * 100),
          progress: stats.participantPaymentRate,
        ),
        const SizedBox(height: 12),
        Text(
          stats.averageSettlementDays == null
              ? 'Average settlement time is not available yet.'
              : 'Average settlement time: ${stats.averageSettlementDays} day${stats.averageSettlementDays == 1 ? '' : 's'}',
          style: TextStyle(
            color: kAnalyticsDarkGreen.withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String label;
  final String value;
  final double progress;

  const _ProgressRow({required this.label, required this.value, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: kAnalyticsDarkGreen,
                fontSize: 13,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: kAnalyticsDarkGreen,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress.isNaN ? 0 : progress.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
            valueColor: const AlwaysStoppedAnimation<Color>(kAnalyticsDarkGreen),
          ),
        ),
      ],
    );
  }
}
