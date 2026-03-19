import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

class AuthServiceException implements Exception {
  final String message;

  const AuthServiceException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  static const Duration _networkTimeout = Duration(seconds: 15);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _firestoreInfraErrorMessage(FirebaseException exception) {
    final message = (exception.message ?? '').toLowerCase();
    final isMissingDefaultDb =
        exception.code == 'not-found' &&
        message.contains('database (default) does not exist');

    if (isMissingDefaultDb) {
      return 'Cloud Firestore is not set up for this Firebase project yet. Please create the default Firestore database in Firebase Console and try again.';
    }

    return exception.message ?? 'Database request failed. Please try again.';
  }

  // Sign up
  Future<RooviaUser?> signUp(String name, String email, String password) async {
    UserCredential? credential;

    try {
      credential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password)
          .timeout(_networkTimeout);

      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        throw const AuthServiceException(
          'Unable to create your account right now.',
        );
      }

      await firebaseUser.updateDisplayName(name).timeout(_networkTimeout);

      final user = RooviaUser(uid: firebaseUser.uid, name: name, email: email);

      await _db
          .collection('users')
          .doc(user.uid)
          .set(user.toMap())
          .timeout(_networkTimeout);
      debugPrint('AuthService.signUp success: ${user.uid} ($email)');
      return user;
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('AuthService.signUp timeout: $e');
      debugPrintStack(stackTrace: stackTrace);
      await _rollbackFailedSignUp(credential?.user);
      throw const AuthServiceException(
        'Request timed out. Please check your network and try again.',
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('AuthService.signUp auth error: ${e.code}');
      throw AuthServiceException(_authErrorMessage(e));
    } on FirebaseException catch (e) {
      debugPrint('AuthService.signUp firestore error: ${e.code}');
      await _rollbackFailedSignUp(credential?.user);

      if (e.code == 'permission-denied') {
        throw const AuthServiceException(
          'Account created, but profile setup was blocked by Firestore rules.',
        );
      }

      throw AuthServiceException(_firestoreInfraErrorMessage(e));
    } catch (e, stackTrace) {
      debugPrint('AuthService.signUp unexpected error: $e');
      debugPrintStack(stackTrace: stackTrace);
      await _rollbackFailedSignUp(credential?.user);
      throw AuthServiceException(_unexpectedErrorMessage(e));
    }
  }

  // Sign in
  Future<RooviaUser?> signIn(String email, String password) async {
    try {
      final credential = await _auth
          .signInWithEmailAndPassword(email: email, password: password)
          .timeout(_networkTimeout);
      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        throw const AuthServiceException('Unable to sign in right now.');
      }

      final fallbackUser = _buildAuthBackedUser(firebaseUser, email);

      try {
        final doc = await _db
            .collection('users')
            .doc(firebaseUser.uid)
            .get()
            .timeout(_networkTimeout);
        final data = doc.data();

        if (data != null) {
          debugPrint(
            'AuthService.signIn success with profile: ${firebaseUser.uid}',
          );
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
            .set(fallbackUser.toMap())
            .timeout(_networkTimeout);
      } on FirebaseException catch (e) {
        debugPrint(
          'AuthService.signIn profile sync skipped due to firestore error: ${e.code}',
        );
        return fallbackUser;
      } on TimeoutException catch (e, stackTrace) {
        debugPrint('AuthService.signIn profile sync timeout: $e');
        debugPrintStack(stackTrace: stackTrace);
        return fallbackUser;
      } on TypeError catch (e, stackTrace) {
        debugPrint('AuthService.signIn profile parsing fallback: $e');
        debugPrintStack(stackTrace: stackTrace);
        return fallbackUser;
      }

      debugPrint('AuthService.signIn success: ${firebaseUser.uid}');
      return fallbackUser;
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('AuthService.signIn timeout: $e');
      debugPrintStack(stackTrace: stackTrace);
      throw const AuthServiceException(
        'Request timed out. Please check your network and try again.',
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('AuthService.signIn auth error: ${e.code}');
      throw AuthServiceException(_authErrorMessage(e));
    } catch (e, stackTrace) {
      debugPrint('AuthService.signIn unexpected error: $e');
      debugPrintStack(stackTrace: stackTrace);
      throw AuthServiceException(_unexpectedErrorMessage(e));
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _auth.signOut().timeout(_networkTimeout);
      debugPrint('AuthService.signOut success');
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('AuthService.signOut timeout: $e');
      debugPrintStack(stackTrace: stackTrace);
      throw const AuthServiceException('Sign out timed out. Please try again.');
    } catch (e, stackTrace) {
      debugPrint('AuthService.signOut error: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> _rollbackFailedSignUp(User? firebaseUser) async {
    if (firebaseUser == null) {
      return;
    }

    try {
      await firebaseUser.delete().timeout(_networkTimeout);
    } catch (_) {
      if (_auth.currentUser?.uid == firebaseUser.uid) {
        try {
          await _auth.signOut().timeout(_networkTimeout);
        } catch (_) {}
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
