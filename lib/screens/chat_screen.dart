import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import '../models/house_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';
import '../services/house_service.dart';

class ChatScreen extends StatefulWidget {
  final String houseId;

  const ChatScreen({super.key, required this.houseId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _darkGreen = Color(0xFF0B3D2E);
  static const _emptyStateMessage = 'No messages yet. Start the conversation.';
  static const _loadErrorMessage = 'Failed to load messages. Please try again.';

  final ChatService _chatService = ChatService();
  final HouseService _houseService = HouseService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late Future<House?> _houseFuture;

  bool _isSending = false;
  bool _hasMarkedSeen = false;
  RooviaUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _houseFuture = _houseService.getHouseById(widget.houseId);
    _loadCurrentUser();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) {
      return;
    }

    try {
      final userSnapshot = await _db.collection('users').doc(firebaseUser.uid).get();
      if (!mounted) {
        return;
      }

      if (userSnapshot.exists && userSnapshot.data() != null) {
        setState(() {
          _currentUser = RooviaUser.fromMap(userSnapshot.data()!);
        });
      } else {
        setState(() {
          final emailPrefix = (firebaseUser.email ?? '').split('@').first.toLowerCase();
          final cleaned = emailPrefix.replaceAll(RegExp(r'[^a-z0-9_]'), '');
          final base = cleaned.isEmpty ? 'user000' : cleaned;
          final padded = base.padRight(3, '0');
          final fallbackUsername = padded.substring(0, padded.length > 20 ? 20 : padded.length);
          _currentUser = RooviaUser(
            uid: firebaseUser.uid,
            name: firebaseUser.displayName?.trim().isNotEmpty == true
                ? firebaseUser.displayName!.trim()
                : (firebaseUser.email ?? 'User').split('@').first,
            email: firebaseUser.email ?? '',
            username: fallbackUsername,
            profileImageUrl: '',
            rating: 0.0,
          );
        });
      }
    } catch (e) {
      debugPrint('Error loading current user: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_isSending || _currentUser == null) {
      return;
    }

    final trimmedText = _messageController.text.trim();
    if (trimmedText.isEmpty) {
      return;
    }

    setState(() => _isSending = true);
    try {
      await _chatService.sendMessage(
        houseId: widget.houseId,
        senderId: _currentUser!.uid,
        senderName: _currentUser!.name,
        text: trimmedText,
      );

      if (!mounted) {
        return;
      }

      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _renameChat(House house) async {
    final controller = TextEditingController(text: house.displayChatName);

    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Chat name'),
          textInputAction: TextInputAction.done,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();

    final trimmedName = newName?.trim();
    if (trimmedName == null || trimmedName.isEmpty || trimmedName == house.displayChatName) {
      return;
    }

    try {
      await _houseService.updateHouseChatName(houseId: house.houseId, chatName: trimmedName);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Chat name updated')));
      setState(() {
        _houseFuture = _houseService.getHouseById(widget.houseId);
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      final message = e is StateError ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTimestamp(Timestamp timestamp) {
    final dateTime = timestamp.toDate();
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<House?>(
      future: _houseFuture,
      builder: (context, houseSnapshot) {
        if (houseSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('House Chat')),
            body: const Center(child: CircularProgressIndicator(color: _darkGreen)),
          );
        }

        if (houseSnapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('House Chat')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _loadErrorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _darkGreen),
                ),
              ),
            ),
          );
        }

        final house = houseSnapshot.data;
        final currentUserId = _currentUser?.uid;
        final isOwner = house != null && currentUserId != null && house.leaderId == currentUserId;

        return Scaffold(
          appBar: AppBar(
            title: Text(house?.displayChatName ?? 'House Chat'),
            actions: [
              if (house != null && isOwner)
                IconButton(
                  onPressed: () => _renameChat(house),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Rename chat',
                ),
            ],
          ),
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<Message>>(
                    stream: _chatService.streamMessages(widget.houseId),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && !_hasMarkedSeen) {
                        final currentUserId = _auth.currentUser?.uid;
                        if (currentUserId != null && currentUserId.isNotEmpty) {
                          _hasMarkedSeen = true;
                          unawaited(_chatService.markChatAsSeen(widget.houseId, currentUserId));
                        }
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: _darkGreen));
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _loadErrorMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: _darkGreen),
                            ),
                          ),
                        );
                      }

                      final messages = snapshot.data ?? const <Message>[];

                      if (messages.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _emptyStateMessage,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _darkGreen.withValues(alpha: 0.7)),
                            ),
                          ),
                        );
                      }

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _scrollToBottom();
                      });

                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          final isCurrentUser = message.senderId == _currentUser?.uid;
                          final backgroundColor = isCurrentUser
                              ? const Color(0xFFD4EDDA)
                              : const Color(0xFFE9ECEF);
                          final alignment = isCurrentUser
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start;

                          return Row(
                            mainAxisAlignment: alignment,
                            children: [
                              Flexible(
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                                  ),
                                  decoration: BoxDecoration(
                                    color: backgroundColor,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        message.senderName,
                                        style: const TextStyle(
                                          color: _darkGreen,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        message.text,
                                        style: const TextStyle(color: _darkGreen, fontSize: 14),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _formatTimestamp(message.createdAt),
                                        style: TextStyle(
                                          color: _darkGreen.withValues(alpha: 0.6),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                AnimatedPadding(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(color: _darkGreen.withValues(alpha: 0.1), width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            decoration: InputDecoration(
                              hintText: 'Type a message...',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            maxLines: null,
                            minLines: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _isSending ? null : _sendMessage,
                          icon: _isSending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                          label: const Text('Send'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _darkGreen,
                            disabledBackgroundColor: _darkGreen.withValues(alpha: 0.5),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
