import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/house_model.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/house_service.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _darkGreen = Color(0xFF0B3D2E);
  static const _surfaceGreen = Color(0xFFE9F7EE);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final HouseService _houseService = HouseService();
  final AuthService _authService = AuthService();

  String _formatTry(double value) => '₺${value.toStringAsFixed(2)}';

  String _avatarInitial(String username) {
    final clean = username.trim();
    if (clean.isEmpty) {
      return 'U';
    }
    return clean[0].toUpperCase();
  }

  Future<void> _signOut() async {
    try {
      await _authService.signOut();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not sign out right now. Please try again.')),
      );
    }
  }

  Future<void> _openEditProfile(RooviaUser user) async {
    final updated = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => EditProfileScreen(user: user)));

    if (updated == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated successfully.')));
    }
  }

  String _fallbackUsername(User firebaseUser) {
    final emailPrefix = (firebaseUser.email ?? '').split('@').first.toLowerCase();
    final cleaned = emailPrefix.replaceAll(RegExp(r'[^a-z0-9_]'), '');

    if (cleaned.length >= 3) {
      return cleaned.length > 20 ? cleaned.substring(0, 20) : cleaned;
    }

    return 'user000';
  }

  RooviaUser _buildProfile({required User firebaseUser, required Map<String, dynamic>? rawData}) {
    final fallback = RooviaUser(
      uid: firebaseUser.uid,
      name: firebaseUser.displayName?.trim().isNotEmpty == true
          ? firebaseUser.displayName!.trim()
          : (firebaseUser.email ?? 'Roovia User').split('@').first,
      email: firebaseUser.email ?? 'No email available',
      username: _fallbackUsername(firebaseUser),
      profileImageUrl: '',
      rating: 0.0,
    );

    if (rawData == null) {
      return fallback;
    }

    try {
      return RooviaUser.fromMap({
        ...rawData,
        'uid': rawData['uid'] ?? fallback.uid,
        'name': rawData['name'] ?? fallback.name,
        'email': rawData['email'] ?? fallback.email,
        'username': rawData['username'] ?? fallback.username,
        'profileImageUrl': rawData['profileImageUrl'] ?? fallback.profileImageUrl,
        'rating': rawData['rating'] ?? fallback.rating,
      });
    } catch (_) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    final firebaseUser = _auth.currentUser;

    if (firebaseUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: _buildPlaceholderCard(
                context,
                icon: Icons.lock_outline_rounded,
                title: 'No active account',
                description: 'Sign in again to load your profile details.',
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _db.collection('users').doc(firebaseUser.uid).snapshots(),
        builder: (context, profileSnapshot) {
          final profile = _buildProfile(
            firebaseUser: firebaseUser,
            rawData: profileSnapshot.data?.data(),
          );

          return StreamBuilder<House?>(
            stream: _houseService.getCurrentUserHouse(),
            builder: (context, houseSnapshot) {
              final currentHouse = houseSnapshot.data;
              final housesLivedIn = currentHouse == null ? 0 : 1;

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                children: [
                  _buildProfileHeader(context, profile),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: () => _openEditProfile(profile),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit Profile'),
                  ),
                  const SizedBox(height: 18),
                  _buildStatsSection(
                    context,
                    housesLivedIn: housesLivedIn,
                    averageRating: profile.rating,
                  ),
                  const SizedBox(height: 18),
                  _buildSectionTitle(context, 'Current House'),
                  const SizedBox(height: 12),
                  _buildCurrentHouseCard(
                    context,
                    houseSnapshot: houseSnapshot,
                    currentHouse: currentHouse,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, RooviaUser user) {
    final imageUrl = user.profileImageUrl.trim();
    final avatarInitial = _avatarInitial(user.username);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 14)),
        ],
      ),
      child: Column(
        children: [
          imageUrl.isNotEmpty
              ? CircleAvatar(radius: 56, backgroundImage: CachedNetworkImageProvider(imageUrl))
              : CircleAvatar(
                  radius: 56,
                  backgroundColor: _surfaceGreen,
                  child: Text(
                    avatarInitial,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _darkGreen,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
          const SizedBox(height: 16),
          Text(
            user.name,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: _darkGreen, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '@${user.username}',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: _darkGreen.withValues(alpha: 0.62)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(
    BuildContext context, {
    required int housesLivedIn,
    required double averageRating,
  }) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildStatCard(
          context,
          label: 'Houses lived in',
          value: '$housesLivedIn',
          icon: Icons.home_work_outlined,
        ),
        _buildStatCard(
          context,
          label: 'Rating',
          value: averageRating.toStringAsFixed(1),
          icon: Icons.star_outline_rounded,
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    final width = (MediaQuery.of(context).size.width - 56) / 2;

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: math.min(width, 190)),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 10)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _darkGreen),
            const SizedBox(height: 14),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(color: _darkGreen, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _darkGreen.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentHouseCard(
    BuildContext context, {
    required AsyncSnapshot<House?> houseSnapshot,
    required House? currentHouse,
  }) {
    if (houseSnapshot.connectionState == ConnectionState.waiting) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(color: _darkGreen),
        ),
      );
    }

    if (houseSnapshot.hasError) {
      return _buildPlaceholderCard(
        context,
        icon: Icons.error_outline_rounded,
        title: 'Could not load current house',
        description: 'Please try again in a moment.',
      );
    }

    if (currentHouse == null) {
      return _buildPlaceholderCard(
        context,
        icon: Icons.home_outlined,
        title: 'No current house yet',
        description: 'Create or join a house to see details here.',
      );
    }

    return FutureBuilder<Map<String, String>>(
      future: _houseService.getUserNamesByIds([currentHouse.leaderId]),
      builder: (context, namesSnapshot) {
        final leaderName =
            (namesSnapshot.data ?? const <String, String>{})[currentHouse.leaderId] ??
            'House owner';

        return Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 10)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 52,
                    width: 52,
                    decoration: const BoxDecoration(color: _surfaceGreen, shape: BoxShape.circle),
                    child: const Icon(Icons.apartment_rounded, color: _darkGreen),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentHouse.name,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: _darkGreen,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Leader: $leaderName',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: _darkGreen.withValues(alpha: 0.72),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildHouseDetailChip(label: 'Members', value: '${currentHouse.members.length}'),
              const SizedBox(height: 8),
              _buildHouseDetailChip(
                label: 'Total monthly cost',
                value: _formatTry(currentHouse.totalHouseCost),
              ),
              const SizedBox(height: 8),
              _buildHouseDetailChip(
                label: 'Estimated per-person cost',
                value: _formatTry(currentHouse.perPersonMonthlyCost),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHouseDetailChip({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: _surfaceGreen, borderRadius: BorderRadius.circular(16)),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: _darkGreen),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 52,
            width: 52,
            decoration: const BoxDecoration(color: _surfaceGreen, shape: BoxShape.circle),
            child: Icon(icon, color: _darkGreen),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: _darkGreen, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: _darkGreen.withValues(alpha: 0.74),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(color: _darkGreen, fontWeight: FontWeight.w800),
    );
  }
}
