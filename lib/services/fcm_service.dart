import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();
bool _localNotificationsReady = false;

const AndroidNotificationChannel _androidNotificationChannel = AndroidNotificationChannel(
  'roovia_channel',
  'Roovia Notifications',
  description: 'General notifications',
  importance: Importance.max,
  playSound: true,
);

int _stableNotificationId(String seed) {
  var value = 0;
  for (final codeUnit in seed.codeUnits) {
    value = 0x1fffffff & (value + codeUnit);
    value = 0x1fffffff & (value + ((0x0007ffff & value) << 10));
    value ^= (value >> 6);
  }
  value = 0x1fffffff & (value + ((0x03ffffff & value) << 3));
  value ^= (value >> 11);
  value = 0x1fffffff & (value + ((0x00003fff & value) << 15));
  return value == 0 ? 1 : value;
}

Future<void> _ensureLocalNotificationsReady({
  void Function(Map<String, String> payload)? onNotificationTap,
}) async {
  if (_localNotificationsReady) return;

  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings();
  await _localNotificationsPlugin.initialize(
    settings: const InitializationSettings(android: android, iOS: ios),
    onDidReceiveNotificationResponse: (details) async {
      final payload = _decodeNotificationPayload(details.payload);
      if (payload != null && onNotificationTap != null) {
        onNotificationTap(payload);
      }
    },
  );

  await _localNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
  await _localNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_androidNotificationChannel);
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
  final payload = _notificationPayload(data);

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
    id: _stableNotificationId(
      '${data['notificationId'] ?? ''}_${data['expenseId'] ?? ''}_${data['type'] ?? ''}',
    ),
    title: title,
    body: body,
    notificationDetails: platform,
    payload: jsonEncode(payload),
  );
}

Map<String, String> _notificationPayload(Map<String, dynamic> data) {
  final payload = <String, String>{};
  for (final entry in data.entries) {
    final value = entry.value;
    if (value == null) {
      continue;
    }
    payload[entry.key] = value.toString();
  }
  return payload;
}

Map<String, String>? _decodeNotificationPayload(String? payload) {
  if (payload == null || payload.trim().isEmpty) {
    return null;
  }

  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) {
      return decoded.map((key, value) => MapEntry(key, value?.toString() ?? ''));
    }
  } catch (_) {
    return {'expenseId': payload};
  }

  return null;
}

/// Must be a top-level function to handle background messages.
@pragma('vm:entry-point')
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
  String? _savedTokenKey;
  String? _savingTokenKey;

  Future<void> init({
    required void Function(Map<String, String> payload)? onNotificationTap,
  }) async {
    // Initialize local notifications so foreground and background handlers can reuse them.
    await _ensureLocalNotificationsReady(onNotificationTap: onNotificationTap);

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
      final payload = _notificationPayload(message.data);
      if (onNotificationTap != null) {
        onNotificationTap(payload);
      }
    });
  }

  Future<NotificationSettings> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    debugPrint('FCM permission status: ${settings.authorizationStatus}');
    return settings;
  }

  Future<void> refreshNotificationRegistration() async {
    await requestPermission();
    await _saveTokenToDatabaseIfSignedIn(await _messaging.getToken());
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
    final normalizedToken = token.trim();
    final tokenKey = '${user.uid}:$normalizedToken';
    if (_savedTokenKey == tokenKey || _savingTokenKey == tokenKey) {
      debugPrint('FCM token skipped: already saved for user ${user.uid}');
      return;
    }

    _savingTokenKey = tokenKey;
    final userRef = _db.collection('users').doc(user.uid);
    try {
      await userRef.set({
        'fcmToken': normalizedToken,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _savedTokenKey = tokenKey;
      debugPrint('FCM token saved for user ${user.uid}');
    } catch (e) {
      // Ignore failures to avoid blocking UX
      debugPrint('FCM token save failed: $e');
    } finally {
      if (_savingTokenKey == tokenKey) {
        _savingTokenKey = null;
      }
    }
  }
}
