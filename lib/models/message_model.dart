import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final Timestamp createdAt;

  Message({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.createdAt,
  });

  factory Message.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Message(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      senderName: data['senderName'] as String? ?? '',
      text: data['text'] as String? ?? '',
      createdAt: data['createdAt'] is Timestamp ? data['createdAt'] as Timestamp : Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {'senderId': senderId, 'senderName': senderName, 'text': text, 'createdAt': createdAt};
  }
}
