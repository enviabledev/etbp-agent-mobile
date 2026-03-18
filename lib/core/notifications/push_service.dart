import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etbp_agent_mobile/core/auth/auth_provider.dart';
import 'package:etbp_agent_mobile/core/api/endpoints.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background message: ${message.messageId}');
}

final _localNotifications = FlutterLocalNotificationsPlugin();

const _channel = AndroidNotificationChannel(
  'etbp_agent_notifications',
  'Enviable Transport Agent',
  description: 'Booking alerts and terminal notifications',
  importance: Importance.high,
);

class PushNotificationService {
  final Ref _ref;
  PushNotificationService(this._ref);

  Future<void> initialize() async {
    debugPrint('Push: initializing...');
    final messaging = FirebaseMessaging.instance;

    debugPrint('Push: requesting permission...');
    final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
    debugPrint('Push: permission = ${settings.authorizationStatus}');

    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true,
    );

    await _setupLocalNotifications();

    debugPrint('Push: getting token...');
    final token = await messaging.getToken();
    if (token != null) {
      debugPrint('Push: token = ${token.substring(0, 30)}...');
      await _registerToken(token);
    } else {
      debugPrint('Push: token is null');
    }

    messaging.onTokenRefresh.listen(_registerToken);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Foreground push: ${message.notification?.title}');
      if (message.notification != null) {
        _showLocalNotification(
          message.notification!.title ?? 'Enviable Transport',
          message.notification!.body ?? '',
          payload: message.data['type'],
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    final initial = await messaging.getInitialMessage();
    if (initial != null) _handleNotificationTap(initial);
  }

  Future<void> _setupLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('Notification tapped: ${response.payload}');
      },
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  Future<void> _showLocalNotification(String title, String body, {String? payload}) async {
    const androidDetails = AndroidNotificationDetails(
      'etbp_agent_notifications',
      'Enviable Transport Agent',
      channelDescription: 'Booking alerts and terminal notifications',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails);
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title, body, details, payload: payload,
    );
  }

  Future<void> _registerToken(String token) async {
    try {
      debugPrint('Push: registering with backend...');
      final api = _ref.read(apiClientProvider);
      await api.post(Endpoints.registerDevice, data: {
        'token': token,
        'device_type': Platform.isIOS ? 'ios' : 'android',
        'app_type': 'agent',
      });
      debugPrint('Push: registered successfully');
    } catch (e) {
      debugPrint('Push: registration failed: $e');
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('Notification tap: type=${message.data['type']}');
  }

  Future<void> unregister() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        final api = _ref.read(apiClientProvider);
        await api.post(Endpoints.unregisterDevice, data: {
          'token': token,
          'device_type': Platform.isIOS ? 'ios' : 'android',
          'app_type': 'agent',
        });
      }
    } catch (_) {}
  }
}

final pushServiceProvider = Provider<PushNotificationService>(
  (ref) => PushNotificationService(ref),
);
