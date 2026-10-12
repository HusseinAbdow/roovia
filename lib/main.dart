import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/scheduler.dart';
import 'package:roovia/screens/chat_screen.dart';
import 'package:roovia/screens/login_screen.dart';
import 'package:roovia/screens/main_screen.dart';
import 'package:roovia/services/fcm_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/expense_detail_screen.dart';
import 'firebase_options.dart';

/// Declarative startup destination. Pure and unit-testable:
/// errors never resolve to signed-out; [initializing] always shows splash.
enum AuthHome { splash, login, main, error }

AuthHome resolveAuthHome({
  required bool initializing,
  required bool hasError,
  required bool hasUser,
}) {
  if (initializing) {
    return AuthHome.splash;
  }
  if (hasError) {
    return AuthHome.error;
  }
  if (hasUser) {
    return AuthHome.main;
  }
  return AuthHome.login;
}

/// True when a notification payload carries a private destination.
/// Trims values so whitespace-only payloads are ignored.
bool notificationHasDestination(Map<String, String>? payload) {
  if (payload == null) {
    return false;
  }
  final expenseId = payload['expenseId']?.trim() ?? '';
  final houseId = payload['houseId']?.trim() ?? '';
  return expenseId.isNotEmpty || houseId.isNotEmpty;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  final Map<String, String>? initialNotificationData = initialMessage?.data.map(
    (key, value) => MapEntry(key, value.toString()),
  );

  runApp(MyApp(navigatorKey: navigatorKey, initialNotificationData: initialNotificationData));
}

class MyApp extends StatefulWidget {
  final GlobalKey<NavigatorState>? navigatorKey;
  final Map<String, String>? initialNotificationData;

  const MyApp({super.key, this.navigatorKey, this.initialNotificationData});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  static const _darkGreen = Color(0xFF0B3D2E);

  StreamSubscription<User?>? _authSubscription;
  bool _authInitializing = true;
  User? _authUser;
  Object? _authError;

  Map<String, String>? _pendingNotification;
  bool _initialNotificationStashed = false;
  bool _fcmInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribeAuth();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _fcmInitialized) return;
      _fcmInitialized = true;
      unawaited(
        FcmService.instance.init(
          onNotificationTap: _handleNotificationTap,
        ),
      );
    });
  }

  void _subscribeAuth() {
    unawaited(_authSubscription?.cancel());
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      (user) {
        if (!mounted) {
          return;
        }
        setState(() {
          final wasSignedIn = _authUser != null;
          final signedOut = wasSignedIn && user == null;
          // Avoid leaking one account's pending destination into the next
          // session. Pending created while signed out is kept so login can
          // still route to it (requirement: do not discard merely because
          // auth was initially unresolved).
          if (signedOut) {
            _pendingNotification = null;
          }
          _authInitializing = false;
          _authUser = user;
          _authError = null;
        });
        _drainPendingNotificationIfReady();
      },
      onError: (Object error) {
        if (!mounted) {
          return;
        }
        // Never treat stream errors as signed-out.
        setState(() {
          _authInitializing = false;
          _authError = error;
        });
      },
    );
  }

  void _handleNotificationTap(Map<String, String> payload) {
    if (!notificationHasDestination(payload)) {
      return;
    }
    _pendingNotification = Map<String, String>.from(payload);
    _drainPendingNotificationIfReady();
  }

  void _drainPendingNotificationIfReady() {
    if (_authInitializing || _authError != null) {
      return;
    }
    // Keep pending while signed out so a subsequent login can still route.
    if (_authUser == null) {
      return;
    }
    final pending = _pendingNotification;
    if (pending == null || !notificationHasDestination(pending)) {
      return;
    }
    _pendingNotification = null;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _pendingNotification = pending;
        return;
      }
      if (FirebaseAuth.instance.currentUser == null) {
        _pendingNotification = pending;
        return;
      }
      _pushNotificationDestination(pending);
    });
  }

  void _pushNotificationDestination(Map<String, String> payload) {
    final expenseId = payload['expenseId']?.trim() ?? '';
    final houseId = payload['houseId']?.trim() ?? '';

    if (expenseId.isNotEmpty) {
      widget.navigatorKey?.currentState?.push(
        MaterialPageRoute(builder: (_) => ExpenseDetailScreen(expenseId: expenseId)),
      );
    } else if (houseId.isNotEmpty) {
      widget.navigatorKey?.currentState?.push(
        MaterialPageRoute(builder: (_) => ChatScreen(houseId: houseId)),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(FcmService.instance.refreshNotificationRegistration());
    }
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialNotificationStashed) return;
    final payload = widget.initialNotificationData;
    if (payload == null || !notificationHasDestination(payload)) return;

    // Cold-start notification: stash and route only after auth resolves.
    // Never push private screens before authentication is known.
    _initialNotificationStashed = true;
    _pendingNotification = Map<String, String>.from(payload);
    _drainPendingNotificationIfReady();
  }

  void _retryAuth() {
    if (!mounted) return;
    setState(() {
      _authInitializing = true;
      _authError = null;
    });
    _subscribeAuth();
  }

  Widget _buildHome() {
    final destination = resolveAuthHome(
      initializing: _authInitializing,
      hasError: _authError != null,
      hasUser: _authUser != null,
    );
    switch (destination) {
      case AuthHome.splash:
        return const _AuthSplashScreen();
      case AuthHome.error:
        return _AuthErrorScreen(onRetry: _retryAuth);
      case AuthHome.main:
        return const MainScreen();
      case AuthHome.login:
        return const LoginScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    const darkGreen = Color(0xFF0B3D2E);
    const lightGreen = Color(0xFFB9E8C9);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Roovia',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7FAF8),
        colorScheme: ColorScheme.fromSeed(
          seedColor: darkGreen,
          primary: darkGreen,
          secondary: lightGreen,
          brightness: Brightness.light,
        ),
        textTheme: Theme.of(context).textTheme.apply(bodyColor: darkGreen, displayColor: darkGreen),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7FAF8),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(color: darkGreen, fontSize: 22, fontWeight: FontWeight.w800),
          iconTheme: IconThemeData(color: darkGreen),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFF0F4F2),
          selectedColor: const Color(0xFFD5ECD9),
          disabledColor: const Color(0xFFE8ECEA),
          labelStyle: const TextStyle(color: darkGreen, fontWeight: FontWeight.w600),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: darkGreen, width: 1.6),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: darkGreen,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      navigatorKey: widget.navigatorKey,
      home: _buildHome(),
    );
  }
}

class _AuthSplashScreen extends StatelessWidget {
  const _AuthSplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF7FAF8),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.eco_rounded,
                size: 44,
                color: _MyAppState._darkGreen,
              ),
              SizedBox(height: 20),
              CircularProgressIndicator(
                color: _MyAppState._darkGreen,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthErrorScreen extends StatelessWidget {
  final VoidCallback onRetry;

  const _AuthErrorScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF8),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 44,
                  color: _MyAppState._darkGreen,
                ),
                const SizedBox(height: 16),
                Text(
                  'Could not check your sign-in status.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _MyAppState._darkGreen,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please check your connection and try again. You have not been signed out.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _MyAppState._darkGreen.withValues(alpha: 0.75),
                      ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
