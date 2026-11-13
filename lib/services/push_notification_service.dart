import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_options.dart';

const String _notificationHistoryKey = 'pcwork_notification_history_v1';
const int _maxNotificationHistoryRecords = 200;

@pragma('vm:entry-point')
Future<void> pcworkFirebaseBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (DefaultFirebaseOptions.isConfigured) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
    await PushNotificationService.storeNotification(message);
  } catch (_) {
    // Notification delivery must never be interrupted by local history storage.
  }
}


class PushNotificationService {
  PushNotificationService({required this.baseUrl});
  final String baseUrl;
  // Reuse a process-wide client to keep HTTP connections alive between API calls.
  static final http.Client _httpClient = http.Client();
  static bool _initialized = false;
  static StreamSubscription<String>? _tokenSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<RemoteMessage>? _openedSubscription;
  static String? _activeBearerToken;
  static final StreamController<Map<String, dynamic>> foregroundDataEvents = StreamController<Map<String, dynamic>>.broadcast();
  static const MethodChannel _androidNotificationChannel = MethodChannel('com.pcworkbg.pcwork_mobile/notifications');
  static Future<void> showLocalNotification(String title, String body, Map<String, dynamic> data) async {
    if (!Platform.isAndroid) return;
    try {
      await _androidNotificationChannel.invokeMethod<void>('showLocalNotification', {
        'title': title, 'body': body, 'data': data,
      });
    } catch (_) { /* Remote FCM delivery remains available if local display is unavailable. */ }
  }

  static String _notificationCategory(String event) {
    final value = event.toLowerCase();
    if (value.contains('repair')) return 'repair';
    if (value.contains('part_delivery')) return 'order';
    if (value.contains('order')) return 'order';
    if (value.contains('chat') || value.contains('message')) return 'chat';
    if (value.contains('booking') || value.contains('appointment')) return 'booking';
    if (value.contains('campaign') || value.contains('marketing')) return 'promotion';
    return 'general';
  }

  static String _notificationPriority(String event, String status) {
    final value = event.toLowerCase();
    final state = status.toLowerCase();
    if (state == 'ready' || state == 'waiting_approval' || state == 'cancelled' || value.contains('security') || value.contains('part_delivery_overdue')) return 'high';
    if (value.contains('repair') || value.contains('order') || value.contains('chat') || value.contains('booking') || value.contains('part_delivery')) return 'normal';
    if (value.contains('campaign') || value.contains('marketing')) return 'low';
    return 'normal';
  }

  static Future<String> storeNotification(RemoteMessage message) async {
    final data = Map<String, dynamic>.from(message.data);
    final title = (message.notification?.title ?? data['title'] ?? data['notification_title'] ?? 'Известие от PCWork').toString();
    final body = (message.notification?.body ?? data['body'] ?? data['message'] ?? data['notification_body'] ?? '').toString();
    final suppliedId = (data['notification_id'] ?? data['id'] ?? '').toString().trim();
    final id = suppliedId.isNotEmpty
        ? suppliedId
        : (message.messageId?.trim().isNotEmpty == true ? message.messageId!.trim() : '${DateTime.now().microsecondsSinceEpoch}');
    await saveNotificationRecord({
      'id': id,
      'title': title.trim().isEmpty ? 'Известие от PCWork' : title,
      'body': body,
      'url': (data['url'] ?? '').toString(),
      'event': (data['event'] ?? '').toString(),
      'screen': (data['screen'] ?? '').toString(),
      'category': _notificationCategory((data['event'] ?? '').toString()),
      'priority': _notificationPriority((data['event'] ?? '').toString(), (data['status'] ?? '').toString()),
      'repair_id': (data['repair_id'] ?? data['repairId'] ?? '').toString(),
      'order_id': (data['order_id'] ?? data['orderId'] ?? '').toString(),
      'campaign_id': (data['campaign_id'] ?? '').toString(),
      'image': (data['image'] ?? '').toString(),
      'data': {...data, '_notification_id': id},
      'received_at': DateTime.now().toIso8601String(),
      'read': false,
    });
    return id;
  }

