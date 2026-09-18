import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:roovia/models/expense_model.dart';
import 'package:roovia/models/expense_participant.dart';
import 'package:roovia/models/financial_analytics.dart';

ExpenseParticipant participantFrom(String docId, Map<String, dynamic> data) {
  return ExpenseParticipant.fromMap(docId, data);
}

ExpenseModel buildExpense({
  required String id,
  DateTime? createdAt,
  required DateTime dueDate,
}) {
  return ExpenseModel(
    id: id,
    houseId: 'house-1',
    category: 'other',
    title: 'Bill $id',
    description: '',
    dueDate: dueDate,
    reference: '',
    totalAmount: 100,
    perPersonAmount: 50,
    createdBy: 'user-1',
    createdAt: createdAt,
    status: 'pending',
  );
}

void main() {
  group('ExpenseParticipant parsing', () {
    test('parses a fully populated participant document', () {
      final paidAt = DateTime(2026, 9, 10);
      final confirmedAt = DateTime(2026, 9, 12);
      final participant = participantFrom('user-1', {
        'userId': 'user-1',
        'amountOwed': 250.5,
        'status': 'paid',
        'paidAt': Timestamp.fromDate(paidAt),
        'confirmedAt': Timestamp.fromDate(confirmedAt),
        'paymentProofStatus': 'submitted',
        'paymentProofRevision': 2,
        'paymentProofs': [
          {'fileName': 'a.pdf'},
          {'fileName': 'b.pdf'},
        ],
      });

      expect(participant.userId, 'user-1');
      expect(participant.amountOwed, 250.5);
      expect(participant.status, 'paid');
      expect(participant.paidAt, paidAt);
      expect(participant.confirmedAt, confirmedAt);
      expect(participant.paymentProofStatus, 'submitted');
      expect(participant.paymentProofRevision, 2);
      expect(participant.paymentProofsCount, 2);
      expect(participant.state, PaymentState.paid);
    });

    test('missing fields fall back to safe defaults', () {
      final participant = participantFrom('user-2', <String, dynamic>{});

      expect(participant.userId, 'user-2');
      expect(participant.amountOwed, 0);
      expect(participant.status, 'pending');
      expect(participant.paidAt, isNull);
      expect(participant.confirmedAt, isNull);
      expect(participant.paymentProofStatus, isNull);
      expect(participant.paymentProofRevision, 0);
      expect(participant.paymentProofsCount, 0);
      expect(participant.state, PaymentState.pending);
    });

    test('document ID is authoritative when userId field is missing', () {
      final participant = participantFrom('doc-id-wins', <String, dynamic>{});
      expect(participant.userId, 'doc-id-wins');
    });

    test('int amountOwed is converted to double', () {
      final participant = participantFrom('user-3', {
        'amountOwed': 100,
        'status': 'confirmed',
      });

      expect(participant.amountOwed, 100.0);
      expect(participant.amountOwed, isA<double>());
      expect(participant.state, PaymentState.confirmed);
    });

    test('handles DateTime values in addition to Timestamp', () {
      final date = DateTime(2026, 1, 15);
      final participant = participantFrom('user-4', {
        'paidAt': date,
        'confirmedAt': date,
      });

      expect(participant.paidAt, date);
      expect(participant.confirmedAt, date);
    });

    test('unknown status string is preserved but maps to pending state', () {
      final participant = participantFrom('user-5', {'status': 'weird_state'});

      expect(participant.status, 'weird_state');
      expect(participant.state, PaymentState.pending);
    });
  });

  group('FinancialSnapshot.filterToPeriod', () {
    final namesById = {'user-1': 'Alice'};

    FinancialSnapshot buildSnapshot(List<ExpenseModel> expenses) {
      return FinancialSnapshot(
        houseId: 'house-1',
        expenses: expenses,
        participantsByExpenseId: {
          for (final expense in expenses)
            expense.id: [
              const ExpenseParticipant(
                userId: 'user-1',
                amountOwed: 10,
                status: 'pending',
                paidAt: null,
                confirmedAt: null,
                paymentProofStatus: null,
                paymentProofRevision: 0,
                paymentProofsCount: 0,
              ),
            ],
        },
        namesById: namesById,
        house: null,
        loadedAt: DateTime(2026, 9, 15),
      );
    }

    test('does not mutate the original snapshot', () {
      final now = DateTime(2026, 9, 15);
      final original = buildSnapshot([
        buildExpense(
          id: 'old',
          createdAt: DateTime(2025, 1, 1),
          dueDate: DateTime(2025, 2, 1),
        ),
        buildExpense(
          id: 'new',
          createdAt: DateTime(2026, 9, 1),
          dueDate: DateTime(2026, 9, 20),
        ),
      ]);

      final filtered = original.filterToPeriod(
        AnalyticsPeriod.last3Months,
        now,
      );

      expect(original.expenses.length, 2);
      expect(filtered.expenses.length, 1);
      expect(filtered.expenses.first.id, 'new');
      expect(original.houseId, filtered.houseId);
      expect(original.loadedAt, filtered.loadedAt);
      expect(original.house, filtered.house);
      expect(identical(original.namesById, filtered.namesById), isTrue);
    });

    test('falls back to dueDate when createdAt is null', () {
      final now = DateTime(2026, 9, 15);
      final snapshot = buildSnapshot([
        buildExpense(id: 'a', createdAt: null, dueDate: DateTime(2026, 1, 1)),
        buildExpense(id: 'b', createdAt: null, dueDate: DateTime(2026, 9, 1)),
      ]);

      final filtered = snapshot.filterToPeriod(
        AnalyticsPeriod.last3Months,
        now,
      );

      expect(filtered.expenses.map((e) => e.id), ['b']);
    });

    test('preserves participants and names of filtered expenses', () {
      final now = DateTime(2026, 9, 15);
      final snapshot = buildSnapshot([
        buildExpense(
          id: 'kept',
          createdAt: DateTime(2026, 9, 1),
          dueDate: DateTime(2026, 9, 10),
        ),
        buildExpense(
          id: 'dropped',
          createdAt: DateTime(2025, 3, 1),
          dueDate: DateTime(2025, 4, 1),
        ),
      ]);

      final filtered = snapshot.filterToPeriod(
        AnalyticsPeriod.last6Months,
        now,
      );

      expect(filtered.participantsByExpenseId.keys, ['kept']);
      expect(filtered.participantsFor('kept').first.userId, 'user-1');
      expect(filtered.participantsFor('dropped'), isEmpty);
      expect(filtered.nameFor('user-1'), 'Alice');
      expect(filtered.nameFor('unknown'), 'Member');
      expect(filtered.houseId, 'house-1');
      expect(filtered.loadedAt, DateTime(2026, 9, 15));
    });

    test('all period keeps every expense', () {
      final now = DateTime(2026, 9, 15);
      final snapshot = buildSnapshot([
        buildExpense(
          id: 'ancient',
          createdAt: DateTime(2020, 1, 1),
          dueDate: DateTime(2020, 1, 5),
        ),
        buildExpense(
          id: 'recent',
          createdAt: DateTime(2026, 9, 1),
          dueDate: DateTime(2026, 9, 10),
        ),
      ]);

      final filtered = snapshot.filterToPeriod(AnalyticsPeriod.all, now);

      expect(filtered.expenses.length, 2);
    });
  });

  group('HouseFinancialAnalytics.compute (minimal Phase 1)', () {
    FinancialSnapshot buildSnapshot(List<ExpenseModel> expenses) {
      return FinancialSnapshot(
        houseId: 'house-1',
        expenses: expenses,
        participantsByExpenseId: const {},
        namesById: const {},
        house: null,
        loadedAt: DateTime(2026, 9, 15),
      );
    }

    test('empty snapshot produces zeroed overview', () {
      final analytics = HouseFinancialAnalytics.compute(
        buildSnapshot(const []),
        period: AnalyticsPeriod.all,
        now: DateTime(2026, 9, 15),
      );

      expect(analytics.overview.totalRequestedAmount, 0);
      expect(analytics.overview.billCount, 0);
      expect(analytics.overview.settledBillCount, 0);
      expect(analytics.overview.overdueBillCount, 0);
      expect(analytics.completion.completionRate, 0);
    });

    test('aggregates participant state amounts and overdue count', () {
      final now = DateTime(2026, 9, 15);
      final snapshot = buildSnapshot([
        buildExpense(
          id: 'overdue',
          createdAt: DateTime(2026, 8, 1),
          dueDate: DateTime(2026, 9, 1),
        ),
        buildExpense(
          id: 'future',
          createdAt: DateTime(2026, 9, 1),
          dueDate: DateTime(2026, 10, 1),
        ),
      ]);

      final analytics = HouseFinancialAnalytics.compute(
        snapshot,
        period: AnalyticsPeriod.all,
        now: now,
      );

      expect(analytics.overview.billCount, 2);
      expect(analytics.overview.overdueBillCount, 1);
      expect(analytics.overview.totalRequestedAmount, 200);
      expect(analytics.overview.totalOutstandingAmount, 0);
    });
  });
}
