import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/api_service.dart';

/// Staff-only QR scanner. The QR contains only the repair number, never customer PII.
class RepairQrScannerScreen extends StatefulWidget {
  const RepairQrScannerScreen({super.key, required this.api, required this.token, required this.english});
  final ApiService api;
  final String token;
  final bool english;

  @override
  State<RepairQrScannerScreen> createState() => _RepairQrScannerScreenState();
}

class _RepairQrScannerScreenState extends State<RepairQrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _resolving = false;
  String? _message;
  String tr(String bg, String en) => widget.english ? en : bg;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_resolving) return;
    final raw = capture.barcodes.map((b) => b.rawValue).firstWhere((v) => v != null && v.trim().isNotEmpty, orElse: () => null);
    if (raw == null) return;
    final code = raw.trim();
    // Accept the legacy repair-number QR and the PCW-<id> fallback format.
    if (code.length > 100 || code.contains('\n') || code.contains('\r')) {
      setState(() => _message = tr('Невалиден QR код.','Invalid QR code.'));
      return;
    }
    setState(() { _resolving = true; _message = tr('Намиране на ремонта…','Finding repair…'); });
    try {
      final repair = await widget.api.lookupRepairByQr(widget.token, code);
      if (!mounted) return;
      await _controller.stop();
      if (!mounted) return;
      Navigator.of(context).pop(repair);
    } catch (e) {
      if (!mounted) return;
      setState(() { _resolving = false; _message = e.toString().replaceFirst('Exception: ', ''); });
      await _controller.start();
    }
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Сканирай сервизен QR','Scan service QR')), actions: [
      IconButton(tooltip: tr('Светкавица','Flash'), onPressed: () => _controller.toggleTorch(), icon: const Icon(Icons.flash_on_outlined)),
      IconButton(tooltip: tr('Смени камерата','Switch camera'), onPressed: () => _controller.switchCamera(), icon: const Icon(Icons.cameraswitch_outlined)),
    ]),
    body: Column(children: [
      Expanded(child: Stack(fit: StackFit.expand, children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        IgnorePointer(child: Center(child: Container(width: 260, height: 190, decoration: BoxDecoration(border: Border.all(color: const Color(0xFF21D4D8), width: 3), borderRadius: BorderRadius.circular(18))))),
        if (_resolving) Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator())),
      ])),
      Padding(padding: const EdgeInsets.all(18), child: Column(children: [
        Text(tr('Насочете камерата към QR кода от сервизния протокол.','Point the camera at the QR code on the service protocol.'), textAlign: TextAlign.center),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_message!, textAlign: TextAlign.center, style: TextStyle(color: _resolving ? Colors.cyanAccent : Colors.orangeAccent))),
        const SizedBox(height: 8),
        Text(tr('QR кодът съдържа само номера на ремонта.','The QR code contains only the repair number.'), style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
      ])),
    ]),
  );
}
