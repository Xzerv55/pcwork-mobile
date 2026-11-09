import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.phone = '',
    this.billing = const {},
    this.shipping = const {},
    this.roles = const [],
  });

  final int id;
  final String name;
  final String email;
  final String phone;
  final Map<String, dynamic> billing;
  final Map<String, dynamic> shipping;
  final List<String> roles;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final rawRoles = json['roles'];
    final roles = rawRoles is List
        ? rawRoles.map((value) => value.toString()).toList()
        : <String>[];
    final rawId = json['id'];
    final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId') ?? 0;
    if (id <= 0) {
      throw const FormatException('Сървърът върна невалиден потребителски профил.');
    }
    return AuthUser(
      id: id,
      name: (json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      billing: json['billing'] is Map ? Map<String, dynamic>.from(json['billing']) : const {},
      shipping: json['shipping'] is Map ? Map<String, dynamic>.from(json['shipping']) : const {},
      roles: roles,
    );
  }
}

class AuthService {
  AuthService({required this.baseUrl});

  final String baseUrl;
  // Reuse a process-wide client to keep HTTP connections alive between API calls.
  static final http.Client _httpClient = http.Client();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _tokenKey = 'pcwork_access_token';
  static const String _cachedUserKey = 'pcwork_cached_user_profile';

  Uri _uri(String path) {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$base/wp-json/pcwork/v1/$path');
    if (uri == null || uri.host.isEmpty || uri.scheme != 'https') {
      throw const FormatException(
        'Входът изисква валиден HTTPS адрес на PCWork сайта.',
      );
    }
    return uri;
  }

  Future<String?> get token => _storage.read(key: _tokenKey);

