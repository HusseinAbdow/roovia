import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/house_model.dart';
import '../models/join_request_model.dart';
import '../services/house_service.dart';
import 'analytics_screen.dart';
import 'chat_screen.dart';
import 'create_house_screen.dart';
import 'house_detail_screen.dart';
import 'user_profile_screen.dart';

class HouseDashboardScreen extends StatefulWidget {
  const HouseDashboardScreen({super.key});

  @override
  State<HouseDashboardScreen> createState() => _HouseDashboardScreenState();
}

class _HouseDashboardScreenState extends State<HouseDashboardScreen> {
  static const _darkGreen = Color(0xFF0B3D2E);
  static const _lightGreen = Color(0xFFB9E8C9);
  static const _surfaceGreen = Color(0xFFE9F7EE);

  final HouseService _houseService = HouseService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Set<String> _processingRequestIds = <String>{};

  Future<void> _openCreateHouse() async {
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const CreateHouseScreen()));

    if (created == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('House created successfully.')));
    }
  }

  String _currentUserName() {
    final user = _auth.currentUser;
    if (user == null) {
      return 'there';
    }
    final displayName = (user.displayName ?? '').trim();
    if (displayName.isNotEmpty) {
      return displayName;
    }
    final email = user.email ?? '';
    if (email.contains('@')) {
      return email.split('@').first;
    }
    return 'there';
  }

  String _formatTry(double value) {
    if (value.isNaN || value.isInfinite) {
      return '0';
    }

    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }

  String _memberInitials(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '?';
    }

    final parts = trimmed.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();

    if (parts.isEmpty) {
      return trimmed.substring(0, trimmed.length >= 2 ? 2 : trimmed.length).toUpperCase();
    }

    final initials = parts.take(2).map((part) => part.isNotEmpty ? part[0] : '').join();

    return initials.toUpperCase();
  }

  double? _parseNonNegative(String rawValue) {
    final normalized = rawValue.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }

    final parsed = double.tryParse(normalized);
    if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed < 0) {
      return null;
    }

    return parsed;
  }

  Future<void> _showInviteCodeDialog(House house) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Invite Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              house.inviteCode,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: _darkGreen,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: house.inviteCode));
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Invite code copied.')));
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy Code'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLocationDialog(House house) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('City: ${house.city}'),
            if (house.district.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('District: ${house.district}'),
            ],
            if (house.address.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Address: ${house.address}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMembersPlaceholder(House house) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Members page coming soon. Current members: ${house.members.length}')),
    );
  }

  Future<void> _openUserProfile(String userId) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)));
  }

  Future<void> _handleJoinRequest(JoinRequest request, {required bool approve}) async {
    if (_processingRequestIds.contains(request.id)) {
      return;
    }

    setState(() => _processingRequestIds.add(request.id));
    try {
      await _houseService.respondToJoinRequest(requestId: request.id, approve: approve);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(approve ? 'Request approved' : 'Request rejected')));
    } catch (e) {
      if (!mounted) {
        return;
      }

      final message = (e is StateError ? e.message : e).toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _processingRequestIds.remove(request.id));
      }
    }
  }

  Future<void> _showRequestsSheet(House house) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.65,
              child: _buildJoinRequestsSection(house),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showUpdateMonthlyCostsSheet(House house) async {
    final currentUserId = _auth.currentUser?.uid ?? '';
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (house.leaderId != currentUserId) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Only the house owner can update monthly costs.')),
      );
      return;
    }

    final rentController = TextEditingController(text: _formatTry(house.rentTotal));
    final electricityController = TextEditingController(text: _formatTry(house.electricityTotal));
    final waterController = TextEditingController(text: _formatTry(house.waterTotal));
    final internetController = TextEditingController(text: _formatTry(house.internetTotal));

    bool saving = false;

    double? currentRent = _parseNonNegative(rentController.text);
    double? currentElectricity = _parseNonNegative(electricityController.text);
    double? currentWater = _parseNonNegative(waterController.text);
    double? currentInternet = _parseNonNegative(internetController.text);

    bool allValid() {
      return currentRent != null &&
          currentElectricity != null &&
          currentWater != null &&
          currentInternet != null;
    }

    double totalMonthlyCost() {
      if (!allValid()) {
        return 0;
      }
      return currentRent! + currentElectricity! + currentWater! + currentInternet!;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final valid = allValid();
            final total = totalMonthlyCost();
            final maxMembers = house.maxMembers;
            final canDivide = maxMembers > 0;
            final perPerson = canDivide ? total / maxMembers : 0.0;

            Widget buildCostField({
              required String label,
              required IconData icon,
              required TextEditingController controller,
            }) {
              return TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
                onChanged: (_) {
                  setSheetState(() {
                    currentRent = _parseNonNegative(rentController.text);
                    currentElectricity = _parseNonNegative(electricityController.text);
                    currentWater = _parseNonNegative(waterController.text);
                    currentInternet = _parseNonNegative(internetController.text);
                  });
                },
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Update Monthly Costs',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: _darkGreen,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Edit current total house costs only.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _darkGreen.withValues(alpha: 0.68),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      buildCostField(
                        label: 'Rent (total house)',
                        icon: Icons.payments_outlined,
                        controller: rentController,
                      ),
                      const SizedBox(height: 10),
                      buildCostField(
                        label: 'Electricity',
                        icon: Icons.bolt_outlined,
                        controller: electricityController,
                      ),
                      const SizedBox(height: 10),
                      buildCostField(
                        label: 'Water',
                        icon: Icons.water_drop_outlined,
                        controller: waterController,
                      ),
                      const SizedBox(height: 10),
                      buildCostField(
                        label: 'Internet',
                        icon: Icons.wifi_rounded,
                        controller: internetController,
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
                              'Total Monthly Cost: ${_formatTry(total)}',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: _darkGreen,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              canDivide ? 'Per Person: ${_formatTry(perPerson)}' : 'Per Person: -',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: _darkGreen.withValues(alpha: 0.78),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (!canDivide)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Set max members above 0 to calculate per-person.',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: _darkGreen.withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (!valid)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Enter valid non-negative numbers for all fields.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: !valid || saving
                              ? null
                              : () async {
                                  setSheetState(() => saving = true);
                                  try {
                                    await _houseService.updateHouseMonthlyCosts(
                                      houseId: house.houseId,
                                      rentTotal: currentRent!,
                                      electricityTotal: currentElectricity!,
                                      waterTotal: currentWater!,
                                      internetTotal: currentInternet!,
                                    );

                                    if (!mounted) {
                                      return;
                                    }

                                    navigator.pop();
                                    messenger.showSnackBar(
                                      const SnackBar(content: Text('Monthly costs updated')),
                                    );
                                  } catch (e) {
                                    if (!mounted) {
                                      return;
                                    }

                                    setSheetState(() => saving = false);
                                    final message = (e is StateError ? e.message : e).toString();
                                    messenger.showSnackBar(SnackBar(content: Text(message)));
                                  }
                                },
                          child: saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Save Monthly Costs'),
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
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      rentController.dispose();
      electricityController.dispose();
      waterController.dispose();
      internetController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_darkGreen, Color(0xFF145941), _lightGreen],
          ),
        ),
        child: StreamBuilder<House?>(
          stream: _houseService.getCurrentUserHouse(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: _darkGreen));
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Could not load home dashboard right now.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _openCreateHouse,
                        child: const Text('Create or Join House'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final house = snapshot.data;
            if (house == null) {
              return _buildEmptyState();
            }

            final currentUserId = _auth.currentUser?.uid ?? '';
            final isLeader = house.leaderId == currentUserId;
            final memberPreviewIds = house.members.take(4).toList();

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.28),
                            Colors.white.withValues(alpha: 0.14),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.36), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: _darkGreen.withValues(alpha: 0.16),
                            blurRadius: 12,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HOME DASHBOARD',
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.86),
                              letterSpacing: 0.7,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Hello, ${_currentUserName()} 👋',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            house.name,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontSize: 15.5,
                              color: Colors.white.withValues(alpha: 0.88),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: _darkGreen.withValues(alpha: 0.1)),
                        boxShadow: [
                          BoxShadow(
                            color: _darkGreen.withValues(alpha: 0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: FutureBuilder<Map<String, String>>(
                        future: _houseService.getUserNamesByIds(memberPreviewIds),
                        builder: (context, namesSnapshot) {
                          final memberNames = namesSnapshot.data ?? const <String, String>{};

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                house.name,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: _darkGreen,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _StatusInfoTile(
                                      label: 'Members',
                                      value: '${house.members.length}/${house.maxMembers}',
                                      icon: Icons.groups_rounded,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _StatusInfoTile(
                                      label: 'Estimated per-person cost',
                                      value: _formatTry(house.perPersonMonthlyCost),
                                      icon: Icons.account_balance_wallet_outlined,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Members preview',
                                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: _darkGreen.withValues(alpha: 0.8),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  ...memberPreviewIds.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final memberId = entry.value;
                                    final memberName = memberNames[memberId] ?? memberId;

                                    return Padding(
                                      padding: EdgeInsets.only(
                                        right: index == memberPreviewIds.length - 1 ? 0 : 10,
                                      ),
                                      child: GestureDetector(
                                        onTap: () => _openUserProfile(memberId),
                                        child: CircleAvatar(
                                          radius: 18,
                                          backgroundColor: index.isEven ? _darkGreen : _lightGreen,
                                          child: Text(
                                            _memberInitials(memberName),
                                            style: TextStyle(
                                              color: index.isEven ? Colors.white : _darkGreen,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                  if (house.members.length > memberPreviewIds.length) ...[
                                    const SizedBox(width: 10),
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: _surfaceGreen,
                                      child: Text(
                                        '+${house.members.length - memberPreviewIds.length}',
                                        style: const TextStyle(
                                          color: _darkGreen,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No recent activity',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: _darkGreen.withValues(alpha: 0.68),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (isLeader) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _surfaceGreen,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.edit_note_rounded,
                                          color: _darkGreen,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Monthly Costs',
                                              style: Theme.of(context).textTheme.labelLarge
                                                  ?.copyWith(
                                                    color: _darkGreen,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                            Text(
                                              'Owner can edit current totals',
                                              style: Theme.of(context).textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: _darkGreen.withValues(alpha: 0.7),
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => _showUpdateMonthlyCostsSheet(house),
                                        child: const Text('Update'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 1.03,
                        children: [
                          UnreadBadgeBuilder(
                            stream: currentUserId.isEmpty
                                ? const Stream<int>.empty()
                                : _houseService.getUnreadMessageCount(house.houseId, currentUserId),
                            builder: (context, badgeText) {
                              return DashboardCard(
                                icon: Icons.chat_bubble_outline_rounded,
                                title: 'Messages',
                                badgeText: badgeText,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ChatScreen(houseId: house.houseId),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                          DashboardCard(
                            icon: Icons.group_outlined,
                            title: 'Members',
                            onTap: () => _showMembersPlaceholder(house),
                          ),
                          if (isLeader)
                            DashboardCard(
                              icon: Icons.assignment_outlined,
                              title: 'Requests',
                              onTap: () => _showRequestsSheet(house),
                            ),
                          DashboardCard(
                            icon: Icons.vpn_key_outlined,
                            title: 'Invite Code',
                            onTap: () => _showInviteCodeDialog(house),
                          ),
                          DashboardCard(
                            icon: Icons.payments_outlined,
                            title: 'Expenses',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => HouseDetailScreen(house: house)),
                              );
                            },
                          ),
                          DashboardCard(
                            icon: Icons.insights_outlined,
                            title: 'Financial Analytics',
                            onTap: () {
                              Navigator.of(
                                context,
                              ).push(MaterialPageRoute(builder: (_) => const AnalyticsScreen()));
                            },
                          ),
                          DashboardCard(
                            icon: Icons.location_on_outlined,
                            title: 'Location',
                            onTap: () => _showLocationDialog(house),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "You're not in a house yet",
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: _darkGreen, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            ElevatedButton(onPressed: _openCreateHouse, child: const Text('Create or Join House')),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinRequestsSection(House house) {
    return StreamBuilder<List<JoinRequest>>(
      stream: _houseService.watchPendingJoinRequestsForHouse(house.houseId),
      builder: (context, snapshot) {
        final requests = snapshot.data ?? const <JoinRequest>[];

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _darkGreen));
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Could not load join requests right now.',
              style: TextStyle(color: _darkGreen, fontWeight: FontWeight.w600),
            ),
          );
        }

        if (requests.isEmpty) {
          return const Center(
            child: Text(
              'No pending join requests.',
              style: TextStyle(color: _darkGreen, fontWeight: FontWeight.w600),
            ),
          );
        }

        final requesterIds = requests.map((request) => request.userId).toList();
        return FutureBuilder<Map<String, String>>(
          future: _houseService.getUserNamesByIds(requesterIds),
          builder: (context, namesSnapshot) {
            final requesterNames = namesSnapshot.data ?? const <String, String>{};

            return ListView.separated(
              itemCount: requests.length,
              separatorBuilder: (_, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final request = requests[index];
                final requesterName = requesterNames[request.userId] ?? 'Unknown member';
                final isProcessing = _processingRequestIds.contains(request.id);

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _surfaceGreen,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        requesterName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: _darkGreen,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isProcessing
                                  ? null
                                  : () => _handleJoinRequest(request, approve: false),
                              child: const Text('Reject'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isProcessing
                                  ? null
                                  : () => _handleJoinRequest(request, approve: true),
                              child: isProcessing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Approve'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _StatusInfoTile extends StatelessWidget {
  static const _darkGreen = Color(0xFF0B3D2E);
  static const _lightGreen = Color(0xFFB9E8C9);

  final String label;
  final String value;
  final IconData icon;

  const _StatusInfoTile({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _lightGreen.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 18, color: _darkGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: _darkGreen.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: _darkGreen, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardCard extends StatelessWidget {
  static const _darkGreen = Color(0xFF0B3D2E);
  static const _lightGreen = Color(0xFFB9E8C9);
  static const _inkBlack = Color(0xFF111111);

  final IconData icon;
  final String title;
  final String? badgeText;
  final VoidCallback onTap;

  const DashboardCard({
    super.key,
    required this.icon,
    required this.title,
    this.badgeText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        splashColor: _darkGreen.withValues(alpha: 0.12),
        highlightColor: _darkGreen.withValues(alpha: 0.06),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFDFEFD), Color(0xFFF4F8F6)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _darkGreen.withValues(alpha: 0.18), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0E4B39), Color(0xFF0B3D2E)],
                      ),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: _lightGreen.withValues(alpha: 0.35)),
                    ),
                    child: Icon(icon, size: 28, color: Colors.white),
                  ),
                  if (badgeText != null)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Text(
                          badgeText!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _inkBlack,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UnreadBadgeBuilder extends StatefulWidget {
  final Stream<int> stream;
  final Widget Function(BuildContext context, String? badgeText) builder;
  final Duration hideDelay;

  const UnreadBadgeBuilder({
    super.key,
    required this.stream,
    required this.builder,
    this.hideDelay = const Duration(milliseconds: 1200),
  });

  @override
  State<UnreadBadgeBuilder> createState() => _UnreadBadgeBuilderState();
}

class _UnreadBadgeBuilderState extends State<UnreadBadgeBuilder> {
  StreamSubscription<int>? _sub;
  String? _badgeText;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _sub = widget.stream.listen(
      _onCount,
      onError: (e) {
        setState(() => _badgeText = null);
      },
    );
  }

  void _onCount(int count) {
    _hideTimer?.cancel();

    if (count > 0) {
      setState(() => _badgeText = '$count');
    } else {
      // debounce hiding so the badge doesn't flash away instantly
      _hideTimer = Timer(widget.hideDelay, () {
        if (mounted) setState(() => _badgeText = null);
      });
    }
  }

  @override
  void didUpdateWidget(covariant UnreadBadgeBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream != widget.stream) {
      _sub?.cancel();
      _hideTimer?.cancel();
      _badgeText = null;
      _sub = widget.stream.listen(
        _onCount,
        onError: (e) {
          setState(() => _badgeText = null);
        },
      );
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _badgeText);
}
