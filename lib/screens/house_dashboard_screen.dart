import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/house_model.dart';
import '../models/join_request_model.dart';
import '../services/auth_service.dart';
import '../services/house_service.dart';
import 'chat_screen.dart';
import 'create_house_screen.dart';
import 'login_screen.dart';

class HouseDashboardScreen extends StatefulWidget {
  const HouseDashboardScreen({super.key});

  @override
  State<HouseDashboardScreen> createState() => _HouseDashboardScreenState();
}

class _HouseDashboardScreenState extends State<HouseDashboardScreen> with WidgetsBindingObserver {
  static const _darkGreen = Color(0xFF0B3D2E);
  static const _lightGreen = Color(0xFFB9E8C9);
  static const _surfaceGreen = Color(0xFFE9F7EE);

  final HouseService _houseService = HouseService();
  final AuthService _authService = AuthService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Timer? _streamWaitingTimer;
  bool _streamWaitingTimedOut = false;
  bool _isDeletingHouse = false;
  final Set<String> _processingRequestIds = <String>{};

  String _formatTry(double value) => '₺${value.toStringAsFixed(2)}';

  @override
  void initState() {
    super.initState();
    _startStreamWaitingFallbackTimer();
  }

  @override
  void dispose() {
    _streamWaitingTimer?.cancel();
    super.dispose();
  }

