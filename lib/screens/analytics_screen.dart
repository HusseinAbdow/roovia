import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/financial_analytics.dart';
import '../services/analytics_service.dart';
import '../services/house_service.dart';
import 'analytics/analytics_category_section.dart';
import 'analytics/analytics_completion_section.dart';
import 'analytics/analytics_insights_section.dart';
import 'analytics/analytics_members_section.dart';
import 'analytics/analytics_monthly_section.dart';
import 'analytics/analytics_outstanding_section.dart';
import 'analytics/analytics_overview_section.dart';
import 'analytics/analytics_payment_section.dart';
import 'analytics/analytics_period_selector.dart';
import 'analytics/analytics_shared.dart';
import 'analytics/analytics_state_views.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

enum _ScreenStatus { loading, loaded, error, noHouse, notLeader }

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  static const _darkGreen = Color(0xFF0B3D2E);
  final HouseService _houseService = HouseService();
  final AnalyticsService _analyticsService = AnalyticsService();

  _ScreenStatus _status = _ScreenStatus.loading;
  FinancialSnapshot? _snapshot;
  AnalyticsPeriod _selectedPeriod = AnalyticsPeriod.last6Months;

  @override
  void initState() {
    super.initState();
    _loadSnapshot();
  }

  Future<void> _loadSnapshot() async {
    setState(() => _status = _ScreenStatus.loading);
    try {
      final house = await _houseService.getCurrentUserHouse().first;
      if (!mounted) return;
      if (house == null) {
        setState(() => _status = _ScreenStatus.noHouse);
        return;
      }
      // Financial analytics expose individual member financial data, so they
      // are restricted to the house leader even on direct navigation.
      final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (house.leaderId != currentUserId) {
        setState(() => _status = _ScreenStatus.notLeader);
        return;
      }
      final snapshot = await _analyticsService.loadFinancialSnapshot(house.houseId);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _status = _ScreenStatus.loaded;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _ScreenStatus.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Financial Analytics')),
      body: switch (_status) {
        _ScreenStatus.loading => const Center(child: CircularProgressIndicator(color: _darkGreen)),
        _ScreenStatus.error => AnalyticsErrorState(onRetry: _loadSnapshot),
        _ScreenStatus.noHouse => AnalyticsNoHouseState(onRetry: _loadSnapshot),
        _ScreenStatus.notLeader => const AnalyticsLeaderOnlyState(),
        _ScreenStatus.loaded => _buildContent(),
      },
    );
  }

  Widget _buildContent() {
    final snapshot = _snapshot!;
    final analytics = HouseFinancialAnalytics.compute(
      snapshot,
      period: _selectedPeriod,
      now: DateTime.now(),
    );

    if (snapshot.expenses.isEmpty) {
      return const AnalyticsEmptyState();
    }

    if (analytics.overview.billCount == 0) {
      // The house has financial data, but none inside the selected period.
      // Keep the header and period selector visible so the user can switch.
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _AnalyticsHeader(houseName: snapshot.house?.name ?? 'Your house'),
          const SizedBox(height: 16),
          AnalyticsPeriodSelector(
            selected: _selectedPeriod,
            onSelected: (period) => setState(() => _selectedPeriod = period),
          ),
          const SizedBox(height: 16),
          const AnalyticsPeriodEmptyState(),
        ],
      );
    }

    return RefreshIndicator(
      color: _darkGreen,
      onRefresh: _loadSnapshot,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _AnalyticsHeader(houseName: snapshot.house?.name ?? 'Your house'),
          const SizedBox(height: 16),
          AnalyticsPeriodSelector(
            selected: _selectedPeriod,
            onSelected: (period) => setState(() => _selectedPeriod = period),
          ),
          const SizedBox(height: 16),
          AnalyticsOverviewSection(overview: analytics.overview, formatMoney: formatMoney),
          const SizedBox(height: 16),
          AnalyticsSectionCard(
            title: 'Monthly spending',
            child: AnalyticsMonthlySection(
              points: analytics.monthlySpending,
              formatMoney: formatMoney,
            ),
          ),
          const SizedBox(height: 16),
          AnalyticsSectionCard(
            title: 'Category breakdown',
            child: AnalyticsCategorySection(
              shares: analytics.categoryBreakdown,
              formatMoney: formatMoney,
              formatPercent: formatPercent,
            ),
          ),
          const SizedBox(height: 16),
          AnalyticsSectionCard(
            title: 'Payment status',
            child: AnalyticsPaymentSection(statistics: analytics.paymentStatistics),
          ),
          const SizedBox(height: 16),
          AnalyticsSectionCard(
            title: 'Outstanding balances',
            child: AnalyticsOutstandingSection(
              outstanding: analytics.outstanding,
              formatMoney: formatMoney,
            ),
          ),
          const SizedBox(height: 16),
          AnalyticsSectionCard(
            title: 'Member contributions',
            child: AnalyticsMembersSection(
              contributions: analytics.memberContributions,
              formatMoney: formatMoney,
            ),
          ),
          const SizedBox(height: 16),
          AnalyticsSectionCard(
            title: 'Completion',
            child: AnalyticsCompletionSection(
              stats: analytics.completion,
              formatPercent: formatPercent,
            ),
          ),
          const SizedBox(height: 16),
          AnalyticsSectionCard(
            title: 'Insights',
            child: AnalyticsInsightsSection(insights: analytics.insights),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsHeader extends StatelessWidget {
  final String houseName;

  const _AnalyticsHeader({required this.houseName});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
            houseName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: kAnalyticsDarkGreen,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Financial overview derived from house bills',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: kAnalyticsDarkGreen.withValues(alpha: 0.68)),
          ),
        ],
      ),
    );
  }
}
