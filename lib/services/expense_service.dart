import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/expense_model.dart';

class ExpenseService {
  static const Duration _networkTimeout = Duration(seconds: 15);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User get _currentUser {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user found');
    }
    return user;
  }

  Stream<List<ExpenseModel>> streamExpenses(String houseId) {
    final trimmedHouseId = houseId.trim();
    if (trimmedHouseId.isEmpty) {
      return const Stream<List<ExpenseModel>>.empty();
    }

    return _db
        .collection('house_expenses')
        .where('houseId', isEqualTo: trimmedHouseId)
        .snapshots()
        .map((snapshot) {
          final expenses = snapshot.docs.map(ExpenseModel.fromFirestore).toList();
          expenses.sort((left, right) {
            final leftCreatedAt = left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final rightCreatedAt = right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return rightCreatedAt.compareTo(leftCreatedAt);
          });
          return expenses;
        });
  }

  Future<String> createExpense({
    required String houseId,
    required String category,
    required String title,
    required double totalAmount,
    required List<String> members,
  }) async {
    final trimmedHouseId = houseId.trim();
    final trimmedCategory = category.trim().isEmpty ? 'other' : category.trim();
    final trimmedTitle = title.trim();
    final cleanedMembers = members
        .map((member) => member.trim())
        .where((member) => member.isNotEmpty)
        .toSet()
        .toList();

    if (trimmedHouseId.isEmpty) {
      throw ArgumentError('House ID cannot be empty');
    }
    if (trimmedTitle.isEmpty) {
      throw ArgumentError('Expense title cannot be empty');
    }
    if (totalAmount.isNaN || totalAmount.isInfinite || totalAmount < 0) {
      throw ArgumentError('Total amount must be a valid non-negative number');
    }
    if (cleanedMembers.isEmpty) {
      throw ArgumentError('At least 1 member is required');
    }

    final currentUserId = _currentUser.uid;
    final perPersonAmount = totalAmount / cleanedMembers.length;
    final expenseRef = _db.collection('house_expenses').doc();
    final batch = _db.batch();

    batch.set(expenseRef, {
      'houseId': trimmedHouseId,
      'category': trimmedCategory,
      'title': trimmedTitle,
      'totalAmount': totalAmount,
      'perPersonAmount': perPersonAmount,
      'createdBy': currentUserId,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'open',
    });

    for (final memberId in cleanedMembers) {
      batch.set(expenseRef.collection('participants').doc(memberId), {
        'userId': memberId,
        'amountOwed': perPersonAmount,
        'status': 'pending',
        'paidAt': null,
      });
    }

    // Create lightweight in-app notification documents for each participant
    // so members get alerted that a new bill was requested.
    try {
      for (final memberId in cleanedMembers) {
        if (memberId == currentUserId) continue;
        final notifRef = _db
            .collection('user_notifications')
            .doc(memberId)
            .collection('notifications')
            .doc();

        batch.set(notifRef, {
          'title': 'New bill requested',
          'body': '"$trimmedTitle" — ${trimmedCategory}',
          'createdAt': FieldValue.serverTimestamp(),
          'read': false,
          'type': 'expense_request',
          'payload': {'expenseId': expenseRef.id, 'houseId': trimmedHouseId},
        });
      }
    } catch (_) {
      // If notifications cannot be prepared for batching, ignore and continue.
    }

    await batch.commit().timeout(_networkTimeout);
    return expenseRef.id;
  }

  Future<void> markAsPaid(String expenseId, String userId) async {
    final trimmedExpenseId = expenseId.trim();
    final trimmedUserId = userId.trim();

    if (trimmedExpenseId.isEmpty || trimmedUserId.isEmpty) {
      throw ArgumentError('Expense ID and user ID cannot be empty');
    }

    final currentUserId = _currentUser.uid;
    if (trimmedUserId != currentUserId) {
      throw StateError('You can only mark your own payment as paid');
    }

    final participantRef = _db
        .collection('house_expenses')
        .doc(trimmedExpenseId)
        .collection('participants')
        .doc(trimmedUserId);
    final participantSnapshot = await participantRef.get().timeout(_networkTimeout);

    if (!participantSnapshot.exists) {
      throw StateError('Participant record not found');
    }

    final status = participantSnapshot.data()?['status'] as String? ?? 'pending';
    if (status == 'confirmed') {
      return;
    }

    await participantRef
        .update({'status': 'paid', 'paidAt': FieldValue.serverTimestamp()})
        .timeout(_networkTimeout);

    // Notify the expense creator that this participant marked as paid.
    try {
      final expenseRef = _db.collection('house_expenses').doc(trimmedExpenseId);
      final expenseSnapshot = await expenseRef.get().timeout(_networkTimeout);
      final expenseData = expenseSnapshot.data() ?? <String, dynamic>{};
      final creatorId = (expenseData['createdBy'] as String?) ?? '';
      if (creatorId.isNotEmpty) {
        await _db
            .collection('user_notifications')
            .doc(creatorId)
            .collection('notifications')
            .add({
              'title': 'Member marked paid',
              'body': '$trimmedUserId marked payment for ${trimmedExpenseId}',
              'createdAt': FieldValue.serverTimestamp(),
              'read': false,
              'type': 'payment_marked',
              'payload': {'expenseId': trimmedExpenseId, 'userId': trimmedUserId},
            })
            .timeout(_networkTimeout);
      }
    } catch (_) {}
  }

  Future<void> confirmPayment(String expenseId, String userId) async {
    final trimmedExpenseId = expenseId.trim();
    final trimmedUserId = userId.trim();

    if (trimmedExpenseId.isEmpty || trimmedUserId.isEmpty) {
      throw ArgumentError('Expense ID and user ID cannot be empty');
    }

    final expenseRef = _db.collection('house_expenses').doc(trimmedExpenseId);
    final expenseSnapshot = await expenseRef.get().timeout(_networkTimeout);
    final expenseData = expenseSnapshot.data();

    if (!expenseSnapshot.exists || expenseData == null) {
      throw StateError('Expense not found');
    }

    if ((expenseData['createdBy'] as String? ?? '') != _currentUser.uid) {
      throw StateError('Only the expense creator can confirm payments');
    }

    final participantRef = expenseRef.collection('participants').doc(trimmedUserId);
    final participantSnapshot = await participantRef.get().timeout(_networkTimeout);
    if (!participantSnapshot.exists) {
      throw StateError('Participant record not found');
    }

    final participantData = participantSnapshot.data() ?? const <String, dynamic>{};
    final currentStatus = participantData['status'] as String? ?? 'pending';
    if (currentStatus != 'paid') {
      throw StateError('Payment must be marked as paid first');
    }

    await participantRef.update({'status': 'confirmed'}).timeout(_networkTimeout);

    // Notify the participant that the owner confirmed their payment.
    try {
      await _db
          .collection('user_notifications')
          .doc(trimmedUserId)
          .collection('notifications')
          .add({
            'title': 'Payment confirmed',
            'body': 'Your payment for ${trimmedExpenseId} was confirmed',
            'createdAt': FieldValue.serverTimestamp(),
            'read': false,
            'type': 'payment_confirmed',
            'payload': {'expenseId': trimmedExpenseId},
          })
          .timeout(_networkTimeout);
    } catch (_) {}

    final participantsSnapshot = await expenseRef
        .collection('participants')
        .get()
        .timeout(_networkTimeout);
    final allConfirmed =
        participantsSnapshot.docs.isNotEmpty &&
        participantsSnapshot.docs.every(
          (doc) => (doc.data()['status'] as String? ?? 'pending') == 'confirmed',
        );

    await expenseRef
        .update({'status': allConfirmed ? 'confirmed' : 'open'})
        .timeout(_networkTimeout);
  }
}
