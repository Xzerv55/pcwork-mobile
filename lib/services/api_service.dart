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

class _TimedRepairListCache {
  const _TimedRepairListCache(this.expiresAt, this.rows);
  final DateTime expiresAt;
  final List<Repair> rows;
}

class _TimedRepairCache {
  const _TimedRepairCache(this.expiresAt, this.repair);
  final DateTime expiresAt;
  final Repair repair;
}

class ApiService {
  ApiService({required this.baseUrl, this.userId = 0, this.clientBuild = 156});
  final String baseUrl;
  final int userId;
  final int clientBuild;
  // Reuse a process-wide client to keep HTTP connections alive between API calls.
  static final http.Client _httpClient = http.Client();
  static const FlutterSecureStorage _offlineStorage = FlutterSecureStorage();
  static final Map<String, _TimedShopCache> _shopCache = <String, _TimedShopCache>{};
  static final Map<String, Future<List<Map<String, dynamic>>>> _shopRowsInFlight = <String, Future<List<Map<String, dynamic>>>>{};
  static final Map<String, _TimedRepairCache> _repairDetailCache = <String, _TimedRepairCache>{};
  static final Map<String, _TimedShopCache> _customerHistoryCache = <String, _TimedShopCache>{};
  static final Map<String, Future<List<Map<String, dynamic>>>> _shopOrdersInFlight = <String, Future<List<Map<String, dynamic>>>>{};
  static final Map<String, Future<List<Map<String, dynamic>>>> _customerHistoryInFlight = <String, Future<List<Map<String, dynamic>>>>{};
  static final Map<String, _TimedRepairListCache> _repairsListCache = <String, _TimedRepairListCache>{};
  static final Map<String, Future<List<Repair>>> _repairsInFlight = <String, Future<List<Repair>>>{};

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

  void _storeRepairDetailCache(String key, Repair repair, Duration ttl) {
    final now = DateTime.now();
    _repairDetailCache.removeWhere((_, entry) => !entry.expiresAt.isAfter(now));
    if (_repairDetailCache.length >= 60 && !_repairDetailCache.containsKey(key)) {
      final oldestKey = _repairDetailCache.entries
          .reduce((a, b) => a.value.expiresAt.isBefore(b.value.expiresAt) ? a : b)
          .key;
      _repairDetailCache.remove(oldestKey);
    }
    _repairDetailCache[key] = _TimedRepairCache(now.add(ttl), repair);
  }

  String _scope(String token) => userId > 0 ? 'user_$userId' : crypto.sha256.convert(utf8.encode(token)).toString();
  String _repairsCacheKey(String token) => 'pcwork_v37_repairs_${_scope(token)}';
  String _locationsCacheKey() => 'pcwork_v37_locations_${crypto.sha256.convert(utf8.encode(baseUrl.trim()))}';
  String _queueKey(String token) => 'pcwork_v37_queue_${_scope(token)}';
  String _syncHistoryKey(String token) => 'pcwork_v37_sync_history_${_scope(token)}';
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

