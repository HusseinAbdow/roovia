import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/house_model.dart';
import '../models/join_request_model.dart';

class HouseService {
  static const String _inviteCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const Duration _networkTimeout = Duration(seconds: 15);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Random _random = Random.secure();

  StateError _missingFirestoreDbError() {
    return StateError(
      'Cloud Firestore is not set up for this Firebase project yet. Please create the default Firestore database in Firebase Console and try again.',
    );
  }

  bool _isMissingDefaultDbError(FirebaseException exception) {
    final message = (exception.message ?? '').toLowerCase();
    return exception.code == 'not-found' && message.contains('database (default) does not exist');
  }

  User get _currentUser {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user found');
    }
    return user;
  }

  String _extractStringField(Map<String, dynamic> raw, List<String> keys) {
    for (final key in keys) {
      final value = raw[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  String _normalizeInviteCode(String code) {
    return code.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '').replaceAll('-', '');
  }

  String _normalizeSearchValue(String text) {
    return text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _fallbackNameFromUid(String uid) {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) {
      return 'Unknown member';
    }
    if (trimmed.length <= 8) {
      return trimmed;
    }
    return '${trimmed.substring(0, 8)}...';
  }

  String _nameFromUserData(Map<String, dynamic> data, String fallbackUid) {
    final name = _extractStringField(data, const ['name', 'fullName']);
    if (name.isNotEmpty) {
      return name;
    }

    final email = _extractStringField(data, const ['email']);
    if (email.isNotEmpty) {
      return email.split('@').first;
    }

    return _fallbackNameFromUid(fallbackUid);
  }

  bool _matchesHouseName(String houseName, String query) {
    if (query.isEmpty) {
      return true;
    }

    final lowerName = houseName.trim().toLowerCase();
    final lowerQuery = query.trim().toLowerCase();
    if (lowerName.contains(lowerQuery)) {
      return true;
    }

    final compactName = _normalizeSearchValue(houseName);
    final compactQuery = _normalizeSearchValue(query);
    if (compactQuery.isEmpty) {
      return true;
    }

    return compactName.contains(compactQuery);
  }

  List<String> _extractMembers(Map<String, dynamic> raw) {
    final candidates = <dynamic>[raw['members'], raw['memberIds'], raw['users'], raw['userIds']];

    for (final candidate in candidates) {
      if (candidate is List) {
        return candidate
            .map((item) => item?.toString().trim() ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
      }
    }

    return const [];
  }

  bool _extractDiscoverable(Map<String, dynamic> raw) {
    final candidates = <dynamic>[raw['discoverable'], raw['isDiscoverable'], raw['public']];

    for (final candidate in candidates) {
      if (candidate is bool) {
        return candidate;
      }
      if (candidate is String) {
        final normalized = candidate.trim().toLowerCase();
        if (normalized == 'true') {
          return true;
        }
        if (normalized == 'false') {
          return false;
        }
      }
    }

    return true;
  }

  House _houseFromDocWithFallback(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required String source,
  }) {
    return _houseFromRawWithFallback(doc.data(), doc.id, source: source);
  }

  House _houseFromRawWithFallback(
    Map<String, dynamic> raw,
    String docId, {
    required String source,
  }) {
    final normalizedInviteCode = _normalizeInviteCode(
      _extractStringField(raw, const ['inviteCode', 'invite_code', 'code']),
    );
    if (normalizedInviteCode.isEmpty) {
      debugPrint('HouseService.$source warning: house $docId has missing/empty inviteCode');
    }

    final hasDiscoverableField = raw.containsKey('discoverable');
    final rawDiscoverable = raw['discoverable'];
    final normalizedDiscoverable = _extractDiscoverable(raw);

    if (!hasDiscoverableField || rawDiscoverable == null) {
      debugPrint(
        'HouseService.$source warning: house $docId missing discoverable; treating as true',
      );
    }

    final normalizedName = _extractStringField(raw, const [
      'name',
      'houseName',
      'house_name',
      'title',
    ]);
    final normalizedLeaderId = _extractStringField(raw, const [
      'leaderId',
      'ownerId',
      'adminId',
      'leader_id',
    ]);
    final normalizedMembers = _extractMembers(raw);

    final normalized = <String, dynamic>{
      ...raw,
      'houseId': (raw['houseId'] as String?)?.trim().isNotEmpty == true ? raw['houseId'] : docId,
      'name': normalizedName,
      'leaderId': normalizedLeaderId,
      'members': normalizedMembers,
      'inviteCode': normalizedInviteCode,
      'discoverable': normalizedDiscoverable,
    };

    return House.fromMap(normalized);
  }

  Future<House?> getHouseById(String houseId) async {
    final trimmedHouseId = houseId.trim();
    if (trimmedHouseId.isEmpty) {
      throw ArgumentError('House ID cannot be empty');
    }

    try {
      final snapshot = await _db
          .collection('houses')
          .doc(trimmedHouseId)
          .get()
          .timeout(_networkTimeout);

      final raw = snapshot.data();
      if (!snapshot.exists || raw == null) {
        return null;
      }

      return _houseFromRawWithFallback(raw, snapshot.id, source: 'getHouseById');
    } on FirebaseException catch (e, stackTrace) {
      debugPrint('HouseService.getHouseById firebase error: ${e.code}');
      debugPrintStack(stackTrace: stackTrace);
      if (_isMissingDefaultDbError(e)) {
        throw _missingFirestoreDbError();
      }
      rethrow;
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('HouseService.getHouseById timeout: $e');
      debugPrintStack(stackTrace: stackTrace);
      throw StateError('Request timed out. Please check your network and try again.');
    } catch (e, stackTrace) {
      debugPrint('HouseService.getHouseById unexpected error: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Stream<House?> getCurrentUserHouse() {
    final uid = _currentUser.uid;
    debugPrint('HouseService.getCurrentUserHouse started for uid: $uid');

    return _db.collection('houses').where('members', arrayContains: uid).snapshots().map((
      snapshot,
    ) {
      debugPrint(
        'HouseService.getCurrentUserHouse query result count: ${snapshot.docs.length} for uid: $uid',
      );

      if (snapshot.docs.isEmpty) {
        return null;
      }

      final firstHouse = _houseFromDocWithFallback(
        snapshot.docs.first,
        source: 'getCurrentUserHouse',
      );
      debugPrint(
        'HouseService.getCurrentUserHouse first house: ${firstHouse.houseId}, members: ${firstHouse.members}, containsUid: ${firstHouse.members.contains(uid)}',
      );

      return firstHouse;
    });
  }

  Stream<List<House>> watchCurrentUserHouses() {
    final uid = _currentUser.uid;
    debugPrint('HouseService.watchCurrentUserHouses started for uid: $uid');

    return _db.collection('houses').where('members', arrayContains: uid).snapshots().map((
      snapshot,
    ) {
      final houses = snapshot.docs
          .map((doc) => _houseFromDocWithFallback(doc, source: 'watchCurrentUserHouses'))
          .toList();

      houses.sort((left, right) {
        final leftCreatedAt = left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rightCreatedAt = right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return rightCreatedAt.compareTo(leftCreatedAt);
      });

      debugPrint(
        'HouseService.watchCurrentUserHouses query result count: ${houses.length} for uid: $uid',
      );

      return houses;
    });
  }

  Future<List<House>> searchDiscoverableHouses(String query, {String locationQuery = ''}) async {
    final currentUserId = _currentUser.uid;
    final normalizedQuery = query.trim().toLowerCase();
    final normalizedLocationQuery = locationQuery.trim().toLowerCase();
    debugPrint(
      'HouseService.searchDiscoverableHouses started | query="$query" | locationQuery="$locationQuery" | normalized="$normalizedQuery" | normalizedLocation="$normalizedLocationQuery" | currentUserId="$currentUserId" | projectId=${Firebase.app().options.projectId}',
    );

    try {
      final discoverableSnapshot = await _db
          .collection('houses')
          .where('discoverable', isEqualTo: true)
          .get()
          .timeout(_networkTimeout);

      final allSnapshot = await _db.collection('houses').get().timeout(_networkTimeout);
      final fallbackDiscoverableDocs = allSnapshot.docs.where((doc) {
        final raw = doc.data();
        return !raw.containsKey('discoverable') || raw['discoverable'] == null;
      });

      final mergedById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
        for (final doc in discoverableSnapshot.docs) doc.id: doc,
        for (final doc in fallbackDiscoverableDocs) doc.id: doc,
      };

      final discoverableHouses = mergedById.values
          .map((doc) => _houseFromDocWithFallback(doc, source: 'searchDiscoverableHouses'))
          .toList();

      final visibleHouses = discoverableHouses
          .where((house) => !house.members.contains(currentUserId))
          .toList();

      debugPrint(
        'HouseService.searchDiscoverableHouses fetched | discoverableQuery=${discoverableSnapshot.docs.length} | fallbackMissingDiscoverable=${fallbackDiscoverableDocs.length} | totalMerged=${discoverableHouses.length}',
      );

      if (normalizedQuery.isEmpty && normalizedLocationQuery.isEmpty) {
        debugPrint(
          'HouseService.searchDiscoverableHouses complete | discoverableOnly=${discoverableHouses.length} | visible=${visibleHouses.length} | filtered=${visibleHouses.length}',
        );
        return visibleHouses;
      }

      final filtered = visibleHouses.where((house) {
        final matchesName = normalizedQuery.isEmpty
            ? true
            : _matchesHouseName(house.name, normalizedQuery);
        final matchesLocation = normalizedLocationQuery.isEmpty
            ? true
            : _matchesHouseName('${house.city} ${house.district}', normalizedLocationQuery);
        return matchesName && matchesLocation;
      }).toList();

      debugPrint(
        'HouseService.searchDiscoverableHouses complete | discoverableOnly=${discoverableHouses.length} | visible=${visibleHouses.length} | filtered=${filtered.length}',
      );
      return filtered;
    } on FirebaseException catch (e, stackTrace) {
      debugPrint('HouseService.searchDiscoverableHouses firebase error: ${e.code}');
      debugPrintStack(stackTrace: stackTrace);
      if (_isMissingDefaultDbError(e)) {
        throw _missingFirestoreDbError();
      }
      rethrow;
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('HouseService.searchDiscoverableHouses timeout: $e');
      debugPrintStack(stackTrace: stackTrace);
      throw StateError('Request timed out. Please check your network and try again.');
    } catch (e, stackTrace) {
      debugPrint('HouseService.searchDiscoverableHouses unexpected error: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<House> createHouse({
    required String name,
    required String city,
    required String district,
    required String address,
    required double rentTotal,
    required double electricityTotal,
    required double waterTotal,
    required double internetTotal,
    required int maxMembers,
    String description = '',
  }) async {
    final trimmedName = name.trim();
    final trimmedCity = city.trim();
    final trimmedDistrict = district.trim();
    final trimmedAddress = address.trim();
    final trimmedDescription = description.trim();

    if (trimmedName.isEmpty) {
      throw ArgumentError('House name cannot be empty');
    }
    if (trimmedCity.isEmpty) {
      throw ArgumentError('City cannot be empty');
    }
    if (trimmedDistrict.isEmpty) {
      throw ArgumentError('District cannot be empty');
    }
    if (trimmedAddress.isEmpty) {
      throw ArgumentError('Address cannot be empty');
    }
    if (rentTotal < 0) {
      throw ArgumentError('Total rent cannot be negative');
    }
    if (electricityTotal < 0) {
      throw ArgumentError('Total electricity cannot be negative');
    }
    if (waterTotal < 0) {
      throw ArgumentError('Total water cannot be negative');
    }
    if (internetTotal < 0) {
      throw ArgumentError('Total internet cannot be negative');
    }
    if (maxMembers <= 0) {
      throw ArgumentError('Max members must be greater than 0');
    }

    try {
      final uid = _currentUser.uid;
      final docRef = _db.collection('houses').doc();
      final inviteCode = await _generateUniqueInviteCode();
      final data = {
        'houseId': docRef.id,
        'name': trimmedName,
        'chatName': '$trimmedName Chat',
        'leaderId': uid,
        'members': [uid],
        'inviteCode': inviteCode,
        'discoverable': true,
        'city': trimmedCity,
        'district': trimmedDistrict,
        'address': trimmedAddress,
        'rentTotal': rentTotal,
        'electricityTotal': electricityTotal,
        'waterTotal': waterTotal,
        'internetTotal': internetTotal,
        'maxMembers': maxMembers,
        'description': trimmedDescription,
        'createdAt': FieldValue.serverTimestamp(),
      };

      debugPrint(
        'HouseService.createHouse writing | houseId=${docRef.id} | inviteCode=$inviteCode | discoverable=true | maxMembers=$maxMembers',
      );

      await docRef.set(data).timeout(_networkTimeout);

      final snapshot = await docRef.get().timeout(_networkTimeout);
      final createdData = snapshot.data() ?? data;
      final createdHouse = House.fromMap(createdData);
      if ((createdHouse.inviteCode).trim().isEmpty) {
        debugPrint(
          'HouseService.createHouse warning: created house ${createdHouse.houseId} has empty inviteCode after read',
        );
      }
      debugPrint(
        'HouseService.createHouse success: ${createdHouse.houseId} (${createdHouse.name}) | inviteCode=${createdHouse.inviteCode} | discoverable=${createdHouse.discoverable} | maxMembers=${createdHouse.maxMembers}',
      );
      return createdHouse;
    } on FirebaseException catch (e, stackTrace) {
      debugPrint('HouseService.createHouse firebase error: ${e.code}');
      debugPrintStack(stackTrace: stackTrace);
      if (_isMissingDefaultDbError(e)) {
        throw _missingFirestoreDbError();
      }
      if (e.code == 'permission-denied') {
        throw StateError(
          'Permission denied while creating house. Publish Firestore rules and ensure signed-in users can create in houses.',
        );
      }
      rethrow;
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('HouseService.createHouse timeout: $e');
      debugPrintStack(stackTrace: stackTrace);
      throw StateError('Request timed out. Please check your network and try again.');
    } catch (e, stackTrace) {
      debugPrint('HouseService.createHouse unexpected error: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> updateHouseChatName({required String houseId, required String chatName}) async {
    final trimmedHouseId = houseId.trim();
    final trimmedChatName = chatName.trim();

    if (trimmedHouseId.isEmpty) {
      throw ArgumentError('House ID cannot be empty');
    }

    if (trimmedChatName.isEmpty) {
      throw ArgumentError('Chat name cannot be empty');
    }

    try {
      final currentUserId = _currentUser.uid;
      final houseRef = _db.collection('houses').doc(trimmedHouseId);
      final houseSnapshot = await houseRef.get().timeout(_networkTimeout);

      if (!houseSnapshot.exists || houseSnapshot.data() == null) {
        throw StateError('House not found');
      }

      final leaderId = _extractStringField(houseSnapshot.data()!, const [
        'leaderId',
        'ownerId',
        'adminId',
        'leader_id',
      ]);

      if (leaderId != currentUserId) {
        throw StateError('Only the house owner can rename the chat');
      }

      await houseRef
          .update({'chatName': trimmedChatName, 'updatedAt': FieldValue.serverTimestamp()})
          .timeout(_networkTimeout);
    } on FirebaseException catch (e, stackTrace) {
      debugPrint('HouseService.updateHouseChatName firebase error: ${e.code}');
      debugPrintStack(stackTrace: stackTrace);
      if (_isMissingDefaultDbError(e)) {
        throw _missingFirestoreDbError();
      }
      rethrow;
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('HouseService.updateHouseChatName timeout: $e');
      debugPrintStack(stackTrace: stackTrace);
      throw StateError('Request timed out. Please check your network and try again.');
    } catch (e, stackTrace) {
      debugPrint('HouseService.updateHouseChatName unexpected error: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> updateHouseMonthlyCosts({
    required String houseId,
    required double rentTotal,
    required double electricityTotal,
    required double waterTotal,
    required double internetTotal,
  }) async {
    final trimmedHouseId = houseId.trim();

    if (trimmedHouseId.isEmpty) {
      throw ArgumentError('House ID cannot be empty');
    }
    if (rentTotal.isNaN || rentTotal.isInfinite || rentTotal < 0) {
      throw ArgumentError('Total rent must be a valid non-negative number');
    }
    if (electricityTotal.isNaN || electricityTotal.isInfinite || electricityTotal < 0) {
      throw ArgumentError('Total electricity must be a valid non-negative number');
    }
    if (waterTotal.isNaN || waterTotal.isInfinite || waterTotal < 0) {
      throw ArgumentError('Total water must be a valid non-negative number');
    }
    if (internetTotal.isNaN || internetTotal.isInfinite || internetTotal < 0) {
      throw ArgumentError('Total internet must be a valid non-negative number');
    }

    try {
      final currentUserId = _currentUser.uid;
      final houseRef = _db.collection('houses').doc(trimmedHouseId);
      final houseSnapshot = await houseRef.get().timeout(_networkTimeout);

      if (!houseSnapshot.exists || houseSnapshot.data() == null) {
        throw StateError('House not found');
      }

      final leaderId = _extractStringField(houseSnapshot.data()!, const [
        'leaderId',
        'ownerId',
        'adminId',
        'leader_id',
      ]);

      if (leaderId != currentUserId) {
        throw StateError('Only the house owner can update monthly costs');
      }

      await houseRef
          .update({
            'rentTotal': rentTotal,
            'electricityTotal': electricityTotal,
            'waterTotal': waterTotal,
            'internetTotal': internetTotal,
            'updatedAt': FieldValue.serverTimestamp(),
          })
          .timeout(_networkTimeout);
    } on FirebaseException catch (e, stackTrace) {
      debugPrint('HouseService.updateHouseMonthlyCosts firebase error: ${e.code}');
      debugPrintStack(stackTrace: stackTrace);
      if (_isMissingDefaultDbError(e)) {
        throw _missingFirestoreDbError();
      }
      rethrow;
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('HouseService.updateHouseMonthlyCosts timeout: $e');
      debugPrintStack(stackTrace: stackTrace);
      throw StateError('Request timed out. Please check your network and try again.');
    } catch (e, stackTrace) {
      debugPrint('HouseService.updateHouseMonthlyCosts unexpected error: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<String> _generateUniqueInviteCode({
    int minLength = 5,
    int maxLength = 6,
    int maxAttempts = 20,
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      final length = minLength + _random.nextInt(maxLength - minLength + 1);
      final code = _randomInviteCode(length).toUpperCase();

      final existing = await _db
          .collection('houses')
          .where('inviteCode', isEqualTo: code)
          .limit(1)
          .get()
          .timeout(_networkTimeout);

      if (existing.docs.isEmpty) {
        return code;
      }
    }

    throw StateError('Could not generate a unique invite code. Try again.');
  }

  String _randomInviteCode(int length) {
    final chars = List.generate(length, (_) {
      final index = _random.nextInt(_inviteCodeAlphabet.length);
      return _inviteCodeAlphabet[index];
    });
    return chars.join();
  }

  Future<Map<String, String>> getUserNamesByIds(List<String> userIds) async {
    final normalizedIds = userIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (normalizedIds.isEmpty) {
      return const {};
    }

    final namesById = <String, String>{};
    const chunkSize = 10;

    try {
      for (var i = 0; i < normalizedIds.length; i += chunkSize) {
        final end = (i + chunkSize > normalizedIds.length) ? normalizedIds.length : i + chunkSize;
        final chunk = normalizedIds.sublist(i, end);

        final snapshot = await _db
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get()
            .timeout(_networkTimeout);

        for (final doc in snapshot.docs) {
          final data = doc.data();
          namesById[doc.id] = _nameFromUserData(data, doc.id);
        }

        final unresolvedFromChunk = chunk.where((id) => !namesById.containsKey(id)).toList();

        if (unresolvedFromChunk.isNotEmpty) {
          final byUidFieldSnapshot = await _db
              .collection('users')
              .where('uid', whereIn: unresolvedFromChunk)
              .get()
              .timeout(_networkTimeout);

          for (final doc in byUidFieldSnapshot.docs) {
            final data = doc.data();
            final uid = _extractStringField(data, const ['uid']);
            if (uid.isEmpty) {
              continue;
            }
            namesById[uid] = _nameFromUserData(data, uid);
          }
        }

        final stillUnresolved = chunk.where((id) => !namesById.containsKey(id)).toList();

        for (final uid in stillUnresolved) {
          try {
            final userDoc = await _db.collection('users').doc(uid).get().timeout(_networkTimeout);

            final data = userDoc.data();
            if (data != null) {
              namesById[uid] = _nameFromUserData(data, uid);
            }
          } catch (_) {}
        }
      }

      for (final id in normalizedIds) {
        namesById.putIfAbsent(id, () => _fallbackNameFromUid(id));
      }

      return namesById;
    } on FirebaseException catch (e, stackTrace) {
      debugPrint('HouseService.getUserNamesByIds firebase error: ${e.code}');
      debugPrintStack(stackTrace: stackTrace);
      if (_isMissingDefaultDbError(e)) {
        throw _missingFirestoreDbError();
      }
      if (e.code == 'permission-denied') {
        debugPrint(
          'HouseService.getUserNamesByIds permission-denied: falling back to anonymized names. Update users read rules to enable full names.',
        );
        return {for (final id in normalizedIds) id: _fallbackNameFromUid(id)};
      }
      rethrow;
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('HouseService.getUserNamesByIds timeout: $e');
      debugPrintStack(stackTrace: stackTrace);
      throw StateError('Request timed out. Please check your network and try again.');
    } catch (e, stackTrace) {
      debugPrint('HouseService.getUserNamesByIds unexpected error: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Stream<int> getUnreadMessageCount(String houseId, String userId) {
    final trimmedHouseId = houseId.trim();
    final trimmedUserId = userId.trim();

    if (trimmedHouseId.isEmpty) {
      return Stream.error(ArgumentError('House ID cannot be empty'));
    }

    if (trimmedUserId.isEmpty) {
      return Stream.error(ArgumentError('User ID cannot be empty'));
    }

    final metaDocId = '${trimmedHouseId}_$trimmedUserId';
    final metaDocRef = _db.collection('house_user_meta').doc(metaDocId);
    final messagesRef = _db.collection('house_chats').doc(trimmedHouseId).collection('messages');

    late final StreamController<int> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? metaSubscription;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? messageSubscription;

    bool hasLoadedMeta = false;
    bool metaDocMissing = false;
    Timestamp? latestLastSeenAt;

    int countOtherUserMessages(Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
      return docs.where((doc) {
        final data = doc.data();
        final senderId = (data['senderId'] as String?)?.trim();
        return senderId != null && senderId.isNotEmpty && senderId != trimmedUserId;
      }).length;
    }

    void restartUnreadListener() {
      messageSubscription?.cancel();
      if (!hasLoadedMeta) {
        debugPrint(
          'HouseService.getUnreadMessageCount | houseId=$trimmedHouseId | userId=$trimmedUserId | meta not loaded yet | emitting 0',
        );
        if (!controller.isClosed) controller.add(0);
        return;
      }

      // If the meta document does not exist at all, or we don't have a stable timestamp, count all messages as unread.
      if (metaDocMissing || latestLastSeenAt == null) {
        messageSubscription = messagesRef.orderBy('createdAt').snapshots().listen((snapshot) {
          final unreadCount = countOtherUserMessages(
            snapshot.docs.where((doc) => doc.data()['createdAt'] is Timestamp),
          );

          debugPrint(
            'HouseService.getUnreadMessageCount (meta missing) | houseId=$trimmedHouseId | userId=$trimmedUserId | unreadCount=$unreadCount',
          );

          if (!controller.isClosed) controller.add(unreadCount);
        }, onError: controller.addError);
        return;
      }

      // Normal case: meta exists and we have a stable lastSeenAt timestamp.
      final query = messagesRef
          .where('createdAt', isGreaterThan: latestLastSeenAt)
          .orderBy('createdAt');

      messageSubscription = query.snapshots().listen((snapshot) {
        final unreadCount = countOtherUserMessages(
          snapshot.docs.where((doc) => doc.data()['createdAt'] is Timestamp),
        );

        debugPrint(
          'HouseService.getUnreadMessageCount | houseId=$trimmedHouseId | userId=$trimmedUserId | lastSeenAt=$latestLastSeenAt | unreadCount=$unreadCount',
        );

        for (final doc in snapshot.docs) {
          final createdAt = doc.data()['createdAt'];
          debugPrint(
            'HouseService.getUnreadMessageCount message | houseId=$trimmedHouseId | userId=$trimmedUserId | messageId=${doc.id} | createdAt=$createdAt',
          );
        }

        if (!controller.isClosed) {
          controller.add(unreadCount);
        }
      }, onError: controller.addError);
    }

    controller = StreamController<int>(
      onListen: () {
        metaSubscription = metaDocRef.snapshots().listen((metaSnapshot) {
          final data = metaSnapshot.data();
          final rawLastSeenAt = data?['lastSeenAt'];

          if (rawLastSeenAt is Timestamp) {
            latestLastSeenAt = rawLastSeenAt;
            metaDocMissing = false;
            hasLoadedMeta = true;
          } else if (!metaSnapshot.exists) {
            // No meta doc yet — treat as "meta missing" so we count all messages as unread.
            latestLastSeenAt = null;
            metaDocMissing = true;
            hasLoadedMeta = true;
          } else if (!hasLoadedMeta) {
            // First load and meta doc exists but lastSeenAt field is missing — treat as missing.
            latestLastSeenAt = null;
            metaDocMissing = true;
            hasLoadedMeta = true;
          } else {
            // Keep previous stable timestamp while a server timestamp write is pending.
          }

          debugPrint(
            'HouseService.getUnreadMessageCount meta | houseId=$trimmedHouseId | userId=$trimmedUserId | lastSeenAt=$latestLastSeenAt | metaMissing=$metaDocMissing',
          );

          restartUnreadListener();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await metaSubscription?.cancel();
        await messageSubscription?.cancel();
      },
    );

    return controller.stream;
  }

  Future<void> deleteHouse(String houseId) async {
    final trimmedHouseId = houseId.trim();
    if (trimmedHouseId.isEmpty) {
      throw ArgumentError('House ID cannot be empty');
    }

    final currentUserId = _currentUser.uid;
    debugPrint(
      'HouseService.deleteHouse started | houseId=$trimmedHouseId | userId=$currentUserId',
    );

    try {
      final houseRef = _db.collection('houses').doc(trimmedHouseId);
      final houseSnapshot = await houseRef.get().timeout(_networkTimeout);

      if (!houseSnapshot.exists || houseSnapshot.data() == null) {
        throw StateError('House not found');
      }

      final raw = houseSnapshot.data()!;
      final leaderId = _extractStringField(raw, const [
        'leaderId',
        'ownerId',
        'adminId',
        'leader_id',
      ]);

      if (leaderId != currentUserId) {
        throw StateError('Only the house owner can delete this house');
      }

      final batch = _db.batch();

      final requests = await _db
          .collection('join_requests')
          .where('houseId', isEqualTo: trimmedHouseId)
          .get()
          .timeout(_networkTimeout);
      for (final requestDoc in requests.docs) {
        batch.delete(requestDoc.reference);
      }

      batch.delete(houseRef);

      await batch.commit().timeout(_networkTimeout);
      debugPrint(
        'HouseService.deleteHouse success | houseId=$trimmedHouseId | deletedJoinRequests=${requests.docs.length}',
      );
    } on FirebaseException catch (e, stackTrace) {
      debugPrint('HouseService.deleteHouse firebase error: ${e.code}');
      debugPrintStack(stackTrace: stackTrace);
      if (_isMissingDefaultDbError(e)) {
        throw _missingFirestoreDbError();
      }
      rethrow;
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('HouseService.deleteHouse timeout: $e');
      debugPrintStack(stackTrace: stackTrace);
      throw StateError('Request timed out. Please check your network and try again.');
    } catch (e, stackTrace) {
      debugPrint('HouseService.deleteHouse unexpected error: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<JoinRequest> createJoinRequest({required String houseId, String? userId}) async {
    final trimmedHouseId = houseId.trim();
    if (trimmedHouseId.isEmpty) {
      throw ArgumentError('House ID cannot be empty');
    }

    try {
      final requesterUserId = userId?.trim().isNotEmpty == true ? userId!.trim() : _currentUser.uid;

      final houseRef = _db.collection('houses').doc(trimmedHouseId);
      final houseSnapshot = await houseRef.get().timeout(_networkTimeout);
      if (!houseSnapshot.exists || houseSnapshot.data() == null) {
        throw StateError('House not found');
      }

      final rawHouse = houseSnapshot.data()!;
      final members = _extractMembers(rawHouse);
      final maxMembers = rawHouse['maxMembers'] as int? ?? 1;
      if (members.length >= maxMembers) {
        throw StateError('House is full');
      }

      if (members.contains(requesterUserId)) {
        throw StateError('User is already a member of this house');
      }

      final existingPending = await _db
          .collection('join_requests')
          .where('houseId', isEqualTo: trimmedHouseId)
          .where('userId', isEqualTo: requesterUserId)
          .where('status', isEqualTo: JoinRequestStatus.pending)
          .limit(1)
          .get()
          .timeout(_networkTimeout);

      if (existingPending.docs.isNotEmpty) {
        debugPrint(
          'HouseService.createJoinRequest duplicate pending request blocked | houseId=$trimmedHouseId | userId=$requesterUserId',
        );
        throw StateError('A pending request already exists for this house');
      }

      final docRef = _db.collection('join_requests').doc();
      final data = {
        'houseId': trimmedHouseId,
        'userId': requesterUserId,
        'status': JoinRequestStatus.pending,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await docRef.set(data).timeout(_networkTimeout);

      final snapshot = await docRef.get().timeout(_networkTimeout);
      final createdJoinRequest = JoinRequest.fromMap(docRef.id, snapshot.data() ?? data);
      debugPrint('HouseService.createJoinRequest success: ${createdJoinRequest.id}');
      return createdJoinRequest;
    } on FirebaseException catch (e, stackTrace) {
      debugPrint('HouseService.createJoinRequest firebase error: ${e.code}');
      debugPrintStack(stackTrace: stackTrace);
      if (_isMissingDefaultDbError(e)) {
        throw _missingFirestoreDbError();
      }
      rethrow;
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('HouseService.createJoinRequest timeout: $e');
      debugPrintStack(stackTrace: stackTrace);
      throw StateError('Request timed out. Please check your network and try again.');
    } catch (e, stackTrace) {
      debugPrint('HouseService.createJoinRequest unexpected error: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<JoinRequest> joinByInviteCode(String code, String userId) async {
    final normalizedCode = _normalizeInviteCode(code);
    final normalizedUserId = userId.trim();

    if (normalizedCode.isEmpty) {
      throw ArgumentError('Invite code cannot be empty');
    }

    if (normalizedUserId.isEmpty) {
      throw ArgumentError('User ID cannot be empty');
    }

    debugPrint(
      'HouseService.joinByInviteCode started | code="$normalizedCode" | userId="$normalizedUserId" | projectId=${Firebase.app().options.projectId}',
    );

    try {
      final houseSnapshot = await _db
          .collection('houses')
          .where('inviteCode', isEqualTo: normalizedCode)
          .limit(1)
          .get()
          .timeout(_networkTimeout);

      House? house;
      if (houseSnapshot.docs.isNotEmpty) {
        house = _houseFromDocWithFallback(houseSnapshot.docs.first, source: 'joinByInviteCode');
        debugPrint(
          'HouseService.joinByInviteCode exact match | houseId=${house.houseId} | name=${house.name} | inviteCode=${house.inviteCode}',
        );
      } else {
        final allSnapshot = await _db.collection('houses').get().timeout(_networkTimeout);
        for (final doc in allSnapshot.docs) {
          final candidate = _houseFromDocWithFallback(doc, source: 'joinByInviteCode');
          if (_normalizeInviteCode(candidate.inviteCode) == normalizedCode) {
            house = candidate;
            debugPrint(
              'HouseService.joinByInviteCode fallback normalized match | houseId=${house.houseId} | name=${house.name} | inviteCode=${house.inviteCode}',
            );
            break;
          }
        }
      }

      if (house == null) {
        debugPrint(
          'HouseService.joinByInviteCode no house found with this code | code="$normalizedCode"',
        );
        throw StateError('Invalid code');
      }

      if (house.members.contains(normalizedUserId)) {
        throw StateError('User is already a member of this house');
      }

      final userDoc = await _db
          .collection('users')
          .doc(normalizedUserId)
          .get()
          .timeout(_networkTimeout);
      final userCurrentHouseId = (userDoc.data()?['currentHouseId'] as String?)?.trim();

      if (userCurrentHouseId != null && userCurrentHouseId.isNotEmpty) {
        throw StateError('User is already in another house');
      }

      final existingHouseMembership = await _db
          .collection('houses')
          .where('members', arrayContains: normalizedUserId)
          .limit(1)
          .get()
          .timeout(_networkTimeout);

      if (existingHouseMembership.docs.isNotEmpty) {
        throw StateError('User is already in another house');
      }

      final existingPending = await _db
          .collection('join_requests')
          .where('houseId', isEqualTo: house.houseId)
          .where('userId', isEqualTo: normalizedUserId)
          .where('status', isEqualTo: JoinRequestStatus.pending)
          .limit(1)
          .get()
          .timeout(_networkTimeout);

      if (existingPending.docs.isNotEmpty) {
        throw StateError('A pending request already exists for this house');
      }

      final request = await createJoinRequest(houseId: house.houseId, userId: normalizedUserId);

      debugPrint(
        'HouseService.joinByInviteCode request created | requestId=${request.id} | houseId=${house.houseId} | userId=$normalizedUserId',
      );
      return request;
    } on FirebaseException catch (e, stackTrace) {
      debugPrint('HouseService.joinByInviteCode firebase error: ${e.code}');
      debugPrintStack(stackTrace: stackTrace);
      if (_isMissingDefaultDbError(e)) {
        throw _missingFirestoreDbError();
      }
      rethrow;
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('HouseService.joinByInviteCode timeout: $e');
      debugPrintStack(stackTrace: stackTrace);
      throw StateError('Request timed out. Please check your network and try again.');
    } catch (e, stackTrace) {
      debugPrint('HouseService.joinByInviteCode unexpected error: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Stream<List<JoinRequest>> watchPendingJoinRequestsForHouse(String houseId) {
    final trimmedHouseId = houseId.trim();
    if (trimmedHouseId.isEmpty) {
      throw ArgumentError('House ID cannot be empty');
    }

    return _db
        .collection('join_requests')
        .where('houseId', isEqualTo: trimmedHouseId)
        .where('status', isEqualTo: JoinRequestStatus.pending)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => JoinRequest.fromMap(doc.id, doc.data())).toList(),
        );
  }

  Stream<List<JoinRequest>> watchJoinRequestsForUser(String userId) {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) {
      throw ArgumentError('User ID cannot be empty');
    }

    return _db
        .collection('join_requests')
        .where('userId', isEqualTo: trimmedUserId)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => JoinRequest.fromMap(doc.id, doc.data())).toList(),
        );
  }

  Future<void> respondToJoinRequest({required String requestId, required bool approve}) async {
    final trimmedRequestId = requestId.trim();
    if (trimmedRequestId.isEmpty) {
      throw ArgumentError('Request ID cannot be empty');
    }

    final currentUserId = _currentUser.uid;
    final targetStatus = approve ? JoinRequestStatus.accepted : JoinRequestStatus.rejected;

    try {
      final requestRef = _db.collection('join_requests').doc(trimmedRequestId);

      await _db
          .runTransaction((transaction) async {
            final requestSnapshot = await transaction.get(requestRef);
            if (!requestSnapshot.exists || requestSnapshot.data() == null) {
              throw StateError('Join request not found');
            }

            final request = JoinRequest.fromMap(requestSnapshot.id, requestSnapshot.data()!);

            if (request.status != JoinRequestStatus.pending) {
              throw StateError('This request has already been handled');
            }

            final houseRef = _db.collection('houses').doc(request.houseId);
            final houseSnapshot = await transaction.get(houseRef);
            if (!houseSnapshot.exists || houseSnapshot.data() == null) {
              throw StateError('House not found');
            }

            final rawHouse = houseSnapshot.data()!;
            final leaderId = _extractStringField(rawHouse, const [
              'leaderId',
              'ownerId',
              'adminId',
              'leader_id',
            ]);

            if (leaderId != currentUserId) {
              throw StateError('Only the house owner can manage requests');
            }

            if (approve) {
              final members = _extractMembers(rawHouse);
              final maxMembers = rawHouse['maxMembers'] as int? ?? 1;

              // Check capacity before adding member
              if (members.length >= maxMembers) {
                throw StateError('House is full');
              }

              final updatedMembers = members.toSet();
              updatedMembers.add(request.userId);

              transaction.update(houseRef, {
                'members': updatedMembers.toList(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
            }

            transaction.update(requestRef, {
              'status': targetStatus,
              'updatedAt': FieldValue.serverTimestamp(),
              'handledBy': currentUserId,
            });
          })
          .timeout(_networkTimeout);
    } on FirebaseException catch (e, stackTrace) {
      debugPrint('HouseService.respondToJoinRequest firebase error: ${e.code}');
      debugPrintStack(stackTrace: stackTrace);
      if (_isMissingDefaultDbError(e)) {
        throw _missingFirestoreDbError();
      }
      rethrow;
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('HouseService.respondToJoinRequest timeout: $e');
      debugPrintStack(stackTrace: stackTrace);
      throw StateError('Request timed out. Please check your network and try again.');
    } catch (e, stackTrace) {
      debugPrint('HouseService.respondToJoinRequest unexpected error: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }
}
