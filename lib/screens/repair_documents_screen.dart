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
  final int repairId;
  final String repairNumber;

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
            },
          )
          .timeout(const Duration(seconds: 20));

      dynamic body;
      try {
        body = jsonDecode(response.body);
      } catch (_) {
        body = null;
      }

      if (response.statusCode != 200) {
        final message = body is Map
            ? (body['message'] ?? 'HTTP ${response.statusCode}')
            : 'HTTP ${response.statusCode}';
        throw Exception(message);
      }

      final rows = body is Map ? body['data'] : null;
      if (rows is! List) {
        throw Exception('Невалиден отговор от сървъра.');
      }

      final documents = rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      if (!mounted) return;
      setState(() {
        _documents = documents;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
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

  Future<void> _share(Map<String, dynamic> document) async {
    final rawId = document['id'];
    final id = rawId is num ? rawId.toInt() : 0;

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
            headers: <String, String>{
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

        final message = body is Map
            ? (body['message'] ?? 'HTTP ${response.statusCode}')
            : 'HTTP ${response.statusCode}';
        throw Exception(message);
      }

      final mimeType = (document['mime_type'] ?? 'application/octet-stream')
          .toString();
      final fileName =
          (document['original_name'] ?? 'pcwork_${widget.repairNumber}_$id')
              .toString();
      final kind = (document['kind'] ?? '').toString();

      await Share.shareXFiles(
        <XFile>[
          XFile.fromData(
            response.bodyBytes,
            mimeType: mimeType,
            name: fileName,
          ),
        ],
        text: 'PCWork · ${widget.repairNumber} · ${_label(kind)}',
      );
    } catch (error) {
      _message('Неуспешно изтегляне: $error');
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
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
      );
    }

    if (_documents.isEmpty) {
      return const Center(
        child: Text('Все още няма качени снимки или подписи.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _documents.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.folder_shared, color: cyan),
              title: Text(widget.repairNumber),
              subtitle: Text(
                '${_documents.length} документа · достъпът се проверява от WordPress',
              ),
            ),
          );
        }

        final document = _documents[index - 1];
        final kind = (document['kind'] ?? '').toString();
        final date = (document['created_at'] ?? '').toString();
        final available = document['available'] == true;
        final rawFileSize = document['file_size'];

        var subtitle = date;
        if (rawFileSize is num) {
          final sizeKb = (rawFileSize / 1024).toStringAsFixed(0);
          subtitle = subtitle.isEmpty ? '$sizeKb KB' : '$subtitle · $sizeKb KB';
        }

        IconData documentIcon;
        if (kind == 'photo') {
          documentIcon = Icons.image_outlined;
        } else if (kind == 'protocol_pdf') {
          documentIcon = Icons.picture_as_pdf_outlined;
        } else {
          documentIcon = Icons.draw_outlined;
        }

        return Card(
          child: ListTile(
            leading: Icon(documentIcon, color: cyan),
            title: Text(_label(kind)),
            subtitle: subtitle.isEmpty ? null : Text(subtitle),
            trailing: IconButton(
              onPressed: available ? () => _share(document) : null,
              icon: const Icon(Icons.ios_share),
              tooltip: 'Изтегли и сподели',
            ),
          ),
        );
      },
    );
  }
}
