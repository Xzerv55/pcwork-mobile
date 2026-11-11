import 'package:flutter/material.dart';
import '../services/api_service.dart';

class CacheMonitorScreen extends StatefulWidget {
  const CacheMonitorScreen({super.key, required this.api, required this.token, required this.english});
  final ApiService api;
  final String token;
  final bool english;
  @override
  State<CacheMonitorScreen> createState() => _CacheMonitorScreenState();
}

class _CacheMonitorScreenState extends State<CacheMonitorScreen> {
  Map<String, dynamic> _report = {};
  bool _loading = true;
  String? _error;
  String tr(String bg, String en) => widget.english ? en : bg;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await widget.api.getCacheMonitor(widget.token);
      if (mounted) setState(() { _report = result; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  String _value(dynamic value) => value == null ? '—' : value.toString();
  Widget _metric(String label, dynamic value, {String? suffix}) => Card(child: ListTile(
    title: Text(label, style: const TextStyle(fontSize: 13)),
    trailing: Text('${_value(value)}${value != null ? (suffix ?? '') : ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
  ));

  @override
  Widget build(BuildContext context) {
    final cache = _report['object_cache'] is Map ? Map<String, dynamic>.from(_report['object_cache']) : <String, dynamic>{};
    final redis = _report['redis'] is Map ? Map<String, dynamic>.from(_report['redis']) : <String, dynamic>{};
    final stats = redis['stats'] is Map ? Map<String, dynamic>.from(redis['stats']) : <String, dynamic>{};
    return Scaffold(
      appBar: AppBar(title: Text(tr('Redis и Object Cache', 'Redis & Object Cache')), actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null
        ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center)))
        : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(14), children: [
          Card(child: ListTile(leading: Icon(cache['enabled'] == true ? Icons.check_circle : Icons.warning_amber, color: cache['enabled'] == true ? Colors.green : Colors.orange), title: Text(tr('Постоянен Object Cache', 'Persistent Object Cache')), subtitle: Text(cache['enabled'] == true ? tr('Активиран', 'Enabled') : tr('Не е активиран', 'Not enabled')))),
          _metric(tr('Backend клас', 'Backend class'), cache['backend_class']),
          Card(child: ListTile(leading: Icon(cache['probe_ok'] == true ? Icons.check_circle : Icons.error, color: cache['probe_ok'] == true ? Colors.green : Colors.red), title: Text(tr('Тест запис/четене', 'Read/write test')), subtitle: Text(cache['probe_ok'] == true ? tr('Успешно: временен ключ е записан и прочетен два пъти.', 'Passed: temporary key was written and read twice.') : tr('Неуспешен тест на кеша.', 'Cache probe failed.')))),
          _metric('Object Cache Hits', cache['hits']),
          _metric('Object Cache Misses', cache['misses']),
          const SizedBox(height: 8),
          Text('REDIS', style: Theme.of(context).textTheme.titleMedium),
          _metric(tr('PHP Redis разширение', 'PHP Redis extension'), redis['php_extension_loaded'] == true ? 'Loaded' : 'Not loaded'),
          _metric(tr('Redis статистика достъпна', 'Redis metrics available'), redis['metrics_available'] == true ? tr('Да', 'Yes') : tr('Не', 'No')),
          _metric(tr('Redis Hit Ratio', 'Redis hit ratio'), redis['hit_ratio_percent'], suffix: '%'),
          for (final entry in stats.entries) _metric(entry.key, entry.value),
          const SizedBox(height: 10),
          Text(tr('Показателите се четат от сървъра при всяко обновяване. Ако Redis INFO не е изложен от кеш бекенда, това не означава, че Redis не работи — тестът за запис/четене показва дали WordPress Object Cache отговаря.', 'Metrics are fetched from the server on each refresh. If Redis INFO is not exposed by the cache backend, that does not mean Redis is down — the read/write probe verifies that the WordPress object cache responds.'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
          if (_report['checked_at'] != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text('${tr('Последна проверка', 'Last checked')}: ${_report['checked_at']}', style: const TextStyle(fontSize: 11, color: Colors.grey))),
        ])),
    );
  }
}
