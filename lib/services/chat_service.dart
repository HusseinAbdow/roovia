import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/message_model.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const Duration _networkTimeout = Duration(seconds: 30);

  String _houseUserMetaDocId(String houseId, String userId) {
    return '${houseId.trim()}_${userId.trim()}';
  }

  Future<void> sendMessage({
    required String houseId,
    required String senderId,
    required String senderName,
    required String text,
  }) async {
    final trimmedHouseId = houseId.trim();
    final trimmedSenderId = senderId.trim();
    final trimmedSenderName = senderName.trim();
    final trimmedText = text.trim();

    if (trimmedHouseId.isEmpty) {
      throw ArgumentError('House ID cannot be empty');
    }

    if (trimmedSenderId.isEmpty) {
      throw ArgumentError('Sender ID cannot be empty');
    }

    if (trimmedSenderName.isEmpty) {
      throw ArgumentError('Sender name cannot be empty');
    }

    if (trimmedText.isEmpty) {
      throw ArgumentError('Message text cannot be empty');
    }

    try {
      final messagesRef = _db.collection('house_chats').doc(trimmedHouseId).collection('messages');

      final messageData = {
        'senderId': trimmedSenderId,
        'senderName': trimmedSenderName,
        'text': trimmedText,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await messagesRef.add(messageData).timeout(_networkTimeout);

      debugPrint(
        'ChatService.sendMessage success | houseId=$trimmedHouseId | senderId=$trimmedSenderId',
      );
    } on FirebaseException catch (e, stackTrace) {
      debugPrint('ChatService.sendMessage firebase error: ${e.code}');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('ChatService.sendMessage timeout: $e');
      debugPrintStack(stackTrace: stackTrace);
      throw StateError('Request timed out. Please check your network and try again.');
    } catch (e, stackTrace) {
      debugPrint('ChatService.sendMessage unexpected error: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> markChatAsSeen(String houseId, String userId) async {
    final trimmedHouseId = houseId.trim();
    final trimmedUserId = userId.trim();

    if (trimmedHouseId.isEmpty) {
      throw ArgumentError('House ID cannot be empty');
    }

    if (trimmedUserId.isEmpty) {
      throw ArgumentError('User ID cannot be empty');
    }

    try {
      await _db
          .collection('house_user_meta')
          .doc(_houseUserMetaDocId(trimmedHouseId, trimmedUserId))
          .set({
            'houseId': trimmedHouseId,
            'userId': trimmedUserId,
            'lastSeenAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(_networkTimeout);
    } on FirebaseException catch (e, stackTrace) {
      debugPrint('ChatService.markChatAsSeen firebase error: ${e.code}');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('ChatService.markChatAsSeen timeout: $e');
      debugPrintStack(stackTrace: stackTrace);
      throw StateError('Request timed out. Please check your network and try again.');
    } catch (e, stackTrace) {
      debugPrint('ChatService.markChatAsSeen unexpected error: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Stream<List<Message>> streamMessages(String houseId) {
    final trimmedHouseId = houseId.trim();

    if (trimmedHouseId.isEmpty) {
      return Stream.error(ArgumentError('House ID cannot be empty'));
    }

    try {
      return _db
          .collection('house_chats')
          .doc(trimmedHouseId)
          .collection('messages')
          .orderBy('createdAt', descending: false)
          .snapshots()
          .map((snapshot) {
            return snapshot.docs.map((doc) => Message.fromFirestore(doc)).toList();
          });
    } catch (e, stackTrace) {
      debugPrint('ChatService.streamMessages error: $e');
      debugPrintStack(stackTrace: stackTrace);
      return Stream.error(e);
    }
  }
}
