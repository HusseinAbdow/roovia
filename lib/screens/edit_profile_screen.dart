import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/user_service.dart';

class EditProfileScreen extends StatefulWidget {
  final RooviaUser user;

  const EditProfileScreen({super.key, required this.user});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const _darkGreen = Color(0xFF0B3D2E);
  static const _surfaceGreen = Color(0xFFE9F7EE);

  final UserService _userService = UserService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  String _profileImageUrl = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.user.name;
    _usernameController.text = widget.user.username;
    _profileImageUrl = widget.user.profileImageUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  String _avatarInitial(String username) {
    final clean = username.trim();
    if (clean.isEmpty) {
      return 'U';
    }
    return clean[0].toUpperCase();
  }

  Future<void> _saveProfile() async {
    if (_saving) {
      return;
    }

    final name = _nameController.text.trim();
    final username = _usernameController.text.trim().toLowerCase();

    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Display name cannot be empty.')));
      return;
    }

    setState(() => _saving = true);
    try {
      await _userService.updateProfile(
        name: name,
        username: username,
        profileImageUrl: _profileImageUrl,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated successfully.')));
      Navigator.of(context).pop(true);
    } on UserServiceException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) {
        return;
      }
      debugPrint('Profile save error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to update profile right now. Please try again.')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageWidget = _profileImageUrl.trim().isNotEmpty
        ? CircleAvatar(
            radius: 56,
            backgroundImage: CachedNetworkImageProvider(_profileImageUrl.trim()),
          )
        : CircleAvatar(
            radius: 56,
            backgroundColor: _surfaceGreen,
            child: Text(
              _avatarInitial(_usernameController.text),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _darkGreen, fontSize: 28, fontWeight: FontWeight.w800),
            ),
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Center(child: imageWidget),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'Profile photo upload is currently unavailable.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: _darkGreen.withValues(alpha: 0.72)),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _nameController,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Display name',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _usernameController,
            enabled: !_saving,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Username',
              hintText: 'lowercase, no spaces',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
          ),
          const SizedBox(height: 22),
          _saving
              ? const Center(child: CircularProgressIndicator(color: _darkGreen))
              : ElevatedButton(onPressed: _saveProfile, child: const Text('Save')),
        ],
      ),
    );
  }
}
