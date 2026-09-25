import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';

import '../models/expense_model.dart';
import '../models/payment_proof.dart';

class ExpenseService {
  static const Duration _networkTimeout = Duration(seconds: 15);
  static const int _maxProofAttachmentCount = 3;
  static const int _maxProofAttachmentSizeBytes = 12 * 1024 * 1024;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

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

  String _safePathSegment(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return cleaned.isEmpty ? 'proof' : cleaned;
  }

  String _guessProofKind(PaymentProofInput input) {
    if (input.isPdf || input.mimeType.toLowerCase().contains('pdf')) {
      return 'pdf';
    }
    return 'image';
  }

  String _guessMimeType(PaymentProofInput input) {
    final lowerMime = input.mimeType.trim().toLowerCase();
    if (lowerMime.isNotEmpty) {
      return lowerMime;
    }
    return _guessProofKind(input) == 'pdf' ? 'application/pdf' : 'image/jpeg';
  }

  Future<String> _getDownloadUrlWithRetry(Reference reference) async {
    const maxAttempts = 3;
    var attempt = 0;

    while (true) {
      attempt += 1;
      try {
        return await reference.getDownloadURL();
      } on FirebaseException catch (error) {
        final shouldRetry = error.code == 'object-not-found' && attempt < maxAttempts;
        if (!shouldRetry) {
          rethrow;
        }
      }

      await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
    }
  }

  String _proofStoragePath({
    required String expenseId,
    required String userId,
    required String fileName,
    required int revision,
    required int index,
  }) {
    final safeExpenseId = _safePathSegment(expenseId);
    final safeUserId = _safePathSegment(userId);
    final safeFileName = _safePathSegment(fileName);
    final uniqueStamp = DateTime.now().microsecondsSinceEpoch + Random().nextInt(9999);
    return 'bills/$safeExpenseId/payments/$safeUserId/proofs/${revision}_${index}_${uniqueStamp}_$safeFileName';
  }

  Future<List<PaymentProofAttachment>> _uploadProofAttachments({
    required String expenseId,
    required String userId,
    required int revision,
    required List<PaymentProofInput> attachments,
    void Function(int completed, int total)? onUploadProgress,
  }) async {
    if (attachments.length > _maxProofAttachmentCount) {
      throw StateError('You can attach at most $_maxProofAttachmentCount files');
    }

    final uploaded = <PaymentProofAttachment>[];
    for (var index = 0; index < attachments.length; index += 1) {
      final input = attachments[index];
      if (input.sizeBytes <= 0) {
        throw StateError('One of the attached files is empty');
      }
      if (input.sizeBytes > _maxProofAttachmentSizeBytes) {
        throw StateError('Each proof file must be smaller than 12 MB');
      }

      final kind = _guessProofKind(input);
      if (kind != 'pdf') {
        throw StateError('Only PDF payment proofs are supported');
      }
      final mimeType = _guessMimeType(input);
      final fileName = _safePathSegment(input.fileName);
      final storagePath = _proofStoragePath(
        expenseId: expenseId,
        userId: userId,
        fileName: fileName,
        revision: revision,
        index: index,
      );

      final reference = _storage.ref(storagePath);
      final uploadTask = reference.putData(input.bytes, SettableMetadata(contentType: mimeType));
      final snapshot = await uploadTask;
      final downloadUrl = await _getDownloadUrlWithRetry(snapshot.ref);

      uploaded.add(
        PaymentProofAttachment(
          fileName: input.fileName,
          downloadUrl: downloadUrl,
          storagePath: storagePath,
          mimeType: mimeType,
          kind: kind,
          sizeBytes: input.sizeBytes,
          uploadedAt: DateTime.now(),
        ),
      );

      if (onUploadProgress != null) {
        onUploadProgress(index + 1, attachments.length);
      }
    }

    return uploaded;
  }

