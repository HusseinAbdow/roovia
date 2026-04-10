import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/house_model.dart';
import '../models/join_request_model.dart';
import '../services/house_service.dart';

class HouseDetailScreen extends StatefulWidget {
  final House house;

  const HouseDetailScreen({super.key, required this.house});

  @override
  State<HouseDetailScreen> createState() => _HouseDetailScreenState();
}

class _HouseDetailScreenState extends State<HouseDetailScreen> {
  static const _darkGreen = Color(0xFF0B3D2E);
  static const _surfaceGreen = Color(0xFFE9F7EE);

  final HouseService _houseService = HouseService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isRequesting = false;
  bool _hasRequestedToJoin = false;

  String _formatTry(double value) => '₺${value.toStringAsFixed(2)}';

  @override
  void initState() {
    super.initState();
    _checkIfAlreadyRequested();
  }

  Future<void> _checkIfAlreadyRequested() async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) {
      return;
    }

    try {
      final requests = await _houseService.watchJoinRequestsForUser(currentUserId).first;
      final hasPending = requests.any(
        (request) =>
            request.houseId == widget.house.houseId && request.status == JoinRequestStatus.pending,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _hasRequestedToJoin = hasPending;
      });
    } catch (e) {
      debugPrint('Error checking request status: $e');
    }
  }

  Future<void> _requestToJoin() async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please sign in first')));
      return;
    }

    if (_isRequesting) {
      return;
    }

    setState(() => _isRequesting = true);
    try {
      await _houseService.createJoinRequest(houseId: widget.house.houseId, userId: currentUserId);

      if (!mounted) {
        return;
      }

      setState(() {
        _isRequesting = false;
        _hasRequestedToJoin = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request sent! Waiting for house owner approval.')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() => _isRequesting = false);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to request: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _auth.currentUser?.uid;
    final isMember = widget.house.members.contains(currentUserId);
    final memberCount = widget.house.members.length;
    final maxMembers = widget.house.maxMembers;
    final isFull = memberCount >= maxMembers;

    return Scaffold(
      appBar: AppBar(title: Text(widget.house.name, overflow: TextOverflow.ellipsis)),
      backgroundColor: const Color(0xFFF6FBF8),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: [
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.house.name,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: _darkGreen,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Pill(
                            icon: Icons.people_alt_outlined,
                            text: '$memberCount / $maxMembers members',
                          ),
                          if (isFull)
                            const _Pill(icon: Icons.warning_amber_rounded, text: 'House Full'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _InfoRow(
                        icon: Icons.location_city_outlined,
                        label: 'City',
                        value: widget.house.city,
                      ),
                      if (widget.house.district.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _InfoRow(
                          icon: Icons.map_outlined,
                          label: 'District / Area',
                          value: widget.house.district,
                        ),
                      ],
                      if (widget.house.description.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _InfoRow(
                          icon: Icons.description_outlined,
                          label: 'Description',
                          value: widget.house.description,
                        ),
                      ],
                      const SizedBox(height: 12),
                      _InfoRow(
                        icon: Icons.payments_outlined,
                        label: 'Total Rent',
                        value: _formatTry(widget.house.rentTotal),
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(
                        icon: Icons.bolt_outlined,
                        label: 'Electricity',
                        value: _formatTry(widget.house.electricityTotal),
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(
                        icon: Icons.water_drop_outlined,
                        label: 'Water',
                        value: _formatTry(widget.house.waterTotal),
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(
                        icon: Icons.wifi_rounded,
                        label: 'Internet',
                        value: _formatTry(widget.house.internetTotal),
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Estimated per-person monthly cost',
                        value: _formatTry(widget.house.perPersonMonthlyCost),
                      ),
                      const SizedBox(height: 12),
                      if (isMember)
                        _InfoRow(
                          icon: Icons.location_on_outlined,
                          label: 'Address',
                          value: widget.house.address,
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: _surfaceGreen,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.lock_outlined, color: _darkGreen, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Address is private and visible to members only.',
                                  style: TextStyle(
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
              const SizedBox(height: 14),
              if (!isMember)
                ElevatedButton.icon(
                  onPressed: (_isRequesting || _hasRequestedToJoin || isFull)
                      ? null
                      : _requestToJoin,
                  icon: _isRequesting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.person_add_outlined),
                  label: Text(
                    isFull
                        ? 'House is Full'
                        : _hasRequestedToJoin
                        ? 'Request Sent'
                        : 'Request to Join',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _darkGreen,
                    disabledBackgroundColor: _darkGreen.withValues(alpha: 0.5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                  ),
                ),
              if (isMember)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _surfaceGreen,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _darkGreen.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_outline, color: _darkGreen),
                      const SizedBox(width: 8),
                      Text(
                        'You are a member of this house',
                        style: TextStyle(
                          color: _darkGreen.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF0B3D2E), size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF315A4C),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(color: Color(0xFF0B3D2E), fontSize: 14, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Pill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F7EE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF0B3D2E)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF0B3D2E),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
