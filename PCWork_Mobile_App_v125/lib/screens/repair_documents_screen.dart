import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

class RepairDocumentsScreen extends StatefulWidget {
  const RepairDocumentsScreen({
    super.key,
    required this.baseUrl,
    required this.token,
    required this.repairId,
    required this.repairNumber,
  });

  final String baseUrl;
  final String token;
  final String repairNumber;
  final int repairId;

  @override
  State<RepairDocumentsScreen> createState() => _RepairDocumentsScreenState();
}

class _RepairDocumentsScreenState extends State<RepairDocumentsScreen> {
  static const Color cyan = Color(0xFF21D4D8);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _documents = <Map<String, dynamic>>[];

  Uri _uri(String suffix) {
    final base = widget.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse(
      '$base/wp-json/pcwork/v1/repairs/${widget.repairId}/documents$suffix',
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http
          .get(
            _uri(''),
            headers: <String, String>{
              'Authorization': 'Bearer ${widget.token}',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 20));

      dynamic body;
      try {
        body = jsonDecode(response.body);
      } on FormatException {
        throw Exception('Сървърът върна невалиден отговор.');
      }

      if (response.statusCode != 200) {
        final message = body is Map ? body['message'] : null;
        throw Exception(message?.toString() ?? 'HTTP ${response.statusCode}');
      }

      final dynamic rows = body is Map ? body['data'] : null;
      if (rows is! List) {
        throw Exception('Невалиден списък с документи от сървъра.');
      }

      final documents = rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);

      if (mounted) {
        setState(() {
          _documents = documents;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _label(String kind) {
    switch (kind) {
      case 'photo':
        return 'Снимка на устройството';
      case 'customer_signature':
        return 'Подпис на клиента';
      case 'staff_signature':
        return 'Подпис на служителя';
      case 'protocol_pdf':
        return 'PDF сервизен протокол';
      default:
        return 'Документ';
    }
  }

  IconData _icon(String kind) {
    switch (kind) {
      case 'photo':
        return Icons.image_outlined;
      case 'protocol_pdf':
        return Icons.picture_as_pdf_outlined;
      default:
        return Icons.draw_outlined;
    }
  }

  String _fileSize(dynamic value) {
    if (value is! num || value <= 0) return '';
    final kb = value / 1024;
    return kb >= 1024
        ? '${(kb / 1024).toStringAsFixed(1)} MB'
        : '${kb.toStringAsFixed(0)} KB';
  }

  Future<void> _share(Map<String, dynamic> document) async {
    final rawId = document['id'];
    final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId') ?? 0;
    if (id <= 0 || document['available'] != true) {
      _message('Този документ не е наличен в защитеното хранилище.');
      return;
    }

    try {
      final response = await http
          .get(
            _uri('/$id/download'),
            headers: <String, String>{
              'Authorization': 'Bearer ${widget.token}',
              'Accept': '*/*',
            },
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        dynamic body;
        try {
          body = jsonDecode(response.body);
        } on FormatException {
          body = null;
        }
        final message = body is Map ? body['message'] : null;
        throw Exception(message?.toString() ?? 'HTTP ${response.statusCode}');
      }

      final mime = (document['mime_type'] ?? 'application/octet-stream').toString();
      final originalName = (document['original_name'] ?? '').toString().trim();
      final fileName = originalName.isEmpty
          ? 'pcwork_${widget.repairNumber}_$id'
          : originalName;

      await Share.shareXFiles(
        <XFile>[
          XFile.fromData(
            response.bodyBytes,
            mimeType: mime,
            name: fileName,
          ),
        ],
        text: 'PCWork · ${widget.repairNumber} · '
            '${_label((document['kind'] ?? '').toString())}',
      );
    } catch (error) {
      _message('Неуспешно изтегляне на документа: $error');
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_outlined, size: 42, color: Colors.orangeAccent),
            const SizedBox(height: 12),
            Text(_error ?? 'Възникна неизвестна грешка.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Опитай отново'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Документи към ремонта'),
        actions: <Widget>[
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Обнови',
          ),
        ],
      ),
      body: _loading && _documents.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _documents.isEmpty
              ? _errorView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.folder_shared, color: cyan),
                          title: Text(widget.repairNumber),
                          subtitle: Text(
                            '${_documents.length} документа · достъпът се проверява от WordPress',
                          ),
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
                        ),
                      if (_documents.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Text('Все още няма качени снимки или подписи.'),
                          ),
                        ),
                      ..._documents.map((document) {
                        final kind = (document['kind'] ?? '').toString();
                        final date = (document['created_at'] ?? '').toString();
                        final size = _fileSize(document['file_size']);
                        final available = document['available'] == true;
                        final details = <String>[
                          if (date.isNotEmpty) date,
                          if (size.isNotEmpty) size,
                        ].join(' · ');

                        return Card(
                          child: ListTile(
                            leading: Icon(_icon(kind), color: cyan),
                            title: Text(_label(kind)),
                            subtitle: Text(details.isEmpty ? 'PCWork документ' : details),
                            trailing: IconButton(
                              onPressed: available ? () => _share(document) : null,
                              icon: const Icon(Icons.ios_share),
                              tooltip: 'Изтегли и сподели',
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}
