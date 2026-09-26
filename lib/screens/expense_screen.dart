import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../models/expense_model.dart';
import '../models/house_model.dart';
import '../services/expense_service.dart';
import '../services/house_service.dart';
import 'expense_detail_screen.dart';

class ExpenseScreen extends StatefulWidget {
  final House house;

  const ExpenseScreen({super.key, required this.house});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  static const _darkGreen = Color(0xFF0B3D2E);
  static const _softGreen = Color(0xFFDDF2E3);
  static const _softBlue = Color(0xFFDDEDF9);
  static const _softAmber = Color(0xFFF9E8CC);

  final ExpenseService _expenseService = ExpenseService();
  final HouseService _houseService = HouseService();
  String _selectedCategory = 'all';

  String _formatMoneyCompact(double amount) {
    if (amount >= 1000) {
      return '₺${(amount / 1000).toStringAsFixed(1)}k';
    }
    return '₺${amount.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isOwner = widget.house.leaderId == currentUserId;

    return Scaffold(
      appBar: AppBar(title: const Text('Bills')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isOwner) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Request Bill'),
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => CreateBillScreen(house: widget.house))),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Expenses list
            Expanded(
              child: StreamBuilder<List<ExpenseModel>>(
                stream: _expenseService.streamExpenses(widget.house.houseId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: _darkGreen));
                  }

                  if (snapshot.hasError) {
                    // Surface the error for debugging (also printed to log)
                    final err = snapshot.error?.toString() ?? 'Unknown error';
                    debugPrint('Expense stream error: $err');
                    return Center(child: Text('Could not load bills: $err'));
                  }

                  final bills = snapshot.data ?? const <ExpenseModel>[];
                  if (bills.isEmpty) {
                    return const Center(child: Text('No bills yet.'));
                  }

                  final categories = <String>{'all', ...bills.map((bill) => bill.category)};
                  final visibleBills = _selectedCategory == 'all'
                      ? bills
                      : bills.where((bill) => bill.category == _selectedCategory).toList();

                  final activeCount = bills.where((bill) => bill.status != 'confirmed').length;
                  final totalRequested = bills.fold<double>(
                    0,
                    (total, bill) => total + bill.totalAmount,
                  );
                  final yourEstimatedShare = bills.fold<double>(
                    0,
                    (total, bill) => total + bill.perPersonAmount,
                  );

