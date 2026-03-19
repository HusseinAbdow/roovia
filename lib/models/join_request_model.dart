import 'package:cloud_firestore/cloud_firestore.dart';

class JoinRequest {
  final String id;
  final String houseId;
  final String userId;
  final String status;
  final DateTime? createdAt;

  const JoinRequest({
    required this.id,
    required this.houseId,
    required this.userId,
    required this.status,
    this.createdAt,
  });

  factory JoinRequest.fromMap(String id, Map<String, dynamic> map) {
    final createdAtValue = map['createdAt'];

    return JoinRequest(
      id: id,
      houseId: map['houseId'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      status: map['status'] as String? ?? JoinRequestStatus.pending,
      createdAt: createdAtValue is Timestamp
          ? createdAtValue.toDate()
          : createdAtValue is DateTime
          ? createdAtValue
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'houseId': houseId,
      'userId': userId,
      'status': status,
      'createdAt': createdAt,
    };
  }
}

abstract final class JoinRequestStatus {
  static const String pending = 'pending';
  static const String accepted = 'accepted';
  static const String rejected = 'rejected';
}
