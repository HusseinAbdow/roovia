import 'package:cloud_firestore/cloud_firestore.dart';

class House {
  final String houseId;
  final String name;
  final String leaderId;
  final List<String> members;
  final DateTime? createdAt;

  House({
    required this.houseId,
    required this.name,
    required this.leaderId,
    required this.members,
    this.createdAt,
  });

  factory House.fromMap(Map<String, dynamic> map) {
    final createdAtValue = map['createdAt'];

    return House(
      houseId: map['houseId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      leaderId: map['leaderId'] as String? ?? '',
      members: List<String>.from(map['members'] as List<dynamic>? ?? const []),
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
      'name': name,
      'leaderId': leaderId,
      'members': members,
      'createdAt': createdAt,
    };
  }
}
