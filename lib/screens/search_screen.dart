import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/bartin_locations.dart';
import '../models/house_model.dart';
import '../models/join_request_model.dart';
import '../services/house_service.dart';
import 'house_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _debounceDuration = Duration(milliseconds: 350);

  final HouseService _houseService = HouseService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _inviteCodeController = TextEditingController();

  static const Color _darkGreen = Color(0xFF0B3D2E);
  static const Color _surfaceGreen = Color(0xFFE9F7EE);

  Timer? _searchDebounce;
  List<House> _results = const [];
  bool _isSearching = false;
  bool _isJoiningByCode = false;
  final Set<String> _joiningHouseIds = <String>{};
  final Set<String> _openingHouseIds = <String>{};
  String _searchQuery = '';
  String? _selectedMahalle;

  String _formatTry(double value) => '₺${value.toStringAsFixed(2)}';

  @override
  void initState() {
    super.initState();
    _runSearch();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_debounceDuration, _runSearch);
  }

  Future<void> _runSearch() async {
    final normalizedQuery = _searchController.text.trim();
    final normalizedLocationQuery = _selectedMahalle ?? '';

    if (mounted) {
      setState(() {
        _isSearching = true;
        _searchQuery = normalizedQuery;
      });
    }

    try {
      final houses = await _houseService.searchDiscoverableHouses(
        normalizedQuery,
        locationQuery: normalizedLocationQuery,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _results = houses;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Search failed: $e')));
      setState(() {
        _results = const [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _openHouseDetails(House house) async {
    if (_openingHouseIds.contains(house.houseId)) {
      return;
    }

    setState(() => _openingHouseIds.add(house.houseId));
    try {
      final latestHouse = await _houseService.getHouseById(house.houseId);

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => HouseDetailScreen(house: latestHouse ?? house)),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open house: $e')));
    } finally {
      if (mounted) {
        setState(() => _openingHouseIds.remove(house.houseId));
      }
    }
  }

  Future<void> _requestToJoin(House house) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You must be signed in to request join.')));
      return;
    }

    if (_joiningHouseIds.contains(house.houseId)) {
      return;
    }

    setState(() => _joiningHouseIds.add(house.houseId));
    try {
      await _houseService.createJoinRequest(houseId: house.houseId, userId: currentUserId);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request sent')));
    } catch (e) {
      if (!mounted) {
        return;
      }

      final message = (e is StateError ? e.message : e).toString();

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _joiningHouseIds.remove(house.houseId));
      }
    }
  }

  Future<void> _joinWithCode() async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You must be signed in to join a house.')));
      return;
    }

    if (_isJoiningByCode) {
      return;
    }

    final code = _inviteCodeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter an invite code.')));
      return;
    }

    setState(() => _isJoiningByCode = true);
    try {
      await _houseService.joinByInviteCode(code, currentUserId);

      if (!mounted) {
        return;
      }

      _inviteCodeController.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request sent')));
    } catch (e) {
      if (!mounted) {
        return;
      }

      final message = (e is StateError ? e.message : e).toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isJoiningByCode = false);
      }
    }
  }

  Widget _buildFilterPanel() {
    return Card(
      elevation: 0,
      color: _surfaceGreen,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: (_) => _scheduleSearch(),
              decoration: InputDecoration(
                hintText: 'Search by house name',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchController.clear();
                          _runSearch();
                        },
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_city_outlined, color: _darkGreen),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      bartinMerkezCity,
                      style: const TextStyle(color: _darkGreen, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _selectedMahalle,
              isExpanded: true,
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('All Mahalleler')),
                ...bartinMerkezMahalleleri.map(
                  (mahalle) => DropdownMenuItem<String>(value: mahalle, child: Text(mahalle)),
                ),
              ],
              onChanged: (value) {
                setState(() => _selectedMahalle = value);
                _runSearch();
              },
              decoration: const InputDecoration(
                hintText: 'Select mahalle',
                prefixIcon: Icon(Icons.map_outlined),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String requestStatus) {
    final bool isPending = requestStatus == JoinRequestStatus.pending;
    final bool isAccepted = requestStatus == JoinRequestStatus.accepted;

    final Color background = isAccepted
        ? const Color(0xFFD7F4DF)
        : isPending
        ? const Color(0xFFE7F3EC)
        : const Color(0xFFF1F1F1);
    final Color foreground = isAccepted
        ? const Color(0xFF0B6A3E)
        : isPending
        ? _darkGreen
        : const Color(0xFF555555);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(
        requestStatus,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }

  Widget _buildResultCard(House house, {String? requestStatus}) {
    final isJoining = _joiningHouseIds.contains(house.houseId);
    final isOpening = _openingHouseIds.contains(house.houseId);
    final hasPending = requestStatus == JoinRequestStatus.pending;
    final isAccepted = requestStatus == JoinRequestStatus.accepted;
    final isFull = house.members.length >= house.maxMembers;
    final shouldDisableRequest = isJoining || hasPending || isAccepted || isFull;

    String buttonLabel = 'Request to Join';
    if (hasPending) {
      buttonLabel = 'Pending Approval';
    } else if (isAccepted) {
      buttonLabel = 'Approved';
    } else if (isFull) {
      buttonLabel = 'House Full';
    }

    final locationText = house.district.isEmpty ? house.city : '${house.city} • ${house.district}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              house.name,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: _darkGreen, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _surfaceGreen,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_city_outlined,
                        size: 14,
                        color: _darkGreen.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        locationText,
                        style: TextStyle(
                          color: _darkGreen.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _surfaceGreen,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${house.members.length} / ${house.maxMembers} members',
                    style: TextStyle(
                      color: _darkGreen.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (requestStatus != null) _buildStatusChip(requestStatus),
                if (isFull) const _SearchTag(text: 'Full'),
              ],
            ),
            if (house.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                house.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF46635A)),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Total Rent: ${_formatTry(house.rentTotal)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF2E4D43),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Electricity: ${_formatTry(house.electricityTotal)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF2E4D43),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Water: ${_formatTry(house.waterTotal)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF2E4D43),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Internet: ${_formatTry(house.internetTotal)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF2E4D43),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Estimated per-person monthly cost: ${_formatTry(house.perPersonMonthlyCost)}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: _darkGreen, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isOpening ? null : () => _openHouseDetails(house),
                    icon: isOpening
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.visibility_outlined),
                    label: const Text('View Details'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: shouldDisableRequest ? null : () => _requestToJoin(house),
                    child: isJoining
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(buttonLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinWithCodeSection() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Join with Code',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: _darkGreen, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _inviteCodeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'Enter invite code',
                prefixIcon: Icon(Icons.qr_code_2_rounded),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isJoiningByCode ? null : _joinWithCode,
                child: _isJoiningByCode
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Join House'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsCard() {
    final hasFilters = _searchQuery.isNotEmpty || _selectedMahalle != null;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          hasFilters ? 'No houses found for current filters.' : 'No houses found.',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: _darkGreen.withValues(alpha: 0.75)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasNoResults = !_isSearching && _results.isEmpty;
    final currentUserId = _auth.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Find Houses')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [
            _buildFilterPanel(),
            const SizedBox(height: 12),
            Expanded(
              child: currentUserId == null
                  ? ListView(
                      children: [
                        if (_isSearching)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator(color: _darkGreen)),
                          ),
                        if (hasNoResults) _buildNoResultsCard(),
                        ..._results.map((house) => _buildResultCard(house)),
                        const SizedBox(height: 8),
                        _buildJoinWithCodeSection(),
                        const SizedBox(height: 8),
                      ],
                    )
                  : StreamBuilder<List<JoinRequest>>(
                      stream: _houseService.watchJoinRequestsForUser(currentUserId),
                      builder: (context, requestSnapshot) {
                        final statusByHouseId = <String, String>{};
                        final requests = requestSnapshot.data ?? const <JoinRequest>[];
                        for (final request in requests) {
                          statusByHouseId[request.houseId] = request.status;
                        }

                        return ListView(
                          children: [
                            if (_isSearching)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: CircularProgressIndicator(color: _darkGreen)),
                              ),
                            if (hasNoResults) _buildNoResultsCard(),
                            ..._results.map(
                              (house) => _buildResultCard(
                                house,
                                requestStatus: statusByHouseId[house.houseId],
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildJoinWithCodeSection(),
                            const SizedBox(height: 8),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchTag extends StatelessWidget {
  final String text;

  const _SearchTag({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFDEEEA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFF8B3B2C), fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
