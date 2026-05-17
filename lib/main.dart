import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/scheduler.dart';
import 'package:roovia/screens/login_screen.dart';
import 'package:roovia/services/fcm_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/expense_detail_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  final String? initialExpenseId = initialMessage?.data['expenseId'] as String?;

  // Initialize FCM and wire up navigation for notification taps
  await FcmService.instance.init(
    onNotificationTap: (expenseId) async {
      if (expenseId.isNotEmpty) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => ExpenseDetailScreen(expenseId: expenseId)),
        );
      }
    },
  );

  runApp(MyApp(navigatorKey: navigatorKey, initialExpenseId: initialExpenseId));
}

class MyApp extends StatefulWidget {
  final GlobalKey<NavigatorState>? navigatorKey;
  final String? initialExpenseId;

  const MyApp({super.key, this.navigatorKey, this.initialExpenseId});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _initialRouteHandled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialRouteHandled) return;
    final expenseId = widget.initialExpenseId?.trim() ?? '';
    if (expenseId.isEmpty) return;

    _initialRouteHandled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.navigatorKey?.currentState?.push(
        MaterialPageRoute(builder: (_) => ExpenseDetailScreen(expenseId: expenseId)),
      );
    });
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
      home: const LoginScreen(),
    );
  }
}
