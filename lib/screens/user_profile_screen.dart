import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UserProfileScreen extends StatelessWidget {
  static const _darkGreen = Color(0xFF0B3D2E);
  static const _surfaceGreen = Color(0xFFE9F7EE);

  final String userId;

  const UserProfileScreen({super.key, required this.userId});

  String _toSafeString(dynamic value) {
    if (value is String) {
      return value.trim();
    }
    return '';
  }

  double _toSafeDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return 0;
  }

  String _buildInitials(String name, String username, String fallback) {
    final source = name.isNotEmpty ? name : (username.isNotEmpty ? username : fallback);
    final parts = source
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .map((part) => part.trim())
        .toList();

    if (parts.isEmpty) {
      return 'U';
    }

    if (parts.length == 1) {
      final part = parts.first;
      return part.length >= 2 ? part.substring(0, 2).toUpperCase() : part[0].toUpperCase();
    }

    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Member Profile')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _darkGreen));
          }

          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Could not load profile right now.', textAlign: TextAlign.center),
              ),
            );
          }

          final data = snapshot.data?.data();
          if (data == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('User profile not found.', textAlign: TextAlign.center),
              ),
            );
          }

          final name = _toSafeString(data['name']);
          final username = _toSafeString(data['username']);
          final profileImageUrl = _toSafeString(data['profileImageUrl']);
          final rating = _toSafeDouble(data['rating']);
          final bio = _toSafeString(data['bio']);
          final initials = _buildInitials(name, username, userId);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(color: Color(0x14000000), blurRadius: 22, offset: Offset(0, 12)),
                  ],
                ),
                child: Column(
                  children: [
                    profileImageUrl.isNotEmpty
                        ? CircleAvatar(
                            radius: 52,
                            backgroundImage: CachedNetworkImageProvider(profileImageUrl),
                          )
                        : CircleAvatar(
                            radius: 52,
                            backgroundColor: _surfaceGreen,
                            child: Text(
                              initials,
                              style: const TextStyle(
                                color: _darkGreen,
                                fontWeight: FontWeight.w800,
                                fontSize: 26,
                              ),
                            ),
                          ),
                    const SizedBox(height: 14),
                    Text(
                      name.isEmpty ? 'Roovia Member' : name,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: _darkGreen,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      username.isEmpty ? '@unknown' : '@$username',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: _darkGreen.withValues(alpha: 0.62),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 10)),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _surfaceGreen,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.star_rounded, color: _darkGreen),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rating',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: _darkGreen.withValues(alpha: 0.68),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rating.toStringAsFixed(1),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: _darkGreen,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 10)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bio',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _darkGreen,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      bio.isEmpty ? 'No bio yet' : bio,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: _darkGreen.withValues(alpha: 0.72),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