  Future<void> logout() async {
    final bearer = await _storage.read(key: _tokenKey);
    if (bearer != null && bearer.isNotEmpty) {
      try {
        await _httpClient.post(_uri('auth/revoke-sessions'), headers: {'Authorization': 'Bearer $bearer', 'Accept': 'application/json'}).timeout(const Duration(seconds: 8));
      } catch (_) { /* Local logout must still complete when the server is offline. */ }
    }
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _cachedUserKey);
  }

  Future<String> requestCode({
    required bool register,
    required String email,
    String name = '',
    String phone = '',
    bool dataCollectionOptIn = false,
    bool loyaltyOptIn = false,
    bool marketingOptIn = false,
    bool pushOptIn = false,
    bool viberOptIn = false,
  }) async {
    final path = register ? 'auth/register/request' : 'auth/login/request';
    final body = <String, dynamic>{'email': email.trim()};
    if (register) {
      body['name'] = name.trim();
      body['phone'] = phone.trim();
      body['terms_accepted'] = true;
      body['data_collection_opt_in'] = dataCollectionOptIn;
      body['loyalty_opt_in'] = loyaltyOptIn;
      body['marketing_opt_in'] = marketingOptIn;
      body['push_opt_in'] = pushOptIn;
      body['viber_opt_in'] = viberOptIn;
    }
    late final http.Response response;
    try {
      response = await _httpClient.post(
        _uri(path),
        headers: const {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
          'Cache-Control': 'no-cache',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 25));
    } on Exception catch (error) {
      throw Exception('Неуспешна връзка с PCWork. Провери интернет връзката. ($error)');
    }
    final decoded = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(decoded, response.statusCode));
    }
    return (decoded['message'] ?? 'Изпратихме код на имейла ти.').toString();
  }

  Future<AuthUser> verifyCode({required bool register, required String email, required String code}) =>
      _sendOtp(register ? 'auth/register/verify' : 'auth/login/verify', {
        'email': email.trim(),
        'code': code.trim(),
      });

  /// Password login is accepted by WordPress only for accounts explicitly
  /// authorized by an administrator (or existing staff accounts).
  Future<AuthUser> loginWithPassword({required String identifier, required String password}) =>
      _sendOtp('auth/login', {'login': identifier.trim(), 'password': password});

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw const FormatException('Сървърът върна неочакван формат.');
    } on FormatException {
      throw FormatException(
        'PCWork сървърът върна невалиден отговор (HTTP ${response.statusCode}). '
        'Провери REST API адреса и WordPress плъгина.',
      );
    }
  }

  Map<String, dynamic> _payload(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return response;
  }

  String _message(Map<String, dynamic> response, int statusCode) {
    final message = response['message'] ?? response['error'];
    if (message != null && message.toString().trim().isNotEmpty) {
      return message.toString();
    }
    switch (statusCode) {
      case 401:
        return 'Невалиден код или имейл.';
      case 403:
        return 'Достъпът е отказан от WordPress.';
      case 404:
        return 'Липсва PCWork Auth API. Обнови WordPress плъгина.';
      case 429:
        return 'Твърде много опити за вход. Изчакай и опитай отново.';
      default:
        return 'Грешка при удостоверяване (HTTP $statusCode).';
    }
  }

  Future<AuthUser> _sendOtp(String path, Map<String, dynamic> body) async {
    late final http.Response response;
    try {
      response = await _httpClient.post(
        _uri(path),
        headers: const {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
          'Cache-Control': 'no-cache',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 25));
    } on Exception catch (error) {
      throw Exception('Неуспешна връзка с PCWork. Провери интернет връзката. ($error)');
    }
    final decoded = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(decoded, response.statusCode));
    }
    final payload = _payload(decoded);
    final accessToken = payload['token'];
    final userData = payload['user'];
    if (accessToken is! String || accessToken.isEmpty || userData is! Map) {
      throw const FormatException('WordPress не върна валиден токен и потребителски профил.');
    }
    final user = AuthUser.fromJson(Map<String, dynamic>.from(userData));
    await _storage.write(key: _tokenKey, value: accessToken);
    await _storage.write(key: _cachedUserKey, value: jsonEncode(userData));
    return user;
  }

  Future<AuthUser> updateProfile({required String name, required String phone, Map<String, String> billing = const {}, Map<String, String> shipping = const {}}) async {
    final accessToken = await token;
    if (accessToken == null || accessToken.isEmpty) throw const FormatException('Няма активна сесия. Влез отново.');
    final response = await _httpClient.patch(
      _uri('auth/profile'),
      headers: {'Authorization': 'Bearer $accessToken', 'Content-Type': 'application/json; charset=utf-8', 'Accept': 'application/json'},
      body: jsonEncode({'name': name.trim(), 'phone': phone.trim(), 'billing': billing, 'shipping': shipping}),
    ).timeout(const Duration(seconds: 20));
    final decoded = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(decoded, response.statusCode));
    final user = AuthUser.fromJson(_payload(decoded));
    await _storage.write(key: _cachedUserKey, value: jsonEncode(_payload(decoded)));
    return user;
  }

  Future<AuthUser> me() async {
    final accessToken = await token;
    if (accessToken == null || accessToken.isEmpty) {
      throw const FormatException('Няма активна сесия. Влез отново.');
    }

    try {
      final response = await _httpClient.get(
        _uri('auth/me'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 20));
      final decoded = _decode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401 || response.statusCode == 403) {
          await logout();
        }
        throw Exception(_message(decoded, response.statusCode));
      }
      final user = AuthUser.fromJson(_payload(decoded));
      await _storage.write(key: _cachedUserKey, value: jsonEncode(_payload(decoded)));
      return user;
    } on Exception catch (error) {
      final message = error.toString();
      final networkFailure = message.contains('SocketException') ||
          message.contains('TimeoutException') || message.contains('Failed host lookup') ||
          message.contains('ClientException') || message.contains('HandshakeException') ||
          message.contains('Connection reset') || message.contains('Network is unreachable');
      if (!networkFailure) rethrow;
      final cached = await _storage.read(key: _cachedUserKey);
      if (cached == null || cached.isEmpty) rethrow;
      return AuthUser.fromJson(Map<String, dynamic>.from(jsonDecode(cached) as Map));
    }
  }
}
