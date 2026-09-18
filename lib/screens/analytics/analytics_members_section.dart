import 'package:flutter/material.dart';

import '../../models/financial_analytics.dart';
import 'analytics_shared.dart';

class AnalyticsMembersSection extends StatelessWidget {
  final List<MemberContribution> contributions;
  final String Function(double) formatMoney;

  const AnalyticsMembersSection({
    super.key,
    required this.contributions,
    required this.formatMoney,
  });

  @override
  Widget build(BuildContext context) {
    if (contributions.isEmpty) {
      return const Text('No participant records in this period.');
    }

    return Column(
      children: [
        for (final contribution in contributions)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F8F6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: analyticsAvatarColor(contribution.userId),
                      child: Text(
                        memberInitials(contribution.name),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: kAnalyticsDarkGreen,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        contribution.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: kAnalyticsDarkGreen,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      formatMoney(contribution.owedAmount),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: kAnalyticsDarkGreen,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _MiniPill(
                      label: 'Paid ${formatMoney(contribution.markedPaidAmount)}',
                      color: Colors.blue.shade600,
                    ),
                    _MiniPill(
                      label: 'Confirmed ${formatMoney(contribution.confirmedAmount)}',
                      color: Colors.green.shade600,
                    ),
                    if (contribution.outstandingAmount > 0)
                      _MiniPill(
                        label: 'Outstanding ${formatMoney(contribution.outstandingAmount)}',
                        color: Colors.orange.shade700,
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MiniPill extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }
}
