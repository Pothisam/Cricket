import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Must be top-level for background isolate use.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// FCM + local notifications (shows pushes while the app is in the foreground).
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  static const _channel = AndroidNotificationChannel(
    'cricket_updates',
    'Match updates',
    description: 'Runs, wickets and match notifications',
    importance: Importance.high,
  );

  final _local = FlutterLocalNotificationsPlugin();
  final _refresh = StreamController<String>.broadcast();

  /// Current FCM token (null on web or before init).
  String? token;

  /// Whether the OS allowed notifications.
  bool enabled = false;

  /// Fires whenever Firebase rotates the token.
  Stream<String> get onTokenRefresh => _refresh.stream;

  Future<void> init() async {
    // Web push needs a service worker + VAPID key; not set up yet.
    if (kIsWeb) return;
    try {
      final fcm = FirebaseMessaging.instance;
      final settings = await fcm.requestPermission();
      enabled =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen(_showForeground);

      token = await fcm.getToken();
      debugPrint('FCM token: $token');
      fcm.onTokenRefresh.listen((t) {
        token = t;
        _refresh.add(t);
      });
    } catch (e) {
      debugPrint('Notification setup failed: $e');
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    if (kIsWeb) return;
    await FirebaseMessaging.instance.subscribeToTopic(topic);
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;
    await _local.show(
      id: n.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
