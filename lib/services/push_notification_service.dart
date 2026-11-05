import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import '../firebase_options.dart';

class PushNotificationService {
  PushNotificationService({required this.baseUrl});
  final String baseUrl;
  static bool _initialized = false;
  static StreamSubscription<String>? _tokenSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<RemoteMessage>? _openedSubscription;

  static Future<void> initialize() async {
    if (_initialized || !DefaultFirebaseOptions.isConfigured) return;
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    _initialized = true;
  }

  Future<void> register(String bearerToken,
      {required void Function(String title, String body) onForeground,
      required void Function() onOpened}) async {
    if (!DefaultFirebaseOptions.isConfigured) return;
    try {
      await initialize();
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission(
        alert: true, badge: true, sound: true,
        provisional: false,
      );
      if (permission.authorizationStatus == AuthorizationStatus.denied) return;
      if (Platform.isIOS) {
        // FCM token is issued after APNs registration is available.
        String? apnsToken;
        for (var attempt = 0; attempt < 10 && apnsToken == null; attempt++) {
          apnsToken = await messaging.getAPNSToken();
          if (apnsToken == null) await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        if (apnsToken == null) return;
      }
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _sendToken(bearerToken, token, 'register');
      }
      await _tokenSubscription?.cancel();
      _tokenSubscription = messaging.onTokenRefresh.listen((fresh) {
        _sendToken(bearerToken, fresh, 'register').catchError((_) {});
      });
      await _foregroundSubscription?.cancel();
      _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
        onForeground(
          message.notification?.title ?? 'PCWork',
          message.notification?.body ?? 'Имате ново известие за ремонта си.',
        );
      });
      await _openedSubscription?.cancel();
      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((_) => onOpened());
      final initial = await messaging.getInitialMessage();
      if (initial != null) onOpened();
    } catch (_) {
      // Missing Firebase/APNs configuration must not block login or app use.
    }
  }

  Future<void> unregister(String bearerToken) async {
    if (!_initialized) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _sendToken(bearerToken, token, 'unregister');
      }
    } catch (_) {}
    await _tokenSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    _tokenSubscription = null;
    _foregroundSubscription = null;
    _openedSubscription = null;
  }

  Future<void> _sendToken(String bearerToken, String token, String action) async {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final platform = Platform.isIOS ? 'ios' : 'android';
    await http.post(
      Uri.parse('$base/wp-json/pcwork/v1/push/$action'),
      headers: {
        'Authorization': 'Bearer $bearerToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'token': token, 'platform': platform}),
    ).timeout(const Duration(seconds: 15));
  }

}
