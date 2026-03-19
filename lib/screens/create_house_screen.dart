import 'package:flutter/material.dart';

import '../services/house_service.dart';

class CreateHouseScreen extends StatefulWidget {
  const CreateHouseScreen({super.key});

  @override
  State<CreateHouseScreen> createState() => _CreateHouseScreenState();
}

class _CreateHouseScreenState extends State<CreateHouseScreen> {
  static const _darkGreen = Color(0xFF0B3D2E);
  static const _lightGreen = Color(0xFFB9E8C9);
  static const _surfaceGreen = Color(0xFFE9F7EE);

  final HouseService _houseService = HouseService();
  final TextEditingController houseNameController = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    houseNameController.dispose();
    super.dispose();
  }

  Future<void> _createHouse() async {
    if (_loading) {
      return;
    }

    final houseName = houseNameController.text.trim();
    if (houseName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a house name')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final house = await _houseService.createHouse(houseName);
      debugPrint('Create house success: ${house.houseId} (${house.name})');

      if (!mounted) {
        return;
      }

      setState(() => _loading = false);

      Navigator.of(context).pop(true);
    } catch (e, stackTrace) {
      debugPrint('Create house failed: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      setState(() => _loading = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not create house: $e')));
    } finally {
      if (mounted && _loading) {
        setState(() => _loading = false);
      }
    }
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
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
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: IconButton.styleFrom(
                              backgroundColor: _surfaceGreen,
                              foregroundColor: _darkGreen,
                            ),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        height: 74,
                        width: 74,
                        decoration: const BoxDecoration(
                          color: _surfaceGreen,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.home_work_outlined,
                          size: 36,
                          color: _darkGreen,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Create a house',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: _darkGreen,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start your shared home space and become the first member and leader.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: _darkGreen.withValues(alpha: 0.75),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: houseNameController,
                        decoration: InputDecoration(
                          labelText: 'House name',
                          hintText: 'e.g. Greenview Apartment',
                          prefixIcon: const Icon(
                            Icons.meeting_room_outlined,
                            color: _darkGreen,
                          ),
                          labelStyle: const TextStyle(
                            color: _darkGreen,
                            fontWeight: FontWeight.w600,
                          ),
                          hintStyle: TextStyle(
                            color: _darkGreen.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _loading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: _darkGreen,
                              ),
                            )
                          : ElevatedButton(
                              onPressed: _createHouse,
                              child: const Text('Create House'),
                            ),
                      const SizedBox(height: 18),
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
                              Icons.groups_2_outlined,
                              color: _darkGreen,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Your house will be saved in Firestore with you as leader and first member.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: _darkGreen.withValues(alpha: 0.8),
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
        ),
      ),
    );
  }
}