  Future<void> _deleteProofAttachments(List<PaymentProofAttachment> attachments) async {
    for (final attachment in attachments) {
      final path = attachment.storagePath.trim();
      if (path.isEmpty) {
        continue;
      }

      try {
        await _storage.ref(path).delete();
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  }

  List<PaymentProofAttachment> _parseAttachments(dynamic raw) {
    if (raw is! List) {
      return const <PaymentProofAttachment>[];
    }

    return raw
        .whereType<Map>()
        .map((entry) => PaymentProofAttachment.fromMap(Map<String, dynamic>.from(entry)))
        .where(
          (attachment) => attachment.downloadUrl.isNotEmpty || attachment.storagePath.isNotEmpty,
        )
        .toList();
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

  Future<void> markAsPaid(
    String expenseId,
    String userId, {
    List<PaymentProofInput> attachments = const [],
    String note = '',
    void Function(int completed, int total)? onUploadProgress,
  }) async {
    final trimmedExpenseId = expenseId.trim();
    final trimmedUserId = userId.trim();

    if (trimmedExpenseId.isEmpty || trimmedUserId.isEmpty) {
      throw ArgumentError('Expense ID and user ID cannot be empty');
    }

    final currentUserId = _currentUser.uid;
    if (trimmedUserId != currentUserId) {
      throw StateError('You can only mark your own payment as paid');
    }

    final expenseRef = _db.collection('house_expenses').doc(trimmedExpenseId);
    final expenseSnapshot = await expenseRef.get().timeout(_networkTimeout);
    if (!expenseSnapshot.exists) {
      throw StateError('Expense not found');
    }

    final expenseData = expenseSnapshot.data() ?? const <String, dynamic>{};
    final expenseTitle = (expenseData['title'] as String?) ?? 'a bill';
    final creatorId = (expenseData['createdBy'] as String?) ?? '';

    final participantRef = expenseRef.collection('participants').doc(trimmedUserId);
    final participantSnapshot = await participantRef.get().timeout(_networkTimeout);

    if (!participantSnapshot.exists) {
      throw StateError('Participant record not found');
    }

    final participantData = participantSnapshot.data() ?? const <String, dynamic>{};
    final status = participantData['status'] as String? ?? 'pending';
    // Only allow pending -> paid transition
    if (status != 'pending') {
      throw StateError('Payment can only be marked from pending state');
    }

    final currentRevision = (participantData['paymentProofRevision'] as num?)?.toInt() ?? 0;
    final proofRevision = currentRevision + 1;
    final cleanedNote = note.trim();
    final proofAttachments = attachments.isEmpty
        ? const <PaymentProofAttachment>[]
        : await _uploadProofAttachments(
            expenseId: trimmedExpenseId,
            userId: trimmedUserId,
            revision: proofRevision,
            attachments: attachments,
            onUploadProgress: onUploadProgress,
          );

    try {
      await participantRef
          .update({
            'status': 'paid',
            'paidAt': FieldValue.serverTimestamp(),
            'paymentProofStatus': 'submitted',
            'paymentProofRevision': proofRevision,
            'paymentProofNote': cleanedNote.isEmpty ? null : cleanedNote,
            'paymentProofs': proofAttachments.map((attachment) => attachment.toMap()).toList(),
            'paymentProofSubmittedAt': FieldValue.serverTimestamp(),
            'paymentProofReviewedAt': null,
            'paymentProofReviewReason': null,
          })
          .timeout(_networkTimeout);
    } catch (error) {
      if (proofAttachments.isNotEmpty) {
        await _deleteProofAttachments(proofAttachments);
      }
      rethrow;
    }

    // Notify the expense creator that this participant marked as paid.
    try {
      if (creatorId.isNotEmpty) {
        // Get the user's name for better notification text
        final userDoc = await _db.collection('users').doc(trimmedUserId).get();
        final userData = userDoc.data() ?? const <String, dynamic>{};
        final userName = (userData['name'] as String?)?.trim().isNotEmpty == true
            ? (userData['name'] as String).trim()
            : (userData['username'] as String?)?.trim().isNotEmpty == true
            ? (userData['username'] as String).trim()
            : 'A member';
        final amountOwed = (participantData['amountOwed'] as num?)?.toDouble() ?? 0.0;
        final proofSummary = proofAttachments.isEmpty
            ? 'Payment proof submitted'
            : '${proofAttachments.length} proof file${proofAttachments.length == 1 ? '' : 's'} uploaded';
        final notificationTitle = proofAttachments.isEmpty && cleanedNote.isEmpty
            ? 'Payment submitted'
            : 'Payment proof uploaded';
        final notificationBody = proofAttachments.isEmpty && cleanedNote.isEmpty
            ? '$userName marked $expenseTitle as paid'
            : '$userName uploaded payment proof for $expenseTitle';
        await _db
            .collection('user_notifications')
            .doc(creatorId)
            .collection('notifications')
            .doc(
              _notificationDocId(
                trimmedExpenseId,
                trimmedUserId,
                'payment_proof_submitted_$proofRevision',
              ),
            )
            .set({
              'title': notificationTitle,
              'body': notificationBody,
              'details': proofSummary,
              'createdAt': FieldValue.serverTimestamp(),
              'read': false,
              'type': 'payment_proof_submitted',
              'houseId': expenseData['houseId'] ?? '',
              'expenseId': trimmedExpenseId,
              'fromUserId': trimmedUserId,
              'userName': userName,
              'billTitle': expenseTitle,
              'billAmount': amountOwed,
              'paymentProofRevision': proofRevision,
              'paymentProofCount': proofAttachments.length,
              if (cleanedNote.isNotEmpty) 'paymentProofNote': cleanedNote,
            })
            .timeout(_networkTimeout);
      }
    } catch (_) {}

    // Note: the member-side flow intentionally stops here. It must not read
    // other members' participant documents (privacy boundary enforced by
    // Firestore rules). The expense creator is notified per payment above and
    // is responsible for confirming/settling the bill via the existing
    // leader-only confirmation flows.
  }

  Future<void> confirmPayment(String expenseId, String userId) async {
    await approvePaymentProof(expenseId, userId);
  }

  Future<void> approvePaymentProof(String expenseId, String userId) async {
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

    final revision = (participantData['paymentProofRevision'] as num?)?.toInt() ?? 0;
    final note = (participantData['paymentProofNote'] as String?)?.trim() ?? '';
    final attachments = _parseAttachments(participantData['paymentProofs']);

    await participantRef
        .update({
          'status': 'confirmed',
          'confirmedAt': FieldValue.serverTimestamp(),
          'paymentProofStatus': 'approved',
          'paymentProofReviewedAt': FieldValue.serverTimestamp(),
          'paymentProofReviewReason': null,
        })
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
          .doc(
            _notificationDocId(trimmedExpenseId, trimmedUserId, 'payment_proof_approved_$revision'),
          )
          .set({
            'title': 'Payment proof approved',
            'body': 'Your payment proof for $expenseTitle was approved',
            'createdAt': FieldValue.serverTimestamp(),
            'read': false,
            'type': 'payment_proof_approved',
            'houseId': expenseData['houseId'] ?? '',
            'expenseId': trimmedExpenseId,
            'fromUserId': _currentUser.uid,
            'userName': userName,
            'billTitle': expenseTitle,
            'billAmount': amountOwed,
            'paymentProofRevision': revision,
            'paymentProofCount': attachments.length,
            if (note.isNotEmpty) 'paymentProofNote': note,
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

  Future<void> rejectPaymentProof(String expenseId, String userId, {String reason = ''}) async {
    final trimmedExpenseId = expenseId.trim();
    final trimmedUserId = userId.trim();
    final trimmedReason = reason.trim();

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
      throw StateError('Only the expense creator can reject payments');
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

    final revision = (participantData['paymentProofRevision'] as num?)?.toInt() ?? 0;
    final attachments = _parseAttachments(participantData['paymentProofs']);

    await participantRef
        .update({
          'status': 'pending',
          'paidAt': null,
          'confirmedAt': null,
          'paymentProofStatus': 'rejected',
          'paymentProofReviewedAt': FieldValue.serverTimestamp(),
          'paymentProofReviewReason': trimmedReason.isEmpty ? null : trimmedReason,
          'paymentProofNote': null,
          'paymentProofs': <Map<String, dynamic>>[],
        })
        .timeout(_networkTimeout);

    await expenseRef.update({'status': 'pending'}).timeout(_networkTimeout);

    await _deleteProofAttachments(attachments);

    try {
      final userDoc = await _db.collection('users').doc(trimmedUserId).get();
      final userData = userDoc.data() ?? const <String, dynamic>{};
      final userName = (userData['name'] as String?)?.trim().isNotEmpty == true
          ? (userData['name'] as String).trim()
          : (userData['username'] as String?)?.trim().isNotEmpty == true
          ? (userData['username'] as String).trim()
          : 'Your';
      final expenseTitle = (expenseData['title'] as String?) ?? 'a bill';

      await _db
          .collection('user_notifications')
          .doc(trimmedUserId)
          .collection('notifications')
          .doc(
            _notificationDocId(trimmedExpenseId, trimmedUserId, 'payment_proof_rejected_$revision'),
          )
          .set({
            'title': 'Payment proof rejected',
            'body': trimmedReason.isNotEmpty
                ? 'Your payment proof for $expenseTitle was rejected: $trimmedReason'
                : 'Your payment proof for $expenseTitle was rejected',
            'createdAt': FieldValue.serverTimestamp(),
            'read': false,
            'type': 'payment_proof_rejected',
            'houseId': expenseData['houseId'] ?? '',
            'expenseId': trimmedExpenseId,
            'fromUserId': _currentUser.uid,
            'userName': userName,
            'billTitle': expenseTitle,
            'paymentProofRevision': revision,
            if (trimmedReason.isNotEmpty) 'paymentProofReviewReason': trimmedReason,
          })
          .timeout(_networkTimeout);
    } catch (_) {}
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
