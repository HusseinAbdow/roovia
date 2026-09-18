import 'package:flutter_test/flutter_test.dart';

import 'package:roovia/models/expense_model.dart';
import 'package:roovia/models/expense_participant.dart';
import 'package:roovia/models/financial_analytics.dart';
import 'package:roovia/services/analytics_service.dart';

ExpenseModel buildExpense({
  required String id,
  String createdBy = 'creator-1',
  DateTime? createdAt,
}) {
  return ExpenseModel(
    id: id,
    houseId: 'house-1',
    category: 'other',
    title: 'Bill $id',
    description: '',
    dueDate: DateTime(2026, 10, 1),
    reference: '',
    totalAmount: 100,
    perPersonAmount: 50,
    createdBy: createdBy,
    createdAt: createdAt ?? DateTime(2026, 9, 1),
    status: 'pending',
  );
}

ExpenseParticipant buildParticipant(String userId) {
  return ExpenseParticipant(
    userId: userId,
    amountOwed: 50,
    status: 'pending',
    paidAt: null,
    confirmedAt: null,
    paymentProofStatus: null,
    paymentProofRevision: 0,
    paymentProofsCount: 0,
  );
}

void main() {
  group('AnalyticsService.collectUserIdsForNameResolution', () {
    test('collects creator IDs and participant user IDs without duplicates', () {
      final expenses = [
        buildExpense(id: 'e1', createdBy: 'creator-1'),
        buildExpense(id: 'e2', createdBy: 'creator-2'),
      ];
      final participants = {
        'e1': [buildParticipant('creator-1'), buildParticipant('member-1')],
        'e2': [buildParticipant('member-1'), buildParticipant('member-2')],
      };

      final ids = AnalyticsService.collectUserIdsForNameResolution(expenses, participants);

      expect(ids.toSet(), {'creator-1', 'creator-2', 'member-1', 'member-2'});
      expect(ids.length, ids.toSet().length);
    });

    test('returns empty list for empty snapshot inputs', () {
      final ids = AnalyticsService.collectUserIdsForNameResolution(const [], const {});

      expect(ids, isEmpty);
    });

    test('ignores blank creator and participant IDs', () {
      final expenses = [buildExpense(id: 'e1', createdBy: '  ')];
      final participants = {
        'e1': [
          const ExpenseParticipant(
            userId: '',
            amountOwed: 0,
            status: 'pending',
            paidAt: null,
            confirmedAt: null,
            paymentProofStatus: null,
            paymentProofRevision: 0,
            paymentProofsCount: 0,
          ),
        ],
      };

      final ids = AnalyticsService.collectUserIdsForNameResolution(expenses, participants);

      expect(ids, isEmpty);
    });
  });

  group('FinancialSnapshot construction (service output shape)', () {
    test('snapshot constructed with expense → participant mapping intact', () {
      final expenses = [buildExpense(id: 'e1'), buildExpense(id: 'e2')];
      final participants = {
        'e1': [buildParticipant('member-1')],
        'e2': [buildParticipant('member-2'), buildParticipant('member-3')],
      };

      final snapshot = FinancialSnapshot(
        houseId: 'house-1',
        expenses: expenses,
        participantsByExpenseId: participants,
        namesById: const {'member-1': 'Alice'},
        house: null,
        loadedAt: DateTime(2026, 9, 15),
      );

      expect(snapshot.houseId, 'house-1');
      expect(snapshot.expenses.length, 2);
      expect(snapshot.participantsFor('e1').length, 1);
      expect(snapshot.participantsFor('e2').length, 2);
      expect(snapshot.participantsFor('e1').first.userId, 'member-1');
      expect(snapshot.participantsFor('e2').map((p) => p.userId), ['member-2', 'member-3']);
      expect(snapshot.participantsFor('missing'), isEmpty);
      expect(snapshot.nameFor('member-1'), 'Alice');
      expect(snapshot.nameFor('deleted-user'), 'Member');
      expect(snapshot.loadedAt, DateTime(2026, 9, 15));
    });

    test('snapshot with no expenses has empty participants and valid accessors', () {
      final snapshot = FinancialSnapshot(
        houseId: 'house-1',
        expenses: const [],
        participantsByExpenseId: const {},
        namesById: const {},
        house: null,
        loadedAt: DateTime(2026, 9, 15),
      );

      expect(snapshot.expenses, isEmpty);
      expect(snapshot.participantsFor('any'), isEmpty);
      expect(snapshot.nameFor('user-x'), 'Member');
    });
  });
}
