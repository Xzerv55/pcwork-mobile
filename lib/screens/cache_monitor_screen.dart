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
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final result = await widget.api.getCacheMonitor(widget.token);
      if (mounted) setState(() { _report = result; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  String _value(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return '—';
    if (value is bool) return value ? tr('Да', 'Yes') : tr('Не', 'No');
    return value.toString();
  }

  String _label(String key) {
    const labels = <String, String>{
      'redis_version': 'Redis версия',
      'redis_mode': 'Режим Redis',
      'role': 'Роля на сървъра',
      'uptime_in_seconds': 'Време на работа (сек.)',
      'connected_clients': 'Свързани клиенти',
      'blocked_clients': 'Блокирани клиенти',
      'used_memory': 'Използвана памет (bytes)',
      'used_memory_peak': 'Пикова памет (bytes)',
      'used_memory_rss': 'RSS памет (bytes)',
      'maxmemory': 'Лимит памет (bytes)',
      'mem_fragmentation_ratio': 'Фрагментация на паметта',
      'total_connections_received': 'Общо връзки',
      'total_commands_processed': 'Общо команди',
      'instantaneous_ops_per_sec': 'Операции в секунда',
      'keyspace_hits': 'Redis Hits',
      'keyspace_misses': 'Redis Misses',
      'evicted_keys': 'Премахнати ключове',
      'expired_keys': 'Изтекли ключове',
      'rejected_connections': 'Отхвърлени връзки',
      'total_net_input_bytes': 'Мрежов вход (bytes)',
      'total_net_output_bytes': 'Мрежов изход (bytes)',
      'connected_slaves': 'Свързани реплики',
      'keyspace_keys_total': 'Общо ключове в Redis',
      'keyspace_expiring_keys_total': 'Ключове с изтичане',
      'loading': 'Зареждане на Redis',
      'aof_enabled': 'AOF журнал',
    };
    return labels[key] ?? key.replaceAll('_', ' ');
  }

  Widget _metric(String label, dynamic value, {String? suffix, IconData icon = Icons.analytics_outlined}) =>
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: const Color(0xFF21D4D8)),
            const SizedBox(width: 9),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('${_value(value)}${value != null ? (suffix ?? '') : ''}',
                  softWrap: true, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ])),
          ]),
        ),
      );

  Widget _metricGrid(List<Widget> metrics) => LayoutBuilder(builder: (context, constraints) {
    final columns = constraints.maxWidth >= 760 ? 3 : 2;
    final gap = 9.0;
    final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
    return Wrap(spacing: gap, runSpacing: gap,
        children: metrics.map((metric) => SizedBox(width: width, child: metric)).toList());
  });

  Widget _sectionTitle(String title, String subtitle) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 18, 2, 9),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      const SizedBox(height: 3),
      Text(subtitle, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final cache = _report['object_cache'] is Map
        ? Map<String, dynamic>.from(_report['object_cache']) : <String, dynamic>{};
    final redis = _report['redis'] is Map
        ? Map<String, dynamic>.from(_report['redis']) : <String, dynamic>{};
    final server = _report['server'] is Map
        ? Map<String, dynamic>.from(_report['server']) : <String, dynamic>{};
    final stats = redis['stats'] is Map
        ? Map<String, dynamic>.from(redis['stats']) : <String, dynamic>{};
    final objectStats = cache['stats'] is Map
        ? Map<String, dynamic>.from(cache['stats']) : <String, dynamic>{};

    return Scaffold(
      appBar: AppBar(title: Text(tr('Redis и Object Cache', 'Redis & Object Cache')),
        actions: [IconButton(tooltip: tr('Обнови', 'Refresh'), onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center)))
              : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 24), children: [
                  Card(child: ListTile(
                    leading: Icon(cache['enabled'] == true ? Icons.check_circle : Icons.warning_amber,
                        color: cache['enabled'] == true ? Colors.greenAccent : Colors.orangeAccent),
                    title: Text(tr('Постоянен Object Cache', 'Persistent Object Cache')),
                    subtitle: Text(cache['enabled'] == true ? tr('Активиран', 'Enabled') : tr('Не е активиран', 'Not enabled')),
                    trailing: const Icon(Icons.storage_outlined),
                  )),
                  _sectionTitle(tr('Състояние на Object Cache', 'Object Cache health'), tr('Проверка на реалния запис и четене', 'Live write/read probe')),
                  _metricGrid([
                    _metric(tr('Backend клас', 'Backend class'), cache['backend_class'], icon: Icons.memory_outlined),
                    _metric(tr('Тест запис/четене', 'Read/write test'), cache['probe_ok'], icon: Icons.fact_check_outlined),
                    _metric(tr('Време на теста', 'Probe duration'), cache['probe_duration_ms'], suffix: ' ms', icon: Icons.timer_outlined),
                    _metric('Object Cache Hits', cache['hits'], icon: Icons.trending_up),
                    _metric('Object Cache Misses', cache['misses'], icon: Icons.trending_down),
                  ]),
                  if (objectStats.isNotEmpty) ...[
                    _sectionTitle(tr('Допълнителни показатели на кеша', 'Additional cache metrics'), tr('Показатели, предоставени от активния backend', 'Metrics exposed by the active backend')),
                    _metricGrid(objectStats.entries.map((e) => _metric(_label(e.key), e.value)).toList()),
                  ],
                  _sectionTitle('REDIS', tr('Сървърни показатели от Redis INFO', 'Server metrics from Redis INFO')),
                  Card(child: ListTile(
                    leading: Icon(redis['metrics_available'] == true ? Icons.check_circle : Icons.info_outline,
                        color: redis['metrics_available'] == true ? Colors.greenAccent : Colors.orangeAccent),
                    title: Text(tr('Redis диагностика', 'Redis diagnostics')),
                    subtitle: Text('${tr('PHP разширение', 'PHP extension')}: ${_value(redis['php_extension_loaded'])} · ${tr('INFO показатели', 'INFO metrics')}: ${_value(redis['metrics_available'])}'),
                  )),
                  if (redis['hit_ratio_percent'] != null)
                    _metric(tr('Redis Hit Ratio', 'Redis hit ratio'), redis['hit_ratio_percent'], suffix: '%', icon: Icons.speed),
                  if (stats.isNotEmpty)
                    _metricGrid(stats.entries.map((e) => _metric(_label(e.key), e.value)).toList())
                  else
                    Card(child: Padding(padding: const EdgeInsets.all(13), child: Text(
                      tr('Активният backend не предоставя Redis INFO показатели. Това не означава непременно, че Redis не работи; проверката за запис и четене по-горе показва дали WordPress Object Cache отговаря.',
                         'The active backend does not expose Redis INFO metrics. This does not necessarily mean Redis is offline; the write/read probe above verifies whether the WordPress object cache responds.'),
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)))),
                  _sectionTitle(tr('Среда на сървъра', 'Server environment'), tr('Ограничена техническа информация без данни за връзка или тайни', 'Limited technical information; no connection details or secrets')),
                  _metricGrid([
                    _metric('PHP', server['php_version'], icon: Icons.code),
                    _metric('WordPress', server['wordpress_version'], icon: Icons.public),
                    _metric(tr('PHP memory limit', 'PHP memory limit'), server['memory_limit'], icon: Icons.memory),
                    _metric(tr('Използвана памет', 'Memory usage'), server['memory_usage_bytes'], suffix: ' B', icon: Icons.data_usage),
                    _metric(tr('Пикова памет', 'Peak memory'), server['memory_peak_bytes'], suffix: ' B', icon: Icons.stacked_line_chart),
                  ]),
                  if (_report['notes'] is Map && (_report['notes'] as Map)['metrics'] != null)
                    Padding(padding: const EdgeInsets.only(top: 12), child: Text('${tr('Бележка', 'Note')}: ${(_report['notes'] as Map)['metrics']}',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                  if (_report['checked_at'] != null)
                    Padding(padding: const EdgeInsets.only(top: 10), child: Text('${tr('Последна проверка', 'Last checked')}: ${_report['checked_at']}',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                ])),
    );
  }
}
