import 'package:cloud_firestore/cloud_firestore.dart';

class House {
  final String houseId;
  final String name;
  final String? chatName;
  final String leaderId;
  final List<String> members;
  final String inviteCode;
  final bool discoverable;
  final String city;
  final String district;
  final String address;
  final double rentTotal;
  final double electricityTotal;
  final double waterTotal;
  final double internetTotal;
  final int maxMembers;
  final String description;
  final DateTime? createdAt;

  House({
    required this.houseId,
    required this.name,
    this.chatName,
    required this.leaderId,
    required this.members,
    required this.inviteCode,
    required this.discoverable,
    required this.city,
    required this.district,
    required this.address,
    required this.rentTotal,
    required this.electricityTotal,
    required this.waterTotal,
    required this.internetTotal,
    required this.maxMembers,
    required this.description,
    this.createdAt,
  });

  double get totalHouseCost => rentTotal + electricityTotal + waterTotal + internetTotal;

  String get displayChatName {
    final normalizedChatName = chatName?.trim();
    if (normalizedChatName != null && normalizedChatName.isNotEmpty) {
      return normalizedChatName;
    }
    return '${name.trim()} Chat';
  }

  double get perPersonMonthlyCost {
    final normalizedMaxMembers = maxMembers < 1 ? 1 : maxMembers;
    return totalHouseCost / normalizedMaxMembers;
  }

  factory House.fromMap(Map<String, dynamic> map) {
    final createdAtValue = map['createdAt'];

    return House(
      houseId: map['houseId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      chatName: map['chatName'] as String?,
      leaderId: map['leaderId'] as String? ?? '',
      members: List<String>.from(map['members'] as List<dynamic>? ?? const []),
      inviteCode: map['inviteCode'] as String? ?? '',
      discoverable: map['discoverable'] as bool? ?? true,
      city: map['city'] as String? ?? '',
      district: map['district'] as String? ?? map['area'] as String? ?? '',
      address: map['address'] as String? ?? '',
      rentTotal: _asDouble(map['rentTotal']),
      electricityTotal: _asDouble(map['electricityTotal']),
      waterTotal: _asDouble(map['waterTotal']),
      internetTotal: _asDouble(map['internetTotal']),
      maxMembers: _asInt(map['maxMembers'], fallback: 1, min: 1),
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
      if (chatName != null && chatName!.trim().isNotEmpty) 'chatName': chatName,
      'leaderId': leaderId,
      'members': members,
      'inviteCode': inviteCode,
      'discoverable': discoverable,
      'city': city,
      'district': district,
      'address': address,
      'rentTotal': rentTotal,
      'electricityTotal': electricityTotal,
      'waterTotal': waterTotal,
      'internetTotal': internetTotal,
      'maxMembers': maxMembers,
      'description': description,
      'createdAt': createdAt,
    };
  }

  static double _asDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  static int _asInt(dynamic value, {required int fallback, required int min}) {
    int parsed = fallback;
    if (value is int) {
      parsed = value;
    } else if (value is num) {
      parsed = value.toInt();
    } else if (value is String) {
      parsed = int.tryParse(value) ?? fallback;
    }
    return parsed < min ? min : parsed;
  }
}
