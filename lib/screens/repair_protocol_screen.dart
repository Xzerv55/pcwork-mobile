import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:signature/signature.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;

class RepairProtocolScreen extends StatefulWidget {
  const RepairProtocolScreen({super.key, required this.repairNumber, required this.device, required this.location, required this.problem, required this.status, required this.createdAt, this.baseUrl = '', this.token = '', this.repairId = 0, this.canEmail = false});
  final String repairNumber, device, location, problem, status, createdAt, baseUrl, token;
  final int repairId;
  final bool canEmail;
  @override
  State<RepairProtocolScreen> createState() => _RepairProtocolScreenState();
}

class _RepairProtocolScreenState extends State<RepairProtocolScreen> {
  late final SignatureController _signature;
  bool _working = false;
  bool _emailCustomer = false;
  String? _serverMessage;
  static const cyan = Color(0xFF21D4D8);

  @override
  void initState() {
    super.initState();
    _signature = SignatureController(penStrokeWidth: 2.5, penColor: Colors.black, exportBackgroundColor: Colors.white);
  }
  @override
  void dispose() { _signature.dispose(); super.dispose(); }

  Future<void> _makePdf() async {
    if (_signature.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Моля, добавете подпис в полето преди генериране на PDF.')));
      return;
    }
    setState(() => _working = true);
    try {
      final Uint8List? signature = await _signature.toPngBytes();
      if (signature == null) throw Exception('Подписът не може да бъде прочетен.');
      final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
      final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));
      doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(32), build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('PCWork', style: pw.TextStyle(font: bold, fontSize: 24)), pw.Text('Сервизен протокол', style: pw.TextStyle(font: bold, fontSize: 17))]),
          pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: widget.repairNumber, width: 76, height: 76),
        ]),
        pw.SizedBox(height: 16), pw.Divider(),
        _pdfLine('Номер на ремонт', widget.repairNumber, bold),
        _pdfLine('Дата на регистрация', widget.createdAt, bold),
        _pdfLine('Сервизен обект', widget.location, bold),
        _pdfLine('Устройство', widget.device, bold),
        _pdfLine('Статус', widget.status, bold),
        pw.SizedBox(height: 10), pw.Text('Описание на проблема', style: pw.TextStyle(font: bold)),
        pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)), child: pw.Text(widget.problem.isEmpty ? 'Не е посочено.' : widget.problem)),
        pw.Spacer(), pw.Text('Подпис на клиента', style: pw.TextStyle(font: bold)), pw.SizedBox(height: 6),
        pw.Container(height: 95, width: 260, padding: const pw.EdgeInsets.all(4), decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey500)), child: pw.Image(pw.MemoryImage(signature), fit: pw.BoxFit.contain)),
        pw.SizedBox(height: 8), pw.Text('Подписът е въведен в мобилното приложение. Този файл е генериран за преглед и не удостоверява сам по себе си правно съгласие или приемане на общи условия.', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        pw.SizedBox(height: 12), pw.Divider(), pw.Text('PCWork · pcwork-bg.com', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      ])));
      final pdfBytes = await doc.save();
      if (widget.canEmail && widget.baseUrl.isNotEmpty && widget.token.isNotEmpty && widget.repairId > 0) {
        final uri = Uri.parse('${widget.baseUrl.replaceFirst(RegExp(r'/+$'), '')}/wp-json/pcwork/v1/repairs/${widget.repairId}/protocol');
        final request = http.MultipartRequest('POST', uri)..headers['Authorization'] = 'Bearer ${widget.token}'..files.add(http.MultipartFile.fromBytes('protocol_pdf', pdfBytes, filename: 'PCWork_${widget.repairNumber}.pdf'));
        if (_emailCustomer && widget.canEmail) request.fields['send_email'] = '1';
        final response = await request.send().timeout(const Duration(seconds: 45));
        final body = await response.stream.bytesToString();
        if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Сървърът не записа PDF (HTTP ${response.statusCode}): $body');
        if (mounted) setState(() => _serverMessage = _emailCustomer ? 'PDF е записан. Заявено е изпращане по имейл.' : 'PDF е записан в защитеното досие на ремонта.');
      } else {
       if (mounted) {
  setState(() => _serverMessage = widget.canEmail);
}
            ? 'PDF е създаден локално. Няма конфигурирана сървърна сесия за архивиране.'
            : 'PDF е създаден локално и може да бъде споделен. Качването в сервизния архив е достъпно само за служители.');
      }
      await Printing.sharePdf(bytes: pdfBytes, filename: 'PCWork_${widget.repairNumber}.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Грешка при генериране на PDF: $e')));
    } finally { if (mounted) setState(() => _working = false); }
  }

  pw.Widget _pdfLine(String label, String value, pw.Font bold) => pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4), child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.SizedBox(width: 145, child: pw.Text('$label:', style: pw.TextStyle(font: bold))), pw.Expanded(child: pw.Text(value.isEmpty ? '—' : value))]));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Сервизен протокол')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('PCWork · Сервизен протокол', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12), _line('Номер', widget.repairNumber), _line('Устройство', widget.device), _line('Обект', widget.location), _line('Статус', widget.status), _line('Дата', widget.createdAt), _line('Проблем', widget.problem),
      ]))),
      const SizedBox(height: 14),
      Center(child: QrImageView(data: widget.repairNumber, version: QrVersions.auto, size: 176, backgroundColor: Colors.white, padding: const EdgeInsets.all(12))),
      const Center(child: Text('QR код с номера на ремонта', style: TextStyle(color: Colors.white70))),
      const SizedBox(height: 22), const Text('Подпис на клиента', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8), Container(height: 190, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Signature(controller: _signature, backgroundColor: Colors.white)),
      Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _signature.clear, icon: const Icon(Icons.refresh), label: const Text('Изчисти подписа'))),
      if (widget.canEmail) CheckboxListTile(contentPadding: EdgeInsets.zero, value: _emailCustomer, onChanged: _working ? null : (v) => setState(() => _emailCustomer = v ?? false), title: const Text('Изпрати копие на клиента по имейл'), subtitle: const Text('Изпращането се извършва от WordPress след успешно записване на PDF.'), controlAffinity: ListTileControlAffinity.leading),
      if (_serverMessage != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_serverMessage!, style: const TextStyle(color: cyan))),
      const SizedBox(height: 8),
      FilledButton.icon(onPressed: _working ? null : _makePdf, icon: _working ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf), label: Text(_working ? 'Подготвяне…' : 'Генерирай и сподели PDF')),
      const SizedBox(height: 10),
      const Text('Важно: в тази версия подписът се използва само при генериране на PDF на устройството и не се записва на сървъра. Преди използване като официален приемо-предавателен документ трябва да се добавят сървърно съхранение, идентификация на подписващия и потвърждение на приложимите условия.', style: TextStyle(color: Colors.white60, fontSize: 12)),
    ]),
  );

  Widget _line(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 92, child: Text(label, style: const TextStyle(color: Colors.white60))), Expanded(child: Text(value.isEmpty ? '—' : value))]));
}
