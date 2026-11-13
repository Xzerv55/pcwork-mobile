import 'package:flutter/material.dart';
import '../services/api_service.dart';

class SyncCenterScreen extends StatefulWidget {
  const SyncCenterScreen({
    super.key,
    required this.api,
    required this.token,
    required this.english,
    required this.autoSyncEnabled,
    required this.onAutoSyncChanged,
  });

  final ApiService api;
  final String token;
  final bool english;
  final bool autoSyncEnabled;
  final ValueChanged<bool> onAutoSyncChanged;

  @override
  State<SyncCenterScreen> createState() => _SyncCenterScreenState();
}

class _SyncCenterScreenState extends State<SyncCenterScreen> {
  bool _loading = true;
  bool _refreshInProgress = false;
  bool _checkingServer = false;
  bool _syncing = false;
  bool _connected = false;
  bool _autoSync = true;
  int _pending = 0;
  List<Map<String, dynamic>> _queue = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];
  Map<String, dynamic>? _health;
  String? _message;
  String? _error;
  DateTime? _lastChecked;

  String tr(String bg, String en) => widget.english ? en : bg;

  @override
  void initState() {
    super.initState();
    _autoSync = widget.autoSyncEnabled;
    _refresh(checkServer: true);
  }

  @override
  void didUpdateWidget(covariant SyncCenterScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoSyncEnabled != widget.autoSyncEnabled) {
      _autoSync = widget.autoSyncEnabled;
    }
  }

  Future<void> _refresh({bool checkServer = true}) async {
    if (_refreshInProgress || _syncing || _checkingServer) return;
    _refreshInProgress = true;
    setState(() {
      _loading = true;
      _checkingServer = checkServer;
      _error = null;
      _message = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        widget.api.pendingOperations(widget.token),
        widget.api.getSyncHistory(widget.token),
        widget.api.pendingOperationCount(widget.token),
      ]);
      final queue = results[0] as List<Map<String, dynamic>>;
      final history = results[1] as List<Map<String, dynamic>>;
      final pending = results[2] as int;
      Map<String, dynamic>? health = _health;
      var connected = _connected;
      if (checkServer) {
        health = await widget.api.getHealthDetails();
        connected = health['ok'] == true;
      }
      if (!mounted) return;
      setState(() {
        _queue = queue;
        _history = history;
        _pending = pending;
        _health = health;
        _connected = connected;
        _lastChecked = DateTime.now();
        _message = checkServer
            ? tr('Проверката на сървъра и локалната опашка приключи.', 'Server and local queue check completed.')
            : tr('Локалната опашка е обновена.', 'Local queue refreshed.');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (checkServer) _connected = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      _refreshInProgress = false;
      if (mounted) setState(() { _loading = false; _checkingServer = false; });
    }
  }

  Future<void> _syncNow() async {
    if (_syncing || _checkingServer || _pending == 0) return;
    setState(() { _syncing = true; _error = null; _message = null; });
    try {
      final health = await widget.api.getHealthDetails();
      if (health['ok'] != true) throw Exception(tr('Сървърът не потвърди готовност.', 'The server did not confirm readiness.'));
      final report = await widget.api.syncPendingOperationsDetailed(widget.token);
      final sent = (report['sent'] as num?)?.toInt() ?? 0;
      await _refreshAfterSync();
      if (!mounted) return;
      setState(() => _message = report['busy'] == true
          ? tr('Вече се изпълнява синхронизация. Опашката е обновена.', 'A synchronization is already running. The queue was refreshed.')
          : tr('Изпратени операции: $sent. Оставащи: $_pending.', 'Operations sent: $sent. Remaining: $_pending.'));
    } catch (error) {
      await _refreshAfterSync();
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _refreshAfterSync() async {
    final results = await Future.wait<dynamic>([
      widget.api.pendingOperations(widget.token),
      widget.api.getSyncHistory(widget.token),
      widget.api.pendingOperationCount(widget.token),
    ]);
    if (!mounted) return;
    setState(() {
      _queue = results[0] as List<Map<String, dynamic>>;
      _history = results[1] as List<Map<String, dynamic>>;
      _pending = results[2] as int;
      _connected = true;
      _lastChecked = DateTime.now();
    });
  }

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return value?.toString() ?? '—';
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _sectionTitle(String title, IconData icon) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 18, 2, 9),
    child: Row(children: [Icon(icon, color: const Color(0xFF21D4D8), size: 19), const SizedBox(width: 9), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))) ]),
  );

  Widget _metric(String title, String value, IconData icon, Color color) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(13),
      child: Row(children: [Icon(icon, color: color, size: 22), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .65))), const SizedBox(height: 4), Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900))]))]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final successful = _history.where((row) => row['success'] == true).length;
    final failed = _history.where((row) => row['success'] != true).length;
    final lastSuccess = _history.where((row) => row['success'] == true).toList();
    final lastSuccessAt = lastSuccess.isEmpty ? null : lastSuccess.last['at'];
    final busy = _loading || _checkingServer || _syncing;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Център за синхронизация', 'Synchronization center')),
        actions: [IconButton(tooltip: tr('Обнови', 'Refresh'), onPressed: busy ? null : () => _refresh(checkServer: true), icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(checkServer: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(_connected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, color: _connected ? Colors.greenAccent : Colors.orangeAccent, size: 27),
                    const SizedBox(width: 11),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_connected ? tr('Сървърът е достъпен', 'Server is reachable') : tr('Няма потвърдена връзка', 'Connection not confirmed'), style: const TextStyle(fontWeight: FontWeight.w900)),
                      Text(widget.api.baseUrl, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .65)), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ])),
                    if (_health?['version'] != null) Text('v${_health!['version']}', style: const TextStyle(fontSize: 11)),
                  ]),
                  if (_lastChecked != null) Padding(padding: const EdgeInsets.only(top: 9), child: Text('${tr('Последна проверка', 'Last checked')}: ${_formatDate(_lastChecked!.toIso8601String())}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .6)))),
                  if (_checkingServer) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text('${tr('Грешка', 'Error')}: $_error', style: const TextStyle(color: Colors.orangeAccent, fontSize: 12))),
                  if (_message != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_message!, style: const TextStyle(color: Color(0xFF21D4D8), fontSize: 12))),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(onPressed: busy ? null : () => _refresh(checkServer: true), icon: const Icon(Icons.wifi_tethering_rounded), label: Text(tr('Провери сървъра', 'Check server'))),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _metric(tr('Чакащи', 'Pending'), '$_pending', Icons.pending_actions_rounded, Colors.orangeAccent)),
              const SizedBox(width: 9),
              Expanded(child: _metric(tr('Успешни', 'Successful'), '$successful', Icons.check_circle_outline_rounded, Colors.greenAccent)),
            ]),
            const SizedBox(height: 9),
            Row(children: [
              Expanded(child: _metric(tr('Неуспешни', 'Failed'), '$failed', Icons.error_outline_rounded, Colors.orangeAccent)),
              const SizedBox(width: 9),
              Expanded(child: _metric(tr('Общо в историята', 'History records'), '${_history.length}', Icons.history_rounded, const Color(0xFF21D4D8))),
            ]),
            _sectionTitle(tr('Автоматична синхронизация', 'Automatic synchronization'), Icons.autorenew_rounded),
            Card(child: SwitchListTile(
              value: _autoSync,
              onChanged: (value) {
                setState(() => _autoSync = value);
                widget.onAutoSyncChanged(value);
              },
              title: Text(_autoSync ? tr('Включена', 'Enabled') : tr('Изключена', 'Disabled'), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(tr('При включване приложението проверява опашката периодично на всеки 2 минути и при връщане на приложението на преден план.', 'When enabled, the app checks the queue every 2 minutes and when it returns to the foreground.'), style: const TextStyle(fontSize: 11)),
              secondary: const Icon(Icons.sync_rounded, color: Color(0xFF21D4D8)),
            )),
            _sectionTitle(tr('Локална офлайн опашка', 'Local offline queue'), Icons.storage_rounded),
            if (_queue.isEmpty)
              Card(child: Padding(padding: const EdgeInsets.all(15), child: Row(children: [const Icon(Icons.check_circle_outline, color: Colors.greenAccent), const SizedBox(width: 10), Expanded(child: Text(tr('Няма чакащи операции. Опашката е празна.', 'No pending operations. The queue is empty.')))])))
            else ..._queue.map((item) {
              final type = item['type'] == 'create' ? tr('Нов прием на устройство', 'New device intake') : item['type'] == 'status' ? tr('Промяна на статус', 'Status change') : tr('Непозната операция', 'Unknown operation');
              final id = item['repair_id'] == null ? tr('Чака изпращане', 'Waiting to send') : '${tr('Ремонт', 'Repair')} #${item['repair_id']}';
              return Card(margin: const EdgeInsets.only(bottom: 7), child: ListTile(dense: true, leading: const Icon(Icons.schedule_rounded, color: Colors.orangeAccent), title: Text(type, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)), subtitle: Text('$id · ${_formatDate(item['queued_at'])}', style: const TextStyle(fontSize: 11)), trailing: const Icon(Icons.cloud_upload_outlined)));
            }),
            _sectionTitle(tr('История на синхронизацията', 'Synchronization history'), Icons.history_rounded),
            if (_history.isEmpty)
              Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(tr('Все още няма записани резултати.', 'No synchronization results have been recorded yet.'), style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .65)))))
            else ..._history.reversed.take(20).map((item) {
              final ok = item['success'] == true;
              final type = item['type'] == 'create' ? tr('Нов прием', 'New intake') : item['type'] == 'status' ? tr('Статус', 'Status') : tr('Операция', 'Operation');
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 7),
                leading: Icon(ok ? Icons.check_circle_outline : Icons.error_outline, color: ok ? Colors.greenAccent : Colors.orangeAccent),
                title: Text(type, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                subtitle: Text('${item['message'] ?? '—'}\n${_formatDate(item['at'])}', style: const TextStyle(fontSize: 11)),
                isThreeLine: true,
              );
            }),
            if (lastSuccessAt != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${tr('Последна успешна синхронизация', 'Last successful synchronization')}: ${_formatDate(lastSuccessAt)}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .65)))),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy || _pending == 0 ? null : _syncNow,
              icon: _syncing ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync_rounded),
              label: Text(_syncing ? tr('Синхронизиране…', 'Synchronizing…') : tr('Синхронизирай сега', 'Sync now')),
            ),
            OutlinedButton.icon(onPressed: busy ? null : () => _refresh(checkServer: false), icon: const Icon(Icons.refresh_rounded), label: Text(tr('Обнови локалната опашка', 'Refresh local queue'))),
            if (_loading && _lastChecked == null) const Padding(padding: EdgeInsets.only(top: 16), child: Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    );
  }
}
