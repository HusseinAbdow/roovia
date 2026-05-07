import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'create_house_screen.dart';
import 'house_dashboard_screen.dart';
import 'alerts_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _darkGreen = Color(0xFF0B3D2E);

  int _selectedIndex = 0;

  static const _screens = [
    HouseDashboardScreen(),
    SearchScreen(),
    SizedBox.shrink(),
    AlertsScreen(),
    ProfileScreen(),
  ];

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

  void _onItemTapped(int index) {
    if (index == 2) {
      _openCreateHouse();
      return;
    }

    setState(() => _selectedIndex = index);
  }

  int get _bodyIndex {
    if (_selectedIndex == 2) {
      return 0;
    }

    return _selectedIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _bodyIndex, children: _screens),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateHouse,
        backgroundColor: _darkGreen,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: const CircleBorder(),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: _darkGreen,
        unselectedItemColor: _darkGreen.withValues(alpha: 0.55),
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
        showUnselectedLabels: true,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.dynamic_feed_outlined),
            activeIcon: Icon(Icons.dynamic_feed_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search_rounded),
            activeIcon: Icon(Icons.travel_explore_rounded),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add, color: Colors.transparent),
            activeIcon: Icon(Icons.add, color: Colors.transparent),
            label: 'Create',
          ),
          BottomNavigationBarItem(
            icon: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseAuth.instance.currentUser == null
                  ? const Stream.empty()
                  : FirebaseFirestore.instance
                        .collection('user_notifications')
                        .doc(FirebaseAuth.instance.currentUser!.uid)
                        .collection('notifications')
                        .where('read', isEqualTo: false)
                        .snapshots(),
              builder: (context, snap) {
                final unread = snap.data?.docs.length ?? 0;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_none_rounded),
                    if (unread > 0)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                          child: Text(
                            unread > 99 ? '99+' : unread.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            activeIcon: Icon(Icons.notifications_rounded),
            label: 'Alerts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded),
            activeIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
