import 'package:flutter/material.dart';

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  static const _darkGreen = Color(0xFF0B3D2E);
  static const _surfaceGreen = Color(0xFFE9F7EE);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed'),
        actions: [
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Messages are coming soon.')),
              );
            },
            icon: const Icon(Icons.mail_outline_rounded),
            tooltip: 'Messages',
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 24,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 72,
                    width: 72,
                    decoration: const BoxDecoration(
                      color: _surfaceGreen,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.dynamic_feed_outlined,
                      color: _darkGreen,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Your house activity feed will live here.',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: _darkGreen,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'For now, this is a clean empty state. Later it can show rent updates, chores, payments, announcements, and other activity from your house.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _darkGreen.withValues(alpha: 0.75),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: _surfaceGreen,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome_outlined,
                          color: _darkGreen,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'A future feed can combine house events, roommate actions, reminders, and notifications in one timeline.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: _darkGreen.withValues(alpha: 0.82),
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
