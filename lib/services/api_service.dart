import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Decodes JSON safely and reports useful errors when WordPress returns HTML,
/// an empty response, or a proxy/server error page.
dynamic _decodeResponse(http.Response response) {
  final body = response.body.trim();
  if (body.isEmpty) return <String, dynamic>{};
  try {
    return jsonDecode(body);
  } on FormatException {
    final preview = body.length > 180 ? '${body.substring(0, 180)}…' : body;
    throw Exception(
      'Сървърът върна невалиден JSON (HTTP ${response.statusCode}). '
      'Проверете WordPress API и дали сайтът не връща HTML грешка. '
      'Отговор: $preview',
    );
  }
}

String _responseMessage(dynamic decoded, int statusCode) {
  if (decoded is Map) {
    final value = decoded['message'] ?? decoded['error'];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }
  }
  return 'HTTP $statusCode';
}

class _TimedShopCache {
  const _TimedShopCache(this.expiresAt, this.rows);
  final DateTime expiresAt;
  final List<Map<String, dynamic>> rows;
}

class ApiService {
  ApiService({required this.baseUrl, this.userId = 0});
  final String baseUrl;
  final int userId;
  // Reuse a process-wide client to keep HTTP connections alive between API calls.
  static final http.Client _httpClient = http.Client();
  static const FlutterSecureStorage _offlineStorage = FlutterSecureStorage();
  static final Map<String, _TimedShopCache> _shopCache = <String, _TimedShopCache>{};

  List<Map<String, dynamic>> _copyShopRows(List<Map<String, dynamic>> rows) =>
      rows.map((row) => Map<String, dynamic>.from(row)).toList(growable: false);

  void _storeShopCache(String key, List<Map<String, dynamic>> rows, Duration ttl) {
    final now = DateTime.now();
    _shopCache.removeWhere((_, entry) => !entry.expiresAt.isAfter(now));
    if (_shopCache.length >= 40 && !_shopCache.containsKey(key)) {
      final oldestKey = _shopCache.entries.reduce((a, b) =>
          a.value.expiresAt.isBefore(b.value.expiresAt) ? a : b).key;
      _shopCache.remove(oldestKey);
    }
    _shopCache[key] = _TimedShopCache(now.add(ttl), rows);
  }

  String _scope(String token) => userId > 0 ? 'user_$userId' : crypto.sha256.convert(utf8.encode(token)).toString();
  String _repairsCacheKey(String token) => 'pcwork_v37_repairs_${_scope(token)}';
  String _locationsCacheKey() => 'pcwork_v37_locations_${crypto.sha256.convert(utf8.encode(baseUrl.trim()))}';
  String _queueKey(String token) => 'pcwork_v37_queue_${_scope(token)}';
  String createClientRequestId() => _newRequestId();

