import 'package:flutter/material.dart';

import '../../models/financial_analytics.dart';
import 'analytics_shared.dart';

class AnalyticsOverviewSection extends StatelessWidget {
  final AnalyticsOverview overview;
  final String Function(double) formatMoney;

  const AnalyticsOverviewSection({super.key, required this.overview, required this.formatMoney});

  @override
  Widget build(BuildContext context) {
    const surfaceGreen = Color(0xFFE9F7EE);
    const softBlue = Color(0xFFDDEDF9);
    const softAmber = Color(0xFFF9E8CC);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kAnalyticsDarkGreen.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: kAnalyticsDarkGreen.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overview',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: kAnalyticsDarkGreen,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Requested',
                  value: formatMoney(overview.totalRequestedAmount),
                  color: softBlue,
                  icon: Icons.receipt_long_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  label: 'Marked paid',
                  value: formatMoney(overview.totalMarkedPaidAmount),
                  color: softBlue,
                  icon: Icons.schedule_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Confirmed',
                  value: formatMoney(overview.totalConfirmedAmount),
                  color: surfaceGreen,
                  icon: Icons.verified_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  label: 'Outstanding',
                  value: formatMoney(overview.totalOutstandingAmount),
                  color: softAmber,
                  icon: Icons.hourglass_bottom_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _CountTile(label: 'Bills', value: '${overview.billCount}'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CountTile(label: 'Settled', value: '${overview.settledBillCount}'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CountTile(
                  label: 'Overdue',
                  value: '${overview.overdueBillCount}',
                  highlight: overview.overdueBillCount > 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: kAnalyticsDarkGreen),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: kAnalyticsDarkGreen,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: kAnalyticsDarkGreen,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _CountTile({required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final color = highlight ? Colors.red.shade700 : kAnalyticsDarkGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15),
          ),
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
