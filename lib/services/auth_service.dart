import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Sign up
  Future<RooviaUser?> signUp(String name, String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = RooviaUser(
      uid: credential.user!.uid,
      name: name,
      email: email,
    );

    await _db.collection('users').doc(user.uid).set(user.toMap());
    return user;
  }

  // Sign in
  Future<RooviaUser?> signIn(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final doc = await _db.collection('users').doc(credential.user!.uid).get();
    return RooviaUser.fromMap(doc.data()!);
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
