import 'package:flutter/material.dart';

import '../../models/financial_analytics.dart';

class AnalyticsPeriodSelector extends StatelessWidget {
  final AnalyticsPeriod selected;
  final ValueChanged<AnalyticsPeriod> onSelected;

  const AnalyticsPeriodSelector({super.key, required this.selected, required this.onSelected});

  static const _labels = {
    AnalyticsPeriod.last3Months: 'Last 3 months',
    AnalyticsPeriod.last6Months: 'Last 6 months',
    AnalyticsPeriod.last12Months: 'Last 12 months',
    AnalyticsPeriod.all: 'All',
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: AnalyticsPeriod.values.map((period) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: selected == period,
              label: Text(_labels[period]!),
              onSelected: (_) => onSelected(period),
            ),
          );
        }).toList(),
      ),
    );
  }
}
