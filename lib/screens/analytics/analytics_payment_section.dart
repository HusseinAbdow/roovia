import 'package:flutter/material.dart';

import '../../models/financial_analytics.dart';
import 'analytics_shared.dart';

class AnalyticsPaymentSection extends StatelessWidget {
  final PaymentStatistics statistics;

  const AnalyticsPaymentSection({super.key, required this.statistics});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PaymentStateRow(
          label: 'Pending',
          detail: 'Awaiting member payment',
          amount: statistics.pendingAmount,
          count: statistics.pendingCount,
          color: Colors.orange.shade600,
          icon: Icons.circle_outlined,
        ),
        _PaymentStateRow(
          label: 'Paid',
          detail: 'Marked paid, awaiting approval',
          amount: statistics.markedPaidAmount,
          count: statistics.markedPaidCount,
          color: Colors.blue.shade600,
          icon: Icons.schedule_rounded,
        ),
        _PaymentStateRow(
          label: 'Confirmed',
          detail: 'Approved by house owner',
          amount: statistics.confirmedAmount,
          count: statistics.confirmedCount,
          color: Colors.green.shade600,
          icon: Icons.check_circle_rounded,
        ),
      ],
    );
  }
}

class _PaymentStateRow extends StatelessWidget {
  final String label;
  final String detail;
  final double amount;
  final int count;
  final Color color;
  final IconData icon;

  const _PaymentStateRow({
    required this.label,
    required this.detail,
    required this.amount,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: kAnalyticsDarkGreen,
                    fontSize: 13,
                  ),
                ),
                Text(
                  detail,
                  style: TextStyle(color: kAnalyticsDarkGreen.withValues(alpha: 0.6), fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            '${formatExactMoney(amount)} · $count',
            style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
