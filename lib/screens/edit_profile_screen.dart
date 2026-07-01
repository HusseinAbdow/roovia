import 'dart:typed_data';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

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
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  String _profileImageUrl = '';
  Uint8List? _localAvatarPreview;
  bool _saving = false;
  bool _uploadingAvatar = false;
  double _avatarUploadProgress = 0;

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

  Widget _buildAvatar() {
    final fallback = CircleAvatar(
      radius: 56,
      backgroundColor: _surfaceGreen,
      child: Text(
        _avatarInitial(_usernameController.text),
        textAlign: TextAlign.center,
        style: const TextStyle(color: _darkGreen, fontSize: 28, fontWeight: FontWeight.w800),
      ),
    );

    if (_localAvatarPreview != null) {
      return CircleAvatar(radius: 56, backgroundImage: MemoryImage(_localAvatarPreview!));
    }

    final imageUrl = _profileImageUrl.trim();
    if (imageUrl.isEmpty) {
      return fallback;
    }

    return CircleAvatar(
      radius: 56,
      backgroundColor: _surfaceGreen,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          width: 112,
          height: 112,
          fit: BoxFit.cover,
          placeholder: (context, url) => const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: _darkGreen),
          ),
          errorWidget: (context, url, error) => fallback,
        ),
      ),
    );
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    if (_saving || _uploadingAvatar) {
      return;
    }
    final picked = await _imagePicker.pickImage(source: source, requestFullMetadata: false);

    if (picked == null) {
      return;
    }

    // Open cropper before uploading. If user cancels, do not upload.
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: picked.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop avatar',
          toolbarColor: _darkGreen,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(title: 'Crop avatar', aspectRatioLockEnabled: true),
      ],
    );

    if (croppedFile == null) {
      // User cancelled crop — do nothing.
      return;
    }

    final rawBytes = await File(croppedFile.path).readAsBytes();
    if (rawBytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selected image could not be read.')));
      return;
    }

    // Compress if necessary (goal: keep under 5MB and reasonable quality)
    Uint8List finalBytes = rawBytes;
    try {
      if (rawBytes.lengthInBytes > 1024 * 1024) {
        final compressed = await FlutterImageCompress.compressWithList(
          rawBytes,
          quality: 88,
          minWidth: 800,
          minHeight: 800,
          rotate: 0,
        );
        if (compressed.isNotEmpty) {
          finalBytes = Uint8List.fromList(compressed);
        }
      }
    } catch (_) {
      // Compression is best-effort — fall back to original bytes on failure.
      finalBytes = rawBytes;
    }

    if (!mounted) return;

    setState(() {
      _uploadingAvatar = true;
      _avatarUploadProgress = 0;
      _localAvatarPreview = finalBytes;
    });

    try {
      final mimeType = _mimeFromPath(croppedFile.path);
      final uploadedUrl = await _userService.uploadProfileImage(
        imageBytes: finalBytes,
        mimeType: mimeType,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _avatarUploadProgress = progress;
          });
        },
      );

      if (!mounted) return;

      setState(() {
        _profileImageUrl = uploadedUrl;
        _localAvatarPreview = null;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile photo updated.')));
    } on UserServiceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      setState(() {
        _localAvatarPreview = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to upload image right now. Please try again.')),
      );
      setState(() {
        _localAvatarPreview = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _uploadingAvatar = false;
          _avatarUploadProgress = 0;
        });
      }
    }
  }

  String _mimeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _showAvatarActions() async {
    if (_saving || _uploadingAvatar) {
      return;
    }

    final selectedSource = await showModalBottomSheet<ImageSource?>(
      context: context,
      builder: (context) {
        final hasImage = _profileImageUrl.trim().isNotEmpty;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.of(context).pop(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take photo'),
                onTap: () {
                  Navigator.of(context).pop(ImageSource.camera);
                },
              ),
              if (hasImage)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  title: const Text('Remove current photo'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _removeAvatar();
                  },
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || selectedSource == null) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) {
      return;
    }

    await _pickAndUploadAvatar(selectedSource);
  }

  Future<void> _removeAvatar() async {
    if (_saving || _uploadingAvatar || _profileImageUrl.trim().isEmpty) {
      return;
    }

    setState(() {
      _uploadingAvatar = true;
      _avatarUploadProgress = 0;
    });

    try {
      await _userService.removeProfileImage();
      if (!mounted) {
        return;
      }
      setState(() {
        _profileImageUrl = '';
        _localAvatarPreview = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile photo removed.')));
    } on UserServiceException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to remove photo right now. Please try again.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploadingAvatar = false;
          _avatarUploadProgress = 0;
        });
      }
    }
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
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Center(
            child: Stack(
              children: [
                _buildAvatar(),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _showAvatarActions,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.edit_rounded, size: 18, color: _darkGreen),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Tap the icon to upload, replace, or remove your profile photo.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: _darkGreen.withValues(alpha: 0.72)),
              textAlign: TextAlign.center,
            ),
          ),
          if (_uploadingAvatar) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: _avatarUploadProgress == 0 ? null : _avatarUploadProgress,
              ),
            ),
          ],
          const SizedBox(height: 18),
          TextField(
            controller: _nameController,
            enabled: !_saving && !_uploadingAvatar,
            decoration: const InputDecoration(
              labelText: 'Display name',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _usernameController,
            enabled: !_saving && !_uploadingAvatar,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Username',
              hintText: 'lowercase, no spaces',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
          ),
          const SizedBox(height: 22),
          (_saving || _uploadingAvatar)
              ? const Center(child: CircularProgressIndicator(color: _darkGreen))
              : ElevatedButton(onPressed: _saveProfile, child: const Text('Save')),
        ],
      ),
    );
  }
}
