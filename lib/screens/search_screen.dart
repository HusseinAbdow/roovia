import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/house_model.dart';
import '../models/join_request_model.dart';
import '../services/house_service.dart';

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
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _runSearch('');
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_debounceDuration, () {
      _runSearch(value);
    });
  }

  Future<void> _runSearch(String query) async {
    final normalizedQuery = query.trim();
    if (mounted) {
      setState(() {
        _isSearching = true;
        _searchQuery = normalizedQuery;
      });
    }

    try {
      final houses = await _houseService.searchDiscoverableHouses(
        normalizedQuery,
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Search failed: $e')));
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

  Future<void> _requestToJoin(House house) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in to request join.')),
      );
      return;
    }

    if (_joiningHouseIds.contains(house.houseId)) {
      return;
    }

    setState(() => _joiningHouseIds.add(house.houseId));
    try {
      await _houseService.createJoinRequest(
        houseId: house.houseId,
        userId: currentUserId,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Request sent')));
    } catch (e) {
      if (!mounted) {
        return;
      }

      final message = (e is StateError ? e.message : e).toString();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _joiningHouseIds.remove(house.houseId));
      }
    }
  }

  Future<void> _joinWithCode() async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in to join a house.')),
      );
      return;
    }

    if (_isJoiningByCode) {
      return;
    }

    final code = _inviteCodeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an invite code.')),
      );
      return;
    }

    setState(() => _isJoiningByCode = true);
    try {
      await _houseService.joinByInviteCode(code, currentUserId);

      if (!mounted) {
        return;
      }

      _inviteCodeController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Request sent')));
    } catch (e) {
      if (!mounted) {
        return;
      }

      final message = (e is StateError ? e.message : e).toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isJoiningByCode = false);
      }
    }
  }

  Widget _buildResultCard(House house, {String? requestStatus}) {
    final isJoining = _joiningHouseIds.contains(house.houseId);
    final hasPending = requestStatus == JoinRequestStatus.pending;
    final isAccepted = requestStatus == JoinRequestStatus.accepted;
    final shouldDisableRequest = isJoining || hasPending || isAccepted;

    String buttonLabel = 'Request to Join';
    if (hasPending) {
      buttonLabel = 'Pending Approval';
    } else if (isAccepted) {
      buttonLabel = 'Approved';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              house.name,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _darkGreen,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Members: ${house.members.length}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _darkGreen.withValues(alpha: 0.75),
              ),
            ),
            if (requestStatus != null) ...[
              const SizedBox(height: 6),
              Text(
                'Request status: $requestStatus',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _darkGreen.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: shouldDisableRequest
                    ? null
                    : () => _requestToJoin(house),
                child: isJoining
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(buttonLabel),
              ),
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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _darkGreen,
                fontWeight: FontWeight.w800,
              ),
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
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Join House'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasNoResults = !_isSearching && _results.isEmpty;
    final currentUserId = _auth.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [
            Card(
              elevation: 0,
              color: _surfaceGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: const InputDecoration(
                    hintText: 'Search houses by name',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: currentUserId == null
                  ? ListView(
                      children: [
                        if (_isSearching)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: _darkGreen,
                              ),
                            ),
                          ),
                        if (hasNoResults)
                          Card(
                            elevation: 0,
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Text(
                                _searchQuery.isEmpty
                                    ? 'No houses found'
                                    : 'No houses found for "$_searchQuery"',
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      color: _darkGreen.withValues(alpha: 0.75),
                                    ),
                              ),
                            ),
                          ),
                        ..._results.map((house) => _buildResultCard(house)),
                        const SizedBox(height: 8),
                        _buildJoinWithCodeSection(),
                        const SizedBox(height: 8),
                      ],
                    )
                  : StreamBuilder<List<JoinRequest>>(
                      stream: _houseService.watchJoinRequestsForUser(
                        currentUserId,
                      ),
                      builder: (context, requestSnapshot) {
                        final statusByHouseId = <String, String>{};
                        final requests =
                            requestSnapshot.data ?? const <JoinRequest>[];
                        for (final request in requests) {
                          statusByHouseId[request.houseId] = request.status;
                        }

                        return ListView(
                          children: [
                            if (_isSearching)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: _darkGreen,
                                  ),
                                ),
                              ),
                            if (hasNoResults)
                              Card(
                                elevation: 0,
                                color: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Text(
                                    _searchQuery.isEmpty
                                        ? 'No houses found'
                                        : 'No houses found for "$_searchQuery"',
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(
                                          color: _darkGreen.withValues(
                                            alpha: 0.75,
                                          ),
                                        ),
                                  ),
                                ),
                              ),
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
