import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/house_model.dart';

class HouseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User get _currentUser {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user found');
    }
    return user;
  }

  Stream<House?> getCurrentUserHouse() {
    final uid = _currentUser.uid;

    return _db
        .collection('houses')
        .where('members', arrayContains: uid)
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) {
            return null;
          }

          return House.fromMap(snapshot.docs.first.data());
        });
  }

  Future<House> createHouse(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('House name cannot be empty');
    }

    final uid = _currentUser.uid;
    final docRef = _db.collection('houses').doc();
    final data = {
      'houseId': docRef.id,
      'name': trimmedName,
      'leaderId': uid,
      'members': [uid],
      'createdAt': FieldValue.serverTimestamp(),
    };

    await docRef.set(data);

    final snapshot = await docRef.get();
    return House.fromMap(snapshot.data() ?? data);
  }
}
