import 'package:cloud_firestore/cloud_firestore.dart';

class ExpenseModel {
  final String id;
  final String houseId;
  final String category;
  final String title;
  final double totalAmount;
  final double perPersonAmount;
  final String createdBy;
  final DateTime? createdAt;
  final String status;

  const ExpenseModel({
    required this.id,
    required this.houseId,
    required this.category,
    required this.title,
    required this.totalAmount,
    required this.perPersonAmount,
    required this.createdBy,
    required this.createdAt,
    required this.status,
  });

  factory ExpenseModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdAtValue = data['createdAt'];

    return ExpenseModel(
      id: doc.id,
      houseId: data['houseId'] as String? ?? '',
      category: data['category'] as String? ?? 'other',
      title: data['title'] as String? ?? '',
      totalAmount: (data['totalAmount'] as num?)?.toDouble() ?? 0,
      perPersonAmount: (data['perPersonAmount'] as num?)?.toDouble() ?? 0,
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: createdAtValue is Timestamp
          ? createdAtValue.toDate()
          : createdAtValue is DateTime
          ? createdAtValue
          : null,
      status: data['status'] as String? ?? 'open',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'houseId': houseId,
      'category': category,
      'title': title,
      'totalAmount': totalAmount,
      'perPersonAmount': perPersonAmount,
      'createdBy': createdBy,
      'createdAt': createdAt,
      'status': status,
    };
  }
}
