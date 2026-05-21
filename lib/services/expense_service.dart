import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

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

  String _displayNameFor(User user) {
    final displayName = user.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) {
      return displayName;
    }

    final email = user.email ?? '';
    if (email.contains('@')) {
      return email.split('@').first;
    }

    return 'A member';
  }

  String _notificationDocId(String expenseId, String userId, String kind) {
    return '${expenseId.trim()}_${userId.trim()}_$kind';
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
    required DateTime dueDate,
    required double totalAmount,
    required List<String> members,
    String description = '',
    String reference = '',
  }) async {
    final trimmedHouseId = houseId.trim();
    final trimmedCategory = category.trim().isEmpty ? 'other' : category.trim();
    final trimmedTitle = title.trim();
    final trimmedDescription = description.trim();
    final trimmedReference = reference.trim();
    final cleanedMembers = members
        .map((member) => member.trim())
        .where((member) => member.isNotEmpty)
        .where((member) => member != _currentUser.uid)
        .toSet()
        .toList();

    if (trimmedHouseId.isEmpty) {
      throw ArgumentError('House ID cannot be empty');
    }
    if (trimmedTitle.isEmpty) {
      throw ArgumentError('Expense title cannot be empty');
    }
    if (dueDate.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
      throw ArgumentError('Due date must be today or later');
    }
    if (totalAmount.isNaN || totalAmount.isInfinite || totalAmount < 0) {
      throw ArgumentError('Total amount must be a valid non-negative number');
    }
    if (cleanedMembers.isEmpty) {
      throw ArgumentError('At least 1 member is required');
    }

    final currentUser = _currentUser;
    final currentUserId = currentUser.uid;
    final currentUserName = _displayNameFor(currentUser);
    // Owner is always included in the split, but never stored in the selectable member list.
    final totalParticipants = cleanedMembers.length + 1;
    final perPersonAmount = totalAmount / totalParticipants;
    final expenseRef = _db.collection('house_expenses').doc();
    final batch = _db.batch();

    batch.set(expenseRef, {
      'houseId': trimmedHouseId,
      'category': trimmedCategory,
      'title': trimmedTitle,
      'description': trimmedDescription,
      'dueDate': Timestamp.fromDate(dueDate),
      'reference': trimmedReference,
      'totalAmount': totalAmount,
      'perPersonAmount': perPersonAmount,
      'createdBy': currentUserId,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
      'reminderEnabled': true,
      'reminderCount': 0,
      'overdueReminderCount': 0,
      'lastReminderAt': null,
      'lastReminderSentAt': null,
    });

    // Add owner as a confirmed participant (already paid their share)
    batch.set(expenseRef.collection('participants').doc(currentUserId), {
      'userId': currentUserId,
      'amountOwed': perPersonAmount,
      'status': 'confirmed',
      'confirmedAt': FieldValue.serverTimestamp(),
    });

    for (final memberId in cleanedMembers) {
      batch.set(expenseRef.collection('participants').doc(memberId), {
        'userId': memberId,
        'amountOwed': perPersonAmount,
        'status': 'pending',
        'paidAt': null,
      });
    }

    await batch.commit().timeout(_networkTimeout);

    // Create lightweight in-app notification documents for each participant.
    // Done separately so expense creation succeeds even if notifications fail.
    for (final memberId in cleanedMembers) {
      if (memberId == currentUserId) continue;
      try {
        final dueLabel = DateFormat('MMMM d').format(dueDate);
        await _db
            .collection('user_notifications')
            .doc(memberId)
            .collection('notifications')
            .doc(_notificationDocId(expenseRef.id, memberId, 'bill_created'))
            .set({
              'title': 'New House Bill',
              'body':
                  '$currentUserName created $trimmedTitle • ₺${totalAmount.toStringAsFixed(2)} due $dueLabel',
              'createdAt': FieldValue.serverTimestamp(),
              'read': false,
              'type': 'expense_request',
              'houseId': trimmedHouseId,
              'expenseId': expenseRef.id,
              'fromUserId': currentUserId,
              'billTitle': trimmedTitle,
              'billAmount': totalAmount,
              'dueDate': Timestamp.fromDate(dueDate),
            })
            .timeout(_networkTimeout);
      } catch (_) {
        // Notification creation failed, but expense is already created. Continue.
      }
    }

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
    // Only allow pending -> paid transition
    if (status != 'pending') {
      throw StateError('Payment can only be marked from pending state');
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
        // Get the user's name for better notification text
        final userDoc = await _db.collection('users').doc(trimmedUserId).get();
        final userData = userDoc.data() ?? const <String, dynamic>{};
        final userName = (userData['name'] as String?)?.trim().isNotEmpty == true
            ? (userData['name'] as String).trim()
            : (userData['username'] as String?)?.trim().isNotEmpty == true
            ? (userData['username'] as String).trim()
            : 'A member';
        final expenseTitle = (expenseData['title'] as String?) ?? 'a bill';
        final amountOwed = (participantSnapshot.data()?['amountOwed'] as num?)?.toDouble() ?? 0.0;
        await _db
            .collection('user_notifications')
            .doc(creatorId)
            .collection('notifications')
            .doc(_notificationDocId(trimmedExpenseId, trimmedUserId, 'payment_submitted'))
            .set({
              'title': 'Payment Submitted',
              'body': '$userName paid ₺${amountOwed.toStringAsFixed(2)} for $expenseTitle',
              'createdAt': FieldValue.serverTimestamp(),
              'read': false,
              'type': 'payment_marked',
              'houseId': expenseSnapshot.data()?['houseId'] ?? '',
              'expenseId': trimmedExpenseId,
              'fromUserId': trimmedUserId,
              'userName': userName,
              'billTitle': expenseTitle,
              'billAmount': amountOwed,
            })
            .timeout(_networkTimeout);
      }
    } catch (_) {}

    // After marking as paid, check if all non-owner participants have marked as 'paid'.
    try {
      final expenseRef = _db.collection('house_expenses').doc(trimmedExpenseId);
      final expenseSnapshot = await expenseRef.get().timeout(_networkTimeout);
      final expenseData = expenseSnapshot.data() ?? <String, dynamic>{};
      final creatorId = (expenseData['createdBy'] as String?) ?? '';
      if (creatorId.isNotEmpty) {
        final participantsSnapshot = await expenseRef
            .collection('participants')
            .get()
            .timeout(_networkTimeout);

        final nonOwnerParticipants = participantsSnapshot.docs
            .where((doc) => doc.id != creatorId)
            .toList();
        final allNonOwnersPaid =
            nonOwnerParticipants.isNotEmpty &&
            nonOwnerParticipants.every(
              (doc) => (doc.data()['status'] as String? ?? 'pending') == 'paid',
            );

        if (allNonOwnersPaid) {
          // Notify the creator that all members marked as paid and the bill is ready for owner confirmation.
          final expenseTitle = (expenseData['title'] as String?) ?? 'a bill';
          await _db
              .collection('user_notifications')
              .doc(creatorId)
              .collection('notifications')
              .doc(_notificationDocId(trimmedExpenseId, creatorId, 'owner_confirmation_ready'))
              .set({
                'title': 'Bill ready for confirmation',
                'body': 'All members have paid for $expenseTitle. Please confirm settlement.',
                'createdAt': FieldValue.serverTimestamp(),
                'read': false,
                'type': 'bill_ready_for_owner_confirmation',
                'houseId': expenseSnapshot.data()?['houseId'] ?? '',
                'expenseId': trimmedExpenseId,
                'fromUserId': trimmedUserId,
                'billTitle': expenseTitle,
              })
              .timeout(_networkTimeout);
        }
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

    await participantRef
        .update({'status': 'confirmed', 'confirmedAt': FieldValue.serverTimestamp()})
        .timeout(_networkTimeout);

    // Notify the participant that the owner confirmed their payment.
    try {
      // Get the user's name for better notification text
      final userDoc = await _db.collection('users').doc(trimmedUserId).get();
      final userData = userDoc.data() ?? const <String, dynamic>{};
      final userName = (userData['name'] as String?)?.trim().isNotEmpty == true
          ? (userData['name'] as String).trim()
          : (userData['username'] as String?)?.trim().isNotEmpty == true
          ? (userData['username'] as String).trim()
          : 'Your';
      final expenseTitle = (expenseData['title'] as String?) ?? 'a bill';
      final amountOwed = (participantSnapshot.data()?['amountOwed'] as num?)?.toDouble() ?? 0.0;

      await _db
          .collection('user_notifications')
          .doc(trimmedUserId)
          .collection('notifications')
          .doc(_notificationDocId(trimmedExpenseId, trimmedUserId, 'payment_confirmed'))
          .set({
            'title': 'Payment Confirmed',
            'body':
                'Your ₺${amountOwed.toStringAsFixed(2)} payment for $expenseTitle was confirmed',
            'createdAt': FieldValue.serverTimestamp(),
            'read': false,
            'type': 'payment_confirmed',
            'houseId': expenseData['houseId'] ?? '',
            'expenseId': trimmedExpenseId,
            'fromUserId': _currentUser.uid,
            'userName': userName,
            'billTitle': expenseTitle,
            'billAmount': amountOwed,
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

    if (allConfirmed) {
      await expenseRef.update({'status': 'confirmed'}).timeout(_networkTimeout);

      // Notify all participants that the bill is now fully paid/settled by the owner.
      try {
        final expenseTitle = (expenseData['title'] as String?) ?? 'a bill';
        final billAmount = (expenseData['totalAmount'] as num?)?.toDouble() ?? 0.0;
        for (final doc in participantsSnapshot.docs) {
          final participantId = doc.id;
          if (participantId == _currentUser.uid) continue; // skip creator/owner
          await _db
              .collection('user_notifications')
              .doc(participantId)
              .collection('notifications')
              .doc(_notificationDocId(trimmedExpenseId, participantId, 'bill_settled'))
              .set({
                'title': 'Bill settled',
                'body': '$expenseTitle is settled • ₺${billAmount.toStringAsFixed(2)} total',
                'createdAt': FieldValue.serverTimestamp(),
                'read': false,
                'type': 'bill_paid',
                'houseId': expenseData['houseId'] ?? '',
                'expenseId': trimmedExpenseId,
                'fromUserId': _currentUser.uid,
                'billTitle': expenseTitle,
                'billAmount': billAmount,
              })
              .timeout(_networkTimeout);
        }
      } catch (_) {}
    } else {
      await expenseRef.update({'status': 'pending'}).timeout(_networkTimeout);
    }
  }

  /// Confirms all participants who have status == 'paid' for the given expense.
  /// This is intended to be called by the expense creator as a final settlement action.
  Future<void> confirmAllPaidParticipants(String expenseId) async {
    final trimmedExpenseId = expenseId.trim();
    if (trimmedExpenseId.isEmpty) {
      throw ArgumentError('Expense ID cannot be empty');
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

    final participantsRef = expenseRef.collection('participants');
    final participantsSnapshot = await participantsRef.get().timeout(_networkTimeout);

    final batch = _db.batch();
    final List<String> toNotify = [];

    for (final doc in participantsSnapshot.docs) {
      final pid = doc.id;
      final pdata = doc.data();
      final status = (pdata['status'] as String?) ?? 'pending';
      if (status == 'paid') {
        final pRef = participantsRef.doc(pid);
        batch.update(pRef, {'status': 'confirmed', 'confirmedAt': FieldValue.serverTimestamp()});
        toNotify.add(pid);
      }
    }

    if (toNotify.isNotEmpty) {
      await batch.commit().timeout(_networkTimeout);

      // Send notifications to each participant that their payment was confirmed.
      try {
        final expenseTitle = (expenseData['title'] as String?) ?? 'a bill';
        for (final pid in toNotify) {
          final participantDoc = participantsSnapshot.docs.firstWhere((doc) => doc.id == pid);
          final participantAmount =
              (participantDoc.data()['amountOwed'] as num?)?.toDouble() ?? 0.0;
          await _db
              .collection('user_notifications')
              .doc(pid)
              .collection('notifications')
              .doc(_notificationDocId(trimmedExpenseId, pid, 'payment_confirmed_batch'))
              .set({
                'title': 'Payment confirmed',
                'body':
                    'Your ₺${participantAmount.toStringAsFixed(2)} payment for $expenseTitle was confirmed',
                'createdAt': FieldValue.serverTimestamp(),
                'read': false,
                'type': 'payment_confirmed',
                'houseId': expenseData['houseId'] ?? '',
                'expenseId': trimmedExpenseId,
                'fromUserId': _currentUser.uid,
                'billTitle': expenseTitle,
                'billAmount': participantAmount,
              })
              .timeout(_networkTimeout);
        }
      } catch (_) {}
    }

    // Re-load participants to determine final status
    final refreshed = await participantsRef.get().timeout(_networkTimeout);
    final allConfirmed =
        refreshed.docs.isNotEmpty &&
        refreshed.docs.every(
          (doc) => (doc.data()['status'] as String? ?? 'pending') == 'confirmed',
        );

    if (allConfirmed) {
      await expenseRef.update({'status': 'confirmed'}).timeout(_networkTimeout);

      // Notify all non-owner participants that the bill was settled by owner
      try {
        final expenseTitle = (expenseData['title'] as String?) ?? 'a bill';
        final billAmount = (expenseData['totalAmount'] as num?)?.toDouble() ?? 0.0;
        for (final doc in refreshed.docs) {
          final participantId = doc.id;
          if (participantId == _currentUser.uid) continue;
          await _db
              .collection('user_notifications')
              .doc(participantId)
              .collection('notifications')
              .doc(_notificationDocId(trimmedExpenseId, participantId, 'bill_settled_batch'))
              .set({
                'title': 'Bill settled',
                'body': '$expenseTitle is settled • ₺${billAmount.toStringAsFixed(2)} total',
                'createdAt': FieldValue.serverTimestamp(),
                'read': false,
                'type': 'bill_paid',
                'houseId': expenseData['houseId'] ?? '',
                'expenseId': trimmedExpenseId,
                'fromUserId': _currentUser.uid,
                'billTitle': expenseTitle,
                'billAmount': billAmount,
              })
              .timeout(_networkTimeout);
        }
      } catch (_) {}
    }
  }
}
