import 'package:flutter/material.dart';
import '../services/api_service.dart';

class SynchronizationCenterScreen extends StatefulWidget {
  const SynchronizationCenterScreen({super.key, required this.api, required this.token, required this.english, required this.onSyncCompleted});
  final ApiService api;
  final String token;
  final bool english;
  final Future<void> Function() onSyncCompleted;

  @override
  State<SynchronizationCenterScreen> createState() => _SynchronizationCenterScreenState();
}

class _SynchronizationCenterScreenState extends State<SynchronizationCenterScreen> {
  bool _loading = false, _syncing = false, _connected = false;
  int _pending = 0;
  String? _pluginVersion, _message;
  DateTime? _lastChecked;
  List<Map<String, dynamic>> _queue = [], _history = [];
  String tr(String bg, String en) => widget.english ? en : bg;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _refresh()); }

  Future<void> _refresh({bool checkServer = true}) async {
    if (_loading || _syncing) return;
    setState(() { _loading = true; _message = null; });
    try {
      final count = await widget.api.pendingOperationCount(widget.token);
      final queue = await widget.api.pendingOperations(widget.token);
      final history = await widget.api.getSyncHistory(widget.token);
      var connected = _connected;
      var version = _pluginVersion;
      if (checkServer) {
        final health = await widget.api.getHealthDetails();
        connected = health['ok'] == true;
        version = health['version']?.toString();
      }
      if (!mounted) return;
      setState(() { _pending = count; _queue = queue; _history = history; _connected = connected; _pluginVersion = version; _lastChecked = DateTime.now(); _message = tr('Данните са обновени.', 'Information refreshed.'); });
    } catch (e) {
      if (!mounted) return;
      setState(() { if (checkServer) _connected = false; _message = '${tr('Грешка', 'Error')}: ${e.toString().replaceFirst('Exception: ', '')}'; });
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _sync() async {
    if (_syncing || _loading || _pending == 0) return;
    setState(() { _syncing = true; _message = null; });
    try {
      final health = await widget.api.getHealthDetails();
      if (health['ok'] != true) throw Exception(tr('Сървърът не потвърди готовност.', 'Server did not confirm readiness.'));
      final report = await widget.api.syncPendingOperationsDetailed(widget.token);
      await widget.onSyncCompleted();
      await _refreshAfterSync();
      if (!mounted) return;
      final sent = (report['sent'] as num?)?.toInt() ?? 0;
      final remaining = (report['remaining'] as num?)?.toInt() ?? 0;
      setState(() => _message = tr('Изпратени: $sent · Оставащи: $remaining', 'Sent: $sent · Remaining: $remaining'));
    } catch (e) { if (mounted) setState(() => _message = '${tr('Синхронизацията е неуспешна', 'Synchronization failed')}: $e'); }
    finally { if (mounted) setState(() => _syncing = false); }
  }

  Future<void> _refreshAfterSync() async {
    _pending = await widget.api.pendingOperationCount(widget.token);
    _queue = await widget.api.pendingOperations(widget.token);
    _history = await widget.api.getSyncHistory(widget.token);
    _lastChecked = DateTime.now();
    _connected = true;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading || _syncing;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Център за синхронизация', 'Synchronization center')), actions: [IconButton(tooltip: tr('Обнови', 'Refresh'), onPressed: busy ? null : () => _refresh(), icon: const Icon(Icons.refresh))]),
      body: SafeArea(child: RefreshIndicator(onRefresh: _refresh, child: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: ListTile(leading: Icon(_connected ? Icons.cloud_done : Icons.cloud_off, color: _connected ? Colors.green : Colors.orange), title: Text(_connected ? tr('Сървърът е достъпен', 'Server reachable') : tr('Няма потвърдена връзка', 'Connection not confirmed')), subtitle: Text(widget.api.baseUrl), trailing: _pluginVersion == null ? null : Text('v$_pluginVersion'))),
        Row(children: [Expanded(child: _metric(tr('Чакащи', 'Pending'), '$_pending', Icons.pending_actions)), const SizedBox(width: 10), Expanded(child: _metric(tr('Записани резултати', 'Recorded results'), '${_history.length}', Icons.history))]),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: busy || _pending == 0 ? null : _sync, icon: const Icon(Icons.sync), label: Text(tr('Синхронизирай сега', 'Sync now'))),
        OutlinedButton.icon(onPressed: busy ? null : () => _refresh(checkServer: true), icon: const Icon(Icons.wifi_tethering), label: Text(tr('Провери връзката и обнови', 'Check connection and refresh'))),
        if (busy) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()),
        if (_message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_message!)),
        if (_lastChecked != null) Text('${tr('Последна проверка', 'Last checked')}: ${_lastChecked!.toLocal()}'),
        const SizedBox(height: 18), Text(tr('Чакащи операции', 'Pending operations'), style: Theme.of(context).textTheme.titleMedium),
        if (_queue.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(tr('Няма чакащи операции.', 'No pending operations.'))),
        ..._queue.map((e) => Card(child: ListTile(leading: const Icon(Icons.schedule), title: Text(e['type']?.toString() ?? '—'), subtitle: Text([if (e['repair_id'] != null) 'ID ${e['repair_id']}', e['queued_at']?.toString() ?? ''].where((v) => v.isNotEmpty).join(' · '))))),
        const SizedBox(height: 18), Text(tr('История на синхронизацията', 'Synchronization history'), style: Theme.of(context).textTheme.titleMedium),
        if (_history.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(tr('Все още няма записани резултати.', 'No recorded results yet.'))),
        ..._history.reversed.take(30).map((e) { final ok = e['success'] == true; return ListTile(dense: true, leading: Icon(ok ? Icons.check_circle : Icons.error_outline, color: ok ? Colors.green : Colors.orange), title: Text(e['message']?.toString() ?? '—'), subtitle: Text('${e['type'] ?? ''} · ${e['at'] ?? ''}')); }),
        const SizedBox(height: 20), Text(tr('Офлайн операциите се пазят на устройството до успешно потвърждение от сървъра. Неуспешните операции остават в опашката за повторен опит.', 'Offline operations remain on this device until the server confirms success. Failed operations stay queued for retry.'), style: Theme.of(context).textTheme.bodySmall),
      ]))),
    );
  }

  Widget _metric(String label, String value, IconData icon) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [Icon(icon), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 12)), Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))]))])));
}
