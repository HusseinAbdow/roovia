import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class UserServiceException implements Exception {
  final String message;

  const UserServiceException(this.message);

  @override
  String toString() => message;
}

class UserService {
  static const Duration _networkTimeout = Duration(seconds: 15);
  static const Duration _storageTimeout = Duration(seconds: 60);
  static final RegExp _usernameRule = RegExp(r'^[a-z0-9_]{3,20}$');
  static const int _maxProfileImageBytes = 5 * 1024 * 1024;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

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

  String _profileImagePath(String uid, String extension) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'users/$uid/profile/avatar_$timestamp.$extension';
  }

  String _extensionFromMime(String mimeType) {
    final normalized = mimeType.toLowerCase().trim();
    if (normalized.endsWith('png')) {
      return 'png';
    }
    if (normalized.endsWith('webp')) {
      return 'webp';
    }
    return 'jpg';
  }

  bool _isSupportedImageMime(String mimeType) {
    final normalized = mimeType.toLowerCase().trim();
    return normalized == 'image/jpeg' ||
        normalized == 'image/jpg' ||
        normalized == 'image/png' ||
        normalized == 'image/webp';
  }

  Future<String> _getDownloadUrlWithRetry(Reference reference) async {
    const maxAttempts = 3;
    var attempt = 0;

    while (true) {
      attempt += 1;
      try {
        return await reference.getDownloadURL();
      } on FirebaseException catch (error) {
        final shouldRetry = error.code == 'object-not-found' && attempt < maxAttempts;
        if (!shouldRetry) {
          rethrow;
        }
      }

      await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
    }
  }

  String _storagePathFromDownloadUrl(String downloadUrl) {
    final raw = downloadUrl.trim();
    if (raw.isEmpty) {
      return '';
    }

    final uri = Uri.tryParse(raw);
    if (uri == null) {
      return '';
    }

    final segments = uri.pathSegments;
    final objectIndex = segments.indexOf('o');
    if (objectIndex < 0 || objectIndex + 1 >= segments.length) {
      return '';
    }

    return Uri.decodeComponent(segments.sublist(objectIndex + 1).join('/')).trim();
  }

  Future<void> _deleteProfileImageByPath(String storagePath) async {
    final path = storagePath.trim();
    if (path.isEmpty) {
      return;
    }

    try {
      await _storage.ref(path).delete().timeout(_storageTimeout);
    } catch (_) {
      // Best-effort cleanup for replaced avatars.
    }
  }

  Future<String> uploadProfileImage({
    required Uint8List imageBytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    final user = _currentUser;
    final normalizedMime = mimeType.toLowerCase().trim();

    if (imageBytes.isEmpty) {
      throw const UserServiceException('Selected image could not be read.');
    }
    if (imageBytes.length > _maxProfileImageBytes) {
      throw const UserServiceException('Profile image must be smaller than 5 MB.');
    }
    if (!_isSupportedImageMime(normalizedMime)) {
      throw const UserServiceException('Only JPG, PNG, or WEBP images are supported.');
    }

    final userDocRef = _db.collection('users').doc(user.uid);
    final snapshot = await userDocRef.get().timeout(_networkTimeout);
    final data = snapshot.data() ?? const <String, dynamic>{};
    final previousPath = ((data['profileImageStoragePath'] as String?) ?? '').trim();
    final previousUrl = ((data['profileImageUrl'] as String?) ?? '').trim();

    final extension = _extensionFromMime(normalizedMime);
    final storagePath = _profileImagePath(user.uid, extension);
    final reference = _storage.ref(storagePath);
    final uploadTask = reference.putData(imageBytes, SettableMetadata(contentType: normalizedMime));

    if (onProgress != null) {
      uploadTask.snapshotEvents.listen((snapshotEvent) {
        final total = snapshotEvent.totalBytes;
        if (total <= 0) {
          return;
        }
        onProgress((snapshotEvent.bytesTransferred / total).clamp(0, 1));
      });
    }

    try {
      final uploadSnapshot = await uploadTask.timeout(_storageTimeout);
      final downloadUrl = await _getDownloadUrlWithRetry(uploadSnapshot.ref);

      await userDocRef
          .set({
            'profileImageUrl': downloadUrl,
            'profileImageStoragePath': storagePath,
            'profileImageUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(_networkTimeout);

      if (previousPath.isNotEmpty && previousPath != storagePath) {
        await _deleteProfileImageByPath(previousPath);
      } else if (previousPath.isEmpty && previousUrl.isNotEmpty) {
        final previousPathFromUrl = _storagePathFromDownloadUrl(previousUrl);
        if (previousPathFromUrl.isNotEmpty && previousPathFromUrl != storagePath) {
          await _deleteProfileImageByPath(previousPathFromUrl);
        }
      }

      return downloadUrl;
    } on FirebaseException catch (error) {
      if (error.code == 'unauthorized' || error.code == 'permission-denied') {
        throw const UserServiceException(
          'Storage permissions blocked this upload. Please make sure the latest storage rules are deployed, then try again.',
        );
      }
      throw UserServiceException(error.message ?? 'Unable to upload profile image right now.');
    } on TimeoutException {
      throw const UserServiceException('Profile image upload timed out. Please try again.');
    }
  }

  Future<void> removeProfileImage() async {
    final user = _currentUser;
    final userDocRef = _db.collection('users').doc(user.uid);
    final snapshot = await userDocRef.get().timeout(_networkTimeout);
    final data = snapshot.data() ?? const <String, dynamic>{};

    final existingPath = ((data['profileImageStoragePath'] as String?) ?? '').trim();
    final existingUrl = ((data['profileImageUrl'] as String?) ?? '').trim();

    await userDocRef
        .set({
          'profileImageUrl': '',
          'profileImageStoragePath': FieldValue.delete(),
          'profileImageUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true))
        .timeout(_networkTimeout);

    if (existingPath.isNotEmpty) {
      await _deleteProfileImageByPath(existingPath);
      return;
    }

    final extractedPath = _storagePathFromDownloadUrl(existingUrl);
    if (extractedPath.isNotEmpty) {
      await _deleteProfileImageByPath(extractedPath);
    }
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
