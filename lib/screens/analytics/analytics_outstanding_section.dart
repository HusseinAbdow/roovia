import 'package:flutter/material.dart';

import '../../models/financial_analytics.dart';
import 'analytics_shared.dart';

class AnalyticsOutstandingSection extends StatelessWidget {
  final OutstandingBalance outstanding;
  final String Function(double) formatMoney;

  const AnalyticsOutstandingSection({
    super.key,
    required this.outstanding,
    required this.formatMoney,
  });

  @override
  Widget build(BuildContext context) {
    if (outstanding.totalOutstanding <= 0) {
      return const Text('Nothing outstanding. All payments confirmed.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _OutstandingTile(
                label: 'Total outstanding',
                value: formatMoney(outstanding.totalOutstanding),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _OutstandingTile(
                label: 'Overdue',
                value: formatMoney(outstanding.overdueOutstanding),
                highlight: outstanding.overdueOutstanding > 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final member in outstanding.outstandingByMember)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: analyticsAvatarColor(member.userId),
                  child: Text(
                    memberInitials(member.name),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: kAnalyticsDarkGreen,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    member.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: kAnalyticsDarkGreen,
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  formatMoney(member.outstandingAmount),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: kAnalyticsDarkGreen,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _OutstandingTile extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _OutstandingTile({required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final color = highlight ? Colors.red.shade700 : kAnalyticsDarkGreen;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight ? Colors.red.shade50 : const Color(0xFFF4F8F6),
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
