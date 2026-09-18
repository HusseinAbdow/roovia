import 'package:flutter/material.dart';

import '../../models/financial_analytics.dart';
import 'analytics_shared.dart';

class AnalyticsCategorySection extends StatelessWidget {
  final List<CategoryShare> shares;
  final String Function(double) formatMoney;
  final String Function(double) formatPercent;

  const AnalyticsCategorySection({
    super.key,
    required this.shares,
    required this.formatMoney,
    required this.formatPercent,
  });

  @override
  Widget build(BuildContext context) {
    if (shares.isEmpty) {
      return const Text('No categories recorded in this period.');
    }

    return Column(
      children: [
        for (final share in shares)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${share.category[0].toUpperCase()}${share.category.substring(1)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: kAnalyticsDarkGreen,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '${formatMoney(share.totalAmount)} · ${formatPercent(share.percentage)}',
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
                    value: share.percentage / 100,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      share == shares.first
                          ? kAnalyticsDarkGreen
                          : kAnalyticsDarkGreen.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
