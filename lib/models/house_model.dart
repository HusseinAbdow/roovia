import 'package:cloud_firestore/cloud_firestore.dart';

class House {
  final String houseId;
  final String name;
  final String leaderId;
  final List<String> members;
  final String inviteCode;
  final bool discoverable;
  final String city;
  final String district;
  final String address;
  final int maxMembers;
  final String description;
  final DateTime? createdAt;

  House({
    required this.houseId,
    required this.name,
    required this.leaderId,
    required this.members,
    required this.inviteCode,
    required this.discoverable,
    required this.city,
    required this.district,
    required this.address,
    required this.maxMembers,
    required this.description,
    this.createdAt,
  });

  factory House.fromMap(Map<String, dynamic> map) {
    final createdAtValue = map['createdAt'];

    return House(
      houseId: map['houseId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      leaderId: map['leaderId'] as String? ?? '',
      members: List<String>.from(map['members'] as List<dynamic>? ?? const []),
      inviteCode: map['inviteCode'] as String? ?? '',
      discoverable: map['discoverable'] as bool? ?? true,
      city: map['city'] as String? ?? '',
      district: map['district'] as String? ?? map['area'] as String? ?? '',
      address: map['address'] as String? ?? '',
      maxMembers: map['maxMembers'] as int? ?? 5,
      description: map['description'] as String? ?? '',
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
      'inviteCode': inviteCode,
      'discoverable': discoverable,
      'city': city,
      'district': district,
      'address': address,
      'maxMembers': maxMembers,
      'description': description,
      'createdAt': createdAt,
    };
  }
}
