import 'package:flutter/material.dart';
import '../services/api_service.dart';

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({super.key, required this.api, required this.token, required this.english});
  final ApiService api;
  final String token;
  final bool english;

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  static const _cyan = Color(0xFF21D4D8);
  late Future<_ManagementData> _future;
  bool _busy = false;
  String tr(String bg, String en) => widget.english ? en : bg;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ManagementData> _load() async {
    final results = await Future.wait([
      widget.api.getStaffOverview(widget.token),
      widget.api.getAttendance(widget.token),
      widget.api.getLeaveRequests(widget.token),
    ]);
    return _ManagementData(
      Map<String, dynamic>.from(results[0] as Map),
      Map<String, dynamic>.from(results[1] as Map),
      (results[2] as List).cast<Map<String, dynamic>>(),
    );
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _attendance(String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.api.recordAttendance(widget.token, action);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(action == 'check_in' ? tr('Работната смяна е започната.', 'Shift started.') : tr('Работната смяна е приключена.', 'Shift ended.'))));
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestLeave() async {
    final reason = TextEditingController();
    DateTime start = DateTime.now().add(const Duration(days: 1));
    DateTime end = start;
    String date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final result = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
      title: Text(tr('Заявка за отпуск', 'Leave request')),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.event_available), title: Text(tr('От дата', 'Start date')), subtitle: Text(date(start)), onTap: () async { final picked = await showDatePicker(context: context, initialDate: start, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730))); if (picked != null) refresh(() { start = picked; if (end.isBefore(start)) end = start; }); }),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.event), title: Text(tr('До дата', 'End date')), subtitle: Text(date(end)), onTap: () async { final picked = await showDatePicker(context: context, initialDate: end.isBefore(start) ? start : end, firstDate: start, lastDate: DateTime.now().add(const Duration(days: 730))); if (picked != null) refresh(() => end = picked); }),
        TextField(controller: reason, maxLines: 3, decoration: InputDecoration(labelText: tr('Причина / бележка', 'Reason / note'))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('Отказ', 'Cancel'))), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(tr('Изпрати', 'Submit')))],
    )));
    if (result != true) { reason.dispose(); return; }
    try {
      await widget.api.submitLeaveRequest(widget.token, startDate: date(start), endDate: date(end), reason: reason.text.trim());
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Заявката е изпратена за одобрение.', 'Request submitted for approval.')))); _reload(); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally { reason.dispose(); }
  }

  Future<void> _review(Map<String, dynamic> request, String status) async {
    final id = int.tryParse('${request['id']}') ?? 0;
    if (id <= 0 || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.api.reviewLeaveRequest(widget.token, id, status);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Заявката е обработена.', 'Request reviewed.')))); _reload(); }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Екип и работно време', 'Team & attendance')), actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))]),
    body: FutureBuilder<_ManagementData>(future: _future, builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${tr('Неуспешно зареждане:', 'Could not load team data:')} ${snapshot.error}', textAlign: TextAlign.center)));
      final data = snapshot.data!;
      final overview = data.overview;
      final attendance = data.attendance['active'];
      final checkedIn = attendance is Map;
      final attendanceRows = (overview['attendance_today'] as List? ?? []).whereType<Map>().toList();
      final leaveRows = data.leaveRequests;
      final isAdmin = overview['is_admin'] == true;
      final stats = (overview['technician_stats'] as List? ?? []).whereType<Map>().toList();
      return RefreshIndicator(onRefresh: () async { final f = _load(); setState(() => _future = f); await f; }, child: ListView(padding: const EdgeInsets.all(16), children: [
        _sectionTitle(tr('Оперативен преглед', 'Operations overview')),
        GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, childAspectRatio: 1.65, crossAxisSpacing: 10, mainAxisSpacing: 10, children: [
          _metric(tr('Активни ремонти', 'Active repairs'), overview['active_repairs']),
          _metric(tr('Приключени · 30 дни', 'Completed · 30 days'), overview['completed_30d']),
          _metric(tr('Присъстват днес', 'Checked in today'), attendanceRows.where((r) => r['check_out'] == null || r['check_out'] == '').length),
          _metric(tr('Чакащи отпуски', 'Pending leave'), overview['pending_leave']),
        ]),
        const SizedBox(height: 18),
        _sectionTitle(tr('Моето присъствие', 'My attendance')),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(checkedIn ? Icons.timer : Icons.timer_off_outlined, color: _cyan), const SizedBox(width: 10), Expanded(child: Text(checkedIn ? tr('Имате активна работна смяна.', 'Your shift is currently active.') : tr('Нямате започната смяна.', 'You have not started a shift.'), style: const TextStyle(fontWeight: FontWeight.w600)))]),
          if (checkedIn) ...[const SizedBox(height: 6), Text('${tr('Начало', 'Started')}: ${attendance['check_in'] ?? '—'}', style: const TextStyle(color: Colors.white60))],
          const SizedBox(height: 12), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : () => _attendance(checkedIn ? 'check_out' : 'check_in'), icon: Icon(checkedIn ? Icons.logout : Icons.login), label: Text(checkedIn ? tr('Приключи смяната', 'End shift') : tr('Започни смяната', 'Start shift')))),
        ]))),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: _requestLeave, icon: const Icon(Icons.event_busy), label: Text(tr('Подай заявка за отпуск', 'Request leave'))),
        const SizedBox(height: 18),
        _sectionTitle(tr('Присъствие на екипа днес', 'Team attendance today')),
        if (attendanceRows.isEmpty) _empty(tr('Все още няма отчетено присъствие.', 'No attendance has been recorded yet.')),
        ...attendanceRows.map((row) => Card(child: ListTile(leading: CircleAvatar(child: const Icon(Icons.person_outline)), title: Text('${row['display_name'] ?? tr('Служител', 'Staff member')}'), subtitle: Text('${tr('Начало', 'In')}: ${row['check_in'] ?? '—'}  ·  ${tr('Край', 'Out')}: ${row['check_out'] ?? tr('На смяна', 'On shift')}'), trailing: Icon(row['check_out'] == null || row['check_out'] == '' ? Icons.circle : Icons.check_circle, color: _cyan, size: 16)))),
        const SizedBox(height: 18),
        _sectionTitle(tr('Резултати по техници · 30 дни', 'Technician results · 30 days')),
        if (stats.isEmpty) _empty(tr('Няма приключени ремонти за периода.', 'No completed repairs in this period.')),
        ...stats.map((row) => Card(child: ListTile(leading: const Icon(Icons.engineering_outlined, color: _cyan), title: Text('${row['technician_name'] ?? tr('Техник', 'Technician')}'), trailing: Chip(label: Text('${row['completed_count'] ?? 0} ${tr('ремонта', 'repairs')}'))))),
        const SizedBox(height: 18),
        _sectionTitle(tr('Заявки за отпуск', 'Leave requests')),
        if (leaveRows.isEmpty) _empty(tr('Няма заявки за отпуск.', 'No leave requests.')),
        ...leaveRows.map((row) {
          final status = '${row['status'] ?? 'pending'}';
          final pending = status == 'pending';
          return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${row['display_name'] ?? tr('Моя заявка', 'My request')} · ${row['start_date'] ?? ''} – ${row['end_date'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
            if ('${row['reason'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text('${row['reason']}')),
            const SizedBox(height: 6), Chip(label: Text(_leaveStatus(status))),
            if (isAdmin && pending) Wrap(spacing: 8, children: [TextButton.icon(onPressed: _busy ? null : () => _review(row, 'rejected'), icon: const Icon(Icons.close), label: Text(tr('Откажи', 'Reject'))), FilledButton.tonalIcon(onPressed: _busy ? null : () => _review(row, 'approved'), icon: const Icon(Icons.check), label: Text(tr('Одобри', 'Approve')))]),
          ])));
        }),
        const SizedBox(height: 12),
        Text(tr('Присъствието се записва към служебния профил. Одобрението/отказът на отпуски е ограничено до WordPress администратор.', 'Attendance is recorded against the signed-in staff account. Leave approval/rejection is restricted to WordPress administrators.'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ]));
    }),
  );

  Widget _sectionTitle(String text) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)));
  Widget _metric(String title, dynamic value) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('${value ?? 0}', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: _cyan)), const SizedBox(height: 4), Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))])));
  Widget _empty(String text) => Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(text, style: const TextStyle(color: Colors.white54)));
  String _leaveStatus(String status) => switch (status) { 'approved' => tr('Одобрена', 'Approved'), 'rejected' => tr('Отказана', 'Rejected'), _ => tr('Чака одобрение', 'Pending') };
}

class _ManagementData {
  const _ManagementData(this.overview, this.attendance, this.leaveRequests);
  final Map<String, dynamic> overview;
  final Map<String, dynamic> attendance;
  final List<Map<String, dynamic>> leaveRequests;
}
