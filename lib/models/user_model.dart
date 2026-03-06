class RooviaUser {
  final String uid;
  final String name;
  final String email;
  final double rating; // for future roommate rating

  RooviaUser({
    required this.uid,
    required this.name,
    required this.email,
    this.rating = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {'uid': uid, 'name': name, 'email': email, 'rating': rating};
  }

  factory RooviaUser.fromMap(Map<String, dynamic> map) {
    return RooviaUser(
      uid: map['uid'],
      name: map['name'],
      email: map['email'],
      rating: map['rating']?.toDouble() ?? 0.0,
    );
  }
}
