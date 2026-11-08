import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DeviceMonitorScreen extends StatefulWidget {
  const DeviceMonitorScreen({super.key, required this.english});
  final bool english;
  @override
  State<DeviceMonitorScreen> createState() => _DeviceMonitorScreenState();
}

class _DeviceMonitorScreenState extends State<DeviceMonitorScreen> {
  static const _channel = MethodChannel('com.pcworkbg.pcwork_mobile/device_monitor');
  Map<String, dynamic>? _metrics;
  Object? _error;
  bool _loading = true;
  String tr(String bg, String en) => widget.english ? en : bg;

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('getDeviceMetrics');
      if (!mounted) return;
      setState(() { _metrics = result ?? {}; _loading = false; });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message ?? e.code; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e; _loading = false; });
    }
  }

  String _value(String key, [String fallback = '—']) => '${_metrics?[key] ?? fallback}';

  int? _intMetric(String key) {
    final value = _metrics?[key];
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  double? _doubleMetric(String key) {
    final value = _metrics?[key];
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }
  Widget _metric(String title, String value, IconData icon, {String? detail}) => Card(
    child: Padding(padding: const EdgeInsets.all(15), child: Row(children: [
      Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFF21D4D8).withValues(alpha: .13), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: const Color(0xFF21D4D8))),
      const SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)), const SizedBox(height: 3), Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), if (detail != null) Text(detail, style: const TextStyle(fontSize: 11, color: Colors.grey))]))
    ])));

  String _displayPercent(String key) {
    final value = _intMetric(key);
    return value == null || value < 0 ? '—' : '$value%';
  }

  String _displayBattery() {
    final value = _intMetric('batteryPercent');
    return value == null || value < 0 ? '—' : '$value%';
  }

  String _displayCpu() {
    final value = int.tryParse(_value('cpuUsage', '-1')) ?? -1;
    return value < 0 ? '—' : '$value%';
  }

  String _displayCharging() {
    final value = _value('chargingState');
    if (widget.english) return value;
    return value == 'Charging' ? 'Зарежда се' : value == 'On battery' ? 'На батерия' : value;
  }

  String _healthSummary() {
    if (_metrics == null) return tr('Няма налични данни.', 'No device data.');
    final battery = _intMetric('batteryPercent');
    final free = _doubleMetric('storageFreePercent');
    final ram = _doubleMetric('ramUsedPercent');
    final issues = <String>[];
    if (battery != null && battery >= 0 && battery <= 15) {
      issues.add(tr('Нисък заряд на батерията', 'Low battery'));
    }
    if (free != null && free < 10) {
      issues.add(tr('Недостатъчно свободно място', 'Low free storage'));
    }
    if (ram != null && ram > 90) {
      issues.add(tr('Високо използване на RAM', 'High RAM usage'));
    }
    if (battery == null && free == null && ram == null) {
      return tr('Няма достатъчно системни данни за оценка.', 'Not enough system data to assess device health.');
    }
    if (issues.isEmpty) return tr('Основните налични показатели са в нормални граници.', 'Available device indicators are within normal ranges.');
    return issues.join(' • ');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('PCWork Device Monitor', 'PCWork Device Monitor')), actions: [IconButton(onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh_rounded))]),
    body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null
      ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.info_outline, size: 42), const SizedBox(height: 12), Text(tr('Мониторингът не е наличен на това устройство.', 'Device monitoring is unavailable on this device.')), const SizedBox(height: 6), Text('$_error', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 12)), TextButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: Text(tr('Опитай отново', 'Try again')))])))
      : RefreshIndicator(onRefresh: _refresh, child: ListView(padding: const EdgeInsets.all(16), children: [
        Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF102C3A), Color(0xFF174B59)]), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.health_and_safety_rounded, color: Color(0xFF21D4D8), size: 32), const SizedBox(height: 8), Text(tr('Проверка на устройството', 'Device health check'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)), const SizedBox(height: 6), Text(_healthSummary(), style: const TextStyle(color: Colors.white70)), const SizedBox(height: 12), FilledButton.tonalIcon(onPressed: _refresh, icon: const Icon(Icons.monitor_heart_outlined), label: Text(tr('Провери устройството', 'Check device')))])),
        const SizedBox(height: 12), _metric(tr('Батерия', 'Battery'), _displayBattery(), Icons.battery_charging_full, detail: '${_displayCharging()} • ${_value('batteryTemperature')} °C'),
        _metric('RAM', _displayPercent('ramUsedPercent'), Icons.memory, detail: '${_value('ramUsed')} / ${_value('ramTotal')}'),
        _metric(tr('Вътрешна памет', 'Internal storage'), _displayPercent('storageUsedPercent'), Icons.storage, detail: '${_value('storageFree')} ${tr('свободни', 'free')} / ${_value('storageTotal')}'),
        _metric('CPU', _displayCpu(), Icons.developer_board, detail: tr('Текущо приблизително натоварване', 'Approximate current load')),
        _metric(tr('Модел на устройството', 'Device model'), _value('deviceModel'), Icons.phone_android),
        _metric(tr('Версия на Android', 'Android version'), _value('androidVersion'), Icons.android),
        const Padding(padding: EdgeInsets.only(top: 10), child: Text('PCWork Device Monitor • Данните се обработват локално на устройството.', style: TextStyle(color: Colors.grey, fontSize: 11))),
      ])),
  );
}
