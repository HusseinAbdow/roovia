import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthServiceException implements Exception {
  final String message;

  const AuthServiceException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Sign up
  Future<RooviaUser?> signUp(String name, String email, String password) async {
    UserCredential? credential;

    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        throw const AuthServiceException(
          'Unable to create your account right now.',
        );
      }

      await firebaseUser.updateDisplayName(name);

      final user = RooviaUser(uid: firebaseUser.uid, name: name, email: email);

      await _db.collection('users').doc(user.uid).set(user.toMap());
      return user;
    } on FirebaseAuthException catch (e) {
      throw AuthServiceException(_authErrorMessage(e));
    } on FirebaseException catch (e) {
      await _rollbackFailedSignUp(credential?.user);

      if (e.code == 'permission-denied') {
        throw const AuthServiceException(
          'Account created, but profile setup was blocked by Firestore rules.',
        );
      }

      throw AuthServiceException(
        e.message ?? 'Your account could not be completed. Please try again.',
      );
    } catch (e) {
      await _rollbackFailedSignUp(credential?.user);
      throw AuthServiceException(_unexpectedErrorMessage(e));
    }
  }

  // Sign in
  Future<RooviaUser?> signIn(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        throw const AuthServiceException('Unable to sign in right now.');
      }

      final fallbackUser = _buildAuthBackedUser(firebaseUser, email);

      try {
        final doc = await _db.collection('users').doc(firebaseUser.uid).get();
        final data = doc.data();

        if (data != null) {
          return RooviaUser.fromMap({
            ...data,
            'uid': data['uid'] ?? firebaseUser.uid,
            'name': data['name'] ?? fallbackUser.name,
            'email': data['email'] ?? fallbackUser.email,
          });
        }

        await _db
            .collection('users')
            .doc(fallbackUser.uid)
            .set(fallbackUser.toMap());
      } on FirebaseException {
        return fallbackUser;
      } on TypeError {
        return fallbackUser;
      }

      return fallbackUser;
    } on FirebaseAuthException catch (e) {
      throw AuthServiceException(_authErrorMessage(e));
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<void> _rollbackFailedSignUp(User? firebaseUser) async {
    if (firebaseUser == null) {
      return;
    }

    try {
      await firebaseUser.delete();
    } catch (_) {
      if (_auth.currentUser?.uid == firebaseUser.uid) {
        await _auth.signOut();
      }
    }
  }

  String _authErrorMessage(FirebaseAuthException exception) {
    switch (exception.code) {
      case 'email-already-in-use':
        return 'That email is already in use.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password should be at least 6 characters long.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'network-request-failed':
        return 'Network error. Please check your connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      default:
        return exception.message ?? 'Authentication failed. Please try again.';
    }
  }

  String _unexpectedErrorMessage(Object error) {
    final message = error.toString().trim();
    if (message.isEmpty) {
      return 'Unexpected error while creating your account.';
    }

    return message;
  }

  RooviaUser _buildAuthBackedUser(User firebaseUser, String email) {
    return RooviaUser(
      uid: firebaseUser.uid,
      name: firebaseUser.displayName?.trim().isNotEmpty == true
          ? firebaseUser.displayName!.trim()
          : email.split('@').first,
      email: firebaseUser.email ?? email,
    );
  }
}
