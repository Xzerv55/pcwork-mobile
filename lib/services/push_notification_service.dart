import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
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

  Future<void> register(String bearerToken,
      {required void Function(String title, String body) onForeground,
      required void Function(Map<String, dynamic> data) onOpened}) async {
    if (!DefaultFirebaseOptions.isConfigured) return;
    try {
      _activeBearerToken = bearerToken;
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
    } catch (_) {
      // Missing Firebase/APNs configuration must not block login or app use.
    }
  }


  /// Requests notification permission and returns this installation's FCM token.
  /// The token is shown only inside the app so an administrator can copy it
  /// into the WordPress test-token field.
  Future<String> getDeviceToken() async {
    if (!DefaultFirebaseOptions.isConfigured) {
      throw Exception('Firebase не е конфигуриран в тази компилация. За Android провери дали android/app/google-services.json е наличен в GitHub и съдържа клиент за com.pcworkbg.pcwork_mobile. След това стартирай нова компилация от GitHub Actions.');
    }
    try {
      await initialize().timeout(const Duration(seconds: 15));
      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);
      final permission = await messaging.requestPermission(
        alert: true, badge: true, sound: true, provisional: false,
      ).timeout(const Duration(seconds: 15));
      if (permission.authorizationStatus == AuthorizationStatus.denied) {
        throw Exception('Разрешението за известия е отказано. Разреши известията за PCWork от настройките на телефона и опитай отново.');
      }
      if (Platform.isIOS) {
        String? apnsToken;
        for (var attempt = 0; attempt < 20 && apnsToken == null; attempt++) {
          apnsToken = await messaging.getAPNSToken();
          if (apnsToken == null) await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        if (apnsToken == null) {
          throw Exception('Липсва APNs token. Провери Apple Push Notifications настройките във Firebase.');
        }
      }
      String? token;
      for (var attempt = 0; attempt < 3 && (token == null || token.isEmpty); attempt++) {
        token = await messaging.getToken().timeout(const Duration(seconds: 15));
        if (token == null || token.isEmpty) await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (token == null || token.isEmpty) {
        throw Exception('Firebase не върна FCM token. Провери google-services.json, package name com.pcworkbg.pcwork_mobile и интернет връзката.');
      }
      return token;
    } on PlatformException catch (error) {
      throw Exception('Firebase Messaging (${error.code}): ${error.message ?? error.details ?? 'неизвестна грешка'}');
    } on TimeoutException {
      throw Exception('Firebase не отговори навреме. Провери интернет връзката и опитай отново.');
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
