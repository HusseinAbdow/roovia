import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:roovia/screens/analytics/analytics_state_views.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AnalyticsPeriodEmptyState', () {
    testWidgets('shows period-specific empty message', (tester) async {
      await tester.pumpWidget(wrap(const AnalyticsPeriodEmptyState()));

      expect(find.text('No bills in this period'), findsOneWidget);
      expect(
        find.text('Try selecting a longer period to see your house\'s financial activity.'),
        findsOneWidget,
      );
      // Must NOT claim the house has no data at all.
      expect(find.text('No financial data yet'), findsNothing);
    });
  });

  group('AnalyticsEmptyState', () {
    testWidgets('shows house-wide empty message', (tester) async {
      await tester.pumpWidget(wrap(const AnalyticsEmptyState()));

      expect(find.text('No financial data yet'), findsOneWidget);
      expect(find.text('No bills in this period'), findsNothing);
    });
  });

  group('AnalyticsLeaderOnlyState', () {
    testWidgets('shows leader-only guard message', (tester) async {
      await tester.pumpWidget(wrap(const AnalyticsLeaderOnlyState()));

      expect(
        find.text('Financial analytics are only available to the house leader.'),
        findsOneWidget,
      );
    });
  });
}