  static Future<void> saveNotificationRecord(Map<String, dynamic> record) async {
    final prefs = await SharedPreferences.getInstance();
    // Background FCM callbacks run in a separate isolate. Reload before the
    // read/modify/write cycle so this isolate does not rely on a stale cache.
    await prefs.reload();
    final raw = prefs.getString(_notificationHistoryKey);
    final records = <Map<String, dynamic>>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) records.add(Map<String, dynamic>.from(item));
          }
        }
      } catch (_) {}
    }
    final id = (record['id'] ?? '').toString();
    if (id.isNotEmpty && records.any((item) => (item['id'] ?? '').toString() == id)) return;
    records.insert(0, Map<String, dynamic>.from(record));
    if (records.length > _maxNotificationHistoryRecords) {
      records.removeRange(_maxNotificationHistoryRecords, records.length);
    }
    await prefs.setString(_notificationHistoryKey, jsonEncode(records));
  }

  static Future<List<Map<String, dynamic>>> loadNotificationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_notificationHistoryKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  static Future<void> saveNotificationHistory(List<Map<String, dynamic>> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_notificationHistoryKey, jsonEncode(records));
  }

  static Future<void> clearNotificationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_notificationHistoryKey);
  }

  static Future<void> markNotificationRead(String id) async {
    if (id.trim().isEmpty) return;
    final records = await loadNotificationHistory();
    for (final record in records) {
      if ((record['id'] ?? '').toString() == id) record['read'] = true;
    }
    await saveNotificationHistory(records);
  }

  /// Synchronizes the bounded local inbox with the authenticated WordPress account.
  /// Server-side merge preserves notifications across reinstallations and devices.
  Future<List<Map<String, dynamic>>> syncNotificationHistory(String bearerToken, {List<String> deletedIds = const <String>[]}) async {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final local = await loadNotificationHistory();
    final response = await _httpClient.post(
      Uri.parse('$base/wp-json/pcwork/v1/notifications/history'),
      headers: {'Authorization': 'Bearer $bearerToken', 'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({'records': local, 'deleted_ids': deletedIds}),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Notification history sync failed (HTTP ${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! List) throw Exception('Invalid notification history response.');
    final records = data.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    await saveNotificationHistory(records);
    return records;
  }

  static Future<void> initialize() async {
    if (_initialized || !DefaultFirebaseOptions.isConfigured) return;
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(pcworkFirebaseBackgroundHandler);
    _initialized = true;
  }

  /// Requests the operating-system notification permission independently
  /// of account login. Token registration is deferred until a user session exists.
  Future<bool> requestPermission() async {
    try {
      if (Platform.isAndroid) {
        // Native Android runtime request is deliberately independent from Firebase
        // initialization, so POST_NOTIFICATIONS is still requested on first launch.
        final granted = await _androidNotificationChannel.invokeMethod<bool>('requestNotificationPermission');
        if (granted != true) return false;
      }
      if (!DefaultFirebaseOptions.isConfigured) return Platform.isAndroid;
      await initialize();
      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);
      var settings = await messaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        settings = await messaging.requestPermission(
          alert: true, badge: true, sound: true, provisional: false,
        );
      }
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      // Fall back to Firebase's permission implementation if the native bridge
      // is unavailable (for example on an older development build).
      if (!DefaultFirebaseOptions.isConfigured) return false;
      try {
        await initialize();
        final settings = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true, provisional: false);
        return settings.authorizationStatus == AuthorizationStatus.authorized || settings.authorizationStatus == AuthorizationStatus.provisional;
      } catch (_) { return false; }
    }
  }

  /// Register a first-run No Reg installation. Marketing consent is explicit
  /// and independent from the operating-system notification permission.
  Future<bool> registerAnonymous({required bool marketingOptIn}) async {
    if (!DefaultFirebaseOptions.isConfigured) return false;
    try {
      await initialize();
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      final allowed = settings.authorizationStatus == AuthorizationStatus.authorized || settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!allowed) return false;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return false;
      final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
      final response = await _httpClient.post(Uri.parse('$base/wp-json/pcwork/v1/push/anonymous/register'),
        headers: {'Content-Type':'application/json','Accept':'application/json'},
        body: jsonEncode({'token':token,'platform':Platform.isIOS ? 'ios' : 'android','marketing_opt_in':marketingOptIn}),
      ).timeout(const Duration(seconds:15));
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['registered'] != true) return false;
      await _tokenSubscription?.cancel();
      _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((fresh) async {
        try {
          await _httpClient.post(Uri.parse('$base/wp-json/pcwork/v1/push/anonymous/register'),
            headers: {'Content-Type':'application/json'},
            body: jsonEncode({'token':fresh,'platform':Platform.isIOS ? 'ios' : 'android','marketing_opt_in':marketingOptIn}),
          ).timeout(const Duration(seconds:15));
        } catch (_) {}
      });
      return true;
    } catch (_) { return false; }
  }

  Future<bool> register(String bearerToken,
      {required void Function(String title, String body, Map<String, dynamic> data) onForeground,
      required void Function(Map<String, dynamic> data) onOpened}) async {
    if (!DefaultFirebaseOptions.isConfigured) return false;
    try {
      _activeBearerToken = bearerToken;
      if (!await requestPermission()) return false;
      await initialize();
      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);
      if (Platform.isIOS) {
        await messaging.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
      }
      _androidNotificationChannel.setMethodCallHandler((call) async {
        if (call.method == 'onNotificationTapped' && call.arguments is Map) {
          onOpened(Map<String, dynamic>.from(call.arguments as Map));
        }
      });
      final permission = await messaging.getNotificationSettings();
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
      _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) async {
        String storedNotificationId = '';
        try { storedNotificationId = await storeNotification(message); } catch (_) { /* Keep live delivery available if local history fails. */ }
        final foregroundData = Map<String, dynamic>.from(message.data);
        foregroundDataEvents.add(foregroundData);
        foregroundData['_notification_id'] = storedNotificationId.isNotEmpty
            ? storedNotificationId
            : (message.messageId ?? foregroundData['notification_id'] ?? foregroundData['id'] ?? '');
        onForeground(
          message.notification?.title ?? 'PCWork',
          message.notification?.body ?? 'Имате ново известие от PCWork.',
          foregroundData,
        );
      });
      await _openedSubscription?.cancel();
      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _dispatchOpenedMessage(message, onOpened);
      });
      final initial = await messaging.getInitialMessage();
      if (initial != null) _dispatchOpenedMessage(initial, onOpened);
      if (Platform.isAndroid) {
        try {
          final pending = await _androidNotificationChannel.invokeMapMethod<String, dynamic>('getPendingNotification');
          if (pending != null && pending.isNotEmpty) onOpened(Map<String, dynamic>.from(pending));
        } catch (_) {}
      }
      return true;
    } catch (_) {
      // Missing Firebase/APNs configuration must not block login or app use.
      return false;
    }
  }


  void _dispatchOpenedMessage(RemoteMessage message, void Function(Map<String, dynamic>) onOpened) {
    final data = Map<String, dynamic>.from(message.data);
    data['_notification_id'] = data['notification_id'] ?? data['id'] ?? message.messageId ?? '';
    final title = message.notification?.title ?? '';
    final body = message.notification?.body ?? '';
    if (title.isNotEmpty) data['_notification_title'] = title;
    if (body.isNotEmpty) data['_notification_body'] = body;
    // The OS launches the activity before Flutter has completed its first frame.
    // Defer routing/display so the initial notification is not lost during startup.
    unawaited(() async {
      // Persist the tapped message before the UI refreshes its history/badge.
      try {
        final storedId = await storeNotification(message);
        if ((data['_notification_id'] ?? '').toString().isEmpty) data['_notification_id'] = storedId;
      } catch (_) {}
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 650));
      onOpened(data);
    }());
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
    final response = await _httpClient.post(Uri.parse('$base/wp-json/pcwork/v1/push/status'),
      headers: {'Authorization':'Bearer $bearerToken','Content-Type':'application/json'},
      body: jsonEncode({'token': token ?? '', 'platform': Platform.isIOS ? 'ios' : 'android'})).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('HTTP ${response.statusCode}');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw Exception('Невалиден отговор за статуса на известията.');
    return {...Map<String, dynamic>.from(decoded), 'permission': permission, 'token_available': token != null && token.isNotEmpty};
  }

  Future<bool> getMarketingConsent(String bearerToken) async {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await _httpClient.get(Uri.parse('$base/wp-json/pcwork/v1/push/preferences'), headers: {'Authorization':'Bearer $bearerToken'}).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('HTTP ${response.statusCode}');
    final decoded = jsonDecode(response.body);
    return decoded is Map && decoded['marketing_opt_in'] == true;
  }

  Future<void> setMarketingConsent(String bearerToken, bool enabled) async {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await _httpClient.post(Uri.parse('$base/wp-json/pcwork/v1/push/preferences'), headers: {'Authorization':'Bearer $bearerToken','Content-Type':'application/json'}, body: jsonEncode({'marketing_opt_in':enabled})).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('HTTP ${response.statusCode}');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['saved'] != true) throw Exception('Server did not confirm the preference.');
  }

  Future<void> _sendToken(String bearerToken, String token, String action) async {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final platform = Platform.isIOS ? 'ios' : 'android';
    final response = await _httpClient.post(
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
