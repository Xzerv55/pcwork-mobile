import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:signature/signature.dart';

/// Uploads repair photos and signatures to the authenticated PCWork REST API.
/// Photos and staff signature are restricted to staff by the server as well.
class RepairEvidenceScreen extends StatefulWidget {
  const RepairEvidenceScreen({super.key, required this.baseUrl, required this.token, required this.repairId, required this.repairNumber, required this.isStaff});
  final String baseUrl, token, repairNumber;
  final int repairId;
  final bool isStaff;
  @override
  State<RepairEvidenceScreen> createState() => _RepairEvidenceScreenState();
}

class _RepairEvidenceScreenState extends State<RepairEvidenceScreen> {
  static const cyan = Color(0xFF21D4D8);
  final _picker = ImagePicker();
  final List<XFile> _photos = [];
  late final SignatureController _customer;
  late final SignatureController _staff;
  bool _busy = false;
  String? _result;

  @override
  void initState() {
    super.initState();
    _customer = SignatureController(penStrokeWidth: 2.4, penColor: Colors.black, exportBackgroundColor: Colors.white);
    _staff = SignatureController(penStrokeWidth: 2.4, penColor: Colors.black, exportBackgroundColor: Colors.white);
  }
  @override
  void dispose() { _customer.dispose(); _staff.dispose(); super.dispose(); }

  Future<void> _addPhotos(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        final photo = await _picker.pickImage(source: source, imageQuality: 82, maxWidth: 1800);
        if (photo != null && mounted) setState(() => _photos.add(photo));
      } else {
        final photos = await _picker.pickMultiImage(imageQuality: 82, maxWidth: 1800, limit: 6 - _photos.length);
        if (mounted) setState(() => _photos.addAll(photos.take(6 - _photos.length)));
      }
    } catch (e) { if (mounted) _message('Неуспешно добавяне на снимка: $e'); }
  }

  Future<void> _upload() async {
    if (_customer.isEmpty && (!widget.isStaff || _staff.isEmpty) && _photos.isEmpty) {
      _message('Добавете поне един подпис или снимка.'); return;
    }
    setState(() { _busy = true; _result = null; });
    try {
      final base = widget.baseUrl.replaceFirst(RegExp(r'/+$'), '');
      final uri = Uri.parse('$base/wp-json/pcwork/v1/repairs/${widget.repairId}/evidence');
      final request = http.MultipartRequest('POST', uri)..headers['Authorization'] = 'Bearer ${widget.token}';
      if (_customer.isNotEmpty) {
        final bytes = await _customer.toPngBytes();
        if (bytes != null) request.fields['customer_signature'] = 'data:image/png;base64,${base64Encode(bytes)}';
      }
      if (widget.isStaff && _staff.isNotEmpty) {
        final bytes = await _staff.toPngBytes();
        if (bytes != null) request.fields['staff_signature'] = 'data:image/png;base64,${base64Encode(bytes)}';
      }
      for (var i = 0; i < _photos.length; i++) {
        final bytes = await _photos[i].readAsBytes();
        request.files.add(http.MultipartFile.fromBytes('photos[]', bytes, filename: 'pcwork_${widget.repairNumber}_$i.jpg'));
      }
      final streamed = await request.send().timeout(const Duration(seconds: 90));
      final response = await http.Response.fromStream(streamed);
      final decoded = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map ? (decoded['message'] ?? 'HTTP ${response.statusCode}') : 'HTTP ${response.statusCode}';
        throw Exception(message);
      }
      if (!mounted) return;
      setState(() { _result = 'Документите са записани към ремонт ${widget.repairNumber}.'; _photos.clear(); _customer.clear(); _staff.clear(); });
    } catch (e) { if (mounted) _message('Грешка при запис: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  void _message(String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  Widget _signatureBox(String title, SignatureController controller, {required bool clearable}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Container(height: 170, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Signature(controller: controller, backgroundColor: Colors.white)), if (clearable) Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: controller.clear, icon: const Icon(Icons.refresh), label: const Text('Изчисти')))]);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Снимки и подписи')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      Card(child: ListTile(leading: const Icon(Icons.qr_code_2, color: cyan), title: Text(widget.repairNumber), subtitle: const Text('Сервизен протокол'))),
      _signatureBox('Подпис на клиента', _customer, clearable: true),
      if (widget.isStaff) ...[const SizedBox(height: 16), _signatureBox('Подпис на служителя', _staff, clearable: true)],
      if (widget.isStaff) ...[
        const SizedBox(height: 18), const Text('Снимки на устройството', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8), Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _photos.length >= 6 ? null : () => _addPhotos(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: const Text('Камера'))), const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: _photos.length >= 6 ? null : () => _addPhotos(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('Галерия')))]),
        if (_photos.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: [for (var i=0;i<_photos.length;i++) Stack(children: [ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(File(_photos[i].path), width: 94, height: 94, fit: BoxFit.cover)), Positioned(right: 0, top: 0, child: IconButton(onPressed: () => setState(() => _photos.removeAt(i)), icon: const Icon(Icons.cancel, color: Colors.red)))])]),
        Text('${_photos.length}/6 снимки · максимум 8 MB на снимка', style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ],
      const SizedBox(height: 20),
      if (_result != null) Card(child: ListTile(leading: const Icon(Icons.cloud_done, color: Colors.greenAccent), title: Text(_result!))),
      FilledButton.icon(onPressed: _busy ? null : _upload, icon: _busy ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.cloud_upload), label: Text(_busy ? 'Записване…' : 'Запиши към ремонта')),
      const SizedBox(height: 10),
      const Text('Достъпът се проверява от WordPress. Клиентът може да добави своя подпис към собствен ремонт; снимки и подпис на служител са достъпни само за служители с права за съответния обект. За продукционна употреба файловете трябва да се обслужват през защитен файлов endpoint или частно хранилище, а не чрез публични URL адреси.', style: TextStyle(color: Colors.white60, fontSize: 12)),
    ]),
  );
}
