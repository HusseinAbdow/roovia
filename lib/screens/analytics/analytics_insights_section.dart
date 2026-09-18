import 'package:flutter/material.dart';

import '../../models/financial_analytics.dart';
import 'analytics_shared.dart';

class AnalyticsInsightsSection extends StatelessWidget {
  final List<FinancialInsight> insights;

  const AnalyticsInsightsSection({super.key, required this.insights});

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) {
      return const Text('Nothing noteworthy in this period.');
    }

    return Column(
      children: [
        for (final insight in insights)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: insight.severity == FinancialInsightSeverity.warning
                  ? Colors.orange.shade50
                  : const Color(0xFFF4F8F6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: insight.severity == FinancialInsightSeverity.warning
                    ? Colors.orange.shade200
                    : const Color(0xFFE2ECE7),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  insight.severity == FinancialInsightSeverity.warning
                      ? Icons.warning_amber_rounded
                      : Icons.lightbulb_outline_rounded,
                  size: 18,
                  color: insight.severity == FinancialInsightSeverity.warning
                      ? Colors.orange.shade700
                      : kAnalyticsDarkGreen,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    insight.message,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: kAnalyticsDarkGreen,
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
