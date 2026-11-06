import 'dart:convert';
import 'package:http/http.dart' as http;

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

class ApiService {
  ApiService({required this.baseUrl});
  final String baseUrl;

  Uri _uri(String path) {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base/wp-json/pcwork/v1/$path');
  }

  Future<bool> checkHealth() async {
    final response = await http.get(_uri('health')).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('API върна HTTP ${response.statusCode}');
    }
    return true;
  }

  Future<List<ServiceLocation>> getLocations() async {
    final response = await http.get(_uri('locations')).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Грешка при зареждане на обектите (HTTP ${response.statusCode})');
    }
    final decoded = _decodeResponse(response);
    final dynamic rows = decoded is List ? decoded : (decoded is Map ? (decoded['data'] ?? decoded['locations'] ?? decoded['items']) : null);
    if (rows is! List) throw Exception('Сървърът върна неочакван формат за сервизните обекти.');
    return rows.whereType<Map>().map((row) => ServiceLocation.fromJson(Map<String, dynamic>.from(row))).toList();
  }


  Future<List<Repair>> getRepairs(String token) async {
    final response = await http.get(_uri('repairs'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) {
      final message = decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}';
      throw Exception(message);
    }
    final rows = decoded is Map
        ? (decoded['data'] ?? decoded['repairs'] ?? decoded['items'] ?? [])
        : decoded;
    if (rows is! List) throw Exception('Невалиден формат на списъка с ремонти.');
    return rows.whereType<Map>().map((e) => Repair.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<Repair> updateRepairStatus(String token, int id, String status, {String note = ''}) async {
    final response = await http.patch(_uri('repairs/$id/status'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'status': status, 'note': note})).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) {
      final message = decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}';
      throw Exception(message);
    }
    final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    if (data is! Map) throw Exception('Невалиден отговор при промяна на статуса.');
    return Repair.fromJson(Map<String, dynamic>.from(data));
  }

  Future<List<Map<String, dynamic>>> getTechnicians(String token, String locationCode) async {
    final uri = _uri('staff/technicians').replace(queryParameters: {'location_code': locationCode});
    final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
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
    final response = await http.get(_uri('staff/schedule'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
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
    final response = await http.post(_uri('staff/schedule'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'technician_id': technicianId, 'schedule': schedule})).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) {
      final message = decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}';
      throw Exception(message);
    }
  }

  Future<Map<String, dynamic>> getStaffOverview(String token) async {
    final response = await http.get(_uri('staff/overview'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    if (data is! Map) throw Exception('Невалиден формат на служебната статистика.');
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> getAttendance(String token) async {
    final response = await http.get(_uri('staff/attendance'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<void> recordAttendance(String token, String action) async {
    final response = await http.post(_uri('staff/attendance'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({'action': action})).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
  }

  Future<List<Map<String, dynamic>>> getLeaveRequests(String token) async {
    final response = await http.get(_uri('staff/leave'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
    final rows = decoded is Map ? (decoded['data'] ?? []) : decoded;
    return rows is List ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }

  Future<void> submitLeaveRequest(String token, {required String startDate, required String endDate, required String reason}) async {
    final response = await http.post(_uri('staff/leave'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({'start_date': startDate, 'end_date': endDate, 'reason': reason})).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
  }

  Future<void> reviewLeaveRequest(String token, int id, String decision) async {
    final response = await http.patch(_uri('staff/leave/$id'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({'status': decision})).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) throw Exception(decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}');
  }

  Future<Repair> updateRepairAssignment(String token, int id, {required int technicianId, required String priority, String dueAt = ''}) async {
    final response = await http.patch(_uri('repairs/$id/assignment'),
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

  Future<Repair> getRepair(String token, int id) async {
    final response = await http.get(_uri('repairs/$id'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 200) {
      final message = decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}';
      throw Exception(message);
    }
    final data = decoded is Map ? (decoded['data'] ?? decoded['repair'] ?? decoded) : decoded;
    if (data is! Map) throw Exception('Невалиден формат на ремонта.');
    return Repair.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Map<String, dynamic>> createRepair(String token, Map<String, dynamic> payload) async {
    final response = await http.post(
      _uri('repairs'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 25));
    final decoded = _decodeResponse(response);
    if (response.statusCode != 201 && response.statusCode != 200) {
      final message = decoded is Map ? _responseMessage(decoded, response.statusCode) : 'HTTP ${response.statusCode}';
      throw Exception(message);
    }
    final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    if (data is! Map) throw Exception('Сървърът върна невалиден протокол.');
    return Map<String, dynamic>.from(data);
  }

  Future<Uri?> getChatwayUrl({String? token}) async {
    final authenticated = token != null && token.trim().isNotEmpty;
    final response = authenticated
        ? await http.post(_uri('chatway/session'),
            headers: {'Authorization': 'Bearer ${token!.trim()}', 'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{})).timeout(const Duration(seconds: 15))
        : await http.get(_uri('chatway/config')).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      final decoded = _decodeResponse(response);
      throw Exception(_responseMessage(decoded, response.statusCode));
    }
    final decoded = _decodeResponse(response);
    if (decoded is! Map) return null;
    final data = decoded['data'] is Map ? decoded['data'] as Map : decoded;
    if (data['enabled'] != true) return null;
    final raw = data['chat_url'];
    if (raw is! String || raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    final apiHost = Uri.tryParse(baseUrl.trim())?.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final chatHost = uri?.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (uri == null || uri.scheme != 'https' || apiHost == null || chatHost != apiHost) return null;
    return uri;
  }

  Future<Uri?> getBookingUrl() async {
    final response = await http.get(_uri('booking/config')).timeout(const Duration(seconds: 15));
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
  const ServiceLocation({required this.name, this.code = '', this.address = '', this.phone = ''});
  final String name;
  final String code;
  final String address;
  final String phone;

  factory ServiceLocation.fromJson(Map<String, dynamic> json) => ServiceLocation(
    name: (json['name'] ?? json['title'] ?? json['location_name'] ?? 'Сервизен обект').toString(),
    code: (json['code'] ?? json['location_code'] ?? '').toString(),
    address: (json['address'] ?? '').toString(),
    phone: (json['phone'] ?? '').toString(),
  );
}


class Repair {
  const Repair({required this.id, required this.number, required this.status, this.device = '', this.model = '', this.location = '', this.createdAt = '', this.updatedAt = '', this.problem = '', this.phone = '', this.serial = '', this.customer = '', this.locationCode = '', this.technicianId = 0, this.technicianName = '', this.priority = 'normal', this.dueAt = '', this.history = const []});
  final int id;
  final String number, status, device, model, location, createdAt, updatedAt, problem, phone, serial, customer, locationCode, technicianName, priority, dueAt;
  final int technicianId;
  final List<RepairHistory> history;
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
  );
}
class RepairHistory {
  const RepairHistory(this.status, this.note, this.createdAt);
  final String status, note, createdAt;
  factory RepairHistory.fromJson(Map<String,dynamic> j) => RepairHistory((j['status'] ?? '').toString(), (j['note'] ?? '').toString(), (j['created_at'] ?? '').toString());
}
