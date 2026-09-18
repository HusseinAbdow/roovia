import 'expense_model.dart';
import 'expense_participant.dart';
import 'house_model.dart';

enum AnalyticsPeriod { last3Months, last6Months, last12Months, all }

enum FinancialInsightType {
  overdueBills,
  highPending,
  topCategory,
  settlementSpeed,
  memberBalance,
  noData,
}

enum FinancialInsightSeverity { info, warning }

class FinancialSnapshot {
  final String houseId;
  final List<ExpenseModel> expenses;
  final Map<String, List<ExpenseParticipant>> participantsByExpenseId;
  final Map<String, String> namesById;
  final House? house;
  final DateTime loadedAt;

  const FinancialSnapshot({
    required this.houseId,
    required this.expenses,
    required this.participantsByExpenseId,
    required this.namesById,
    required this.house,
    required this.loadedAt,
  });

  DateTime _periodStart(AnalyticsPeriod period, DateTime now) {
    switch (period) {
      case AnalyticsPeriod.last3Months:
        return DateTime(now.year, now.month - 3, now.day);
      case AnalyticsPeriod.last6Months:
        return DateTime(now.year, now.month - 6, now.day);
      case AnalyticsPeriod.last12Months:
        return DateTime(now.year, now.month - 12, now.day);
      case AnalyticsPeriod.all:
        return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  DateTime? _basisDate(ExpenseModel expense) {
    return expense.createdAt ?? expense.dueDate;
  }

  FinancialSnapshot filterToPeriod(AnalyticsPeriod period, DateTime now) {
    final start = _periodStart(period, now);
    final filteredExpenses = expenses
        .where((expense) {
          final basis = _basisDate(expense);
          return basis == null || !basis.isBefore(start);
        })
        .toList(growable: false);

    final filteredParticipants = <String, List<ExpenseParticipant>>{
      for (final expense in filteredExpenses)
        expense.id: participantsByExpenseId[expense.id] ?? const <ExpenseParticipant>[],
    };

    return FinancialSnapshot(
      houseId: houseId,
      expenses: filteredExpenses,
      participantsByExpenseId: filteredParticipants,
      namesById: namesById,
      house: house,
      loadedAt: loadedAt,
    );
  }

  List<ExpenseParticipant> participantsFor(String expenseId) {
    return participantsByExpenseId[expenseId] ?? const <ExpenseParticipant>[];
  }

  String nameFor(String userId) {
    return namesById[userId] ?? 'Member';
  }
}

class AnalyticsOverview {
  final double totalRequestedAmount;
  final double totalMarkedPaidAmount;
  final double totalConfirmedAmount;
  final double totalOutstandingAmount;
  final int billCount;
  final int settledBillCount;
  final int overdueBillCount;

  const AnalyticsOverview({
    required this.totalRequestedAmount,
    required this.totalMarkedPaidAmount,
    required this.totalConfirmedAmount,
    required this.totalOutstandingAmount,
    required this.billCount,
    required this.settledBillCount,
    required this.overdueBillCount,
  });
}

class MonthlySpendingPoint {
  final String monthKey;
  final String label;
  final double totalAmount;
  final int billCount;

  const MonthlySpendingPoint({
    required this.monthKey,
    required this.label,
    required this.totalAmount,
    required this.billCount,
  });
}

class CategoryShare {
  final String category;
  final double totalAmount;
  final double percentage;
  final int billCount;

  const CategoryShare({
    required this.category,
    required this.totalAmount,
    required this.percentage,
    required this.billCount,
  });
}

class PaymentStatistics {
  final double markedPaidAmount;
  final int markedPaidCount;
  final double confirmedAmount;
  final int confirmedCount;
  final double pendingAmount;
  final int pendingCount;
  final double paidVsPendingRatio;

  const PaymentStatistics({
    required this.markedPaidAmount,
    required this.markedPaidCount,
    required this.confirmedAmount,
    required this.confirmedCount,
    required this.pendingAmount,
    required this.pendingCount,
    required this.paidVsPendingRatio,
  });
}

class MemberOutstanding {
  final String userId;
  final String name;
  final double outstandingAmount;

  const MemberOutstanding({
    required this.userId,
    required this.name,
    required this.outstandingAmount,
  });
}

class OutstandingBalance {
  final double totalOutstanding;
  final List<MemberOutstanding> outstandingByMember;
  final double overdueOutstanding;

  const OutstandingBalance({
    required this.totalOutstanding,
    required this.outstandingByMember,
    required this.overdueOutstanding,
  });
}

class MemberContribution {
  final String userId;
  final String name;
  final double owedAmount;
  final double markedPaidAmount;
  final double confirmedAmount;
  final double outstandingAmount;
  final double contributionPercentage;

  const MemberContribution({
    required this.userId,
    required this.name,
    required this.owedAmount,
    required this.markedPaidAmount,
    required this.confirmedAmount,
    required this.outstandingAmount,
    required this.contributionPercentage,
  });
}

class CompletionStats {
  final double completionRate;
  final double participantPaymentRate;
  final int? averageSettlementDays;
  final int settledBillCount;
  final int totalBillCount;
  final int totalParticipants;
  final int confirmedParticipants;

  const CompletionStats({
    required this.completionRate,
    required this.participantPaymentRate,
    required this.averageSettlementDays,
    required this.settledBillCount,
    required this.totalBillCount,
    required this.totalParticipants,
    required this.confirmedParticipants,
  });
}

class FinancialInsight {
  final FinancialInsightType type;
  final FinancialInsightSeverity severity;
  final String message;

  const FinancialInsight({required this.type, required this.severity, required this.message});
}

class HouseFinancialAnalytics {
  final AnalyticsPeriod period;
  final AnalyticsOverview overview;
  final List<MonthlySpendingPoint> monthlySpending;
  final List<CategoryShare> categoryBreakdown;
  final PaymentStatistics paymentStatistics;
  final OutstandingBalance outstanding;
  final List<MemberContribution> memberContributions;
  final CompletionStats completion;
  final List<FinancialInsight> insights;

  const HouseFinancialAnalytics({
    required this.period,
    required this.overview,
    required this.monthlySpending,
    required this.categoryBreakdown,
    required this.paymentStatistics,
    required this.outstanding,
    required this.memberContributions,
    required this.completion,
    required this.insights,
  });

  /// Pure entry point for all financial analytics. Applies the requested
  /// period filter via [FinancialSnapshot.filterToPeriod] and derives every
  /// metric from that single scoped dataset. No Firebase access, no mutation,
  /// no wall-clock reads — all time-based math uses the [now] parameter.
  static HouseFinancialAnalytics compute(
    FinancialSnapshot snapshot, {
    required AnalyticsPeriod period,
    required DateTime now,
  }) {
    final scoped = snapshot.filterToPeriod(period, now);

    final overview = _calculateOverview(scoped, now);
    final categories = _calculateCategoryBreakdown(scoped);
    final paymentStatistics = _calculatePaymentStatistics(scoped);
    final outstanding = _calculateOutstandingBalance(scoped, now);
    final contributions = _calculateMemberContributions(scoped);
    final completion = _calculateCompletionStats(scoped);

    return HouseFinancialAnalytics(
      period: period,
      overview: overview,
      monthlySpending: _calculateMonthlySpending(scoped),
      categoryBreakdown: categories,
      paymentStatistics: paymentStatistics,
      outstanding: outstanding,
      memberContributions: contributions,
      completion: completion,
      insights: _calculateInsights(
        overview: overview,
        categories: categories,
        outstanding: outstanding,
        completion: completion,
        billCount: scoped.expenses.length,
      ),
    );
  }

  static AnalyticsOverview _calculateOverview(FinancialSnapshot snapshot, DateTime now) {
    double requested = 0;
    double markedPaid = 0;
    double confirmed = 0;
    double outstanding = 0;
    int settledCount = 0;
    int overdueCount = 0;

    for (final expense in snapshot.expenses) {
      requested += _nonNegative(expense.totalAmount);
      if (expense.status == 'confirmed') {
        settledCount += 1;
      } else if (expense.dueDate.isBefore(now)) {
        overdueCount += 1;
      }

      for (final participant in snapshot.participantsFor(expense.id)) {
        final owed = _nonNegative(participant.amountOwed);
        switch (participant.state) {
          case PaymentState.confirmed:
            confirmed += owed;
            break;
          case PaymentState.paid:
            markedPaid += owed;
            break;
          case PaymentState.pending:
            outstanding += owed;
            break;
        }
      }
    }

    return AnalyticsOverview(
      totalRequestedAmount: requested,
      totalMarkedPaidAmount: markedPaid,
      totalConfirmedAmount: confirmed,
      totalOutstandingAmount: outstanding,
      billCount: snapshot.expenses.length,
      settledBillCount: settledCount,
      overdueBillCount: overdueCount,
    );
  }

  static List<MonthlySpendingPoint> _calculateMonthlySpending(FinancialSnapshot snapshot) {
    final buckets = <String, _MonthAccumulator>{};

    for (final expense in snapshot.expenses) {
      final basis = expense.createdAt ?? expense.dueDate;
      final key =
          '${basis.year.toString().padLeft(4, '0')}-${basis.month.toString().padLeft(2, '0')}';
      final bucket = buckets.putIfAbsent(
        key,
        () => _MonthAccumulator(year: basis.year, month: basis.month),
      );
      bucket.total += _nonNegative(expense.totalAmount);
      bucket.count += 1;
    }

    final keys = buckets.keys.toList()..sort();
    return [
      for (final key in keys)
        MonthlySpendingPoint(
          monthKey: key,
          label: '${_monthNames[buckets[key]!.month - 1]} ${buckets[key]!.year}',
          totalAmount: buckets[key]!.total,
          billCount: buckets[key]!.count,
        ),
    ];
  }

  static List<CategoryShare> _calculateCategoryBreakdown(FinancialSnapshot snapshot) {
    final totals = <String, double>{};
    final counts = <String, int>{};

    for (final expense in snapshot.expenses) {
      final category = expense.category.trim().isEmpty ? 'other' : expense.category.trim();
      totals[category] = (totals[category] ?? 0) + _nonNegative(expense.totalAmount);
      counts[category] = (counts[category] ?? 0) + 1;
    }

    double grandTotal = 0;
    for (final total in totals.values) {
      grandTotal += total;
    }

    final entries = totals.keys.toList()..sort();
    final shares = [
      for (final category in entries)
        CategoryShare(
          category: category,
          totalAmount: totals[category]!,
          percentage: grandTotal <= 0 ? 0 : (totals[category]! / grandTotal) * 100,
          billCount: counts[category] ?? 0,
        ),
    ];
    shares.sort((left, right) {
      final byAmount = right.totalAmount.compareTo(left.totalAmount);
      return byAmount != 0 ? byAmount : left.category.compareTo(right.category);
    });
    return shares;
  }

  static PaymentStatistics _calculatePaymentStatistics(FinancialSnapshot snapshot) {
    double markedPaidAmount = 0;
    int markedPaidCount = 0;
    double confirmedAmount = 0;
    int confirmedCount = 0;
    double pendingAmount = 0;
    int pendingCount = 0;

    for (final expense in snapshot.expenses) {
      for (final participant in snapshot.participantsFor(expense.id)) {
        final owed = _nonNegative(participant.amountOwed);
        switch (participant.state) {
          case PaymentState.paid:
            markedPaidAmount += owed;
            markedPaidCount += 1;
            break;
          case PaymentState.confirmed:
            confirmedAmount += owed;
            confirmedCount += 1;
            break;
          case PaymentState.pending:
            pendingAmount += owed;
            pendingCount += 1;
            break;
        }
      }
    }

    final ratioDenominator = markedPaidAmount + pendingAmount;
    return PaymentStatistics(
      markedPaidAmount: markedPaidAmount,
      markedPaidCount: markedPaidCount,
      confirmedAmount: confirmedAmount,
      confirmedCount: confirmedCount,
      pendingAmount: pendingAmount,
      pendingCount: pendingCount,
      paidVsPendingRatio: ratioDenominator <= 0 ? 0 : markedPaidAmount / ratioDenominator,
    );
  }

  static OutstandingBalance _calculateOutstandingBalance(FinancialSnapshot snapshot, DateTime now) {
    final byMember = <String, double>{};
    double totalOutstanding = 0;
    double overdueOutstanding = 0;

    for (final expense in snapshot.expenses) {
      final isOverdue = expense.status != 'confirmed' && expense.dueDate.isBefore(now);
      for (final participant in snapshot.participantsFor(expense.id)) {
        if (participant.state != PaymentState.pending) {
          continue;
        }
        final owed = _nonNegative(participant.amountOwed);
        if (owed <= 0) {
          continue;
        }
        totalOutstanding += owed;
        byMember[participant.userId] = (byMember[participant.userId] ?? 0) + owed;
        if (isOverdue) {
          overdueOutstanding += owed;
        }
      }
    }

    final memberIds = byMember.keys.toList()..sort();
    final memberOutstanding = [
      for (final userId in memberIds)
        MemberOutstanding(
          userId: userId,
          name: snapshot.nameFor(userId),
          outstandingAmount: byMember[userId] ?? 0,
        ),
    ];
    memberOutstanding.sort((left, right) {
      final byAmount = right.outstandingAmount.compareTo(left.outstandingAmount);
      return byAmount != 0 ? byAmount : left.userId.compareTo(right.userId);
    });

    return OutstandingBalance(
      totalOutstanding: totalOutstanding,
      outstandingByMember: memberOutstanding,
      overdueOutstanding: overdueOutstanding,
    );
  }

  static List<MemberContribution> _calculateMemberContributions(FinancialSnapshot snapshot) {
    final userIds = <String>{};
    final owedBy = <String, double>{};
    final paidBy = <String, double>{};
    final confirmedBy = <String, double>{};
    final outstandingBy = <String, double>{};

    for (final expense in snapshot.expenses) {
      for (final participant in snapshot.participantsFor(expense.id)) {
        final userId = participant.userId;
        if (userId.isEmpty) {
          continue;
        }
        userIds.add(userId);
        final owed = _nonNegative(participant.amountOwed);
        owedBy[userId] = (owedBy[userId] ?? 0) + owed;
        switch (participant.state) {
          case PaymentState.paid:
            paidBy[userId] = (paidBy[userId] ?? 0) + owed;
            break;
          case PaymentState.confirmed:
            confirmedBy[userId] = (confirmedBy[userId] ?? 0) + owed;
            break;
          case PaymentState.pending:
            outstandingBy[userId] = (outstandingBy[userId] ?? 0) + owed;
            break;
        }
      }
    }

    double totalConfirmed = 0;
    for (final confirmed in confirmedBy.values) {
      totalConfirmed += confirmed;
    }

    final ids = userIds.toList()..sort();
    final contributions = [
      for (final userId in ids)
        MemberContribution(
          userId: userId,
          name: snapshot.nameFor(userId),
          owedAmount: owedBy[userId] ?? 0,
          markedPaidAmount: paidBy[userId] ?? 0,
          confirmedAmount: confirmedBy[userId] ?? 0,
          outstandingAmount: outstandingBy[userId] ?? 0,
          contributionPercentage: totalConfirmed <= 0
              ? 0
              : ((confirmedBy[userId] ?? 0) / totalConfirmed) * 100,
        ),
    ];
    contributions.sort((left, right) {
      final byConfirmed = right.confirmedAmount.compareTo(left.confirmedAmount);
      if (byConfirmed != 0) return byConfirmed;
      final byPaid = right.markedPaidAmount.compareTo(left.markedPaidAmount);
      if (byPaid != 0) return byPaid;
      return left.userId.compareTo(right.userId);
    });
    return contributions;
  }

  static CompletionStats _calculateCompletionStats(FinancialSnapshot snapshot) {
    int totalParticipants = 0;
    int confirmedParticipants = 0;
    for (final expense in snapshot.expenses) {
      for (final participant in snapshot.participantsFor(expense.id)) {
        totalParticipants += 1;
        if (participant.state == PaymentState.confirmed) {
          confirmedParticipants += 1;
        }
      }
    }

    final totalBills = snapshot.expenses.length;
    int settledBills = 0;
    int settlementDaySum = 0;
    int settlementSamples = 0;

    for (final expense in snapshot.expenses) {
      if (expense.status != 'confirmed') {
        continue;
      }
      settledBills += 1;

      DateTime? latestConfirmedAt;
      for (final participant in snapshot.participantsFor(expense.id)) {
        final confirmedAt = participant.confirmedAt;
        if (confirmedAt != null &&
            (latestConfirmedAt == null || confirmedAt.isAfter(latestConfirmedAt))) {
          latestConfirmedAt = confirmedAt;
        }
      }
      if (latestConfirmedAt == null) {
        continue;
      }
      final basis = expense.createdAt ?? expense.dueDate;
      final days = latestConfirmedAt.difference(basis).inDays;
      settlementDaySum += days < 0 ? 0 : days;
      settlementSamples += 1;
    }

    return CompletionStats(
      completionRate: totalBills == 0 ? 0 : settledBills / totalBills,
      participantPaymentRate: totalParticipants == 0
          ? 0
          : confirmedParticipants / totalParticipants,
      averageSettlementDays: settlementSamples == 0
          ? null
          : (settlementDaySum / settlementSamples).round(),
      settledBillCount: settledBills,
      totalBillCount: totalBills,
      totalParticipants: totalParticipants,
      confirmedParticipants: confirmedParticipants,
    );
  }

  static List<FinancialInsight> _calculateInsights({
    required AnalyticsOverview overview,
    required List<CategoryShare> categories,
    required OutstandingBalance outstanding,
    required CompletionStats completion,
    required int billCount,
  }) {
    if (billCount == 0) {
      return const [
        FinancialInsight(
          type: FinancialInsightType.noData,
          severity: FinancialInsightSeverity.info,
          message: 'No bills recorded for this period yet.',
        ),
      ];
    }

    final insights = <FinancialInsight>[];

    if (overview.overdueBillCount > 0) {
      insights.add(
        FinancialInsight(
          type: FinancialInsightType.overdueBills,
          severity: FinancialInsightSeverity.warning,
          message:
              '${overview.overdueBillCount} bill${overview.overdueBillCount == 1 ? ' is' : 's are'} past the due date.',
        ),
      );
    }

    final pendingRatio = overview.totalRequestedAmount > 0
        ? overview.totalOutstandingAmount / overview.totalRequestedAmount
        : 0;
    if (overview.totalOutstandingAmount > 0 && pendingRatio > 0.4) {
      insights.add(
        FinancialInsight(
          type: FinancialInsightType.highPending,
          severity: FinancialInsightSeverity.warning,
          message: 'More than 40% of requested money is still pending confirmation.',
        ),
      );
    }

    if (outstanding.totalOutstanding > 0) {
      final largestMemberOwed = outstanding.outstandingByMember.isEmpty
          ? 0.0
          : outstanding.outstandingByMember.first.outstandingAmount;
      insights.add(
        FinancialInsight(
          type: FinancialInsightType.memberBalance,
          severity: FinancialInsightSeverity.warning,
          message:
              'Members still owe ₺${_formatAmount(outstanding.totalOutstanding)}'
              '${outstanding.outstandingByMember.length == 1 && largestMemberOwed == outstanding.totalOutstanding ? ' (one member)' : ''}.',
        ),
      );
    }

    if (categories.isNotEmpty && billCount > 1 && categories.first.percentage > 60) {
      insights.add(
        FinancialInsight(
          type: FinancialInsightType.topCategory,
          severity: FinancialInsightSeverity.info,
          message: '${categories.first.category} accounts for most spending this period.',
        ),
      );
    }

    final averageSettlementDays = completion.averageSettlementDays;
    if (averageSettlementDays != null && averageSettlementDays > 7) {
      insights.add(
        FinancialInsight(
          type: FinancialInsightType.settlementSpeed,
          severity: FinancialInsightSeverity.info,
          message: 'Bills took about $averageSettlementDays days to settle on average.',
        ),
      );
    }

    return insights;
  }

  static double _nonNegative(num value) {
    if (value.isNaN || value.isInfinite || value < 0) {
      return 0;
    }
    return value.toDouble();
  }

  static String _formatAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  static const List<String> _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

class _MonthAccumulator {
  final int year;
  final int month;
  double total = 0;
  int count = 0;

  _MonthAccumulator({required this.year, required this.month});
}
