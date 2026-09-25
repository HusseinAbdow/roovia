import 'package:flutter/material.dart';

import 'analytics_shared.dart';

class AnalyticsErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const AnalyticsErrorState({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: kAnalyticsDarkGreen.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not load financial analytics right now.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class AnalyticsNoHouseState extends StatelessWidget {
  final VoidCallback onRetry;

  const AnalyticsNoHouseState({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home_outlined, size: 48, color: kAnalyticsDarkGreen.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text(
              'You are not in a house yet, so there is nothing to analyze.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Reload')),
          ],
        ),
      ),
    );
  }
}

class AnalyticsEmptyState extends StatelessWidget {
  const AnalyticsEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: kAnalyticsDarkGreen.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'No financial data yet',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: kAnalyticsDarkGreen,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Once bills are requested in your house, their spending and payment activity will appear here.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the house HAS financial data but the selected period contains
/// no bills. Unlike [AnalyticsEmptyState], the period selector stays visible
/// so the user can switch to a longer period.
class AnalyticsPeriodEmptyState extends StatelessWidget {
  const AnalyticsPeriodEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          children: [
            Icon(
              Icons.event_busy_rounded,
              size: 48,
              color: kAnalyticsDarkGreen.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'No bills in this period',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: kAnalyticsDarkGreen,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try selecting a longer period to see your house\'s financial activity.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Defense-in-depth guard: financial analytics expose individual member
/// financial data, so only the house leader may use this screen.
class AnalyticsLeaderOnlyState extends StatelessWidget {
  const AnalyticsLeaderOnlyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 48,
              color: kAnalyticsDarkGreen.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'Financial analytics are only available to the house leader.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
