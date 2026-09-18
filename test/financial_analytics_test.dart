import 'package:flutter_test/flutter_test.dart';

import 'package:roovia/models/expense_model.dart';
import 'package:roovia/models/expense_participant.dart';
import 'package:roovia/models/financial_analytics.dart';

ExpenseModel buildExpense({
  required String id,
  String category = 'rent',
  double totalAmount = 100,
  DateTime? dueDate,
  DateTime? createdAt,
  String status = 'pending',
  String createdBy = 'creator-1',
}) {
  return ExpenseModel(
    id: id,
    houseId: 'house-1',
    category: category,
    title: 'Bill $id',
    description: '',
    dueDate: dueDate ?? DateTime(2026, 10, 1),
    reference: '',
    totalAmount: totalAmount,
    perPersonAmount: totalAmount / 2,
    createdBy: createdBy,
    createdAt: createdAt,
    status: status,
  );
}

ExpenseParticipant buildParticipant({
  required String userId,
  double amountOwed = 50,
  String status = 'pending',
  DateTime? paidAt,
  DateTime? confirmedAt,
}) {
  return ExpenseParticipant(
    userId: userId,
    amountOwed: amountOwed,
    status: status,
    paidAt: paidAt,
    confirmedAt: confirmedAt,
    paymentProofStatus: null,
    paymentProofRevision: 0,
    paymentProofsCount: 0,
  );
}

FinancialSnapshot buildSnapshot({
  required List<ExpenseModel> expenses,
  Map<String, List<ExpenseParticipant>> participants = const {},
  Map<String, String> namesById = const {},
}) {
  return FinancialSnapshot(
    houseId: 'house-1',
    expenses: expenses,
    participantsByExpenseId: {
      for (final expense in expenses) expense.id: participants[expense.id] ?? const [],
    },
    namesById: namesById,
    house: null,
    loadedAt: DateTime(2026, 9, 15, 12),
  );
}

final now = DateTime(2026, 9, 15, 12);

