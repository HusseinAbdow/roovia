import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserServiceException implements Exception {
  final String message;

  const UserServiceException(this.message);

  @override
  String toString() => message;
}

class UserService {
  static const Duration _networkTimeout = Duration(seconds: 15);
  static final RegExp _usernameRule = RegExp(r'^[a-z0-9_]{3,20}$');

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User get _currentUser {
    final user = _auth.currentUser;
    if (user == null) {
      throw const UserServiceException('You need to sign in again.');
    }
    return user;
  }

  String normalizeUsername(String value) {
    return value.trim().toLowerCase();
  }

  void validateUsernameFormat(String username) {
    final normalized = normalizeUsername(username);

    if (normalized.contains(' ')) {
      throw const UserServiceException('Username cannot contain spaces.');
    }

    if (!_usernameRule.hasMatch(normalized)) {
      throw const UserServiceException(
        'Username must be 3 to 20 characters and use only lowercase letters, numbers, or underscore.',
      );
    }
  }

  Future<bool> _usernameExists(String username, {String? excludingUid}) async {
    final query = await _db
        .collection('users')
        .where('username', isEqualTo: username)
        .limit(1)
        .get()
        .timeout(_networkTimeout);

    if (query.docs.isEmpty) {
      return false;
    }

    if (excludingUid == null) {
      return true;
    }

    return query.docs.first.id != excludingUid;
  }

  Future<void> updateUsername(String newUsername) async {
    final user = _currentUser;
    final normalized = normalizeUsername(newUsername);

    validateUsernameFormat(normalized);

    if (await _usernameExists(normalized, excludingUid: user.uid)) {
      throw const UserServiceException('That username is already taken.');
    }

    await _db
        .collection('users')
        .doc(user.uid)
        .set({'username': normalized}, SetOptions(merge: true))
        .timeout(_networkTimeout);
  }

  Future<void> updateProfile({
    required String name,
    required String username,
    String? profileImageUrl,
  }) async {
    final user = _currentUser;
    final trimmedName = name.trim();
    final normalizedUsername = normalizeUsername(username);

    if (trimmedName.isEmpty) {
      throw const UserServiceException('Display name cannot be empty.');
    }

    validateUsernameFormat(normalizedUsername);

    if (await _usernameExists(normalizedUsername, excludingUid: user.uid)) {
      throw const UserServiceException('That username is already taken.');
    }

    final payload = <String, dynamic>{'name': trimmedName, 'username': normalizedUsername};

    if (profileImageUrl != null) {
      payload['profileImageUrl'] = profileImageUrl;
    }

    try {
      await user.updateDisplayName(trimmedName).timeout(_networkTimeout);
    } catch (_) {
      // Best effort only; Firestore remains source of truth for profile screen.
    }

    await _db
        .collection('users')
        .doc(user.uid)
        .set(payload, SetOptions(merge: true))
        .timeout(_networkTimeout);
  }
}
