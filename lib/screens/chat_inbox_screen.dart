import 'package:flutter/material.dart';

import '../models/house_model.dart';
import '../services/house_service.dart';
import 'chat_screen.dart';

class ChatInboxScreen extends StatelessWidget {
  const ChatInboxScreen({super.key});

  static const _darkGreen = Color(0xFF0B3D2E);
  static const _lightGreen = Color(0xFFB9E8C9);
  static const _surfaceGreen = Color(0xFFE9F7EE);

  @override
  Widget build(BuildContext context) {
    final houseService = HouseService();

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
          child: StreamBuilder<List<House>>(
            stream: houseService.watchCurrentUserHouses(),
            builder: (context, snapshot) {
              return CustomScrollView(
                slivers: [
                  SliverAppBar(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    pinned: true,
                    title: const Text('Chats'),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: snapshot.connectionState == ConnectionState.waiting
                          ? const Center(child: CircularProgressIndicator(color: Colors.white))
                          : _buildContent(context, snapshot.data ?? const <House>[]),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<House> houses) {
    if (houses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 72,
              width: 72,
              decoration: const BoxDecoration(color: _surfaceGreen, shape: BoxShape.circle),
              child: const Icon(Icons.chat_bubble_outline_rounded, color: _darkGreen, size: 34),
            ),
            const SizedBox(height: 20),
            Text(
              'No chats yet',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: _darkGreen),
            ),
            const SizedBox(height: 8),
            Text(
              'Once you are part of a house, your chat will appear here.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: _darkGreen.withValues(alpha: 0.75),
                height: 1.45,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your houses',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        ...houses.map(
          (house) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Material(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(22),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                leading: Container(
                  height: 48,
                  width: 48,
                  decoration: const BoxDecoration(color: _surfaceGreen, shape: BoxShape.circle),
                  child: const Icon(Icons.home_work_outlined, color: _darkGreen),
                ),
                title: Text(
                  house.displayChatName,
                  style: const TextStyle(color: _darkGreen, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  house.name,
                  style: TextStyle(color: _darkGreen.withValues(alpha: 0.7)),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, color: _darkGreen),
                onTap: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => ChatScreen(houseId: house.houseId)));
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
