import 'package:flutter/material.dart';

import '../constants/bartin_locations.dart';
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
  final TextEditingController _houseNameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _rentTotalController = TextEditingController();
  final TextEditingController _electricityTotalController = TextEditingController();
  final TextEditingController _waterTotalController = TextEditingController();
  final TextEditingController _internetTotalController = TextEditingController();
  final TextEditingController _maxMembersController = TextEditingController(text: '5');
  final TextEditingController _descriptionController = TextEditingController();
  String? _selectedDistrict;

  bool _loading = false;

  @override
  void dispose() {
    _houseNameController.dispose();
    _addressController.dispose();
    _rentTotalController.dispose();
    _electricityTotalController.dispose();
    _waterTotalController.dispose();
    _internetTotalController.dispose();
    _maxMembersController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createHouse() async {
    if (_loading) {
      return;
    }

    final houseName = _houseNameController.text.trim();
    final city = bartinMerkezCity;
    final district = _selectedDistrict?.trim() ?? '';
    final address = _addressController.text.trim();
    final description = _descriptionController.text.trim();
    final rentTotalStr = _rentTotalController.text.trim();
    final electricityTotalStr = _electricityTotalController.text.trim();
    final waterTotalStr = _waterTotalController.text.trim();
    final internetTotalStr = _internetTotalController.text.trim();
    final maxMembersStr = _maxMembersController.text.trim();

    // Validation
    if (houseName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a house name')));
      return;
    }
    if (district.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a mahalle')));
      return;
    }
    if (address.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter an address')));
      return;
    }

    if (rentTotalStr.isEmpty ||
        electricityTotalStr.isEmpty ||
        waterTotalStr.isEmpty ||
        internetTotalStr.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please fill all monthly total fields')));
      return;
    }

    double rentTotal = 0.0;
    double electricityTotal = 0.0;
    double waterTotal = 0.0;
    double internetTotal = 0.0;

    try {
      rentTotal = double.parse(rentTotalStr);
      electricityTotal = double.parse(electricityTotalStr);
      waterTotal = double.parse(waterTotalStr);
      internetTotal = double.parse(internetTotalStr);
    } catch (_) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter valid numeric cost values')));
      return;
    }

    if (rentTotal < 0 || electricityTotal < 0 || waterTotal < 0 || internetTotal < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cost values must be greater than or equal to 0')),
      );
      return;
    }

    int maxMembers = 5;
    if (maxMembersStr.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter max members')));
      return;
    }

    try {
      maxMembers = int.parse(maxMembersStr);
      if (maxMembers < 1) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Max members must be at least 1')));
        return;
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a valid number')));
      return;
    }

    setState(() => _loading = true);
    try {
      final house = await _houseService.createHouse(
        name: houseName,
        city: city,
        district: district,
        address: address,
        rentTotal: rentTotal,
        electricityTotal: electricityTotal,
        waterTotal: waterTotal,
        internetTotal: internetTotal,
        maxMembers: maxMembers,
        description: description,
      );
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
                      BoxShadow(color: Color(0x22000000), blurRadius: 24, offset: Offset(0, 14)),
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
                        child: const Icon(Icons.home_work_outlined, size: 36, color: _darkGreen),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Create a house',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
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
                      // House Name
                      TextField(
                        controller: _houseNameController,
                        decoration: InputDecoration(
                          labelText: 'House name',
                          hintText: 'e.g. Greenview Apartment',
                          prefixIcon: const Icon(Icons.meeting_room_outlined, color: _darkGreen),
                          labelStyle: const TextStyle(
                            color: _darkGreen,
                            fontWeight: FontWeight.w600,
                          ),
                          hintStyle: TextStyle(color: _darkGreen.withValues(alpha: 0.45)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: _surfaceGreen,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_city_outlined, color: _darkGreen),
                            const SizedBox(width: 10),
                            Text(
                              'City: $bartinMerkezCity',
                              style: const TextStyle(
                                color: _darkGreen,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedDistrict,
                        items: bartinMerkezMahalleleri
                            .map(
                              (mahalle) =>
                                  DropdownMenuItem<String>(value: mahalle, child: Text(mahalle)),
                            )
                            .toList(),
                        onChanged: _loading
                            ? null
                            : (value) {
                                setState(() => _selectedDistrict = value);
                              },
                        decoration: const InputDecoration(
                          labelText: 'Mahalle',
                          prefixIcon: Icon(Icons.map_outlined, color: _darkGreen),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Address
                      TextField(
                        controller: _addressController,
                        decoration: InputDecoration(
                          labelText: 'Address',
                          hintText: 'e.g. 123 Main Street, Apt 4B',
                          prefixIcon: const Icon(Icons.location_on_outlined, color: _darkGreen),
                          labelStyle: const TextStyle(
                            color: _darkGreen,
                            fontWeight: FontWeight.w600,
                          ),
                          hintStyle: TextStyle(color: _darkGreen.withValues(alpha: 0.45)),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _rentTotalController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Total Rent (monthly for entire house)',
                          hintText: 'e.g. 14000',
                          prefixIcon: const Icon(Icons.payments_outlined, color: _darkGreen),
                          labelStyle: const TextStyle(
                            color: _darkGreen,
                            fontWeight: FontWeight.w600,
                          ),
                          hintStyle: TextStyle(color: _darkGreen.withValues(alpha: 0.45)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _electricityTotalController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Total Electricity (monthly)',
                          hintText: 'e.g. 1200',
                          prefixIcon: const Icon(Icons.bolt_outlined, color: _darkGreen),
                          labelStyle: const TextStyle(
                            color: _darkGreen,
                            fontWeight: FontWeight.w600,
                          ),
                          hintStyle: TextStyle(color: _darkGreen.withValues(alpha: 0.45)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _waterTotalController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Total Water (monthly)',
                          hintText: 'e.g. 600',
                          prefixIcon: const Icon(Icons.water_drop_outlined, color: _darkGreen),
                          labelStyle: const TextStyle(
                            color: _darkGreen,
                            fontWeight: FontWeight.w600,
                          ),
                          hintStyle: TextStyle(color: _darkGreen.withValues(alpha: 0.45)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _internetTotalController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Total Internet/WiFi (monthly)',
                          hintText: 'e.g. 450',
                          prefixIcon: const Icon(Icons.wifi_rounded, color: _darkGreen),
                          labelStyle: const TextStyle(
                            color: _darkGreen,
                            fontWeight: FontWeight.w600,
                          ),
                          hintStyle: TextStyle(color: _darkGreen.withValues(alpha: 0.45)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Max Members
                      TextField(
                        controller: _maxMembersController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Max Members (number of people the house supports)',
                          hintText: 'e.g. 5',
                          prefixIcon: const Icon(Icons.groups_outlined, color: _darkGreen),
                          labelStyle: const TextStyle(
                            color: _darkGreen,
                            fontWeight: FontWeight.w600,
                          ),
                          hintStyle: TextStyle(color: _darkGreen.withValues(alpha: 0.45)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Description
                      TextField(
                        controller: _descriptionController,
                        decoration: InputDecoration(
                          labelText: 'Description (optional)',
                          hintText: 'e.g. Cozy apartment near campus',
                          prefixIcon: const Icon(Icons.description_outlined, color: _darkGreen),
                          labelStyle: const TextStyle(
                            color: _darkGreen,
                            fontWeight: FontWeight.w600,
                          ),
                          hintStyle: TextStyle(color: _darkGreen.withValues(alpha: 0.45)),
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 28),
                      _loading
                          ? const Center(child: CircularProgressIndicator(color: _darkGreen))
                          : ElevatedButton(
                              onPressed: _createHouse,
                              child: const Text('Create House'),
                            ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: _surfaceGreen,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.groups_2_outlined, color: _darkGreen),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Your house will be saved in Firestore with you as leader. Address is private to members only.',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