  String _newRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
  bool _isNetworkError(Object error) {
    final value = error.toString();
    return value.contains('SocketException') || value.contains('TimeoutException') ||
        value.contains('Failed host lookup') || value.contains('ClientException') ||
        value.contains('Connection reset') || value.contains('Connection timed out') ||
        value.contains('Network is unreachable') || value.contains('HandshakeException');
  }
  Future<List<Map<String, dynamic>>> _readQueue(String token) async {
    final raw = await _offlineStorage.read(key: _queueKey(token));
    if (raw == null || raw.isEmpty) return [];
    try { return (jsonDecode(raw) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(); }
    catch (_) { return []; }
  }
  Future<void> _writeQueue(String token, List<Map<String, dynamic>> queue) async {
    if (queue.isEmpty) { await _offlineStorage.delete(key: _queueKey(token)); return; }
    await _offlineStorage.write(key: _queueKey(token), value: jsonEncode(queue));
  }
  Future<int> pendingOperationCount(String token) async => (await _readQueue(token)).length;
  Future<void> clearOfflineData(String token) async {
    await _offlineStorage.delete(key: _repairsCacheKey(token));
    await _offlineStorage.delete(key: _queueKey(token));
  }

  Uri _uri(String path) {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base/wp-json/pcwork/v1/$path');
  }

  /// Public release manifest configured by a PCWork administrator in WordPress.
  /// Only HTTPS APK links are accepted by the app before they are opened.
  Future<Map<String, dynamic>?> getAppUpdateInfo() async {
    final response = await _httpClient.get(_uri('app/update'), headers: const {'Accept': 'application/json'}).timeout(const Duration(seconds: 12));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(_responseMessage(decoded, response.statusCode));
    final data = decoded is Map ? (decoded['data'] ?? decoded) : null;
    if (data is! Map || data['enabled'] != true) return null;
    final url = Uri.tryParse((data['apk_url'] ?? '').toString());
    if (url == null || url.scheme != 'https' || url.host.isEmpty) return null;
    return Map<String, dynamic>.from(data);
  }

  Future<String> downloadAndVerifyUpdate(Map<String, dynamic> info) async {
    final url = Uri.tryParse((info['apk_url'] ?? '').toString());
    if (url == null || url.scheme != 'https' || url.host != 'pcwork-bg.com' && url.host != 'www.pcwork-bg.com') {
      throw Exception('Невалиден HTTPS адрес за актуализация.');
    }
    final expected = (info['sha256'] ?? '').toString().toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) {
      throw Exception('Липсва валидна SHA-256 контролна сума в update.json.');
    }
    final response = await _httpClient.get(url).timeout(const Duration(minutes: 4));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) throw Exception('Изтеглянето на актуализацията е неуспешно (HTTP ${response.statusCode}).');
    final actual = crypto.sha256.convert(response.bodyBytes).toString();
    if (actual != expected) throw Exception('Проверката за цялост на APK файла е неуспешна.');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/pcwork-mobile-update.apk');
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file.path;
  }

  Future<List<Map<String, dynamic>>> getShopProducts({String search = '', int categoryId = 0}) async {
    final cacheKey = '${baseUrl.trim()}:products:$categoryId:${search.trim().toLowerCase()}';
    final cached = _shopCache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) return _copyShopRows(cached.rows);
    final params = <String, String>{'per_page': '20'};
    if (search.isNotEmpty) params['search'] = search;
    if (categoryId > 0) params['category'] = '$categoryId';
    final response = await _httpClient.get(_uri('shop/products').replace(queryParameters: params)).timeout(const Duration(seconds: 15));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
    final result = rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
    _storeShopCache(cacheKey, result, const Duration(seconds: 45));
    return _copyShopRows(result);
  }

  Future<List<Map<String, dynamic>>> getShopProductVariations(int productId) async {
    final response = await _httpClient.get(_uri('shop/products/$productId/variations')).timeout(const Duration(seconds: 15));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    }
    final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
    return rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }

  Future<List<Map<String, dynamic>>> getShopCategories() async {
    final cacheKey = '${baseUrl.trim()}:categories';
    final cached = _shopCache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) return _copyShopRows(cached.rows);
    final response = await _httpClient.get(_uri('shop/categories')).timeout(const Duration(seconds: 12));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
    final result = rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
    _storeShopCache(cacheKey, result, const Duration(minutes: 10));
    return _copyShopRows(result);
  }

  Future<List<Map<String, dynamic>>> getShopShippingRates(String token, {required List<Map<String, dynamic>> items, required Map<String, dynamic> shipping}) async {
    final response = await _httpClient.post(_uri('shop/shipping-rates'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode({'items': items, 'shipping': shipping})).timeout(const Duration(seconds: 30));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
    return rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> createShopOrder(String token, {required List<Map<String, dynamic>> items, required Map<String, dynamic> billing, required Map<String, dynamic> shipping, String? shippingRateId}) async {
    final response = await _httpClient.post(_uri('shop/orders'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({'items': items, 'billing': billing, 'shipping': shipping, 'shipping_rate_id': shippingRateId})).timeout(const Duration(seconds: 35));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    if (data is! Map) throw Exception('Невалиден отговор при създаване на поръчка.');
    return Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> getShopOrders(String token) async {
    final response = await _httpClient.get(_uri('shop/orders'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 25));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
    return rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }

  Future<Map<String, dynamic>> getShopOrder(String token, int id) async {
    final response = await _httpClient.get(_uri('shop/orders/$id'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 25));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    if (data is! Map) throw Exception('Невалидни подробности за поръчката.');
    return Map<String, dynamic>.from(data);
  }

  Future<void> openExternal(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || !['https', 'http'].contains(uri.scheme)) throw Exception('Невалиден адрес за плащане.');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) throw Exception('Неуспешно отваряне на страницата за плащане.');
  }

  Future<bool> checkHealth() async {
    final response = await _httpClient.get(_uri('health')).timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('API върна HTTP ${response.statusCode}');
    }
    return true;
  }

  Future<List<ServiceLocation>> getLocations() async {
    try {
      final response = await _httpClient.get(_uri('locations'), headers: const {'Accept': 'application/json', 'Cache-Control': 'no-cache'}).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) throw Exception('Грешка при зареждане на обектите (HTTP ${response.statusCode})');
      final decoded = _decodeResponse(response);
      final dynamic rows = decoded is List ? decoded : (decoded is Map ? (decoded['data'] ?? decoded['locations'] ?? decoded['items']) : null);
      if (rows is! List) throw Exception('Сървърът върна неочакван формат за сервизните обекти.');
      final result = rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
      if (result.isEmpty) return _fallbackLocations();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_locationsCacheKey(), jsonEncode(result));
      return result.map(ServiceLocation.fromJson).toList();
    } catch (error) {
      // The service directory is public and has a built-in fallback so that
      // customers can still view the agreed nine locations during API outages.
      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString(_locationsCacheKey());
        if (cached != null && cached.isNotEmpty) {
          final rows = jsonDecode(cached) as List;
          final locations = rows.whereType<Map>().map((row) => ServiceLocation.fromJson(Map<String, dynamic>.from(row))).toList();
          if (locations.isNotEmpty) return locations;
        }
      } catch (_) { /* Use the static directory below. */ }
      return _fallbackLocations();
    }
  }

  List<ServiceLocation> _fallbackLocations() => const [
    ServiceLocation(name: 'София, Люлин - 5', code: 'sofia-lyulin', address: 'гр. София, Люлин - 5', description: 'PS4 и PS5', hours: 'Понеделник – Неделя · 09:00–21:00', mapsUrl: 'https://www.google.com/maps/search/?api=1&query=София%20Люлин%205'),
    ServiceLocation(name: 'София, Люлин - 2', code: 'sofia-lyulin-2', address: 'гр. София, Люлин - 2', description: 'Изграждане AI системи', hours: 'Понеделник – Неделя · 09:00–21:00', mapsUrl: 'https://www.google.com/maps/search/?api=1&query=София%20Люлин%202'),
    ServiceLocation(name: 'София, Симеоновско шосе', code: 'sofia-simeonovsko', address: 'гр. София, Симеоновско шосе', description: 'Изграждане AI системи', hours: 'Понеделник – Неделя · 09:00–21:00', mapsUrl: 'https://www.google.com/maps/search/?api=1&query=София%20Симеоновско%20шосе'),
    ServiceLocation(name: 'София, Индустриална 11', code: 'sofia-industrialna-11', address: 'гр. София, Индустриална 11', description: 'Изграждане AI системи', hours: 'Понеделник – Неделя · 09:00–21:00', mapsUrl: 'https://www.google.com/maps/search/?api=1&query=София%20Индустриална%2011'),
    ServiceLocation(name: 'Варна, Център', code: 'varna-center', address: 'гр. Варна, Център', description: 'Предстоящо откриване', availability: 'upcoming', availabilityLabel: 'Предстоящо откриване', isUpcoming: true, canSelect: false),
    ServiceLocation(name: 'Бургас, Център', code: 'burgas-center', address: 'гр. Бургас, Център', description: 'Предстоящо откриване', availability: 'upcoming', availabilityLabel: 'Предстоящо откриване', isUpcoming: true, canSelect: false),
    ServiceLocation(name: 'Пловдив, Велико Търново', code: 'plovdiv-veliko-tarnovo', address: 'Пловдив, Велико Търново', description: 'Предстоящо откриване', availability: 'upcoming', availabilityLabel: 'Предстоящо откриване', isUpcoming: true, canSelect: false),
    ServiceLocation(name: 'Пловдив, Център', code: 'plovdiv-center', address: 'гр. Пловдив, Център', description: 'Предстоящо откриване', availability: 'upcoming', availabilityLabel: 'Предстоящо откриване', isUpcoming: true, canSelect: false),
    ServiceLocation(name: 'Шумен, Център', code: 'shumen-center', address: 'гр. Шумен, Център', description: 'Предстоящо откриване', availability: 'upcoming', availabilityLabel: 'Предстоящо откриване', isUpcoming: true, canSelect: false),
  ];


  Future<List<Repair>> getRepairs(String token) async {
    try {
      final response = await _httpClient.get(_uri('repairs'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
      final decoded = _decodeResponse(response);
      if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
      final rows = decoded is Map ? (decoded['data'] ?? decoded['repairs'] ?? decoded['items'] ?? []) : decoded;
      if (rows is! List) throw Exception('Невалиден формат на списъка с ремонти.');
      final normalized = rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      await _offlineStorage.write(key: _repairsCacheKey(token), value: jsonEncode(normalized));
      return normalized.map(Repair.fromJson).toList();
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      final cached = await _offlineStorage.read(key: _repairsCacheKey(token));
      if (cached == null) rethrow;
      final rows = jsonDecode(cached) as List;
      return rows.whereType<Map>().map((e) => Repair.fromJson({...Map<String, dynamic>.from(e), '_offline_cached': true})).toList();
    }
  }


  Future<Repair> updateRepairStatus(String token, int id, String status, {String note = ''}) async {
    final requestId = _newRequestId();
    final payload = {'status': status, 'note': note, 'client_request_id': requestId};
    try {
      final response = await _httpClient.patch(_uri('repairs/$id/status'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode(payload)).timeout(const Duration(seconds: 20));
      final decoded = _decodeResponse(response);
      if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
      final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
      if (data is! Map) throw Exception('Невалиден отговор при промяна на статуса.');
      return Repair.fromJson(Map<String, dynamic>.from(data));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      final queue = await _readQueue(token);
      queue.add({'type': 'status', 'request_id': requestId, 'repair_id': id, ...payload});
      await _writeQueue(token, queue);
      final raw = await _offlineStorage.read(key: _repairsCacheKey(token));
      if (raw != null) {
        try {
          final rows = (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          for (var i = 0; i < rows.length; i++) {
            if ((rows[i]['id'] as num?)?.toInt() == id) rows[i] = {...rows[i], 'status': status, '_pending_sync': true};
          }
          await _offlineStorage.write(key: _repairsCacheKey(token), value: jsonEncode(rows));
        } catch (_) {}
      }
      return Repair.fromJson({'id': id, 'repair_number': '', 'status': status, '_pending_sync': true});
    }
  }

  Future<int> syncPendingOperations(String token) async {
    final queue = await _readQueue(token);
    if (queue.isEmpty) return 0;
    var completed = 0;
    final remaining = <Map<String, dynamic>>[];
    for (final operation in queue) {
      try {
        if (operation['type'] == 'create') {
          final payload = Map<String, dynamic>.from(operation['payload'] as Map);
          payload['client_request_id'] = operation['request_id'];
          final response = await _httpClient.post(_uri('repairs'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode(payload)).timeout(const Duration(seconds: 25));
          if (response.statusCode != 200 && response.statusCode != 201) throw Exception('HTTP ${response.statusCode}');
        } else if (operation['type'] == 'status') {
          final id = (operation['repair_id'] as num).toInt();
          final payload = {'status': operation['status'], 'note': operation['note'], 'client_request_id': operation['request_id']};
          final response = await _httpClient.patch(_uri('repairs/$id/status'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode(payload)).timeout(const Duration(seconds: 20));
          if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
        } else {
          remaining.add(operation);
          continue;
        }
        completed++;
      } catch (_) { remaining.add(operation); }
    }
    await _writeQueue(token, remaining);
    return completed;
  }


  Future<List<Map<String, dynamic>>> getStockItems(String token) async {
    final response = await _httpClient.get(_uri('stock'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
    return rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }

  Future<void> createStockItem(String token, Map<String, dynamic> item) async {
    final response = await _httpClient.post(_uri('stock'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode(item)).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 201 && response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
  }

  Future<void> updateStockItem(String token, int id, Map<String, dynamic> item) async {
    final response = await _httpClient.patch(_uri('stock/$id'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode(item)).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
  }

  Future<void> moveStockItem(String token, int id, {required String type, required double quantity, String note = ''}) async {
    final response = await _httpClient.post(_uri('stock/$id/movement'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({'type': type, 'quantity': quantity, 'note': note})).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
  }

  Future<List<Map<String, dynamic>>> getTechnicians(String token, String locationCode) async {
    final uri = _uri('staff/technicians').replace(queryParameters: {'location_code': locationCode});
    final response = await _httpClient.get(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) {
      final message = decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}';
      throw Exception(message);
    }
    final rows = decoded is Map ? (decoded['data'] ?? decoded['technicians'] ?? []) : [];
    if (rows is! List) return [];
    return rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<int, Map<String, dynamic>>> getTechnicianSchedules(String token) async {
    final response = await _httpClient.get(_uri('staff/schedule'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) {
      final message = decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}';
      throw Exception(message);
    }
    final rows = decoded is Map ? (decoded['data'] ?? {}) : {};
    if (rows is! Map) return {};
    return rows.map((key, value) => MapEntry(int.tryParse(key.toString()) ?? 0, value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{}));
  }

  Future<void> saveTechnicianSchedule(String token, int technicianId, Map<String, dynamic> schedule) async {
    final response = await _httpClient.post(_uri('staff/schedule'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'technician_id': technicianId, 'schedule': schedule})).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) {
      final message = decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}';
      throw Exception(message);
    }
  }

  Future<Map<String, dynamic>> getStaffOverview(String token) async {
    final response = await _httpClient.get(_uri('staff/overview'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    if (data is! Map) throw Exception('Невалиден формат на служебната статистика.');
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> getAttendance(String token) async {
    final response = await _httpClient.get(_uri('staff/attendance'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<void> recordAttendance(String token, String action) async {
    final response = await _httpClient.post(_uri('staff/attendance'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({'action': action})).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
  }

  Future<List<Map<String, dynamic>>> getLeaveRequests(String token) async {
    final response = await _httpClient.get(_uri('staff/leave'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
    return rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }

  Future<void> submitLeaveRequest(String token, {required String startDate, required String endDate, required String reason}) async {
    final response = await _httpClient.post(_uri('staff/leave'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({'start_date': startDate, 'end_date': endDate, 'reason': reason})).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
  }

  Future<void> reviewLeaveRequest(String token, int id, String decision) async {
    final response = await _httpClient.patch(_uri('staff/leave/$id'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({'status': decision})).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
  }

  Future<Repair> updateRepairAssignment(String token, int id, {required int technicianId, required String priority, String dueAt = ''}) async {
    final response = await _httpClient.patch(_uri('repairs/$id/assignment'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'assigned_technician_id': technicianId, 'priority': priority, 'due_at': dueAt})).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) {
      final message = decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}';
      throw Exception(message);
    }
    final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    if (data is! Map) throw Exception('Невалиден отговор при разпределяне на ремонта.');
    return Repair.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Map<String, dynamic>> getRepairWorklog(String token, int repairId) async {
    final response = await _httpClient.get(_uri('repairs/$repairId/worklog'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? (decoded['data'] ?? []) : [];
    final summary = decoded is Map && decoded['summary'] is Map ? Map<String, dynamic>.from(decoded['summary']) : <String, dynamic>{};
    final entries = data is List ? data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
    return {'entries': entries, 'summary': summary};
  }

  Future<Map<String, dynamic>> addRepairWorklogEntry(String token, int repairId, Map<String, dynamic> entry) async {
    final response = await _httpClient.post(_uri('repairs/$repairId/worklog'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode(entry)).timeout(const Duration(seconds: 25));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    if (data is! Map) throw Exception('Невалиден отговор при записване в сервизния дневник.');
    return Map<String, dynamic>.from(data);
  }

  Future<Repair> getRepair(String token, int id) async {
    try {
      final response = await _httpClient.get(_uri('repairs/$id'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
      final decoded = _decodeResponse(response);
      if (response.statusCode != 200) {
        final message = decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}';
        throw Exception(message);
      }
      final data = decoded is Map ? (decoded['data'] ?? decoded['repair'] ?? decoded) : decoded;
      if (data is! Map) throw Exception('Невалиден формат на ремонта.');
      final normalized = Map<String, dynamic>.from(data);
      final cached = await _offlineStorage.read(key: _repairsCacheKey(token));
      if (cached != null) {
        try {
          final rows = (jsonDecode(cached) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final index = rows.indexWhere((row) => (row['id'] as num?)?.toInt() == id);
          if (index >= 0) {
            rows[index] = normalized;
            await _offlineStorage.write(key: _repairsCacheKey(token), value: jsonEncode(rows));
          }
        } catch (_) {}
      }
      return Repair.fromJson(normalized);
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      final cached = await _offlineStorage.read(key: _repairsCacheKey(token));
      if (cached == null) rethrow;
      final rows = jsonDecode(cached) as List;
      for (final item in rows.whereType<Map>()) {
        if ((item['id'] as num?)?.toInt() == id) {
          return Repair.fromJson({...Map<String, dynamic>.from(item), '_offline_cached': true});
        }
      }
      rethrow;
    }
  }


  Future<Map<String, dynamic>> createCustomerRepairRequest(String token, Map<String, dynamic> payload, {String? clientRequestId}) async {
    final requestId = clientRequestId ?? _newRequestId();
    final body = jsonEncode({...payload, 'client_request_id': requestId});
    Future<Map<String, dynamic>> sendOnce() async {
      final response = await _httpClient.post(
        _uri('repairs/request'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 15));
      final decoded = _decodeResponse(response);
      if (response.statusCode != 201 && response.statusCode != 200) {
        throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
      }
      final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
      if (data is! Map) throw Exception('Сървърът върна невалиден отговор за заявката.');
      return Map<String, dynamic>.from(data);
    }
    try {
      return await sendOnce();
    } catch (error) {
      // A timeout may happen after WordPress has committed the repair. Retry
      // once with the SAME idempotency key so the server returns the original
      // record instead of creating a duplicate.
      if (error is TimeoutException || _isNetworkError(error)) return await sendOnce();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createRepair(String token, Map<String, dynamic> payload) async {
    final requestId = _newRequestId();
    final request = {...payload, 'client_request_id': requestId};
    try {
      final response = await _httpClient.post(_uri('repairs'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode(request)).timeout(const Duration(seconds: 25));
      final decoded = _decodeResponse(response);
      if (response.statusCode != 201 && response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
      final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
      if (data is! Map) throw Exception('Сървърът върна невалиден протокол.');
      return Map<String, dynamic>.from(data);
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      final queue = await _readQueue(token);
      queue.add({'type': 'create', 'request_id': requestId, 'payload': payload});
      await _writeQueue(token, queue);
      return {'queued': true, 'client_request_id': requestId, 'message': 'Записано локално и чака синхронизация.'};
    }
  }


  Future<Map<String, dynamic>> getChatMessages(String token, {int afterId = 0}) async {
    final response = await _httpClient.get(
      _uri('chat/messages').replace(queryParameters: {'after_id': '$afterId'}),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 15));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(_responseMessage(decoded, response.statusCode));
    final data = decoded is Map && decoded['data'] is Map ? decoded['data'] as Map : decoded;
    if (data is! Map) throw Exception('Невалиден отговор от чата.');
    return Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> getAdminChatThreads(String token) async {
    final response = await _httpClient.get(_uri('chat/admin/threads'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 15));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(_responseMessage(decoded, response.statusCode));
    final data = decoded is Map ? decoded['data'] : null;
    return data is List ? data.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList() : <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> getAdminChatMessages(String token, int userId, {int afterId = 0}) async {
    final uri = _uri('chat/admin/messages').replace(queryParameters: {'user_id': '$userId', 'after_id': '$afterId'});
    final response = await _httpClient.get(uri, headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 15));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(_responseMessage(decoded, response.statusCode));
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! Map) throw Exception('Невалиден отговор от административния чат.');
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> getAdminChatContext(String token, int userId) async {
    final uri = _uri('chat/admin/context').replace(queryParameters: {'user_id': '$userId'});
    final response = await _httpClient.get(uri, headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 15));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(_responseMessage(decoded, response.statusCode));
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! Map) throw Exception('Невалиден отговор за данните на клиента.');
    return Map<String, dynamic>.from(data);
  }

  Future<void> sendAdminChatMessage(String token, int userId, String message) async {
    final response = await _httpClient.post(_uri('chat/admin/messages'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({'user_id': userId, 'message': message})).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception(_responseMessage(decoded, response.statusCode));
  }

  Future<void> sendChatMessage(String token, {String message = '', String? imageBase64, String? imageMime}) async {
    final payload = <String, dynamic>{'message': message};
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      payload['image_base64'] = imageBase64;
      payload['image_mime'] = imageMime ?? 'image/jpeg';
    }
    final response = await _httpClient.post(
      _uri('chat/messages'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 30));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_responseMessage(decoded, response.statusCode));
    }
  }

  Future<Uri?> getBookingUrl() async {
    final response = await _httpClient.get(_uri('booking/config')).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final decoded = _decodeResponse(response);
    if (decoded is! Map) return null;
    final data = decoded['data'] is Map ? decoded['data'] as Map : decoded;
    final enabled = data['enabled'] ?? data['active'] ?? data['bookly_enabled'];
    final raw = data['booking_url'] ?? data['url'] ?? data['page_url'];
    if (enabled == false || raw is! String || raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') ? uri : null;
  }
}

class ServiceLocation {
  const ServiceLocation({
    required this.name,
    this.code = '',
    this.address = '',
    this.phone = '',
    this.imageUrl = '',
    this.imageCaption = '',
    this.hours = '',
    this.mapsUrl = '',
    this.websiteUrl = '',
    this.description = '',
    this.availability = 'listed',
    this.availabilityLabel = '',
    this.isUpcoming = false,
    this.canSelect = true,
  });
  final String name;
  final String code;
  final String address;
  final String phone;
  final String imageUrl;
  final String imageCaption;
  final String hours;
  final String mapsUrl;
  final String websiteUrl;
  final String description;
  final String availability;
  final String availabilityLabel;
  final bool isUpcoming;
  final bool canSelect;

  factory ServiceLocation.fromJson(Map<String, dynamic> json) => ServiceLocation(
    name: (json['name'] ?? json['title'] ?? json['location_name'] ?? 'Сервизен обект').toString(),
    code: (json['code'] ?? json['location_code'] ?? '').toString(),
    address: (json['address'] ?? '').toString(),
    phone: (json['phone'] ?? '').toString(),
    imageUrl: (json['image_url'] ?? json['image'] ?? '').toString(),
    imageCaption: (json['image_caption'] ?? '').toString(),
    hours: (json['hours'] ?? '').toString(),
    mapsUrl: (json['maps_url'] ?? '').toString(),
    websiteUrl: (json['website_url'] ?? '').toString(),
    description: (json['description'] ?? '').toString(),
    availability: (json['availability'] ?? 'listed').toString(),
    availabilityLabel: (json['availability_label'] ?? '').toString(),
    isUpcoming: json['is_upcoming'] == true,
    canSelect: json['can_select'] != false,
  );
}


class Repair {
  const Repair({required this.id, required this.number, required this.status, this.device = '', this.model = '', this.location = '', this.createdAt = '', this.updatedAt = '', this.problem = '', this.phone = '', this.serial = '', this.customer = '', this.locationCode = '', this.technicianId = 0, this.technicianName = '', this.priority = 'normal', this.dueAt = '', this.history = const [], this.pendingSync = false, this.fromCache = false});
  final int id;
  final String number, status, device, model, location, createdAt, updatedAt, problem, phone, serial, customer, locationCode, technicianName, priority, dueAt;
  final int technicianId;
  final List<RepairHistory> history;
  final bool pendingSync;
  final bool fromCache;
  factory Repair.fromJson(Map<String, dynamic> j) => Repair(
    id: (j['id'] as num?)?.toInt() ?? 0,
    number: (j['repair_number'] ?? j['number'] ?? '').toString(),
    status: (j['status'] ?? 'received').toString(),
    device: (j['device_type'] ?? j['device'] ?? '').toString(),
    model: (j['device_model'] ?? j['model'] ?? '').toString(),
    location: (j['location_name'] ?? j['location'] ?? '').toString(),
    createdAt: (j['created_at'] ?? '').toString(), updatedAt: (j['updated_at'] ?? '').toString(),
    problem: (j['problem_description'] ?? j['problem'] ?? '').toString(),
    phone: (j['customer_phone'] ?? '').toString(), serial: (j['serial_number'] ?? '').toString(), customer: (j['customer_name'] ?? '').toString(),
    locationCode: (j['location_code'] ?? '').toString(), technicianId: (j['assigned_technician_id'] as num?)?.toInt() ?? 0, technicianName: (j['assigned_technician_name'] ?? '').toString(), priority: (j['priority'] ?? 'normal').toString(), dueAt: (j['due_at'] ?? '').toString(),
    history: (j['history'] as List? ?? []).whereType<Map>().map((e) => RepairHistory.fromJson(Map<String,dynamic>.from(e))).toList(),
    pendingSync: j['_pending_sync'] == true, fromCache: j['_offline_cached'] == true,
  );
}
class RepairHistory {
  const RepairHistory(this.status, this.note, this.createdAt);
  final String status, note, createdAt;
  factory RepairHistory.fromJson(Map<String,dynamic> j) => RepairHistory((j['status'] ?? '').toString(), (j['note'] ?? '').toString(), (j['created_at'] ?? '').toString());
}