  /// Read-only diagnostic view of the local offline queue. Payloads and tokens
  /// are deliberately excluded from the UI-facing result.
  Future<List<Map<String, dynamic>>> pendingOperations(String token) async {
    final queue = await _readQueue(token);
    return queue.map((operation) => <String, dynamic>{
      'type': operation['type'],
      'repair_id': operation['repair_id'],
      'request_id': operation['request_id'],
      'status': operation['status'],
      'queued_at': operation['queued_at'],
    }).toList(growable: false);
  }
  Future<List<Map<String, dynamic>>> getSyncHistory(String token) async {
    final raw = await _offlineStorage.read(key: _syncHistoryKey(token));
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      return (jsonDecode(raw) as List).whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> clearOfflineData(String token) async {
    await _offlineStorage.delete(key: _repairsCacheKey(token));
    await _offlineStorage.delete(key: _queueKey(token));
    await _offlineStorage.delete(key: _syncHistoryKey(token));
  }

  Uri _uri(String path) {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base/wp-json/pcwork/v1/$path');
  }

  /// Public release manifest configured by a PCWork administrator in WordPress.
  /// Only HTTPS APK links are accepted by the app before they are opened.
  Future<Map<String, dynamic>?> getAppUpdateInfo() async {
    final endpoint = _uri('app/update');
    final updateUri = endpoint.replace(queryParameters: {
      ...endpoint.queryParameters,
      'client_build': clientBuild.toString(),
      'ts': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    final response = await _httpClient.get(updateUri, headers: const {
      'Accept': 'application/json',
      'Cache-Control': 'no-cache, no-store, max-age=0',
      'Pragma': 'no-cache',
    }).timeout(const Duration(seconds: 12));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(_responseMessage(decoded, response.statusCode));
    final data = decoded is Map ? (decoded['data'] ?? decoded) : null;
    if (data is! Map) return null;
    final rawBuild = data['version_code'] ?? data['build_number'] ?? data['build'] ?? data['versionCode'] ?? 0;
    final build = int.tryParse(rawBuild.toString()) ?? 0;
    final enabledValue = data['enabled'] ?? data['update_enabled'] ?? data['update_available'] ?? data['active'];
    final enabled = enabledValue == null
        ? build > clientBuild
        : enabledValue == true || enabledValue == 1 ||
            enabledValue.toString().toLowerCase() == 'true' ||
            enabledValue.toString() == '1';
    if (!enabled) return null;
    final rawUrl = (data['apk_url'] ?? data['download_url'] ?? '').toString().trim();
    final url = rawUrl.isEmpty ? null : Uri.tryParse(rawUrl);
    final normalized = Map<String, dynamic>.from(data);
    normalized['version_code'] = build;
    normalized['apk_url'] = url != null && url.scheme == 'https' && url.host.isNotEmpty ? url.toString() : '';
    return normalized;
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
    final normalizedSearch = search.trim();
    final cacheKey = '${baseUrl.trim()}:products:$categoryId:${normalizedSearch.toLowerCase()}';
    final cached = _shopCache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) return _copyShopRows(cached.rows);
    final pending = _shopRowsInFlight[cacheKey];
    if (pending != null) return _copyShopRows(await pending);

    final request = () async {
      final params = <String, String>{'per_page': '20'};
      if (normalizedSearch.isNotEmpty) params['search'] = normalizedSearch;
      if (categoryId > 0) params['category'] = '$categoryId';
      final response = await _httpClient.get(_uri('shop/products').replace(queryParameters: params)).timeout(const Duration(seconds: 15));
      final decoded = _decodeResponse(response);
      if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
      final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
      final result = rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false) : <Map<String, dynamic>>[];
      _storeShopCache(cacheKey, result, const Duration(minutes: 3));
      return result;
    }();
    _shopRowsInFlight[cacheKey] = request;
    try { return _copyShopRows(await request); }
    finally { if (identical(_shopRowsInFlight[cacheKey], request)) _shopRowsInFlight.remove(cacheKey); }
  }

  Future<List<Map<String, dynamic>>> getShopProductVariations(int productId) async {
    final cacheKey = '${baseUrl.trim()}:variations:$productId';
    final cached = _shopCache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) return _copyShopRows(cached.rows);
    final pending = _shopRowsInFlight[cacheKey];
    if (pending != null) return _copyShopRows(await pending);

    final request = () async {
      final response = await _httpClient.get(_uri('shop/products/$productId/variations')).timeout(const Duration(seconds: 15));
      final decoded = _decodeResponse(response);
      if (response.statusCode != 200) {
        throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
      }
      final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
      final result = rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false) : <Map<String, dynamic>>[];
      _storeShopCache(cacheKey, result, const Duration(seconds: 60));
      return result;
    }();
    _shopRowsInFlight[cacheKey] = request;
    try { return _copyShopRows(await request); }
    finally { if (identical(_shopRowsInFlight[cacheKey], request)) _shopRowsInFlight.remove(cacheKey); }
  }

  Future<List<Map<String, dynamic>>> getShopCategories() async {
    final cacheKey = '${baseUrl.trim()}:categories';
    final cached = _shopCache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) return _copyShopRows(cached.rows);
    final pending = _shopRowsInFlight[cacheKey];
    if (pending != null) return _copyShopRows(await pending);

    final request = () async {
      final response = await _httpClient.get(_uri('shop/categories')).timeout(const Duration(seconds: 12));
      final decoded = _decodeResponse(response);
      if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
      final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
      final result = rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false) : <Map<String, dynamic>>[];
      _storeShopCache(cacheKey, result, const Duration(minutes: 10));
      return result;
    }();
    _shopRowsInFlight[cacheKey] = request;
    try { return _copyShopRows(await request); }
    finally { if (identical(_shopRowsInFlight[cacheKey], request)) _shopRowsInFlight.remove(cacheKey); }
  }

  Future<List<Map<String, dynamic>>> getShopShippingRates(String token, {required List<Map<String, dynamic>> items, required Map<String, dynamic> shipping}) async {
    final response = await _httpClient.post(_uri('shop/shipping-rates'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode({'items': items, 'shipping': shipping})).timeout(const Duration(seconds: 15));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
    return rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> createShopOrder(String token, {required List<Map<String, dynamic>> items, required Map<String, dynamic> billing, required Map<String, dynamic> shipping, String paymentMethod = 'cash_courier', String? shippingRateId}) async {
    final response = await _httpClient.post(_uri('shop/orders'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({'items': items, 'billing': billing, 'shipping': shipping, 'payment_method': paymentMethod, 'shipping_rate_id': shippingRateId})).timeout(const Duration(seconds: 35));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    if (data is! Map) throw Exception('Невалиден отговор при създаване на поръчка.');
    _shopCache.remove('${baseUrl.trim()}:orders:${_scope(token)}');
    return Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> getShopOrders(String token, {bool forceRefresh = false}) async {
    final cacheKey = '${baseUrl.trim()}:orders:${_scope(token)}';
    final cached = _shopCache[cacheKey];
    if (!forceRefresh && cached != null && cached.expiresAt.isAfter(DateTime.now())) return _copyShopRows(cached.rows);
    final pending = _shopOrdersInFlight[cacheKey];
    if (!forceRefresh && pending != null) return _copyShopRows(await pending);
    final request = () async {
      final response = await _httpClient.get(_uri('shop/orders'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 12));
      final decoded = _decodeResponse(response);
      if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
      final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
      final result = rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
      _storeShopCache(cacheKey, result, const Duration(seconds: 30));
      return result;
    }();
    _shopOrdersInFlight[cacheKey] = request;
    try { return _copyShopRows(await request); }
    finally { if (identical(_shopOrdersInFlight[cacheKey], request)) _shopOrdersInFlight.remove(cacheKey); }
  }

  Future<String> sendAiMessage(String token, List<Map<String, String>> messages) async {
    final response = await _httpClient.post(
      _uri('ai/chat'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({'messages': messages}),
    ).timeout(const Duration(seconds: 75));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    if (data is! Map || (data['answer'] ?? '').toString().trim().isEmpty) throw Exception('AI асистентът не върна отговор.');
    return data['answer'].toString();
  }

  Future<Map<String, dynamic>> getLoyaltySummary(String token) async {
    final response = await _httpClient.get(_uri('loyalty/summary'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 12));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    if (data is! Map) throw Exception('Невалидни данни за програмата за лоялност.');
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> getShopOrder(String token, int id) async {
    http.Response response = await _httpClient.get(_uri('shop/orders/$id'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) {
      response = await _httpClient.get(_uri('shop/order/$id'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 15));
    }
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

  Future<Map<String, dynamic>> getHealthDetails() async {
    final response = await _httpClient.get(
      _uri('health'),
      headers: const {'Accept': 'application/json', 'Cache-Control': 'no-cache'},
    ).timeout(const Duration(seconds: 8));
    final decoded = _decodeResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'API върна HTTP ${response.statusCode}');
    }
    if (decoded is! Map || decoded['ok'] != true) {
      throw Exception('Сървърът не потвърди готовност на PCWork API.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<bool> checkHealth() async {
    await getHealthDetails();
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


  Future<List<Repair>> getRepairs(String token, {bool forceRefresh = false}) async {
    final key = '${baseUrl.trim()}:repairs:${_scope(token)}';
    final cachedList = _repairsListCache[key];
    if (!forceRefresh && cachedList != null && cachedList.expiresAt.isAfter(DateTime.now())) {
      return List<Repair>.unmodifiable(cachedList.rows);
    }
    final pending = _repairsInFlight[key];
    if (!forceRefresh && pending != null) return pending;
    final request = _fetchRepairs(token, key);
    _repairsInFlight[key] = request;
    try { return await request; }
    finally { if (identical(_repairsInFlight[key], request)) _repairsInFlight.remove(key); }
  }

  Future<List<Repair>> _fetchRepairs(String token, String key) async {
    try {
      final response = await _httpClient.get(_uri('repairs'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
      final decoded = _decodeResponse(response);
      if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
      final rows = decoded is Map ? (decoded['data'] ?? decoded['repairs'] ?? decoded['items'] ?? []) : decoded;
      if (rows is! List) throw Exception('Невалиден формат на списъка с ремонти.');
      final normalized = rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      await _offlineStorage.write(key: _repairsCacheKey(token), value: jsonEncode(normalized));
      final result = normalized.map(Repair.fromJson).toList(growable: false);
      _repairsListCache[key] = _TimedRepairListCache(DateTime.now().add(const Duration(seconds: 60)), result);
      return result;
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
      _repairDetailCache.removeWhere((key, _) => key.endsWith(':repair:$id'));
      return Repair.fromJson(Map<String, dynamic>.from(data));
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      final queue = await _readQueue(token);
      queue.add({'type': 'status', 'request_id': requestId, 'repair_id': id, 'queued_at': DateTime.now().toIso8601String(), ...payload});
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

  Future<Map<String, dynamic>> syncPendingOperationsDetailed(String token) async {
    final queue = await _readQueue(token);
    if (queue.isEmpty) {
      return <String, dynamic>{'sent': 0, 'remaining': 0, 'results': <Map<String, dynamic>>[]};
    }
    var completed = 0;
    final remaining = <Map<String, dynamic>>[];
    final results = <Map<String, dynamic>>[];
    for (var index = 0; index < queue.length; index++) {
      final operation = queue[index];
      final type = operation['type']?.toString() ?? 'unknown';
      final requestId = operation['request_id']?.toString() ?? '';
      final repairId = operation['repair_id'];
      try {
        http.Response response;
        if (type == 'create') {
          final payload = Map<String, dynamic>.from(operation['payload'] as Map);
          payload['client_request_id'] = requestId;
          response = await _httpClient.post(
            _uri('repairs'),
            headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          ).timeout(const Duration(seconds: 25));
          if (response.statusCode != 200 && response.statusCode != 201) {
            final decoded = _decodeResponse(response);
            throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
          }
        } else if (type == 'status') {
          final id = (repairId as num).toInt();
          final payload = {
            'status': operation['status'],
            'note': operation['note'],
            'client_request_id': requestId,
          };
          response = await _httpClient.patch(
            _uri('repairs/$id/status'),
            headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          ).timeout(const Duration(seconds: 20));
          if (response.statusCode != 200) {
            final decoded = _decodeResponse(response);
            throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
          }
        } else {
          remaining.addAll(queue.skip(index));
          results.add(<String, dynamic>{
            'type': type, 'repair_id': repairId, 'request_id': requestId,
            'success': false, 'message': 'Неподдържан тип операция. Опашката е спряна, за да се запази редът.',
          });
          break;
        }
        completed++;
        results.add(<String, dynamic>{
          'type': type, 'repair_id': repairId, 'request_id': requestId,
          'success': true, 'message': 'Изпратена успешно.',
        });
      } catch (error) {
        remaining.addAll(queue.skip(index));
        results.add(<String, dynamic>{
          'type': type, 'repair_id': repairId, 'request_id': requestId,
          'success': false, 'message': error.toString().replaceFirst('Exception: ', ''),
        });
        break;
      }
    }
    // Only remove operations whose server response was successful. The stable
    // client_request_id lets the API safely retry after a timeout/ambiguous response.
    await _writeQueue(token, remaining);
    if (results.isNotEmpty) {
      try {
        final history = await getSyncHistory(token);
        final timestamp = DateTime.now().toIso8601String();
        for (final result in results) {
          final message = result['message']?.toString() ?? '';
          history.add(<String, dynamic>{
            'at': timestamp,
            'type': result['type'],
            'repair_id': result['repair_id'],
            'success': result['success'] == true,
            'message': message.length > 240 ? message.substring(0, 240) : message,
          });
        }
        final bounded = history.length > 50 ? history.sublist(history.length - 50) : history;
        await _offlineStorage.write(key: _syncHistoryKey(token), value: jsonEncode(bounded));
      } catch (_) {
        // The operation queue result is authoritative; history is supplementary.
      }
    }
    return <String, dynamic>{'sent': completed, 'remaining': remaining.length, 'results': results};
  }

  Future<int> syncPendingOperations(String token) async {
    final report = await syncPendingOperationsDetailed(token);
    return (report['sent'] as num?)?.toInt() ?? 0;
  }


  Future<Map<String, dynamic>> getFinancialReport(String token, {String? from, String? to}) async {
    final query = <String, String>{};
    if (from != null) query['from'] = from;
    if (to != null) query['to'] = to;
    final uri = _uri('financial/report').replace(queryParameters: query.isEmpty ? null : query);
    final response = await _httpClient.get(uri, headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 30));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> getFinancialExpenses(String token, {String? from, String? to, int page = 1, int perPage = 50}) async {
    final query = <String, String>{'page': '$page', 'per_page': '$perPage'};
    if (from != null) query['from'] = from;
    if (to != null) query['to'] = to;
    final response = await _httpClient.get(_uri('financial/expenses').replace(queryParameters: query), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
    return rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }

  Future<Map<String, dynamic>> createFinancialExpense(String token, Map<String, dynamic> expense) async {
    final response = await _httpClient.post(_uri('financial/expenses'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode(expense)).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    return decoded is Map && decoded['data'] is Map ? Map<String, dynamic>.from(decoded['data']) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> updateFinancialExpense(String token, int id, Map<String, dynamic> changes) async {
    final response = await _httpClient.patch(_uri('financial/expenses/$id'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode(changes)).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    return decoded is Map && decoded['data'] is Map ? Map<String, dynamic>.from(decoded['data']) : <String, dynamic>{};
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

  Future<List<Map<String, dynamic>>> getStockMovements(String token, {int? itemId, int? repairId, int page = 1, int perPage = 50}) async {
    final params = <String, String>{'page': '$page', 'per_page': '${perPage.clamp(1, 100)}'};
    if (itemId != null && itemId > 0) params['item_id'] = '$itemId';
    if (repairId != null && repairId > 0) params['repair_id'] = '$repairId';
    final response = await _httpClient.get(_uri('stock/movements').replace(queryParameters: params), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
    return rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }

  Future<void> moveStockItem(String token, int id, {required String type, required double quantity, String note = '', int? repairId}) async {
    final payload = <String, dynamic>{'type': type, 'quantity': quantity, 'note': note};
    if (repairId != null && repairId > 0) payload['repair_id'] = repairId;
    final response = await _httpClient.post(_uri('stock/$id/movement'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode(payload)).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
  }

  Future<List<Map<String, dynamic>>> getRepairPartRequests(String token, int repairId) async {
    final response = await _httpClient.get(_uri('repairs/$repairId/part-requests'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
    return rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }

  Future<void> createRepairPartRequest(String token, int repairId, Map<String, dynamic> request) async {
    final response = await _httpClient.post(_uri('repairs/$repairId/part-requests'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode(request)).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
  }

  Future<void> updateRepairPartRequest(String token, int id, Map<String, dynamic> changes) async {
    final response = await _httpClient.patch(_uri('part-requests/$id'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode(changes)).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
  }

  Future<Map<String, dynamic>> receiveRepairPartRequest(String token, int id, {double unitCost = 0}) async {
    final response = await _httpClient.post(_uri('part-requests/$id/receive'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({'unit_cost': unitCost})).timeout(const Duration(seconds: 25));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    return decoded is Map && decoded['data'] is Map ? Map<String, dynamic>.from(decoded['data']) : <String, dynamic>{};
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

  Future<List<Map<String, dynamic>>> getOverdueRepairs(String token, {int page = 1, int perPage = 50}) async {
    final uri = _uri('staff/repairs/overdue').replace(queryParameters: {'page': '$page', 'per_page': '$perPage'});
    final response = await _httpClient.get(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
    return rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }

  Future<List<Map<String, dynamic>>> getStaffTasks(String token, {String status = 'all', int assignedUserId = 0, bool overdueOnly = false, int page = 1, int perPage = 50}) async {
    final params = <String, String>{'page': '$page', 'per_page': '$perPage'};
    if (status != 'all') params['status'] = status;
    if (assignedUserId > 0) params['assigned_user_id'] = '$assignedUserId';
    if (overdueOnly) params['overdue'] = '1';
    final uri = _uri('staff/tasks').replace(queryParameters: params);
    final response = await _httpClient.get(uri, headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
    return rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }

  Future<List<Map<String, dynamic>>> getRepairTasks(String token, int repairId) async {
    final response = await _httpClient.get(_uri('repairs/$repairId/tasks'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
    return rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }

  Future<Map<String, dynamic>> createRepairTask(String token, int repairId, Map<String, dynamic> task) async {
    final response = await _httpClient.post(_uri('repairs/$repairId/tasks'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode(task)).timeout(const Duration(seconds: 25));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    if (data is! Map) throw Exception('Невалиден отговор при създаване на задачата.');
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> updateRepairTask(String token, int taskId, Map<String, dynamic> changes) async {
    final response = await _httpClient.patch(_uri('tasks/$taskId'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode(changes)).timeout(const Duration(seconds: 25));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    if (data is! Map) throw Exception('Невалиден отговор при обновяване на задачата.');
    return Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> getRepairTaskHistory(String token, int taskId) async {
    final response = await _httpClient.get(_uri('tasks/$taskId/history'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
    return rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
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

  Future<List<Map<String, dynamic>>> getCustomerServiceHistory(String token, {int page = 1, int perPage = 50, bool forceRefresh = false}) async {
    final safePage = page < 1 ? 1 : page;
    final safePerPage = perPage.clamp(1, 50);
    final key = '${baseUrl.trim()}:${_scope(token)}:customer-history:$safePage:$safePerPage';
    final now = DateTime.now();
    final cached = _customerHistoryCache[key];
    if (!forceRefresh && cached != null && cached.expiresAt.isAfter(now)) return _copyShopRows(cached.rows);
    final pending = _customerHistoryInFlight[key];
    if (pending != null) return _copyShopRows(await pending);
    final request = () async {
      final uri = _uri('customer/service-history').replace(queryParameters: {'page': '$safePage', 'per_page': '$safePerPage'});
      final response = await _httpClient.get(uri, headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 15));
      final decoded = _decodeResponse(response);
      if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
      final rows = decoded is Map ? decoded['data'] : null;
      final result = rows is List ? rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList(growable: false) : <Map<String, dynamic>>[];
      _customerHistoryCache.removeWhere((_, entry) => !entry.expiresAt.isAfter(DateTime.now()));
      if (_customerHistoryCache.length >= 30 && !_customerHistoryCache.containsKey(key)) _customerHistoryCache.remove(_customerHistoryCache.keys.first);
      _customerHistoryCache[key] = _TimedShopCache(DateTime.now().add(const Duration(seconds: 45)), result);
      return result;
    }();
    _customerHistoryInFlight[key] = request;
    try { return _copyShopRows(await request); }
    finally { _customerHistoryInFlight.remove(key); }
  }

  Future<Map<String, dynamic>> getRepairChecklist(String token, int repairId) async {
    final response = await _httpClient.get(_uri('repairs/$repairId/checklist'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final rows = decoded is Map ? decoded['data'] : null;
    return {'items': rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[], 'editable': decoded is Map && decoded['editable'] == true};
  }

  Future<void> saveRepairChecklist(String token, int repairId, List<Map<String, dynamic>> items) async {
    final response = await _httpClient.post(_uri('repairs/$repairId/checklist'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({'items': items})).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
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

  Future<Map<String, dynamic>> getRepairPartsSummary(String token, int repairId) async {
    final response = await _httpClient.get(_uri('repairs/$repairId/parts-summary'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? decoded['data'] : null;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> addRepairWorklogEntry(String token, int repairId, Map<String, dynamic> entry) async {
    final response = await _httpClient.post(_uri('repairs/$repairId/worklog'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode(entry)).timeout(const Duration(seconds: 25));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    if (data is! Map) throw Exception('Невалиден отговор при записване в сервизния дневник.');
    return Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> getRepairWarrantyCards(String token, int repairId) async {
    final response = await _httpClient.get(_uri('repairs/$repairId'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    if (data is! Map || data['warranty_cards'] is! List) return <Map<String, dynamic>>[];
    return (data['warranty_cards'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>?> getRepairEstimate(String token, int repairId) async {
    final response = await _httpClient.get(_uri('repairs/$repairId/estimate'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? decoded['data'] : null;
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  Future<Map<String, dynamic>> createRepairEstimate(String token, int repairId, {required String description, required double total, required int estimatedDays, String validUntil = ''}) async {
    final response = await _httpClient.post(_uri('repairs/$repairId/estimate'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode({'description': description, 'total': total, 'estimated_days': estimatedDays, 'valid_until': validUntil})).timeout(const Duration(seconds: 25));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! Map) throw Exception('Невалиден отговор при изпращане на офертата.');
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> decideRepairEstimate(String token, int repairId, {required String decision, String note = ''}) async {
    final response = await _httpClient.post(_uri('repairs/$repairId/estimate/decision'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode({'decision': decision, 'note': note})).timeout(const Duration(seconds: 25));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! Map) throw Exception('Невалиден отговор при обработка на офертата.');
    _repairDetailCache.removeWhere((key, _) => key.endsWith(':repair:$repairId'));
    _repairsListCache.removeWhere((key, _) => key.contains(':repairs:'));
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> updateRepairPayment(String token, int repairId, {required bool paid}) async {
    final response = await _httpClient.post(
      _uri('repairs/$repairId/payment'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({'payment_status': paid ? 'paid' : 'pending'}),
    ).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    if (data is! Map) throw Exception('Невалиден отговор за плащането.');
    _repairDetailCache.removeWhere((key, _) => key.endsWith(':repair:$repairId'));
    _repairsListCache.removeWhere((key, _) => key.contains(':repairs:'));
    return Map<String, dynamic>.from(data);
  }

  Future<Repair> lookupRepairByQr(String token, String repairNumber) async {
    final code = repairNumber.trim();
    if (code.isEmpty || code.length > 100) throw Exception('Невалиден номер на ремонт.');
    final uri = _uri('staff/repairs/lookup').replace(queryParameters: {'number': code});
    final response = await _httpClient.get(uri, headers: {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    }
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! Map) throw Exception('Сървърът върна невалидни данни за ремонта.');
    final repair = Repair.fromJson(Map<String, dynamic>.from(data));
    if (repair.id <= 0) throw Exception('Не е намерен валиден ремонт за този QR код.');
    _repairDetailCache.removeWhere((key, _) => key.endsWith(':repair:${repair.id}'));
    return repair;
  }

  Future<Repair> getRepair(String token, int id) async {
    final cacheKey = '${baseUrl.trim()}:${_scope(token)}:repair:$id';
    final cachedDetail = _repairDetailCache[cacheKey];
    if (cachedDetail != null && cachedDetail.expiresAt.isAfter(DateTime.now())) {
      return cachedDetail.repair;
    }

    try {
      final response = await _httpClient.get(
        _uri('repairs/$id'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 20));
      final decoded = _decodeResponse(response);
      if (response.statusCode != 200) {
        final message = decoded is Map
            ? _responseMessage(decoded, response.statusCode)
            : 'HTTP ${response.statusCode}';
        throw Exception(message);
      }
      final data = decoded is Map
          ? (decoded['data'] ?? decoded['repair'] ?? decoded)
          : decoded;
      if (data is! Map) throw Exception('Невалиден формат на ремонта.');
      final normalized = Map<String, dynamic>.from(data);
      final repair = Repair.fromJson(normalized);
      _storeRepairDetailCache(cacheKey, repair, const Duration(seconds: 60));

      final cached = await _offlineStorage.read(key: _repairsCacheKey(token));
      if (cached != null) {
        try {
          final rows = (jsonDecode(cached) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final index = rows.indexWhere(
            (row) => (row['id'] as num?)?.toInt() == id,
          );
          if (index >= 0) {
            rows[index] = normalized;
            await _offlineStorage.write(
              key: _repairsCacheKey(token),
              value: jsonEncode(rows),
            );
          }
        } catch (_) {}
      }
      return repair;
    } catch (error) {
      if (!_isNetworkError(error)) rethrow;
      final cached = await _offlineStorage.read(key: _repairsCacheKey(token));
      if (cached == null) rethrow;
      final rows = jsonDecode(cached) as List;
      for (final item in rows.whereType<Map>()) {
        if ((item['id'] as num?)?.toInt() == id) {
          final repair = Repair.fromJson({
            ...Map<String, dynamic>.from(item),
            '_offline_cached': true,
          });
          _storeRepairDetailCache(cacheKey, repair, const Duration(seconds: 30));
          return repair;
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
      queue.add({'type': 'create', 'request_id': requestId, 'queued_at': DateTime.now().toIso8601String(), 'payload': payload});
      await _writeQueue(token, queue);
      return {'queued': true, 'client_request_id': requestId, 'message': 'Записано локално и чака синхронизация.'};
    }
  }


  Future<Map<String, dynamic>> getChatMessages(String token, {int afterId = 0, int beforeId = 0}) async {
    final params = <String, String>{};
    if (afterId > 0) params['after_id'] = '$afterId';
    if (beforeId > 0) params['before_id'] = '$beforeId';
    final response = await _httpClient.get(
      _uri('chat/messages').replace(queryParameters: params),
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

  Future<Map<String, dynamic>> getCacheMonitor(String token) async {
    final response = await _httpClient.get(
      _uri('cache/monitor'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 15));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(_responseMessage(decoded, response.statusCode));
    if (decoded is! Map) throw Exception('Невалиден отговор от мониторинга на кеша.');
    return Map<String, dynamic>.from(decoded);
  }

  Future<List<Map<String, dynamic>>> getVisitorAnalyticsCustomers(String token) async {
    final response = await _httpClient.get(
      _uri('visitors/customers'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 15));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(_responseMessage(decoded, response.statusCode));
    final data = decoded is Map ? decoded['data'] : null;
    return data is List
        ? data.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
        : <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> getAdminChatMessages(String token, int userId, {int afterId = 0, int beforeId = 0}) async {
    final params = <String, String>{'user_id': '$userId'};
    if (afterId > 0) params['after_id'] = '$afterId';
    if (beforeId > 0) params['before_id'] = '$beforeId';
    final uri = _uri('chat/admin/messages').replace(queryParameters: params);
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

  Future<Map<String, dynamic>> getRatingConfig() async {
    final response = await _httpClient.get(_uri('ratings/config'), headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 10));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(_responseMessage(decoded, response.statusCode));
    final data = decoded is Map && decoded['data'] is Map ? decoded['data'] : decoded;
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> submitRating(String token, {required String type, required int stars, int repairId = 0, String comment = ''}) async {
    final response = await _httpClient.post(_uri('ratings'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode({'rating_type': type, 'stars': stars, 'repair_id': repairId, 'comment': comment})).timeout(const Duration(seconds: 15));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception(_responseMessage(decoded, response.statusCode));
  }

  Future<Map<String, dynamic>> getBookingConfig() async {
    final response = await _httpClient.get(_uri('booking/config'), headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 10));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(_responseMessage(decoded, response.statusCode));
    final data = decoded is Map && decoded['data'] is Map ? Map<String, dynamic>.from(decoded['data']) : Map<String, dynamic>.from(decoded as Map);
    return data;
  }

  Future<List<Map<String, dynamic>>> getBookingServices() async {
    final response = await _httpClient.get(_uri('booking/services'), headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 10));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(_responseMessage(decoded, response.statusCode));
    final data = decoded is Map && decoded['data'] is Map ? decoded['data'] as Map : decoded as Map;
    final rows = data['services'];
    return rows is List ? rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList() : <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> getBookingSlots({required String date, required String locationCode, required int serviceId}) async {
    final uri = _uri('booking/slots').replace(queryParameters: {'date': date, 'location': locationCode, 'service_id': '$serviceId'});
    final response = await _httpClient.get(uri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 12));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(_responseMessage(decoded, response.statusCode));
    final data = decoded is Map && decoded['data'] is Map ? decoded['data'] as Map : decoded as Map;
    final rows = data['slots'];
    return rows is List ? rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList() : <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> createBooking(String token, Map<String, dynamic> booking) async {
    final response = await _httpClient.post(_uri('booking/bookings'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode(booking)).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 201 && response.statusCode != 200) throw Exception(_responseMessage(decoded, response.statusCode));
    final data = decoded is Map && decoded['data'] is Map ? decoded['data'] as Map : decoded as Map;
    return Map<String, dynamic>.from(data['booking'] is Map ? data['booking'] as Map : data);
  }

  Future<List<Map<String, dynamic>>> getMyBookings(String token) async {
    final response = await _httpClient.get(_uri('booking/bookings'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 15));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(_responseMessage(decoded, response.statusCode));
    final data = decoded is Map && decoded['data'] is Map ? decoded['data'] as Map : decoded as Map;
    final rows = data['bookings'];
    return rows is List ? rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList() : <Map<String, dynamic>>[];
  }

  Future<void> cancelBooking(String token, int id) async {
    final response = await _httpClient.patch(_uri('booking/bookings/$id'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode({'status': 'cancelled'})).timeout(const Duration(seconds: 15));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(_responseMessage(decoded, response.statusCode));
  }

  Future<List<Map<String, dynamic>>> getCustomerDevices(String token) async {
    final response = await _httpClient.get(_uri('customer/devices'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 18));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(_responseMessage(decoded, response.statusCode));
    final root = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    final rows = root is Map ? root['devices'] : root;
    return rows is List ? rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList(growable: false) : <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> saveCustomerDevice(String token, Map<String, dynamic> device, {int id = 0}) async {
    final uri = _uri(id > 0 ? 'customer/devices/$id' : 'customer/devices');
    final response = id > 0
        ? await _httpClient.patch(uri, headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode(device)).timeout(const Duration(seconds: 20))
        : await _httpClient.post(uri, headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode(device)).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception(_responseMessage(decoded, response.statusCode));
    final root = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    if (root is! Map || root['device'] is! Map) throw Exception('Сървърът върна невалидни данни за устройството.');
    return Map<String, dynamic>.from(root['device'] as Map);
  }

  Future<void> deleteCustomerDevice(String token, int id) async {
    final response = await _httpClient.delete(_uri('customer/devices/$id'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 18));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(_responseMessage(decoded, response.statusCode));
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
  const Repair({required this.id, required this.number, required this.status, this.device = '', this.model = '', this.location = '', this.createdAt = '', this.updatedAt = '', this.problem = '', this.phone = '', this.serial = '', this.customer = '', this.locationCode = '', this.technicianId = 0, this.technicianName = '', this.priority = 'normal', this.dueAt = '', this.paymentMethod = 'cash_on_site', this.paymentStatus = 'pending', this.history = const [], this.warrantyCards = const [], this.pendingSync = false, this.fromCache = false});
  final int id;
  final String number, status, device, model, location, createdAt, updatedAt, problem, phone, serial, customer, locationCode, technicianName, priority, dueAt, paymentMethod, paymentStatus;
  final int technicianId;
  final List<RepairHistory> history;
  final List<Map<String, dynamic>> warrantyCards;
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
    locationCode: (j['location_code'] ?? '').toString(), technicianId: (j['assigned_technician_id'] as num?)?.toInt() ?? 0, technicianName: (j['assigned_technician_name'] ?? '').toString(), priority: (j['priority'] ?? 'normal').toString(), dueAt: (j['due_at'] ?? '').toString(), paymentMethod: (j['payment_method'] ?? 'cash_on_site').toString(), paymentStatus: (j['payment_status'] ?? 'pending').toString(),
    history: (j['history'] as List? ?? []).whereType<Map>().map((e) => RepairHistory.fromJson(Map<String,dynamic>.from(e))).toList(),
    warrantyCards: (j['warranty_cards'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
    pendingSync: j['_pending_sync'] == true, fromCache: j['_offline_cached'] == true,
  );
}
class RepairHistory {
  const RepairHistory(this.status, this.note, this.createdAt);
  final String status, note, createdAt;
  factory RepairHistory.fromJson(Map<String,dynamic> j) => RepairHistory((j['status'] ?? '').toString(), (j['note'] ?? '').toString(), (j['created_at'] ?? '').toString());
}
