import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etbp_agent_mobile/core/auth/auth_provider.dart';
import 'package:etbp_agent_mobile/core/api/endpoints.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background message: ${message.messageId}');
}

class PushNotificationService {
  final Ref _ref;
  PushNotificationService(this._ref);

  Future<void> initialize() async {
    debugPrint('Push: initializing...');
    final messaging = FirebaseMessaging.instance;
    debugPrint('Push: requesting permission...');
    final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
    debugPrint('Push: permission = ${settings.authorizationStatus}');

    debugPrint('Push: getting token...');
    final token = await messaging.getToken();
    if (token != null) {
      debugPrint('Push: token = ${token.substring(0, 30)}...');
      await _registerToken(token);
    } else {
      debugPrint('Push: token is null');
    }

    messaging.onTokenRefresh.listen(_registerToken);
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    final initial = await messaging.getInitialMessage();
    if (initial != null) _handleNotificationTap(initial);
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

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Foreground push: ${message.notification?.title}');
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
