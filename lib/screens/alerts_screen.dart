import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'expense_detail_screen.dart';
import 'package:intl/intl.dart';

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

  String _prettyTime(Timestamp? ts) {
    if (ts == null) return '';
    final date = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return DateFormat('dd MMM').format(date);
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
      case 'bill_due_soon':
      case 'bill_due_tomorrow':
      case 'bill_overdue_reminder':
        return body.isNotEmpty ? body : (title.isNotEmpty ? title : 'Bill reminder');
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
            separatorBuilder: (context, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final docId = doc.id;
              final read = data['read'] as bool? ?? false;
              final subtitle = _messageFor(data);
              final ts = data['createdAt'] as Timestamp?;
              final timeLabel = _prettyTime(ts);

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: read
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: Colors.blue.withValues(alpha: 0.06),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                    ),
                    child: Row(
                      children: [
                        // Unread indicator
                        Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: read ? Colors.transparent : Colors.blueAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      data['title'] as String? ?? subtitle,
                                      style: TextStyle(
                                        fontWeight: read ? FontWeight.w600 : FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    timeLabel,
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                subtitle,
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                              ),
                            ],
                          ),
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