void main() {
  group('Overview', () {
    test('empty house produces zeroed overview and noData insight', () {
      final analytics = HouseFinancialAnalytics.compute(
        buildSnapshot(expenses: const []),
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics.overview.totalRequestedAmount, 0);
      expect(analytics.overview.totalMarkedPaidAmount, 0);
      expect(analytics.overview.totalConfirmedAmount, 0);
      expect(analytics.overview.totalOutstandingAmount, 0);
      expect(analytics.overview.billCount, 0);
      expect(analytics.overview.settledBillCount, 0);
      expect(analytics.overview.overdueBillCount, 0);
      expect(analytics.insights, hasLength(1));
      expect(analytics.insights.first.type, FinancialInsightType.noData);
    });

    test('aggregates requested/markedPaid/confirmed/outstanding correctly', () {
      final snapshot = buildSnapshot(
        expenses: [
          buildExpense(id: 'e1', totalAmount: 300, status: 'confirmed'),
          buildExpense(id: 'e2', totalAmount: 200, status: 'pending'),
          buildExpense(
            id: 'e3',
            totalAmount: 100,
            status: 'pending',
            dueDate: DateTime(2026, 9, 1),
          ),
        ],
        participants: {
          'e1': [
            buildParticipant(userId: 'creator-1', amountOwed: 100, status: 'confirmed'),
            buildParticipant(userId: 'member-1', amountOwed: 100, status: 'confirmed'),
            buildParticipant(userId: 'member-2', amountOwed: 100, status: 'confirmed'),
          ],
          'e2': [
            buildParticipant(userId: 'creator-1', amountOwed: 100, status: 'confirmed'),
            buildParticipant(userId: 'member-1', amountOwed: 100, status: 'paid'),
            buildParticipant(userId: 'member-2', amountOwed: 100, status: 'pending'),
          ],
          'e3': [buildParticipant(userId: 'member-1', amountOwed: 100, status: 'pending')],
        },
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics.overview.totalRequestedAmount, 600);
      expect(analytics.overview.totalConfirmedAmount, 400);
      expect(analytics.overview.totalMarkedPaidAmount, 100);
      expect(analytics.overview.totalOutstandingAmount, 200);
      expect(analytics.overview.billCount, 3);
      expect(analytics.overview.settledBillCount, 1);
      expect(analytics.overview.overdueBillCount, 1);
    });
  });

  group('Monthly spending', () {
    test('groups expenses by createdAt ?? dueDate, chronological', () {
      final snapshot = buildSnapshot(
        expenses: [
          buildExpense(
            id: 'sep',
            totalAmount: 100,
            createdAt: DateTime(2026, 9, 3),
            dueDate: DateTime(2026, 9, 20),
          ),
          buildExpense(
            id: 'sep2',
            totalAmount: 50,
            createdAt: DateTime(2026, 9, 10),
            dueDate: DateTime(2026, 10, 20),
          ),
          buildExpense(
            id: 'jul',
            totalAmount: 200,
            createdAt: DateTime(2026, 7, 1),
            dueDate: DateTime(2026, 8, 1),
          ),
        ],
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics.monthlySpending.map((p) => p.monthKey).toList(), ['2026-07', '2026-09']);
      expect(analytics.monthlySpending.first.totalAmount, 200);
      expect(analytics.monthlySpending.last.totalAmount, 150);
      expect(analytics.monthlySpending.last.billCount, 2);
      expect(analytics.monthlySpending.first.label, 'Jul 2026');
      expect(analytics.monthlySpending.last.label, 'Sep 2026');
    });

    test('year boundary keeps months distinct', () {
      final snapshot = buildSnapshot(
        expenses: [
          buildExpense(
            id: 'dec',
            totalAmount: 100,
            createdAt: DateTime(2025, 12, 15),
            dueDate: DateTime(2026, 1, 15),
          ),
          buildExpense(
            id: 'jan',
            totalAmount: 100,
            createdAt: DateTime(2026, 1, 2),
            dueDate: DateTime(2026, 1, 20),
          ),
        ],
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics.monthlySpending.map((p) => p.monthKey).toList(), ['2025-12', '2026-01']);
    });

    test('expense without createdAt falls back to dueDate month', () {
      final snapshot = buildSnapshot(
        expenses: [
          buildExpense(
            id: 'legacy',
            totalAmount: 80,
            createdAt: null,
            dueDate: DateTime(2026, 5, 1),
          ),
        ],
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics.monthlySpending.single.monthKey, '2026-05');
    });
  });

  group('Category breakdown', () {
    test('shares sum to 100 and sort descending', () {
      final snapshot = buildSnapshot(
        expenses: [
          buildExpense(id: 'e1', category: 'rent', totalAmount: 600),
          buildExpense(id: 'e2', category: 'water', totalAmount: 200),
          buildExpense(id: 'e3', category: 'internet', totalAmount: 200),
        ],
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      final shares = analytics.categoryBreakdown;
      expect(shares.first.category, 'rent');
      expect(shares.first.percentage, closeTo(60, 0.001));
      expect(shares.map((c) => c.totalAmount).fold<double>(0, (a, b) => a + b), 1000);
      final sum = shares.map((c) => c.percentage).fold<double>(0, (a, b) => a + b);
      expect(sum, closeTo(100, 0.001));
    });

    test('empty or missing category maps to other without NaN', () {
      final snapshot = buildSnapshot(
        expenses: [
          buildExpense(id: 'e1', category: '', totalAmount: 100),
          buildExpense(id: 'e2', category: '   ', totalAmount: 100),
        ],
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics.categoryBreakdown.single.category, 'other');
      expect(analytics.categoryBreakdown.single.percentage, 100);
      expect(analytics.categoryBreakdown.single.percentage.isNaN, isFalse);
    });

    test('zero amounts do not produce NaN or Infinity percentages', () {
      final snapshot = buildSnapshot(
        expenses: [
          buildExpense(id: 'e1', category: 'other', totalAmount: 0),
          buildExpense(id: 'e2', category: 'rent', totalAmount: 0),
        ],
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      for (final share in analytics.categoryBreakdown) {
        expect(share.percentage.isNaN, isFalse);
        expect(share.percentage.isInfinite, isFalse);
        expect(share.percentage, 0);
      }
    });
  });

  group('Payment statistics', () {
    test('counts and amounts per state are separate for paid and confirmed', () {
      final snapshot = buildSnapshot(
        expenses: [
          buildExpense(id: 'e1', totalAmount: 300),
          buildExpense(id: 'e2', totalAmount: 300),
          buildExpense(id: 'e3', totalAmount: 300),
        ],
        participants: {
          'e1': [buildParticipant(userId: 'm1', amountOwed: 100, status: 'pending')],
          'e2': [buildParticipant(userId: 'm2', amountOwed: 100, status: 'paid')],
          'e3': [buildParticipant(userId: 'm3', amountOwed: 100, status: 'confirmed')],
        },
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      final stats = analytics.paymentStatistics;
      expect(stats.pendingCount, 1);
      expect(stats.pendingAmount, 100);
      expect(stats.markedPaidCount, 1);
      expect(stats.markedPaidAmount, 100);
      expect(stats.confirmedCount, 1);
      expect(stats.confirmedAmount, 100);
      expect(stats.paidVsPendingRatio, closeTo(0.5, 0.001));
    });

    test('zero denominator produces ratio 0, not NaN', () {
      final analytics = HouseFinancialAnalytics.compute(
        buildSnapshot(expenses: const []),
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics.paymentStatistics.paidVsPendingRatio, 0);
      expect(analytics.paymentStatistics.paidVsPendingRatio.isNaN, isFalse);
    });
  });

  group('Outstanding balance', () {
    test('only pending participants count as outstanding, grouped per member', () {
      final snapshot = buildSnapshot(
        expenses: [
          buildExpense(id: 'e1', totalAmount: 300),
          buildExpense(id: 'e2', totalAmount: 300),
        ],
        participants: {
          'e1': [
            buildParticipant(userId: 'm1', amountOwed: 100, status: 'pending'),
            buildParticipant(userId: 'm2', amountOwed: 100, status: 'paid'),
            buildParticipant(userId: 'm3', amountOwed: 100, status: 'confirmed'),
          ],
          'e2': [buildParticipant(userId: 'm1', amountOwed: 50, status: 'pending')],
        },
        namesById: {'m1': 'Alice', 'm2': 'Bob'},
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      final outstanding = analytics.outstanding;
      expect(outstanding.totalOutstanding, 150);
      expect(outstanding.outstandingByMember.length, 1);
      expect(outstanding.outstandingByMember.first.userId, 'm1');
      expect(outstanding.outstandingByMember.first.name, 'Alice');
      expect(outstanding.overdueOutstanding, 0);
    });

    test('overdue outstanding counts only unsettled overdue expenses', () {
      final snapshot = buildSnapshot(
        expenses: [
          buildExpense(
            id: 'overdue',
            totalAmount: 200,
            status: 'pending',
            dueDate: DateTime(2026, 8, 1),
          ),
          buildExpense(
            id: 'settled-overdue',
            totalAmount: 200,
            status: 'confirmed',
            dueDate: DateTime(2026, 8, 1),
          ),
          buildExpense(
            id: 'future',
            totalAmount: 200,
            status: 'pending',
            dueDate: DateTime(2026, 10, 1),
          ),
        ],
        participants: {
          'overdue': [buildParticipant(userId: 'm1', amountOwed: 200, status: 'pending')],
          'settled-overdue': [buildParticipant(userId: 'm1', amountOwed: 200, status: 'pending')],
          'future': [buildParticipant(userId: 'm2', amountOwed: 200, status: 'pending')],
        },
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics.outstanding.overdueOutstanding, 200);
      expect(analytics.outstanding.totalOutstanding, 600);
    });

    test('missing names fall back to Member without crashing', () {
      final snapshot = buildSnapshot(
        expenses: [buildExpense(id: 'e1', totalAmount: 100)],
        participants: {
          'e1': [buildParticipant(userId: 'ghost-user', amountOwed: 100)],
        },
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics.outstanding.outstandingByMember.single.name, 'Member');
      expect(analytics.outstanding.outstandingByMember.single.userId, 'ghost-user');
    });
  });

  group('Member contributions', () {
    test('per-member owed/paid/confirmed/outstanding and share of confirmed', () {
      final snapshot = buildSnapshot(
        expenses: [buildExpense(id: 'e1', totalAmount: 400, status: 'confirmed')],
        participants: {
          'e1': [
            buildParticipant(userId: 'owner', amountOwed: 100, status: 'confirmed'),
            buildParticipant(userId: 'm1', amountOwed: 100, status: 'confirmed'),
            buildParticipant(userId: 'm2', amountOwed: 100, status: 'paid'),
            buildParticipant(userId: 'm3', amountOwed: 100, status: 'pending'),
          ],
        },
        namesById: {'owner': 'Owner', 'm1': 'Alice', 'm2': 'Bob', 'm3': 'Cara'},
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      final contributions = analytics.memberContributions;
      expect(contributions, hasLength(4));

      final owner = contributions.firstWhere((c) => c.userId == 'owner');
      expect(owner.owedAmount, 100);
      expect(owner.confirmedAmount, 100);
      expect(owner.outstandingAmount, 0);
      expect(owner.contributionPercentage, closeTo(50, 0.001));

      final m1 = contributions.firstWhere((c) => c.userId == 'm1');
      expect(m1.confirmedAmount, 100);
      expect(m1.contributionPercentage, closeTo(50, 0.001));

      final m2 = contributions.firstWhere((c) => c.userId == 'm2');
      expect(m2.markedPaidAmount, 100);
      expect(m2.confirmedAmount, 0);
      expect(m2.contributionPercentage, 0);

      final m3 = contributions.firstWhere((c) => c.userId == 'm3');
      expect(m3.outstandingAmount, 100);
      expect(m3.owedAmount, 100);
    });

    test('zero confirmed total yields 0 percentage, not NaN', () {
      final snapshot = buildSnapshot(
        expenses: [buildExpense(id: 'e1', totalAmount: 100)],
        participants: {
          'e1': [buildParticipant(userId: 'm1', amountOwed: 100, status: 'pending')],
        },
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics.memberContributions.single.contributionPercentage, 0);
    });
  });

  group('Completion stats', () {
    test('completion and participant rates with guards', () {
      final snapshot = buildSnapshot(
        expenses: [
          buildExpense(id: 'e1', totalAmount: 200, status: 'confirmed'),
          buildExpense(id: 'e2', totalAmount: 200, status: 'pending'),
        ],
        participants: {
          'e1': [
            buildParticipant(userId: 'm1', amountOwed: 100, status: 'confirmed'),
            buildParticipant(userId: 'm2', amountOwed: 100, status: 'confirmed'),
          ],
          'e2': [
            buildParticipant(userId: 'm1', amountOwed: 100, status: 'paid'),
            buildParticipant(userId: 'm2', amountOwed: 100, status: 'pending'),
          ],
        },
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics.completion.completionRate, closeTo(0.5, 0.001));
      expect(analytics.completion.participantPaymentRate, closeTo(0.5, 0.001));
      expect(analytics.completion.settledBillCount, 1);
      expect(analytics.completion.totalBillCount, 2);
    });

    test('average settlement time uses latest confirmedAt vs createdAt', () {
      final snapshot = buildSnapshot(
        expenses: [
          buildExpense(
            id: 'fast',
            totalAmount: 100,
            status: 'confirmed',
            createdAt: DateTime(2026, 9, 1),
            dueDate: DateTime(2026, 10, 1),
          ),
          buildExpense(
            id: 'slow',
            totalAmount: 100,
            status: 'confirmed',
            createdAt: DateTime(2026, 9, 1),
            dueDate: DateTime(2026, 10, 1),
          ),
        ],
        participants: {
          'fast': [
            buildParticipant(userId: 'm1', status: 'confirmed', confirmedAt: DateTime(2026, 9, 3)),
          ],
          'slow': [
            buildParticipant(userId: 'm1', status: 'confirmed', confirmedAt: DateTime(2026, 9, 11)),
            buildParticipant(userId: 'm2', status: 'confirmed', confirmedAt: DateTime(2026, 9, 5)),
          ],
        },
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics.completion.averageSettlementDays, 6);
    });

    test('settlement time is null when no confirmedAt timestamps exist', () {
      final snapshot = buildSnapshot(
        expenses: [buildExpense(id: 'e1', totalAmount: 100, status: 'confirmed')],
        participants: {
          'e1': [buildParticipant(userId: 'm1', status: 'confirmed')],
        },
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics.completion.averageSettlementDays, isNull);
    });

    test('zero expenses produce zero rates, not NaN', () {
      final analytics = HouseFinancialAnalytics.compute(
        buildSnapshot(expenses: const []),
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics.completion.completionRate, 0);
      expect(analytics.completion.participantPaymentRate, 0);
      expect(analytics.completion.completionRate.isNaN, isFalse);
    });
  });

  group('Insights', () {
    test('overdue and high pending insights trigger', () {
      final snapshot = buildSnapshot(
        expenses: [
          buildExpense(
            id: 'overdue',
            totalAmount: 500,
            status: 'pending',
            dueDate: DateTime(2026, 8, 1),
          ),
        ],
        participants: {
          'overdue': [buildParticipant(userId: 'm1', amountOwed: 500, status: 'pending')],
        },
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      final types = analytics.insights.map((i) => i.type).toList();
      expect(types, contains(FinancialInsightType.overdueBills));
      expect(types, contains(FinancialInsightType.highPending));
      expect(types, contains(FinancialInsightType.memberBalance));
      for (final insight in analytics.insights) {
        expect(insight.severity, isNot(FinancialInsightSeverity.info));
      }
    });

    test('top category insight requires multiple bills and >60% share', () {
      final snapshot = buildSnapshot(
        expenses: [
          buildExpense(id: 'e1', category: 'rent', totalAmount: 900),
          buildExpense(id: 'e2', category: 'water', totalAmount: 100),
        ],
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics.insights.any((i) => i.type == FinancialInsightType.topCategory), isTrue);
    });

    test('healthy data produces no warnings', () {
      final snapshot = buildSnapshot(
        expenses: [
          buildExpense(
            id: 'e1',
            category: 'rent',
            totalAmount: 300,
            status: 'confirmed',
            createdAt: DateTime(2026, 9, 1),
            dueDate: DateTime(2026, 9, 30),
          ),
        ],
        participants: {
          'e1': [
            buildParticipant(
              userId: 'm1',
              amountOwed: 300,
              status: 'confirmed',
              confirmedAt: DateTime(2026, 9, 5),
            ),
          ],
        },
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(
        analytics.insights.where((i) => i.severity == FinancialInsightSeverity.warning),
        isEmpty,
      );
    });
  });

  group('Period filtering inside compute', () {
    test('compute respects period without double-filtering', () {
      final snapshot = buildSnapshot(
        expenses: [
          buildExpense(
            id: 'old',
            totalAmount: 1000,
            createdAt: DateTime(2025, 1, 1),
            dueDate: DateTime(2025, 1, 10),
          ),
          buildExpense(
            id: 'recent',
            totalAmount: 100,
            createdAt: DateTime(2026, 9, 1),
            dueDate: DateTime(2026, 9, 30),
          ),
        ],
      );

      final analytics3m = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.last3Months,
        now: now,
      );
      final analyticsAll = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics3m.overview.billCount, 1);
      expect(analytics3m.overview.totalRequestedAmount, 100);
      expect(analyticsAll.overview.billCount, 2);
      expect(analyticsAll.overview.totalRequestedAmount, 1100);
      expect(analytics3m.period, AnalyticsPeriod.last3Months);
      expect(analyticsAll.period, AnalyticsPeriod.all);
    });

    test('unknown participant status treated as pending', () {
      final snapshot = buildSnapshot(
        expenses: [buildExpense(id: 'e1', totalAmount: 100)],
        participants: {
          'e1': [buildParticipant(userId: 'm1', amountOwed: 100, status: 'corrupt')],
        },
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics.overview.totalOutstandingAmount, 100);
      expect(analytics.overview.totalMarkedPaidAmount, 0);
      expect(analytics.paymentStatistics.pendingCount, 1);
    });

    test('malformed amounts never produce NaN or Infinity', () {
      final snapshot = buildSnapshot(
        expenses: [
          buildExpense(id: 'e1', totalAmount: -500),
          buildExpense(id: 'e2', totalAmount: double.nan),
          buildExpense(id: 'e3', totalAmount: double.infinity),
        ],
        participants: {
          'e1': [buildParticipant(userId: 'm1', amountOwed: -10)],
        },
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics.overview.totalRequestedAmount, 0);
      expect(analytics.overview.totalOutstandingAmount, 0);
      expect(analytics.overview.totalRequestedAmount.isNaN, isFalse);
      expect(analytics.overview.totalRequestedAmount.isInfinite, isFalse);
      expect(analytics.overview.totalOutstandingAmount.isNaN, isFalse);
    });

    test('expense with zero participants does not crash and counts in totals', () {
      final snapshot = buildSnapshot(
        expenses: [buildExpense(id: 'lonely', totalAmount: 150, status: 'pending')],
      );

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics.overview.totalRequestedAmount, 150);
      expect(analytics.overview.totalOutstandingAmount, 0);
      expect(analytics.completion.totalParticipants, 0);
      expect(analytics.completion.participantPaymentRate, 0);
    });
  });
}
