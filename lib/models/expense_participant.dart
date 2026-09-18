import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentState { pending, paid, confirmed }

class ExpenseParticipant {
  final String userId;
  final double amountOwed;
  final String status;
  final DateTime? paidAt;
  final DateTime? confirmedAt;
  final String? paymentProofStatus;
  final int paymentProofRevision;
  final int paymentProofsCount;

  const ExpenseParticipant({
    required this.userId,
    required this.amountOwed,
    required this.status,
    required this.paidAt,
    required this.confirmedAt,
    required this.paymentProofStatus,
    required this.paymentProofRevision,
    required this.paymentProofsCount,
  });

  PaymentState get state {
    switch (status) {
      case 'paid':
        return PaymentState.paid;
      case 'confirmed':
        return PaymentState.confirmed;
      default:
        return PaymentState.pending;
    }
  }

  factory ExpenseParticipant.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return ExpenseParticipant.fromMap(
      doc.id,
      doc.data() ?? const <String, dynamic>{},
    );
  }

  factory ExpenseParticipant.fromMap(String docId, Map<String, dynamic> data) {
    final rawUserId = (data['userId'] as String?)?.trim() ?? '';
    final trimmedDocId = docId.trim();

    return ExpenseParticipant(
      userId: rawUserId.isNotEmpty ? rawUserId : trimmedDocId,
      amountOwed: (data['amountOwed'] as num?)?.toDouble() ?? 0,
      status: data['status'] as String? ?? 'pending',
      paidAt: _parseDate(data['paidAt']),
      confirmedAt: _parseDate(data['confirmedAt']),
      paymentProofStatus: data['paymentProofStatus'] as String?,
      paymentProofRevision:
          (data['paymentProofRevision'] as num?)?.toInt() ?? 0,
      paymentProofsCount: _parseProofsCount(data['paymentProofs']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  static int _parseProofsCount(dynamic value) {
    if (value is List) {
      return value.length;
    }
    return 0;
  }
}
