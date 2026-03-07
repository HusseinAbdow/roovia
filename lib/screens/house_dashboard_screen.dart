import 'package:flutter/material.dart';

import '../models/house_model.dart';
import '../services/auth_service.dart';
import '../services/house_service.dart';
import 'create_house_screen.dart';
import 'login_screen.dart';

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
  final AuthService _authService = AuthService();

  Future<void> _openCreateHouse() async {
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const CreateHouseScreen()));

    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('House created successfully.')),
      );
    }
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    if (!mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
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
        child: SafeArea(
          child: StreamBuilder<House?>(
            stream: _houseService.getCurrentUserHouse(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
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

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }

              final house = snapshot.data;
              return _buildShell(
                context,
                child: house == null
                    ? _buildEmptyState(context)
                    : _buildHouseView(context, house),
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
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Manage your shared home responsibilities in one place.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
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
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: child,
              ),
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
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 74,
            width: 74,
            decoration: const BoxDecoration(
              color: _surfaceGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.apartment_rounded,
              size: 36,
              color: _darkGreen,
            ),
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
                value: house.leaderId,
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
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 74,
            width: 74,
            decoration: const BoxDecoration(
              color: _surfaceGreen,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 36, color: _darkGreen),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: _darkGreen,
            ),
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

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _surfaceGreen,
        borderRadius: BorderRadius.circular(16),
      ),
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
                style: const TextStyle(
                  color: _darkGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: _darkGreen,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
