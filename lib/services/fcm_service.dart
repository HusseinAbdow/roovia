import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();
bool _localNotificationsReady = false;

Future<void> _ensureLocalNotificationsReady({
  void Function(String expenseId)? onNotificationTap,
}) async {
  if (_localNotificationsReady) return;

  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings();
  await _localNotificationsPlugin.initialize(
    settings: const InitializationSettings(android: android, iOS: ios),
    onDidReceiveNotificationResponse: (details) async {
      final payload = details.payload;
      if (payload != null && onNotificationTap != null) {
        onNotificationTap(payload);
      }
    },
  );

  await _localNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
  await _localNotificationsPlugin
      .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, badge: true, sound: true);

  _localNotificationsReady = true;
}

Future<void> _showRemoteMessageAsLocalNotification(RemoteMessage message) async {
  await _ensureLocalNotificationsReady();

  final notification = message.notification;
  final data = message.data;
  final title = notification?.title ?? data['title'] as String? ?? 'Roovia';
  final body = notification?.body ?? data['body'] as String? ?? '';
  final expenseId = data['expenseId'] as String? ?? '';

  const androidDetails = AndroidNotificationDetails(
    'roovia_channel',
    'Roovia Notifications',
    channelDescription: 'General notifications',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
  );
  const iosDetails = DarwinNotificationDetails();
  const platform = NotificationDetails(android: androidDetails, iOS: iosDetails);

  await _localNotificationsPlugin.show(
    id: 0,
    title: title,
    body: body,
    notificationDetails: platform,
    payload: expenseId,
  );
}

/// Must be a top-level function to handle background messages.
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('FCM background message received: ${message.data}');
  await _showRemoteMessageAsLocalNotification(message);
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> init({required void Function(String expenseId)? onNotificationTap}) async {
    // Initialize local notifications so foreground and background handlers can reuse them.
    await _ensureLocalNotificationsReady(onNotificationTap: onNotificationTap);

    // Background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Request permission
    await requestPermission();

    // Foreground message presentation (iOS)
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Handle token
    await _saveTokenToDatabaseIfSignedIn(await _messaging.getToken());
    _messaging.onTokenRefresh.listen((token) {
      _saveTokenToDatabaseIfSignedIn(token);
    });
    _auth.authStateChanges().listen((user) async {
      if (user != null) {
        await _saveTokenToDatabaseIfSignedIn(await _messaging.getToken());
      }
    });

    // Handle messages when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final data = message.data;
      final expenseId = data['expenseId'] as String? ?? '';

      debugPrint('FCM foreground message received: type=${data['type']} expenseId=$expenseId');

      _showRemoteMessageAsLocalNotification(message);
    });

    // When the user taps a notification and app is in background (but not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final data = message.data;
      final expenseId = data['expenseId'] as String?;
      if (expenseId != null && expenseId.isNotEmpty && onNotificationTap != null) {
        onNotificationTap(expenseId);
      }
    });
  }

  Future<void> requestPermission() async {
    await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
  }

  Future<void> _saveTokenToDatabaseIfSignedIn(String? token) async {
    if (token == null || token.trim().isEmpty) {
      debugPrint('FCM token skipped: empty token');
      return;
    }
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('FCM token skipped: no signed-in user');
      return;
    }
    final userRef = _db.collection('users').doc(user.uid);
    try {
      await userRef.set({
        'fcmToken': token.trim(),
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('FCM token saved for user ${user.uid}');
    } catch (e) {
      // Ignore failures to avoid blocking UX
      debugPrint('FCM token save failed: $e');
    }
  }
}
