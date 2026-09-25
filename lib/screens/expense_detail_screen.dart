import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/payment_proof.dart';
import '../services/expense_service.dart';
import '../services/house_service.dart';
import 'payment_proof_submission_sheet.dart';

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

  List<PaymentProofAttachment> _parsePaymentProofs(dynamic raw) {
    if (raw is! List) {
      return const <PaymentProofAttachment>[];
    }

    return raw
        .whereType<Map>()
        .map((entry) => PaymentProofAttachment.fromMap(Map<String, dynamic>.from(entry)))
        .where(
          (attachment) => attachment.downloadUrl.isNotEmpty || attachment.storagePath.isNotEmpty,
        )
        .toList();
  }

  Future<String?> _promptRejectionReason(String participantName) async {
    final controller = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reject payment proof'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Optional reason',
              hintText: 'Explain why $participantName needs to resubmit',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    return reason;
  }

  Future<void> _confirmMarkAsPaid(
    String expenseId,
    String participantId,
    String expenseTitle,
  ) async {
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return PaymentProofSubmissionSheet(
          expenseId: expenseId,
          participantId: participantId,
          expenseTitle: expenseTitle,
        );
      },
    );

    if (submitted == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Payment proof submitted')));
    }
  }

  Future<void> _openProofAttachment(PaymentProofAttachment attachment) async {
    final uri = Uri.tryParse(attachment.downloadUrl);
    if (uri == null) {
      return;
    }

    if (attachment.isPdf) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        attachment.fileName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              InteractiveViewer(
                child: Image.network(
                  attachment.downloadUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Could not load image: $error'),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProofReviewCard({
    required String participantId,
    required String participantName,
    required List<PaymentProofAttachment> attachments,
    required String note,
    required String reviewReason,
    required String expenseTitle,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment proof submitted for $expenseTitle',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      participantName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  attachments.isEmpty
                      ? 'No files'
                      : '${attachments.length} file${attachments.length == 1 ? '' : 's'}',
                  style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Text(note, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
          if (reviewReason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Text(
                'Rejection reason: $reviewReason',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.red.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: attachments.map((attachment) {
                return InkWell(
                  onTap: () => _openProofAttachment(attachment),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 122,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 72,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: attachment.isPdf
                                ? const Color(0xFFFDF4EA)
                                : const Color(0xFFF4F7F5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: attachment.isPdf
                              ? const Icon(
                                  Icons.picture_as_pdf_rounded,
                                  color: Color(0xFFC2410C),
                                  size: 34,
                                )
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    attachment.downloadUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Center(
                                        child: Icon(Icons.image_not_supported_outlined),
                                      );
                                    },
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          attachment.isPdf ? 'PDF' : 'Image',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Colors.blue.shade900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          attachment.fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              'No files were attached. You can still approve or reject this payment.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blue.shade700),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await _expenseService.approvePaymentProof(widget.expenseId, participantId);
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Payment proof approved')),
                      );
                    } catch (error) {
                      messenger.showSnackBar(SnackBar(content: Text('Error: ${error.toString()}')));
                    }
                  },
                  child: const Text('Approve'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final reason = await _promptRejectionReason(participantName);
                    if (reason == null) {
                      return;
                    }
                    try {
                      await _expenseService.rejectPaymentProof(
                        widget.expenseId,
                        participantId,
                        reason: reason,
                      );
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Payment proof rejected')),
                      );
                    } catch (error) {
                      messenger.showSnackBar(SnackBar(content: Text('Error: ${error.toString()}')));
                    }
                  },
                  child: const Text('Reject'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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

                                    // House-wide status counts are only shown to
                                    // the bill creator; other members can only
                                    // read their own participant document, so
                                    // aggregate counts would be misleading.
                                    if (!isOwner) {
                                      return const SizedBox.shrink();
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
                              final paymentProofNote =
                                  (d['paymentProofNote'] as String?)?.trim() ?? '';
                              final paymentProofReviewReason =
                                  (d['paymentProofReviewReason'] as String?)?.trim() ?? '';
                              final paymentProofAttachments = _parsePaymentProofs(
                                d['paymentProofs'],
                              );

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
                                        _buildProofReviewCard(
                                          participantId: participantId,
                                          participantName: participantName,
                                          attachments: paymentProofAttachments,
                                          note: paymentProofNote,
                                          reviewReason: paymentProofReviewReason,
                                          expenseTitle: title,
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
                                            onPressed: () => _confirmMarkAsPaid(
                                              widget.expenseId,
                                              participantId,
                                              title,
                                            ),
                                            child: const Text('Submit payment proof'),
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
