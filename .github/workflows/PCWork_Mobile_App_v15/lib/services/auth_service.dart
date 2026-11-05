import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthUser {
  const AuthUser({required this.id, required this.name, required this.email, this.roles = const []});
  final int id;
  final String name;
  final String email;
  final List<String> roles;
  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
    id: (j['id'] as num).toInt(), name: (j['name'] ?? '').toString(),
    email: (j['email'] ?? '').toString(), roles: (j['roles'] as List? ?? []).map((e) => e.toString()).toList());
}

class AuthService {
  AuthService({required this.baseUrl});
  final String baseUrl;
  static const _storage = FlutterSecureStorage();
  Uri _uri(String p) => Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/wp-json/pcwork/v1/$p');
  Future<String?> get token => _storage.read(key: 'pcwork_access_token');
  Future<void> logout() => _storage.delete(key: 'pcwork_access_token');
  Future<AuthUser> login(String email, String password) => _send('auth/login', {'email': email, 'password': password});
  Future<AuthUser> register(String name, String email, String password) => _send('auth/register', {'name': name, 'email': email, 'password': password});
  Future<AuthUser> _send(String path, Map<String, dynamic> body) async {
    final r = await http.post(_uri(path), headers: {'Content-Type':'application/json'}, body: jsonEncode(body)).timeout(const Duration(seconds: 20));
    final data = jsonDecode(r.body);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      final message = data is Map ? (data['message'] ?? 'HTTP ${r.statusCode}') : 'HTTP ${r.statusCode}';
      throw Exception(message);
    }
    final payload = data is Map && data['data'] is Map ? data['data'] as Map : data as Map;
    final t = payload['token'];
    if (t is! String || t.isEmpty) throw Exception('Сървърът не върна токен за достъп.');
    await _storage.write(key: 'pcwork_access_token', value: t);
    return AuthUser.fromJson(Map<String,dynamic>.from(payload['user'] as Map));
  }
  Future<AuthUser> me() async {
    final t = await token; if (t == null) throw Exception('Няма активна сесия.');
    final r = await http.get(_uri('auth/me'), headers: {'Authorization':'Bearer $t'}).timeout(const Duration(seconds: 15));
    final data=jsonDecode(r.body);
    if (r.statusCode != 200) { await logout(); throw Exception(data is Map ? (data['message'] ?? 'Сесията изтече.') : 'Сесията изтече.'); }
    final payload=data is Map && data['data'] is Map ? data['data'] as Map : data as Map;
    return AuthUser.fromJson(Map<String,dynamic>.from(payload));
  }
}
