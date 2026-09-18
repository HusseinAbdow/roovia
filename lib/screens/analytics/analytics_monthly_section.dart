import 'package:flutter/material.dart';

import '../../models/financial_analytics.dart';
import 'analytics_shared.dart';

class AnalyticsMonthlySection extends StatelessWidget {
  final List<MonthlySpendingPoint> points;
  final String Function(double) formatMoney;

  const AnalyticsMonthlySection({super.key, required this.points, required this.formatMoney});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Text('No spending recorded in this period.');
    }

    final maxTotal = points
        .map((point) => point.totalAmount)
        .fold<double>(0, (max, value) => value > max ? value : max);

    return Column(
      children: [
        for (final point in points.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      point.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: kAnalyticsDarkGreen,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${formatMoney(point.totalAmount)} · ${point.billCount} bill${point.billCount == 1 ? '' : 's'}',
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
                    value: maxTotal <= 0 ? 0 : point.totalAmount / maxTotal,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(kAnalyticsDarkGreen),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
