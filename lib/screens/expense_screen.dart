import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/expense_model.dart';
import '../models/house_model.dart';
import '../services/expense_service.dart';
import '../services/house_service.dart';

class ExpenseScreen extends StatefulWidget {
  final House house;

  const ExpenseScreen({super.key, required this.house});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  static const _darkGreen = Color(0xFF0B3D2E);

  final ExpenseService _expenseService = ExpenseService();
  final HouseService _houseService = HouseService();

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isOwner = widget.house.leaderId == currentUserId;

    return Scaffold(
      appBar: AppBar(title: const Text('Bills')),
      floatingActionButton: isOwner
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => CreateBillScreen(house: widget.house)));
              },
              icon: const Icon(Icons.add),
              label: const Text('Request Bill'),
            )
          : null,
      body: StreamBuilder<List<ExpenseModel>>(
        stream: _expenseService.streamExpenses(widget.house.houseId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _darkGreen));
          }

          if (snapshot.hasError) {
            return const Center(child: Text('Could not load bills right now.'));
          }

          final bills = snapshot.data ?? const <ExpenseModel>[];
          if (bills.isEmpty) {
            return const Center(child: Text('No bills yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: bills.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final bill = bills[index];
              return _BillCard(
                bill: bill,
                currentUserId: currentUserId,
                expenseService: _expenseService,
                houseService: _houseService,
              );
            },
          );
        },
      ),
    );
  }
}

class CreateBillScreen extends StatefulWidget {
  final House house;

  const CreateBillScreen({super.key, required this.house});

  @override
  State<CreateBillScreen> createState() => _CreateBillScreenState();
}

class _CreateBillScreenState extends State<CreateBillScreen> {
  static const _darkGreen = Color(0xFF0B3D2E);
  static const _surfaceGreen = Color(0xFFE9F7EE);

  final ExpenseService _expenseService = ExpenseService();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  final Map<String, String> _categoryLabels = const {
    'rent': 'Rent',
    'electricity': 'Electricity',
    'water': 'Water',
    'internet': 'Internet',
    'other': 'Other',
  };

  String _selectedCategory = 'water';
  final Set<String> _selectedMembers = <String>{};
  bool _saving = false;
  String? _errorText;

  double _suggestedAmountForCategory(String category) {
    switch (category) {
      case 'rent':
        return widget.house.rentTotal;
      case 'electricity':
        return widget.house.electricityTotal;
      case 'water':
        return widget.house.waterTotal;
      case 'internet':
        return widget.house.internetTotal;
      default:
        return 0.0;
    }
  }

  double? _parseAmount(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }

    final parsed = double.tryParse(normalized);
    if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed < 0) {
      return null;
    }

    return parsed;
  }

  String _formatMoney(double value) => '₺${value.toStringAsFixed(2)}';

  @override
  void initState() {
    super.initState();
    _selectedMembers.addAll(widget.house.members);
    _amountController.text = _suggestedAmountForCategory(_selectedCategory).toStringAsFixed(2);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _saveBill() async {
    if (_saving) {
      return;
    }

    final totalAmount = _parseAmount(_amountController.text);
    final title = _titleController.text.trim();
    final membersToUse = _selectedMembers.isEmpty
        ? widget.house.members
        : _selectedMembers.toList();

    if (title.isEmpty) {
      setState(() => _errorText = 'Please enter a title.');
      return;
    }
    if (totalAmount == null) {
      setState(() => _errorText = 'Please enter a valid amount.');
      return;
    }
    if (membersToUse.isEmpty) {
      setState(() => _errorText = 'Select at least one member.');
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      await _expenseService.createExpense(
        houseId: widget.house.houseId,
        category: _selectedCategory,
        title: title,
        totalAmount: totalAmount,
        members: membersToUse,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
        _errorText = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalAmount = _parseAmount(_amountController.text);
    final selectedCount = _selectedMembers.isEmpty
        ? widget.house.members.length
        : _selectedMembers.length;
    final perPersonAmount = totalAmount == null || selectedCount == 0
        ? 0.0
        : totalAmount / selectedCount;

    return Scaffold(
      appBar: AppBar(title: const Text('Request Bill')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 10)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Request Bill',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: _darkGreen, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pick a type, set the amount, and optionally target specific members.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: _darkGreen.withValues(alpha: 0.68)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  items: _categoryLabels.entries
                      .map(
                        (entry) =>
                            DropdownMenuItem<String>(value: entry.key, child: Text(entry.value)),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _selectedCategory = value;
                            _errorText = null;
                            _amountController.text = _suggestedAmountForCategory(
                              value,
                            ).toStringAsFixed(2);
                          });
                        },
                  decoration: const InputDecoration(
                    labelText: 'Bill Type',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _titleController,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Title / Note',
                    prefixIcon: Icon(Icons.receipt_long_outlined),
                  ),
                  onChanged: (_) => setState(() => _errorText = null),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _amountController,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    helperText: _selectedCategory == 'other'
                        ? 'Enter a new amount'
                        : 'Suggested from current house ${_categoryLabels[_selectedCategory]!.toLowerCase()} total',
                    prefixIcon: const Icon(Icons.payments_outlined),
                  ),
                  onChanged: (_) => setState(() => _errorText = null),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _surfaceGreen,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total: ${_formatMoney(totalAmount ?? 0)}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: _darkGreen,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Per Person: ${_formatMoney(perPersonAmount)}',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: _darkGreen.withValues(alpha: 0.78),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Members',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: _darkGreen, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      selected:
                          _selectedMembers.length == widget.house.members.length &&
                          widget.house.members.isNotEmpty,
                      label: const Text('All'),
                      onSelected: _saving
                          ? null
                          : (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedMembers
                                    ..clear()
                                    ..addAll(widget.house.members);
                                } else {
                                  _selectedMembers.clear();
                                }
                              });
                            },
                    ),
                    ...widget.house.members.map((memberId) {
                      final shortLabel = memberId.length > 10
                          ? '${memberId.substring(0, 10)}…'
                          : memberId;
                      return FilterChip(
                        selected: _selectedMembers.contains(memberId),
                        label: Text(shortLabel),
                        onSelected: _saving
                            ? null
                            : (_) {
                                setState(() {
                                  if (_selectedMembers.contains(memberId)) {
                                    _selectedMembers.remove(memberId);
                                  } else {
                                    _selectedMembers.add(memberId);
                                  }
                                });
                              },
                      );
                    }),
                  ],
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorText!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveBill,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Request Bill'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  final ExpenseModel bill;
  final String currentUserId;
  final ExpenseService expenseService;
  final HouseService houseService;

  const _BillCard({
    required this.bill,
    required this.currentUserId,
    required this.expenseService,
    required this.houseService,
  });

  @override
  Widget build(BuildContext context) {
    final isCreator = bill.createdBy == currentUserId;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 10)),
        ],
      ),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('house_expenses')
            .doc(bill.id)
            .collection('participants')
            .snapshots(),
        builder: (context, participantSnapshot) {
          final participantDocs = participantSnapshot.data?.docs ?? const [];
          final participantIds = participantDocs
              .map((doc) => (doc.data()['userId'] as String? ?? doc.id).trim())
              .where((id) => id.isNotEmpty)
              .toList();

          String? currentUserStatus;
          for (final doc in participantDocs) {
            final data = doc.data();
            final participantId = (data['userId'] as String? ?? doc.id).trim();
            if (participantId == currentUserId) {
              currentUserStatus = data['status'] as String? ?? 'pending';
              break;
            }
          }

          final paidParticipants = participantDocs.where((doc) {
            final data = doc.data();
            return (data['status'] as String? ?? 'pending') == 'paid';
          }).toList();

          return _BillCardContent(
            bill: bill,
            isCreator: isCreator,
            currentUserId: currentUserId,
            currentUserStatus: currentUserStatus,
            participantDocs: participantDocs,
            participantIds: participantIds,
            paidParticipants: paidParticipants,
            expenseService: expenseService,
            houseService: houseService,
          );
        },
      ),
    );
  }
}

