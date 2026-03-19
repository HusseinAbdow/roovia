import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  static const _darkGreen = Color(0xFF0B3D2E);
  static const _lightGreen = Color(0xFFB9E8C9);
  static const _surfaceGreen = Color(0xFFE9F7EE);

  final AuthService _auth = AuthService();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (_loading) {
      return;
    }

    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;
    final confirmPassword = confirmPasswordController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all required fields')),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password should be at least 6 characters long'),
        ),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
      return;
    }

    setState(() => _loading = true);
    try {
      final user = await _auth.signUp(name, email, password);
      debugPrint('Sign up success for $email');

      if (!mounted) {
        debugPrint('NAVIGATION BLOCKED (signup): widget is not mounted');
        return;
      }

      setState(() => _loading = false);

      if (user != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created successfully')),
        );

        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (!mounted) {
          debugPrint(
            'NAVIGATION BLOCKED (signup delayed): widget is not mounted',
          );
          return;
        }

        await _auth.signOut();

        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created. Please sign in.')),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to create account right now.')),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Sign up failed: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        debugPrint('Sign up error UI skipped: widget is not mounted');
        return;
      }

      setState(() => _loading = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
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
                          Icons.person_add_alt_1_rounded,
                          size: 36,
                          color: _darkGreen,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Create your account',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: _darkGreen,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Join Roovia with the same calm green experience and secure Firebase authentication.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: _darkGreen.withValues(alpha: 0.75),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _buildField(
                        controller: nameController,
                        label: 'Full name',
                        hint: 'Your name',
                        icon: Icons.person_outline_rounded,
                      ),
                      const SizedBox(height: 16),
                      _buildField(
                        controller: emailController,
                        label: 'Email address',
                        hint: 'you@example.com',
                        icon: Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),
                      _buildField(
                        controller: passwordController,
                        label: 'Password',
                        hint: 'At least 6 characters',
                        icon: Icons.lock_outline_rounded,
                        obscureText: true,
                      ),
                      const SizedBox(height: 16),
                      _buildField(
                        controller: confirmPasswordController,
                        label: 'Confirm password',
                        hint: 'Repeat your password',
                        icon: Icons.verified_user_outlined,
                        obscureText: true,
                      ),
                      const SizedBox(height: 24),
                      _loading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: _darkGreen,
                              ),
                            )
                          : ElevatedButton(
                              onPressed: _signUp,
                              child: const Text('Create Account'),
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
                              Icons.verified_outlined,
                              color: _darkGreen,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'We create your Firebase Auth account and save your profile in Cloud Firestore.',
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
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Already have an account?',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: _darkGreen.withValues(alpha: 0.72),
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Sign in'),
                          ),
                        ],
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

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: _darkGreen),
        labelStyle: const TextStyle(
          color: _darkGreen,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(color: _darkGreen.withValues(alpha: 0.45)),
      ),
    );
  }
}
