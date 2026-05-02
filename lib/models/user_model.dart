class RooviaUser {
  final String uid;
  final String name;
  final String email;
  final String username;
  final String profileImageUrl;
  final double rating; // for future roommate rating

  RooviaUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.username,
    this.profileImageUrl = '',
    this.rating = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'username': username,
      'profileImageUrl': profileImageUrl,
      'rating': rating,
    };
  }

  factory RooviaUser.fromFirestore(Map<String, dynamic> map) {
    final email = map['email'] as String? ?? '';
    final emailPrefix = email.split('@').first.toLowerCase();
    final normalizedFallback = emailPrefix.replaceAll(RegExp(r'[^a-z0-9_]'), '');

    return RooviaUser(
      uid: map['uid'] as String? ?? '',
      name: map['name'] as String? ?? '',
      email: email,
      username: (map['username'] as String?)?.toLowerCase().trim().isNotEmpty == true
          ? (map['username'] as String).toLowerCase().trim()
          : (normalizedFallback.isNotEmpty ? normalizedFallback : 'user000'),
      profileImageUrl: (map['profileImageUrl'] as String?)?.trim() ?? '',
      rating: map['rating']?.toDouble() ?? 0.0,
    );
  }

  factory RooviaUser.fromMap(Map<String, dynamic> map) {
    return RooviaUser.fromFirestore(map);
  }
}