class _PaidSummary extends StatelessWidget {
  static const _darkGreen = Color(0xFF0B3D2E);

  final int paidCount;
  final int totalCount;

  const _PaidSummary({required this.paidCount, required this.totalCount});

  @override
  Widget build(BuildContext context) {
    final progress = totalCount == 0 ? 0.0 : (paidCount / totalCount);

    return Row(
      children: [
        Text(
          'Paid: $paidCount / $totalCount',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: _darkGreen.withValues(alpha: 0.72),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LinearProgressIndicator(
            value: progress,
            color: Colors.green.shade600,
            backgroundColor: Colors.green.shade100,
          ),
        ),
      ],
    );
  }
}

class _BillCardContent extends StatelessWidget {
  static const _surfaceGreen = Color(0xFFE9F7EE);

  final ExpenseModel bill;
  final bool isCreator;
  final String currentUserId;
  final String? currentUserStatus;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> participantDocs;
  final List<String> participantIds;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> paidParticipants;
  final ExpenseService expenseService;
  final HouseService houseService;

  const _BillCardContent({
    required this.bill,
    required this.isCreator,
    required this.currentUserId,
    required this.currentUserStatus,
    required this.participantDocs,
    required this.participantIds,
    required this.paidParticipants,
    required this.expenseService,
    required this.houseService,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: houseService.getUserNamesByIds(participantIds),
      builder: (context, namesSnapshot) {
        final participantNames = namesSnapshot.data ?? const <String, String>{};

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              bill.category.toUpperCase(),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              bill.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              '₺${bill.totalAmount.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '₺${bill.perPersonAmount.toStringAsFixed(2)} per person',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _PaidSummary(paidCount: paidParticipants.length, totalCount: participantDocs.length),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: participantDocs.map((doc) {
                final data = doc.data();
                final participantId = (data['userId'] as String? ?? doc.id).trim();
                final name = participantNames[participantId] ?? participantId;
                final status = data['status'] as String? ?? 'pending';

                return Chip(backgroundColor: _surfaceGreen, label: Text('$name · $status'));
              }).toList(),
            ),
            if (currentUserStatus == 'pending') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => expenseService.markAsPaid(bill.id, currentUserId),
                  child: const Text('Mark as Paid'),
                ),
              ),
            ],
            if (isCreator && paidParticipants.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Awaiting owner confirmation',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ...paidParticipants.map((doc) {
                final data = doc.data();
                final participantId = (data['userId'] as String? ?? doc.id).trim();
                final name = participantNames[participantId] ?? participantId;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _surfaceGreen,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text(name)),
                        TextButton(
                          onPressed: () => expenseService.confirmPayment(bill.id, participantId),
                          child: const Text('Confirm Payment'),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
            if (bill.status == 'confirmed') ...[
              const SizedBox(height: 12),
              Text(
                'Confirmed',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
