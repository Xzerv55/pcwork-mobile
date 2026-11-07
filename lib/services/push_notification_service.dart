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
  static String? _activeBearerToken;

  static Future<void> initialize() async {
    if (_initialized || !DefaultFirebaseOptions.isConfigured) return;
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    _initialized = true;
  }

  /// Requests the operating-system notification permission independently
  /// of account login. Token registration is deferred until a user session exists.
  Future<bool> requestPermission() async {
    if (!DefaultFirebaseOptions.isConfigured) return false;
    try {
      await initialize();
      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);
      final settings = await messaging.requestPermission(
        alert: true, badge: true, sound: true, provisional: false,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  Future<bool> register(String bearerToken,
      {required void Function(String title, String body) onForeground,
      required void Function(Map<String, dynamic> data) onOpened}) async {
    if (!DefaultFirebaseOptions.isConfigured) return false;
    try {
      _activeBearerToken = bearerToken;
      await initialize();
      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);
      final permission = await messaging.requestPermission(
        alert: true, badge: true, sound: true,
        provisional: false,
      );
      if (permission.authorizationStatus != AuthorizationStatus.authorized && permission.authorizationStatus != AuthorizationStatus.provisional) return false;
      if (Platform.isIOS) {
        // FCM token is issued after APNs registration is available.
        String? apnsToken;
        for (var attempt = 0; attempt < 10 && apnsToken == null; attempt++) {
          apnsToken = await messaging.getAPNSToken();
          if (apnsToken == null) await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        if (apnsToken == null) return false;
      }
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return false;
      await _sendToken(bearerToken, token, 'register');
      await _tokenSubscription?.cancel();
      _tokenSubscription = messaging.onTokenRefresh.listen((fresh) {
        final activeToken = _activeBearerToken;
        if (activeToken != null && activeToken.isNotEmpty) {
          _sendToken(activeToken, fresh, 'register').catchError((_) {});
        }
      });
      await _foregroundSubscription?.cancel();
      _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
        onForeground(
          message.notification?.title ?? 'PCWork',
          message.notification?.body ?? 'Имате ново известие за ремонта си.',
        );
      });
      await _openedSubscription?.cancel();
      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((message) => onOpened(message.data));
      final initial = await messaging.getInitialMessage();
      if (initial != null) onOpened(initial.data);
      return true;
    } catch (_) {
      // Missing Firebase/APNs configuration must not block login or app use.
      return false;
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
    _activeBearerToken = null;
  }

  Future<Map<String, dynamic>> getDiagnostics(String bearerToken) async {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    var permission = 'unknown';
    String? token;
    if (DefaultFirebaseOptions.isConfigured) {
      try {
        await initialize();
        final settings = await FirebaseMessaging.instance.getNotificationSettings();
        permission = settings.authorizationStatus == AuthorizationStatus.authorized || settings.authorizationStatus == AuthorizationStatus.provisional ? 'granted' : settings.authorizationStatus == AuthorizationStatus.denied ? 'denied' : 'not_determined';
        if (permission == 'granted') token = await FirebaseMessaging.instance.getToken();
      } catch (_) {}
    }
    final response = await http.post(Uri.parse('$base/wp-json/pcwork/v1/push/status'),
      headers: {'Authorization':'Bearer $bearerToken','Content-Type':'application/json'},
      body: jsonEncode({'token': token ?? '', 'platform': Platform.isIOS ? 'ios' : 'android'})).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('HTTP ${response.statusCode}');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw Exception('Невалиден отговор за статуса на известията.');
    return {...Map<String, dynamic>.from(decoded), 'permission': permission, 'token_available': token != null && token.isNotEmpty};
  }

  Future<bool> getMarketingConsent(String bearerToken) async {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await http.get(Uri.parse('$base/wp-json/pcwork/v1/push/preferences'), headers: {'Authorization':'Bearer $bearerToken'}).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('HTTP ${response.statusCode}');
    final decoded = jsonDecode(response.body);
    return decoded is Map && decoded['marketing_opt_in'] == true;
  }

  Future<void> setMarketingConsent(String bearerToken, bool enabled) async {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await http.post(Uri.parse('$base/wp-json/pcwork/v1/push/preferences'), headers: {'Authorization':'Bearer $bearerToken','Content-Type':'application/json'}, body: jsonEncode({'marketing_opt_in':enabled})).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('HTTP ${response.statusCode}');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['saved'] != true) throw Exception('Server did not confirm the preference.');
  }

  Future<void> _sendToken(String bearerToken, String token, String action) async {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final platform = Platform.isIOS ? 'ios' : 'android';
    final response = await http.post(
      Uri.parse('$base/wp-json/pcwork/v1/push/$action'),
      headers: {
        'Authorization': 'Bearer $bearerToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'token': token, 'platform': platform}),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('FCM device registration failed (HTTP ${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    final expectedKey = action == 'register' ? 'registered' : 'unregistered';
    if (decoded is! Map || decoded[expectedKey] != true) {
      throw Exception('The PCWork server did not confirm the FCM device operation.');
    }
  }

}
