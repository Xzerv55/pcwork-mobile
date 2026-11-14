import 'package:flutter/material.dart';
import '../services/api_service.dart';

class JoystickLabScreen extends StatefulWidget {
  const JoystickLabScreen({super.key, required this.api, required this.token, required this.english});
  final ApiService api;
  final String token;
  final bool english;

  @override
  State<JoystickLabScreen> createState() => _JoystickLabScreenState();
}

class _JoystickLabScreenState extends State<JoystickLabScreen> {
  static const cyan = Color(0xFF21D4D8);
  String _model = 'DualSense';
  String _connection = 'not_connected';
  final Map<String, bool> _checks = <String, bool>{};
  bool _saving = false;
  String? _message;
  final _leftDrift = TextEditingController();
  final _rightDrift = TextEditingController();
  final _leftCircularity = TextEditingController();
  final _rightCircularity = TextEditingController();
  final _leftTrigger = TextEditingController();
  final _rightTrigger = TextEditingController();

  @override
  void dispose() {
    _leftDrift.dispose(); _rightDrift.dispose(); _leftCircularity.dispose();
    _rightCircularity.dispose(); _leftTrigger.dispose(); _rightTrigger.dispose();
    super.dispose();
  }

  double? _metric(TextEditingController controller) {
    final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite || value < 0 || value > 100) return null;
    return value;
  }
  bool get en => widget.english;
  String t(String bg, String english) => en ? english : bg;

  final List<String> _controls = const ['D-pad', '△', '○', '×', '□', 'L1', 'R1', 'L2', 'R2', 'L3', 'R3', 'PS', 'Create', 'Options', 'Touchpad'];

  Future<void> _saveReport() async {
    if (_saving) return;
    final metricFields = [_leftDrift, _rightDrift, _leftCircularity, _rightCircularity, _leftTrigger, _rightTrigger];
    if (metricFields.any((field) => field.text.trim().isNotEmpty && _metric(field) == null)) {
      setState(() => _message = t('Невалидна стойност. Използвай число между 0 и 100.', 'Invalid value. Enter a number between 0 and 100.'));
      return;
    }
    setState(() { _saving = true; _message = null; });
    try {
      final result = await widget.api.createJoystickReport(widget.token, {
        'controller_model': _model,
        'connection_status': _connection,
        'test_mode': 'manual_with_measurements',
        'checks': _checks.map((key, value) => MapEntry(key, value ? 'pass' : 'not_tested')),
        'metrics': <String, dynamic>{
          if (_metric(_leftDrift) != null) 'left_drift_percent': _metric(_leftDrift),
          if (_metric(_rightDrift) != null) 'right_drift_percent': _metric(_rightDrift),
          if (_metric(_leftCircularity) != null) 'left_circularity_variation_percent': _metric(_leftCircularity),
          if (_metric(_rightCircularity) != null) 'right_circularity_variation_percent': _metric(_rightCircularity),
          if (_metric(_leftTrigger) != null) 'left_trigger_percent': _metric(_leftTrigger),
          if (_metric(_rightTrigger) != null) 'right_trigger_percent': _metric(_rightTrigger),
        },
        'notes': 'Measurements are technician-entered from the PCWork Windows Joystick Lab. Android live USB/HID capture is not yet enabled.',
      });
      if (!mounted) return;
      setState(() => _message = result['message']?.toString() ?? t('Протоколът е записан.', 'Report saved.'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = '${t('Грешка при запис: ', 'Save failed: ')}$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t('PCWork Joystick Lab', 'PCWork Joystick Lab'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(colors: [Color(0xFF101C32), Color(0xFF173A52)]),
        ), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.gamepad_rounded, color: cyan, size: 30), SizedBox(width: 10), Expanded(child: Text('PCWORK DIAGNOSTICS', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.bold)))]),
          const SizedBox(height: 12),
          Text(t('Диагностика на PS4 / PS5 контролери', 'PS4 / PS5 controller diagnostics'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(t('Версия 1.71: сервизен протокол с измерени показатели от Windows Joystick Lab. Android USB OTG измерването остава отделна следваща задача.', 'Version 1.71: service reports can store measured values from Windows Joystick Lab. Android USB OTG capture remains a separate upcoming task.'), style: const TextStyle(color: Colors.white70, height: 1.45)),
        ])),
        const SizedBox(height: 16),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('Устройство', 'Controller'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: _model, decoration: InputDecoration(labelText: t('Модел', 'Model')), items: const [DropdownMenuItem(value: 'DualSense', child: Text('Sony DualSense (PS5)')), DropdownMenuItem(value: 'DualShock 4', child: Text('Sony DualShock 4 (PS4)')), DropdownMenuItem(value: 'DualSense Edge', child: Text('Sony DualSense Edge'))], onChanged: (v) => setState(() => _model = v ?? _model)),
          const SizedBox(height: 10),
          Row(children: [const Icon(Icons.usb_rounded, color: cyan), const SizedBox(width: 8), Expanded(child: Text(t('USB статус: не е свързан (Android HID engine в разработка)', 'USB status: not connected (Android HID engine in development)')))]),
        ]))),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('Измерени показатели от Windows', 'Measurements from Windows'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(t('Въведи стойностите от JSON/екрана на PCWork Joystick Lab Windows. Полетата са незадължителни; диапазон 0–100%.', 'Enter values from the PCWork Joystick Lab Windows screen/JSON. Fields are optional; range 0–100%.'), style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: TextField(controller: _leftDrift, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: t('Ляв drift %', 'Left drift %')))), const SizedBox(width: 10), Expanded(child: TextField(controller: _rightDrift, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: t('Десен drift %', 'Right drift %'))))]),
          Row(children: [Expanded(child: TextField(controller: _leftCircularity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: t('Ляв circularity %', 'Left circularity %')))), const SizedBox(width: 10), Expanded(child: TextField(controller: _rightCircularity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: t('Десен circularity %', 'Right circularity %'))))]),
          Row(children: [Expanded(child: TextField(controller: _leftTrigger, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: t('L2 натиск %', 'L2 press %')))), const SizedBox(width: 10), Expanded(child: TextField(controller: _rightTrigger, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: t('R2 натиск %', 'R2 press %'))))]),
        ]))),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('Контролен списък', 'Inspection checklist'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(t('Отбелязвай само физически проверени елементи. Този списък не симулира автоматично измерване.', 'Mark only items physically tested. This checklist does not simulate automatic measurements.'), style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          ..._controls.map((control) => CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, activeColor: cyan, title: Text(control), subtitle: Text(_checks[control] == true ? t('Проверен – изправен', 'Tested – passed') : t('Не е проверен', 'Not tested')), value: _checks[control] ?? false, onChanged: (v) => setState(() => _checks[control] = v ?? false))),
        ]))),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _saving ? null : _saveReport, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined), label: Text(t('Запази сервизен протокол', 'Save service report'))),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_message!, style: theme.textTheme.bodyMedium)),
      ]),
    );
  }
}