                  return ListView(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'You have $activeCount active bills',
                              style: Theme.of(
                                context,
                              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _MetricBubble(
                                  label: 'Requested',
                                  value: _formatMoneyCompact(totalRequested),
                                  color: _softBlue,
                                  icon: Icons.receipt_long_rounded,
                                ),
                                _MetricBubble(
                                  label: 'Your Share',
                                  value: _formatMoneyCompact(yourEstimatedShare),
                                  color: _softGreen,
                                  icon: Icons.account_balance_wallet_rounded,
                                ),
                                _MetricBubble(
                                  label: 'Members',
                                  value: '${widget.house.members.length}',
                                  color: _softAmber,
                                  icon: Icons.people_alt_rounded,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 42,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: categories.map((category) {
                            final selected = _selectedCategory == category;
                            final label = category == 'all'
                                ? 'All'
                                : '${category[0].toUpperCase()}${category.substring(1)}';
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                selected: selected,
                                label: Text(label),
                                onSelected: (_) {
                                  setState(() {
                                    _selectedCategory = category;
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...visibleBills.map((bill) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _BillCard(
                            bill: bill,
                            currentUserId: currentUserId,
                            expenseService: _expenseService,
                            houseService: _houseService,
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
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
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  final Map<String, String> _categoryLabels = const {
    'rent': 'Rent',
    'electricity': 'Electricity',
    'water': 'Water',
    'internet': 'Internet',
    'other': 'Other',
  };

  String _selectedCategory = 'water';
  DateTime? _selectedDueDate;
  final Set<String> _selectedMembers = <String>{};
  late Future<Map<String, _MemberUiProfile>> _memberProfilesFuture;
  bool _saving = false;
  String? _errorText;

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<String> get _payingMemberIds {
    final currentUserId = _currentUserId;
    return widget.house.members
        .map((memberId) => memberId.trim())
        .where((memberId) => memberId.isNotEmpty && memberId != currentUserId)
        .toList();
  }

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

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialDate = _selectedDueDate ?? today.add(const Duration(days: 7));

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 3650)),
    );

    if (picked != null) {
      setState(() {
        _selectedDueDate = picked;
        _errorText = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedMembers.addAll(_payingMemberIds);
    _amountController.text = _suggestedAmountForCategory(_selectedCategory).toStringAsFixed(2);
    _memberProfilesFuture = _loadMemberProfiles();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<Map<String, _MemberUiProfile>> _loadMemberProfiles() async {
    final result = <String, _MemberUiProfile>{};

    await Future.wait(
      _payingMemberIds.map((memberId) async {
        try {
          final doc = await _db.collection('users').doc(memberId).get();
          final data = doc.data() ?? const <String, dynamic>{};
          final name = ((data['name'] as String?)?.trim().isNotEmpty ?? false)
              ? (data['name'] as String).trim()
              : ((data['username'] as String?)?.trim().isNotEmpty ?? false)
              ? (data['username'] as String).trim()
              : 'Member';
          final imageUrl = (data['profileImageUrl'] as String?)?.trim() ?? '';
          result[memberId] = _MemberUiProfile(name: name, imageUrl: imageUrl);
        } catch (_) {
          result[memberId] = const _MemberUiProfile(name: 'Member', imageUrl: '');
        }
      }),
    );

    return result;
  }

  Color _avatarColor(String seed) {
    final colors = <Color>[
      const Color(0xFFD9F0E1),
      const Color(0xFFDDEAF8),
      const Color(0xFFF8E6D7),
      const Color(0xFFE8DFF7),
      const Color(0xFFF7E6EF),
    ];
    return colors[seed.hashCode.abs() % colors.length];
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
  }

  Future<void> _saveBill() async {
    if (_saving) {
      return;
    }

    final totalAmount = _parseAmount(_amountController.text);
    final title = _titleController.text.trim();
    final dueDate = _selectedDueDate;
    final membersToUse = (_selectedMembers.isEmpty ? _payingMemberIds : _selectedMembers.toList())
        .map((memberId) => memberId.trim())
        .where((memberId) => memberId.isNotEmpty && memberId != _currentUserId)
        .toSet()
        .toList();

    if (title.isEmpty) {
      setState(() => _errorText = 'Please enter a title.');
      return;
    }
    if (dueDate == null) {
      setState(() => _errorText = 'Please select a due date.');
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
        description: _descriptionController.text,
        dueDate: dueDate,
        reference: '',
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
        ? _payingMemberIds.length
        : _selectedMembers.length;
    final perPersonAmount = totalAmount == null || selectedCount == 0
        ? 0.0
        : totalAmount / (selectedCount + 1);

    return Scaffold(
      appBar: AppBar(title: const Text('Request Bill')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
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
                  'Set title, due date, amount, and optional details.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: _darkGreen.withValues(alpha: 0.68)),
                ),
                const SizedBox(height: 16),
                Text(
                  'Bill Type',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: _darkGreen, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _categoryLabels.entries.map((entry) {
                    return ChoiceChip(
                      selected: _selectedCategory == entry.key,
                      label: Text(entry.value),
                      onSelected: _saving
                          ? null
                          : (_) {
                              setState(() {
                                _selectedCategory = entry.key;
                                _errorText = null;
                                _amountController.text = _suggestedAmountForCategory(
                                  entry.key,
                                ).toStringAsFixed(2);
                              });
                            },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _titleController,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    prefixIcon: Icon(Icons.receipt_long_outlined),
                  ),
                  onChanged: (_) => setState(() => _errorText = null),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _descriptionController,
                  enabled: !_saving,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Bill Details / Proof',
                    prefixIcon: Icon(Icons.receipt_outlined),
                    alignLabelWithHint: true,
                    hintText:
                        'Paste payment instructions, company message, IBAN, invoice text, or any proof/explanation for this bill.',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Include all details members need to process payment',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF0B3D2E).withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _saving ? null : _pickDueDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Due Date',
                      prefixIcon: Icon(Icons.event_outlined),
                    ),
                    child: Text(
                      _selectedDueDate == null ? 'Select due date' : _formatDate(_selectedDueDate!),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _surfaceGreen,
                    borderRadius: BorderRadius.circular(16),
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
                        'Per Person (including you): ${_formatMoney(perPersonAmount)}',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: _darkGreen.withValues(alpha: 0.78),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Who should pay?',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: _darkGreen, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                FutureBuilder<Map<String, _MemberUiProfile>>(
                  future: _memberProfilesFuture,
                  builder: (context, snapshot) {
                    final profiles = snapshot.data ?? const <String, _MemberUiProfile>{};
                    final selectedIds = _selectedMembers.toList();
                    final selectedProfiles = selectedIds
                        .map(
                          (id) => MapEntry(
                            id,
                            profiles[id] ?? const _MemberUiProfile(name: 'Member', imageUrl: ''),
                          ),
                        )
                        .toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 185,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F8F6),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2ECE7)),
                          ),
                          child: Stack(
                            children: [
                              if (selectedProfiles.isEmpty)
                                Center(
                                  child: Text(
                                    'No members selected',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: _darkGreen.withValues(alpha: 0.6),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              else
                                ...selectedProfiles.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final memberId = entry.value.key;
                                  final profile = entry.value.value;
                                  final angle = (2 * math.pi / selectedProfiles.length) * index;
                                  const radius = 48.0;
                                  const centerX = 85.0;
                                  const centerY = 70.0;
                                  final left = centerX + radius * math.cos(angle);
                                  final top = centerY + radius * math.sin(angle);

                                  return Positioned(
                                    left: left,
                                    top: top,
                                    child: GestureDetector(
                                      onTap: _saving
                                          ? null
                                          : () {
                                              setState(() {
                                                if (_selectedMembers.contains(memberId)) {
                                                  _selectedMembers.remove(memberId);
                                                } else {
                                                  _selectedMembers.add(memberId);
                                                }
                                              });
                                            },
                                      child: _MemberAvatar(
                                        size: 54,
                                        name: profile.name,
                                        imageUrl: profile.imageUrl,
                                        color: _avatarColor(memberId),
                                      ),
                                    ),
                                  );
                                }),
                              Positioned(
                                right: 4,
                                bottom: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0B3D2E),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${_selectedMembers.length} selected',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilterChip(
                              selected:
                                  _selectedMembers.length == _payingMemberIds.length &&
                                  _payingMemberIds.isNotEmpty,
                              label: const Text('All Members'),
                              onSelected: _saving
                                  ? null
                                  : (selected) {
                                      setState(() {
                                        if (selected) {
                                          _selectedMembers
                                            ..clear()
                                            ..addAll(_payingMemberIds);
                                        } else {
                                          _selectedMembers.clear();
                                        }
                                      });
                                    },
                            ),
                            ..._payingMemberIds.map((memberId) {
                              final profile =
                                  profiles[memberId] ??
                                  const _MemberUiProfile(name: 'Member', imageUrl: '');
                              return FilterChip(
                                selected: _selectedMembers.contains(memberId),
                                avatar: CircleAvatar(
                                  radius: 12,
                                  backgroundColor: _avatarColor(memberId),
                                  backgroundImage: profile.imageUrl.isNotEmpty
                                      ? NetworkImage(profile.imageUrl)
                                      : null,
                                  child: profile.imageUrl.isEmpty
                                      ? Text(
                                          _initials(profile.name),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: _darkGreen,
                                          ),
                                        )
                                      : null,
                                ),
                                label: Text(profile.name),
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
                      ],
                    );
                  },
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 16),
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
    return GestureDetector(
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => ExpenseDetailScreen(expenseId: bill.id)));
      },
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.all(16),
          // Firestore participant rules allow the bill creator (leader) to
          // read the whole participants collection, while a normal member can
          // only read their own participant document. Rules are not filters:
          // an unfiltered collection LIST would be denied for members, so
          // members stream their own single document instead.
          child: isCreator
              ? StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('house_expenses')
                      .doc(bill.id)
                      .collection('participants')
                      .snapshots(),
                  builder: (context, participantSnapshot) {
                    final participantDocs =
                        participantSnapshot.data?.docs ??
                        const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    final participantIds = List<String>.from(
                      participantDocs
                          .map((doc) => (doc.data()['userId'] as String? ?? doc.id).trim())
                          .where((id) => id.isNotEmpty)
                          .toList(),
                    );

                    String? currentUserStatus;
                    for (final doc in participantDocs) {
                      final data = doc.data();
                      final participantId = (data['userId'] as String? ?? doc.id).trim();
                      if (participantId == currentUserId) {
                        currentUserStatus = data['status'] as String? ?? 'pending';
                        break;
                      }
                    }

                    final paidParticipants = List<DocumentSnapshot<Map<String, dynamic>>>.from(
                      participantDocs.where((doc) {
                        final data = doc.data();
                        return (data['status'] as String? ?? 'pending') == 'paid';
                      }),
                    );

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
                )
              : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('house_expenses')
                      .doc(bill.id)
                      .collection('participants')
                      .doc(currentUserId)
                      .snapshots(),
                  builder: (context, participantSnapshot) {
                    final ownDoc = participantSnapshot.data;
                    final participantDocs = ownDoc != null && ownDoc.exists
                        ? <DocumentSnapshot<Map<String, dynamic>>>[ownDoc]
                        : const <DocumentSnapshot<Map<String, dynamic>>>[];
                    final ownData = ownDoc?.data() ?? const <String, dynamic>{};
                    final currentUserStatus = (ownData['status'] as String?) ?? 'pending';
                    final participantIds = participantDocs
                        .map((doc) => (doc.data()?['userId'] as String? ?? doc.id).trim())
                        .where((id) => id.isNotEmpty)
                        .toList();

                    return _BillCardContent(
                      bill: bill,
                      isCreator: isCreator,
                      currentUserId: currentUserId,
                      currentUserStatus: currentUserStatus,
                      participantDocs: participantDocs,
                      participantIds: List<String>.from(participantIds),
                      paidParticipants: const <DocumentSnapshot<Map<String, dynamic>>>[],
                      expenseService: expenseService,
                      houseService: houseService,
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _MemberUiProfile {
  final String name;
  final String imageUrl;

  const _MemberUiProfile({required this.name, required this.imageUrl});
}

class _MemberAvatar extends StatelessWidget {
  final double size;
  final String name;
  final String imageUrl;
  final Color color;

  const _MemberAvatar({
    required this.size,
    required this.name,
    required this.imageUrl,
    required this.color,
  });

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl.trim().isNotEmpty;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Color(0x1F000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: CircleAvatar(
        backgroundColor: color,
        backgroundImage: hasImage ? NetworkImage(imageUrl) : null,
        child: hasImage
            ? null
            : Text(
                _initials,
                style: const TextStyle(color: Color(0xFF0B3D2E), fontWeight: FontWeight.w800),
              ),
      ),
    );
  }
}

class _BillCardContent extends StatelessWidget {
  // static const _surfaceGreen = Color(0xFFE9F7EE); // Kept for potential future use
  static const _darkGreen = Color(0xFF0B3D2E);

  final ExpenseModel bill;
  final bool isCreator;
  final String currentUserId;
  final String? currentUserStatus;
  final List<DocumentSnapshot<Map<String, dynamic>>> participantDocs;
  final List<String> participantIds;
  final List<DocumentSnapshot<Map<String, dynamic>>> paidParticipants;
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

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _dueText(DateTime dueDate) {
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

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'rent':
        return Icons.home_work_rounded;
      case 'water':
        return Icons.water_drop_rounded;
      case 'internet':
        return Icons.wifi_rounded;
      case 'electricity':
        return Icons.bolt_rounded;
      default:
        return Icons.receipt_long_rounded;
    }
  }

  Color _statusColor(String status, DateTime dueDate) {
    if (status == 'confirmed') {
      return Colors.green.shade600;
    }
    final isOverdue = DateTime.now().isAfter(dueDate);
    if (isOverdue) {
      return Colors.red.shade600;
    }
    if (status == 'paid') {
      return Colors.blue.shade600;
    }
    return Colors.orange.shade600;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: houseService.getUserNamesByIds(participantIds),
      builder: (context, namesSnapshot) {
        // Note: participantNames kept in method signature for potential future use
        final confirmedCount = participantDocs.where((doc) {
          return (doc.data()?['status'] as String? ?? 'pending') == 'confirmed';
        }).length;
        final paidCount = participantDocs.where((doc) {
          return (doc.data()?['status'] as String? ?? 'pending') == 'paid';
        }).length;
        final pendingCount = participantDocs.where((doc) {
          return (doc.data()?['status'] as String? ?? 'pending') == 'pending';
        }).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7F1EA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_categoryIcon(bill.category), color: _darkGreen),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bill.title,
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        bill.category.toUpperCase(),
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Text(
                  '₺${bill.totalAmount.toStringAsFixed(2)}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _dueText(bill.dueDate),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: _dueText(bill.dueDate) == 'Overdue' ? Colors.red.shade700 : _darkGreen,
              ),
            ),
            const SizedBox(height: 8),
            if (bill.description.trim().isNotEmpty) ...[
              Text(bill.description, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
            ],
            if (bill.reference.trim().isNotEmpty) ...[
              Text(
                'Reference: ${bill.reference}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _darkGreen.withValues(alpha: 0.75),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              '₺${bill.perPersonAmount.toStringAsFixed(2)} per person',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            // House-wide payment progress and per-status counts are only shown
            // to the bill creator; other members can only read their own
            // participant document, so aggregate counts would be misleading.
            if (isCreator) ...[
              // Progress bar with status color
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: participantDocs.isEmpty
                      ? 0
                      : (confirmedCount + paidCount) / participantDocs.length,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _statusColor(bill.status, bill.dueDate),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Status summary row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Paid $paidCount / ${participantDocs.length}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _darkGreen,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(bill.status, bill.dueDate).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      bill.status == 'confirmed'
                          ? 'Settled'
                          : DateTime.now().isAfter(bill.dueDate)
                          ? 'Overdue'
                          : bill.status == 'paid'
                          ? 'Partial'
                          : 'Pending',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _statusColor(bill.status, bill.dueDate),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
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
              ),
              const SizedBox(height: 12),
            ] else ...[
              // Non-creators see only their own payment state, not house-wide
              // aggregates their participant read permissions would not cover.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Your status: ${currentUserStatus == 'paid' ? 'AWAITING REVIEW' : (currentUserStatus?.toUpperCase() ?? "PENDING")}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _darkGreen,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(bill.status, bill.dueDate).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      bill.status == 'confirmed'
                          ? 'Settled'
                          : DateTime.now().isAfter(bill.dueDate)
                          ? 'Overdue'
                          : bill.status == 'paid'
                          ? 'Partial'
                          : 'Pending',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _statusColor(bill.status, bill.dueDate),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (bill.status == 'confirmed') ...[
              Text(
                'Confirmed',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        );
      },
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

class _MetricBubble extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _MetricBubble({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF0B3D2E)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0B3D2E)),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0B3D2E),
            ),
          ),
        ],
      ),
    );
  }
}
