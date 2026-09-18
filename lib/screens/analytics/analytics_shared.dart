import 'package:flutter/material.dart';

const Color kAnalyticsDarkGreen = Color(0xFF0B3D2E);

/// Compact money formatting used across the analytics overview sections
/// (matches the ExpenseScreen convention: ₺1.2k above 1000).
String formatMoney(double value) {
  if (value >= 1000) {
    return '₺${(value / 1000).toStringAsFixed(1)}k';
  }
  if (value == value.roundToDouble()) {
    return '₺${value.toStringAsFixed(0)}';
  }
  return '₺${value.toStringAsFixed(2)}';
}

/// Exact money formatting (previously used by the payment status rows).
String formatExactMoney(double value) {
  if (value == value.roundToDouble()) {
    return '₺${value.toStringAsFixed(0)}';
  }
  return '₺${value.toStringAsFixed(2)}';
}

String formatPercent(double value) => '${value.toStringAsFixed(0)}%';

Color analyticsAvatarColor(String seed) {
  final colors = <Color>[
    const Color(0xFFD9F0E1),
    const Color(0xFFDDEAF8),
    const Color(0xFFF8E6D7),
    const Color(0xFFE8DFF7),
    const Color(0xFFF7E6EF),
  ];
  return colors[seed.hashCode.abs() % colors.length];
}

String memberInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
}

class AnalyticsSectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const AnalyticsSectionCard({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
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
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: kAnalyticsDarkGreen,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
