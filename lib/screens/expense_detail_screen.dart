import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/expense_service.dart';
import '../services/house_service.dart';

class ExpenseDetailScreen extends StatefulWidget {
  final String expenseId;

  const ExpenseDetailScreen({super.key, required this.expenseId});

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ExpenseService _expenseService = ExpenseService();
  final HouseService _houseService = HouseService();

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  int _countStatus(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, String status) {
    return docs.where((doc) => (doc.data()['status'] as String? ?? 'pending') == status).length;
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _dueLabel(DateTime dueDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diff = due.difference(today).inDays;
    if (diff < 0) {
      return 'Overdue';
    }
    if (diff <= 3) {
      return 'Due in $diff days';
    }
    return 'Due: ${_formatDate(dueDate)}';
  }

  Color _dueColor(DateTime dueDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diff = due.difference(today).inDays;
    if (diff < 0) {
      return Colors.red.shade700;
    }
    if (diff <= 3) {
      return Colors.orange.shade700;
    }
    return Colors.green.shade700;
  }

  Future<void> _confirmMarkAsPaid(String expenseId, String participantId) async {
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("I've Sent the Money"),
          content: const Text('Confirm that you have sent your payment for this bill.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (shouldProceed == true) {
      await _expenseService.markAsPaid(expenseId, participantId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final col = _db.collection('house_expenses').doc(widget.expenseId);

    return Scaffold(
      appBar: AppBar(title: const Text('Bill')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: col.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('Expense not found'));
          }

          final data = snap.data!.data() ?? {};
          final title = data['title'] as String? ?? '';
          final description = data['description'] as String? ?? '';
          final reference = data['reference'] as String? ?? '';
          final dueDateRaw = data['dueDate'];
          final dueDate = dueDateRaw is Timestamp
              ? dueDateRaw.toDate()
              : dueDateRaw is DateTime
              ? dueDateRaw
              : DateTime.now();
          final total = (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
          final perPerson = (data['perPersonAmount'] as num?)?.toDouble() ?? 0.0;
          final createdBy = data['createdBy'] as String? ?? '';
          final isOwner = createdBy == _uid;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: col.collection('participants').snapshots(),
              builder: (context, partSnap) {
                if (partSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = partSnap.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No participants'));
                }

                final participantIds = docs
                    .map((doc) => (doc.data()['userId'] as String? ?? doc.id).trim())
                    .where((id) => id.isNotEmpty)
                    .toList();

                return FutureBuilder<Map<String, String>>(
                  future: _houseService.getUserNamesByIds(participantIds),
                  builder: (context, namesSnap) {
                    final namesById = namesSnap.data ?? const <String, String>{};
                    final confirmedCount = _countStatus(docs, 'confirmed');
                    final paidCount = _countStatus(docs, 'paid');
                    final pendingCount = _countStatus(docs, 'pending');
                    final totalParticipants = docs.length;
                    final paidOrConfirmed = confirmedCount + paidCount;
                    final paidAmount = perPerson * paidOrConfirmed;
                    final remainingAmount = (total - paidAmount) < 0 ? 0.0 : (total - paidAmount);

                    final confirmedDocs = docs.where((doc) {
                      final status = (doc.data()['status'] as String? ?? 'pending');
                      return status == 'confirmed';
                    }).toList();
                    final pendingDocs = docs.where((doc) {
                      final status = (doc.data()['status'] as String? ?? 'pending');
                      return status != 'confirmed';
                    }).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bill overview',
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _dueLabel(dueDate),
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: _dueColor(dueDate),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (description.trim().isNotEmpty) ...[
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Payment Details / Proof',
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          description,
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (reference.trim().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Reference: $reference',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Text('Total: ₺${total.toStringAsFixed(2)}'),
                                const SizedBox(height: 4),
                                Text('Per person: ₺${perPerson.toStringAsFixed(2)}'),
                                const SizedBox(height: 16),
                                if (isOwner) ...[
                                  Builder(
                                    builder: (context) {
                                      final billStatus = (data['status'] as String?) ?? 'pending';
                                      final isSettled = billStatus == 'confirmed';

                                      if (isSettled) {
                                        return const SizedBox.shrink();
                                      }

                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Paid $paidOrConfirmed / $totalParticipants',
                                            style: const TextStyle(fontWeight: FontWeight.w700),
                                          ),
                                          const SizedBox(height: 8),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(999),
                                            child: LinearProgressIndicator(
                                              value: totalParticipants == 0
                                                  ? 0
                                                  : paidOrConfirmed / totalParticipants,
                                              minHeight: 8,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Remaining amount: ₺${remainingAmount.toStringAsFixed(2)}',
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(height: 16),
                                          // Show button if owner is viewing and the expense is not yet finalized.
                                          // Owner can click to confirm all pending/paid members and notify them.
                                          Builder(
                                            builder: (context) {
                                              final expenseStatus =
                                                  (data['status'] as String?) ?? 'pending';
                                              final expenseIsConfirmed =
                                                  expenseStatus == 'confirmed';

                                              if (isOwner && !expenseIsConfirmed) {
                                                return SizedBox(
                                                  width: double.infinity,
                                                  child: ElevatedButton(
                                                    onPressed: () async {
                                                      final scaffoldMessenger =
                                                          ScaffoldMessenger.of(context);
                                                      try {
                                                        await _expenseService
                                                            .confirmAllPaidParticipants(
                                                              widget.expenseId,
                                                            );
                                                        scaffoldMessenger.showSnackBar(
                                                          const SnackBar(
                                                            content: Text('Payments confirmed'),
                                                          ),
                                                        );
                                                      } catch (e) {
                                                        scaffoldMessenger.showSnackBar(
                                                          SnackBar(
                                                            content: Text('Error: ${e.toString()}'),
                                                          ),
                                                        );
                                                      }
                                                    },
                                                    child: const Text('Confirm Settlement'),
                                                  ),
                                                );
                                              }
                                              return const SizedBox.shrink();
                                            },
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                                Builder(
                                  builder: (context) {
                                    final billStatus = (data['status'] as String?) ?? 'pending';
                                    final isSettled = billStatus == 'confirmed';

                                    if (isSettled) {
                                      return Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 24,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.green.shade200,
                                            width: 2,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Container(
                                              width: 64,
                                              height: 64,
                                              decoration: BoxDecoration(
                                                color: Colors.green.shade100,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.check_rounded,
                                                size: 36,
                                                color: Colors.green.shade700,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              'Bill Settled',
                                              style: Theme.of(context).textTheme.titleLarge
                                                  ?.copyWith(
                                                    color: Colors.green.shade700,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'All members have confirmed payment',
                                              style: Theme.of(context).textTheme.bodyMedium
                                                  ?.copyWith(color: Colors.green.shade600),
                                            ),
                                          ],
                                        ),
                                      );
                                    }

                                    return Wrap(
                                      spacing: 12,
                                      runSpacing: 8,
                                      children: [
                                        _SummaryPill(
                                          icon: Icons.check_circle,
                                          label: 'Confirmed',
                                          value: confirmedCount,
                                          color: Colors.green,
                                        ),
                                        _SummaryPill(
                                          icon: Icons.hourglass_bottom,
                                          label: 'Paid',
                                          value: paidCount,
                                          color: Colors.blue,
                                        ),
                                        _SummaryPill(
                                          icon: Icons.circle_outlined,
                                          label: 'Pending',
                                          value: pendingCount,
                                          color: Colors.grey,
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Participants',
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemBuilder: (context, index) {
                              final groupedDocs = isOwner
                                  ? [...confirmedDocs, ...pendingDocs]
                                  : docs.where((doc) {
                                      final data = doc.data();
                                      final participantId = (data['userId'] as String? ?? doc.id)
                                          .trim();
                                      return participantId == _uid;
                                    }).toList();
                              final d = groupedDocs[index].data();
                              final participantId =
                                  (d['userId'] as String?) ?? groupedDocs[index].id;
                              final status = (d['status'] as String?) ?? 'pending';
                              final amount = (d['amountOwed'] as num?)?.toDouble() ?? 0.0;
                              final participantName = namesById[participantId] ?? 'Unknown user';
                              final isSelf = participantId == _uid;

                              return Card(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                margin: const EdgeInsets.only(bottom: 10),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (isOwner && index == 0 && confirmedDocs.isNotEmpty)
                                        const Padding(
                                          padding: EdgeInsets.only(bottom: 8),
                                          child: Text(
                                            'Confirmed',
                                            style: TextStyle(fontWeight: FontWeight.w800),
                                          ),
                                        ),
                                      if (isOwner &&
                                          index == confirmedDocs.length &&
                                          pendingDocs.isNotEmpty)
                                        const Padding(
                                          padding: EdgeInsets.only(bottom: 8),
                                          child: Text(
                                            'Pending',
                                            style: TextStyle(fontWeight: FontWeight.w800),
                                          ),
                                        ),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  isSelf
                                                      ? '$participantName (You)'
                                                      : participantName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text('Share: ₺${amount.toStringAsFixed(2)}'),
                                              ],
                                            ),
                                          ),
                                          _StatusBadge(status: status, dueDate: dueDate),
                                        ],
                                      ),
                                      if (isOwner && status == 'paid' && !isSelf) ...[
                                        const SizedBox(height: 16),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton(
                                            onPressed: () => _expenseService.confirmPayment(
                                              widget.expenseId,
                                              participantId,
                                            ),
                                            child: const Text('Confirm Payment'),
                                          ),
                                        ),
                                      ],
                                      if (!isOwner && isSelf && status == 'pending') ...[
                                        const SizedBox(height: 12),
                                        if (description.trim().isNotEmpty) ...[
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(12),
                                            margin: const EdgeInsets.only(bottom: 12),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade50,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.blue.shade300),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Payment Instructions',
                                                  style: Theme.of(context).textTheme.labelSmall
                                                      ?.copyWith(
                                                        fontWeight: FontWeight.w700,
                                                        color: Colors.blue.shade700,
                                                      ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  description,
                                                  style: Theme.of(context).textTheme.bodySmall,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton(
                                            onPressed: () =>
                                                _confirmMarkAsPaid(widget.expenseId, participantId),
                                            child: const Text("I've Sent the Money"),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                            itemCount: isOwner
                                ? (confirmedDocs.length + pendingDocs.length)
                                : docs.where((doc) {
                                    final data = doc.data();
                                    final participantId = (data['userId'] as String? ?? doc.id)
                                        .trim();
                                    return participantId == _uid;
                                  }).length,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final DateTime? dueDate;

  const _StatusBadge({required this.status, this.dueDate});

  Color get _color {
    if (status == 'confirmed') {
      return Colors.green;
    }
    if (status == 'paid') {
      return Colors.blue;
    }
    // For pending: check if overdue
    if (dueDate != null && DateTime.now().isAfter(dueDate!)) {
      return Colors.red;
    }
    return Colors.orange;
  }

  String get _label {
    if (status == 'confirmed') return 'Confirmed';
    if (status == 'paid') return 'Paid';
    if (dueDate != null && DateTime.now().isAfter(dueDate!)) return 'Overdue';
    return 'Pending';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _label,
        style: TextStyle(color: _color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  const _SummaryPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$value $label',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
