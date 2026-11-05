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
  State<RepairDocumentsScreen> createState() =>
      _RepairDocumentsScreenState();
}

class _RepairDocumentsScreenState extends State<RepairDocumentsScreen> {
  static const Color cyan = Color(0xFF21D4D8);

  bool _loading = true;
  String? _error;

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
            headers: {
              'Authorization': 'Bearer ${widget.token}',
            },
          )
          .timeout(const Duration(seconds: 20));

      final body = jsonDecode(response.body);

      if (response.statusCode != 200) {
        throw Exception(
          body is Map
              ? (body['message'] ?? 'HTTP ${response.statusCode}')
              : 'HTTP ${response.statusCode}',
        );
      }

      final rows = body is Map ? body['data'] : null;

      if (rows is! List) {
        throw Exception('Невалиден отговор от сървъра.');
      }

      if (mounted) {
        setState(() {
          _documents = rows
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _documents = [];

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

  Future<void> _share(Map<String, dynamic> document) async {
    final id = (document['id'] as num?)?.toInt() ?? 0;

    if (id <= 0 || document['available'] != true) {
      _message(
        'Този стар документ не е наличен в защитеното хранилище.',
      );
      return;
    }

    try {
      final response = await http
          .get(
            _uri('/$id/download'),
            headers: {
              'Authorization': 'Bearer ${widget.token}',
            },
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        dynamic body;

        try {
          body = jsonDecode(response.body);
        } catch (_) {
          body = null;
        }

        throw Exception(
          body is Map
              ? (body['message'] ?? 'HTTP ${response.statusCode}')
              : 'HTTP ${response.statusCode}',
        );
      }

      final mime = (document['mime_type'] ?? 'image/png').toString();

      final name =
          (document['original_name'] ??
                  'pcwork_${widget.repairNumber}_$id')
              .toString();

      await Share.shareXFiles(
        [
          XFile.fromData(
            response.bodyBytes,
            mimeType: mime,
            name: name,
          ),
        ],
        text:
            'PCWork · ${widget.repairNumber} · '
            '${_label((document['kind'] ?? '').toString())}',
      );
    } catch (e) {
      _message('Неуспешно изтегляне: $e');
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Widget _buildDocumentCard(Map<String, dynamic> document) {
    final kind = (document['kind'] ?? '').toString();
    final date = (document['created_at'] ?? '').toString();
    final available = document['available'] == true;

    final fileSize = document['file_size'] as num?;

    final subtitleParts = <String>[
      if (date.isNotEmpty) date,
      if (fileSize != null)
        '${(fileSize.toInt() / 1024).toStringAsFixed(0)} KB',
    ];

    IconData icon;

    if (kind == 'photo') {
      icon = Icons.image_outlined;
    } else if (kind == 'protocol_pdf') {
      icon = Icons.picture_as_pdf_outlined;
    } else {
      icon = Icons.draw_outlined;
    }

    return Card(
      child: ListTile(
        leading: Icon(icon, color: cyan),
        title: Text(_label(kind)),
        subtitle: Text(subtitleParts.join(' · ')),
        trailing: IconButton(
          onPressed: available ? () => _share(document) : null,
          icon: const Icon(Icons.ios_share),
          tooltip: 'Изтегли и сподели',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Документи към ремонта'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Обнови',
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Опитай отново'),
                        ),
                      ],
                    ),
                  ),
                )
              : _documents.isEmpty
                  ? const Center(
                      child: Text(
                        'Все още няма качени снимки или подписи.',
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          child: ListTile(
                            leading: const Icon(
                              Icons.folder_shared,
                              color: cyan,
                            ),
                            title: Text(widget.repairNumber),
                            subtitle: Text(
                              '${_documents.length} документа · '
                              'достъпът се проверява от WordPress',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._documents.map(_buildDocumentCard),
                      ],
                    ),
    );
  }
}