  Future<void> _showInviteDialog(House house) async {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Invite Member'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Share this invite code with your roommates:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F7EE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF0B3D2E), width: 2),
                ),
                child: Text(
                  house.inviteCode,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0B3D2E),
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: house.inviteCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invite code copied to clipboard!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.content_copy),
                label: const Text('Copy Code'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Done')),
        ],
      ),
    );
  }

  void _startStreamWaitingFallbackTimer() {
    _streamWaitingTimer?.cancel();
    _streamWaitingTimedOut = false;

    _streamWaitingTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) {
        return;
      }

      debugPrint('HouseDashboardScreen stream waiting timeout reached, showing fallback UI');
      setState(() => _streamWaitingTimedOut = true);
    });
  }

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

  Future<void> _signOut() async {
    try {
      await _authService.signOut();
      debugPrint('Sign out success from house dashboard');

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e, stackTrace) {
      debugPrint('Sign out failed from house dashboard: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not sign out: $e')));
    }
  }

  Future<void> _confirmAndDeleteHouse(House house) async {
    if (_isDeletingHouse) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete House?'),
        content: Text(
          'This will permanently delete "${house.name}", remove all join requests for it, and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isDeletingHouse = true);
    try {
      await _houseService.deleteHouse(house.houseId);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('House deleted')));
    } catch (e) {
      if (!mounted) {
        return;
      }

      final message = (e is StateError ? e.message : e).toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isDeletingHouse = false);
      }
    }
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

  @override
  Widget build(BuildContext context) {
    debugPrint('DASHBOARD BUILD');

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_darkGreen, Color(0xFF145941), _lightGreen],
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<House?>(
            stream: _houseService.getCurrentUserHouse(),
            builder: (context, snapshot) {
              debugPrint(
                'STREAM STATE: ${snapshot.connectionState} | hasData: ${snapshot.hasData} | hasError: ${snapshot.hasError} | data: ${snapshot.data}',
              );

              if (snapshot.hasError) {
                _streamWaitingTimer?.cancel();
                return _buildShell(
                  context,
                  child: _buildInfoCard(
                    context,
                    title: 'Something went wrong',
                    description: 'We could not load your house right now.',
                    actionLabel: 'Try creating a house',
                    onPressed: _openCreateHouse,
                    icon: Icons.error_outline_rounded,
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting && !_streamWaitingTimedOut) {
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              }

              if (snapshot.connectionState == ConnectionState.waiting && _streamWaitingTimedOut) {
                return _buildShell(
                  context,
                  child: _buildInfoCard(
                    context,
                    title: 'Still loading your house',
                    description:
                        'House data is taking longer than expected. You can retry or create a house now.',
                    actionLabel: 'Create House',
                    onPressed: _openCreateHouse,
                    icon: Icons.hourglass_bottom_rounded,
                  ),
                );
              }

              _streamWaitingTimer?.cancel();

              final house = snapshot.data;
              return _buildShell(
                context,
                child: house == null ? _buildEmptyState(context) : _buildHouseView(context, house),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildShell(BuildContext context, {required Widget child}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Roovia House',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Manage your shared home responsibilities in one place.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _signOut,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.logout_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: child),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return _buildInfoCard(
      context,
      title: 'You are not part of any house yet.',
      description:
          'Create your first house to start managing rent, bills, and shared responsibilities together.',
      actionLabel: 'Create House',
      onPressed: _openCreateHouse,
      icon: Icons.home_work_outlined,
    );
  }

  Widget _buildHouseView(BuildContext context, House house) {
    return FutureBuilder<Map<String, String>>(
      future: _houseService.getUserNamesByIds(house.members),
      builder: (context, namesSnapshot) {
        final namesById = namesSnapshot.data ?? const <String, String>{};
        final currentUserId = _auth.currentUser?.uid ?? '';
        final isOwner = house.leaderId == currentUserId;
        final leaderName = namesById[house.leaderId] ?? 'House owner';

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(color: Color(0x22000000), blurRadius: 24, offset: Offset(0, 14)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 74,
                width: 74,
                decoration: const BoxDecoration(color: _surfaceGreen, shape: BoxShape.circle),
                child: const Icon(Icons.apartment_rounded, size: 36, color: _darkGreen),
              ),
              const SizedBox(height: 24),
              Text(
                house.name,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _darkGreen,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your shared house is set up and ready for bills, payments, and roommate coordination.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: _darkGreen.withValues(alpha: 0.75),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildStatChip(
                    icon: Icons.star_outline_rounded,
                    label: 'Leader',
                    value: leaderName,
                  ),
                  _buildStatChip(
                    icon: Icons.group_outlined,
                    label: 'Members',
                    value: '${house.members.length}',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: _surfaceGreen,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Rent: ${_formatTry(house.rentTotal)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _darkGreen,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Electricity: ${_formatTry(house.electricityTotal)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _darkGreen,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Water: ${_formatTry(house.waterTotal)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _darkGreen,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Internet: ${_formatTry(house.internetTotal)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _darkGreen,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Estimated per-person monthly cost: ${_formatTry(house.perPersonMonthlyCost)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _darkGreen,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: _surfaceGreen,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _darkGreen, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Invite Code',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _darkGreen.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          house.inviteCode,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: _darkGreen,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: house.inviteCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Code copied!'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: const Icon(Icons.content_copy_rounded),
                          color: _darkGreen,
                          tooltip: 'Copy invite code',
                          iconSize: 20,
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showInviteDialog(house),
                      icon: const Icon(Icons.person_add_rounded),
                      label: const Text('Invite Member'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => ChatScreen(houseId: house.houseId)),
                      ),
                      icon: const Icon(Icons.chat_rounded),
                      label: const Text('Chat'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _darkGreen,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              if (isOwner) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _isDeletingHouse ? null : () => _confirmAndDeleteHouse(house),
                  icon: _isDeletingHouse
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline_rounded),
                  label: Text(_isDeletingHouse ? 'Deleting...' : 'Delete House'),
                ),
                const SizedBox(height: 16),
                _buildJoinRequestsSection(house),
              ],
              const SizedBox(height: 16),
              if (house.members.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Members (${house.members.length})',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: _darkGreen,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _surfaceGreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: house.members
                            .asMap()
                            .entries
                            .map(
                              (entry) => Padding(
                                padding: EdgeInsets.only(
                                  bottom: entry.key < house.members.length - 1 ? 8 : 0,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.account_circle_rounded,
                                      size: 24,
                                      color: _darkGreen,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        namesById[entry.value] ?? 'Unknown member',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: _darkGreen,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: _surfaceGreen,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  'Next up, this dashboard can grow into rent tracking, bill splitting, payment reminders, and receipts.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _darkGreen.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required String title,
    required String description,
    required String actionLabel,
    required VoidCallback onPressed,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 24, offset: Offset(0, 14)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 74,
            width: 74,
            decoration: const BoxDecoration(color: _surfaceGreen, shape: BoxShape.circle),
            child: Icon(icon, size: 36, color: _darkGreen),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: _darkGreen),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: _darkGreen.withValues(alpha: 0.75),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: onPressed, child: Text(actionLabel)),
        ],
      ),
    );
  }

  Widget _buildJoinRequestsSection(House house) {
    return StreamBuilder<List<JoinRequest>>(
      stream: _houseService.watchPendingJoinRequestsForHouse(house.houseId),
      builder: (context, snapshot) {
        final requests = snapshot.data ?? const <JoinRequest>[];

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surfaceGreen,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(child: CircularProgressIndicator(color: _darkGreen)),
          );
        }

        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surfaceGreen,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'Could not load join requests right now.',
              style: TextStyle(color: _darkGreen, fontWeight: FontWeight.w600),
            ),
          );
        }

        if (requests.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surfaceGreen,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
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

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _surfaceGreen,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pending Requests (${requests.length})',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: _darkGreen,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...requests.map((request) {
                    final requesterName = requesterNames[request.userId] ?? 'Unknown member';
                    final isProcessing = _processingRequestIds.contains(request.id);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            requesterName,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: _darkGreen,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
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
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatChip({required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: _surfaceGreen, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _darkGreen, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(color: _darkGreen, fontWeight: FontWeight.w600),
              ),
              Text(
                value,
                style: const TextStyle(color: _darkGreen, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
