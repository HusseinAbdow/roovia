import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'expense_detail_screen.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get _currentUserId => _auth.currentUser?.uid ?? '';

  /// Mark a single notification as read when tapped
  Future<void> _markAsRead(String docId) async {
    try {
      await _db
          .collection('user_notifications')
          .doc(_currentUserId)
          .collection('notifications')
          .doc(docId)
          .update({'read': true});
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  String _messageFor(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';
    final body = data['body'] as String? ?? '';
    final title = data['title'] as String? ?? '';

    switch (type) {
      case 'expense_request':
        return body.isNotEmpty ? body : (title.isNotEmpty ? title : 'New bill requested');
      case 'payment_marked':
        return body.isNotEmpty ? body : 'A member sent money';
      case 'payment_confirmed':
        return body.isNotEmpty ? body : 'Your payment was confirmed';
      case 'bill_due_reminder':
        return body.isNotEmpty ? body : (title.isNotEmpty ? title : 'Bill due reminder');
      default:
        return body.isNotEmpty ? body : (title.isNotEmpty ? title : 'Notification');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _currentUserId;
    if (uid.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Alerts')),
        body: const Center(child: Text('Not signed in')),
      );
    }

    final col = _db
        .collection('user_notifications')
        .doc(uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: col.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load alerts.'));
          }

          final docs = snapshot.data?.docs ?? const [];
          if (docs.isEmpty) {
            return const Center(child: Text('No alerts.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final docId = doc.id;
              final read = data['read'] as bool? ?? false;
              final subtitle = _messageFor(data);

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    if (!read) {
                      _markAsRead(docId);
                    }
                    final expenseId = data['expenseId'] as String?;
                    if (expenseId != null && expenseId.isNotEmpty) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ExpenseDetailScreen(expenseId: expenseId),
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: read ? Colors.white : const Color(0xFFEFF7FF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: read ? Colors.grey.shade200 : const Color(0xFFBBDFFF),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['title'] as String? ?? subtitle,
                          style: TextStyle(fontWeight: read ? FontWeight.w500 : FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: TextStyle(fontWeight: read ? FontWeight.w400 : FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
