import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import 'repair_calendar_screen.dart';
import 'technician_dispatch_screen.dart';
import 'staff_management_screen.dart';
import 'repair_statistics_screen.dart';

class StaffDashboardScreen extends StatefulWidget {
  const StaffDashboardScreen({super.key, required this.api, required this.token, required this.english});
  final ApiService api;
  final String token;
  final bool english;
  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<StaffDashboardScreen> {
  static const cyan = Color(0xFF21D4D8);
  final search = TextEditingController();
  String filter = 'all';
  String locationFilter = 'all';
  String priorityFilter = 'all';
  String technicianFilter = 'all';
  late Future<List<Repair>> future;
  bool busy = false;
  String tr(String bg, String en) => widget.english ? en : bg;
  static const statuses = ['received','diagnostics','waiting_approval','in_repair','ready','completed','cancelled'];
  String label(String s) {
    const bg = {'received':'Приет','diagnostics':'Диагностика','waiting_approval':'Очаква одобрение','in_repair':'В ремонт','ready':'Готов','completed':'Приключен','cancelled':'Отменен'};
    const en = {'received':'Received','diagnostics':'Diagnostics','waiting_approval':'Awaiting approval','in_repair':'In repair','ready':'Ready','completed':'Completed','cancelled':'Cancelled'};
    return (widget.english ? en[s] : bg[s]) ?? s;
  }
  @override
  void initState() { super.initState(); future = widget.api.getRepairs(widget.token); }
  @override
  void dispose() { search.dispose(); super.dispose(); }
  void reload() => setState(() => future = widget.api.getRepairs(widget.token));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr('Табло на сервиза', 'Service dashboard')),
      actions: [
        IconButton(
          tooltip: tr('Календар на ремонтите', 'Repair calendar'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => RepairCalendarScreen(api: widget.api, token: widget.token, english: widget.english),
          )),
          icon: const Icon(Icons.calendar_month_outlined),
        ),
        IconButton(
          tooltip: tr('Разпределяне на ремонти', 'Technician dispatch'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TechnicianDispatchScreen(api: widget.api, token: widget.token, english: widget.english),
          )),
          icon: const Icon(Icons.auto_awesome_motion_outlined),
        ),
        IconButton(
          tooltip: tr('Статистика и отчети', 'Statistics & reports'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => RepairStatisticsScreen(api: widget.api, token: widget.token, english: widget.english),
          )),
          icon: const Icon(Icons.query_stats_outlined),
        ),
        IconButton(
          tooltip: tr('Екип и работно време', 'Team & attendance'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => StaffManagementScreen(api: widget.api, token: widget.token, english: widget.english),
          )),
          icon: const Icon(Icons.groups_2_outlined),
        ),
        IconButton(onPressed: reload, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: FutureBuilder<List<Repair>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('${tr('Грешка при зареждане:', 'Could not load repairs:')} ${snap.error}'),
            ),
          );
        }

        final all = snap.data ?? [];
        final locationNames = <String, String>{};
        for (final repair in all) {
          if (repair.locationCode.isNotEmpty) {
            locationNames[repair.locationCode] = repair.location.isEmpty
                ? repair.locationCode
                : repair.location;
          }
        }
        final locationCodes = locationNames.keys.toList()
          ..sort((a, b) => locationNames[a]!.compareTo(locationNames[b]!));
        final technicianNames = <String, String>{};
        for (final repair in all) {
          if (repair.technicianId > 0) {
            technicianNames['${repair.technicianId}'] = repair.technicianName.isEmpty
                ? '${tr('Техник', 'Technician')} #${repair.technicianId}'
                : repair.technicianName;
          }
        }
        final technicianIds = technicianNames.keys.toList()
          ..sort((a, b) => technicianNames[a]!.compareTo(technicianNames[b]!));
        final q = search.text.toLowerCase().trim();
        final rows = all.where((r) {
          final matchesStatus = filter == 'all' || r.status == filter;
          final matchesLocation = locationFilter == 'all' || r.locationCode == locationFilter;
          final matchesPriority = priorityFilter == 'all' || r.priority == priorityFilter;
          final matchesTechnician = technicianFilter == 'all' || '${r.technicianId}' == technicianFilter;
          final matchesSearch = q.isEmpty || [
            r.number, r.customer, r.phone, r.serial, r.model, r.device,
            r.location, r.technicianName,
          ].any((v) => v.toLowerCase().contains(q));
          return matchesStatus && matchesLocation && matchesPriority && matchesTechnician && matchesSearch;
        }).toList();

        rows.sort((a, b) {
          final aOverdue = _isOverdue(a);
          final bOverdue = _isOverdue(b);
          if (aOverdue != bOverdue) return aOverdue ? -1 : 1;
          final aDue = DateTime.tryParse(a.dueAt);
          final bDue = DateTime.tryParse(b.dueAt);
          if (aDue != null && bDue != null) return aDue.compareTo(bDue);
          if (aDue != null) return -1;
          if (bDue != null) return 1;
          return DateTime.tryParse(b.createdAt)?.compareTo(
                DateTime.tryParse(a.createdAt) ?? DateTime.fromMillisecondsSinceEpoch(0),
              ) ?? 0;
        });

        final activeCount = all.where((r) => !['completed', 'cancelled', 'ready'].contains(r.status)).length;
        final readyCount = all.where((r) => r.status == 'ready').length;
        final overdueCount = all.where(_isOverdue).length;

        return RefreshIndicator(
          onRefresh: () async {
            final f = widget.api.getRepairs(widget.token);
            setState(() => future = f);
            await f;
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _metric(tr('Всички', 'All'), all.length),
                  _metric(tr('В работа', 'In progress'), activeCount),
                  _metric(tr('Готови', 'Ready'), readyCount),
                  _metric(tr('Просрочени', 'Overdue'), overdueCount,
                      alert: overdueCount > 0),
                ],
              ),
              const SizedBox(height: 8),
              _buildWorkloadOverview(all, locationNames),
              const SizedBox(height: 14),
              TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: tr('Търси №, клиент, телефон, сериен №…', 'Search no., customer, phone, serial…'),
                  border: const OutlineInputBorder(),
                  suffixIcon: search.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () { search.clear(); setState(() {}); },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: filter,
                decoration: InputDecoration(labelText: tr('Филтър по статус', 'Filter by status')),
                items: [
                  DropdownMenuItem(value: 'all', child: Text(tr('Всички статуси', 'All statuses'))),
                  ...statuses.map((s) => DropdownMenuItem(value: s, child: Text(label(s)))),
                ],
                onChanged: (v) => setState(() => filter = v ?? 'all'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: locationFilter,
                decoration: InputDecoration(
                  labelText: tr('Сервизен обект', 'Service location'),
                  prefixIcon: const Icon(Icons.storefront_outlined),
                ),
                items: [
                  DropdownMenuItem(value: 'all', child: Text(tr('Всички обекти', 'All locations'))),
                  ...locationCodes.map((code) => DropdownMenuItem(
                    value: code,
                    child: Text(locationNames[code] ?? code, overflow: TextOverflow.ellipsis),
                  )),
                ],
                onChanged: (v) => setState(() => locationFilter = v ?? 'all'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: priorityFilter,
                decoration: InputDecoration(
                  labelText: tr('Приоритет', 'Priority'),
                  prefixIcon: const Icon(Icons.flag_outlined),
                ),
                items: [
                  DropdownMenuItem(value: 'all', child: Text(tr('Всички приоритети', 'All priorities'))),
                  ...['low', 'normal', 'high', 'urgent'].map((p) => DropdownMenuItem(
                    value: p,
                    child: Text(_priorityLabel(p)),
                  )),
                ],
                onChanged: (v) => setState(() => priorityFilter = v ?? 'all'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: technicianFilter,
                decoration: InputDecoration(
                  labelText: tr('Назначен техник', 'Assigned technician'),
                  prefixIcon: const Icon(Icons.engineering_outlined),
                ),
                items: [
                  DropdownMenuItem(value: 'all', child: Text(tr('Всички техници', 'All technicians'))),
                  DropdownMenuItem(value: '0', child: Text(tr('Без назначен техник', 'Unassigned'))),
                  ...technicianIds.map((id) => DropdownMenuItem(
                    value: id,
                    child: Text(technicianNames[id] ?? id, overflow: TextOverflow.ellipsis),
                  )),
                ],
                onChanged: (v) => setState(() => technicianFilter = v ?? 'all'),
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('Няма намерени ремонти.', 'No repairs found.'), textAlign: TextAlign.center),
                ),
              ...rows.map((r) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Text(r.number, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                        Chip(label: Text(label(r.status))),
                      ]),
                      if (_isOverdue(r))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Chip(
                            avatar: const Icon(Icons.warning_amber_rounded, size: 17),
                            label: Text(tr('ПРОСРОЧЕН', 'OVERDUE')),
                            backgroundColor: Colors.red.withValues(alpha: 0.18),
                            side: BorderSide(color: Colors.red.withValues(alpha: 0.55)),
                          ),
                        ),
                      Text('${r.device} ${r.model}'.trim(), style: const TextStyle(color: Colors.white70)),
                      if (r.customer.isNotEmpty || r.phone.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text([r.customer, r.phone].where((x) => x.isNotEmpty).join(' · ')),
                        ),
                      if (r.serial.isNotEmpty)
                        Text('${tr('Сериен №', 'Serial')}: ${r.serial}', style: const TextStyle(color: Colors.white60)),
                      if (r.location.isNotEmpty)
                        Text(r.location, style: const TextStyle(color: Colors.white60)),
                      Text(
                        '${tr('Техник', 'Technician')}: ${r.technicianName.isEmpty ? tr('Не е назначен', 'Unassigned') : r.technicianName} · ${tr('Приоритет', 'Priority')}: ${_priorityLabel(r.priority)}${r.dueAt.isNotEmpty ? ' · ${tr('Срок', 'Due')}: ${r.dueAt}' : ''}',
                        style: const TextStyle(color: Colors.white60),
                      ),
                      if (r.problem.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(r.problem, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 4,
                        runSpacing: 0,
                        children: [
                          IconButton(
                            tooltip: tr('Копирай номер на ремонта', 'Copy repair number'),
                            onPressed: () => _copyRepairNumber(r),
                            icon: const Icon(Icons.copy_outlined),
                          ),
                          IconButton(
                            tooltip: tr('Обади се на клиента', 'Call customer'),
                            onPressed: r.phone.trim().isEmpty ? null : () => _callCustomer(r),
                            icon: const Icon(Icons.call_outlined),
                          ),
                          IconButton(
                            tooltip: 'WhatsApp',
                            onPressed: r.phone.trim().isEmpty ? null : () => _messageCustomer(r),
                            icon: const Icon(Icons.chat_outlined),
                          ),
                          TextButton.icon(
                            onPressed: busy ? null : () => _manageAssignment(r),
                            icon: const Icon(Icons.assignment_ind_outlined),
                            label: Text(tr('Назначи техник', 'Assign technician')),
                          ),
                          TextButton.icon(
                            onPressed: busy ? null : () => _changeStatus(r),
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(tr('Статус', 'Status')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )),
            ],
          ),
        );
      },
    ),
  );


  Widget _buildWorkloadOverview(List<Repair> repairs, Map<String, String> locationNames) {
    final active = repairs.where((r) => !['completed', 'cancelled', 'ready'].contains(r.status)).toList();
    final unassigned = active.where((r) => r.technicianId <= 0).length;
    final byTechnician = <int, List<Repair>>{};
    final byLocation = <String, List<Repair>>{};
    for (final repair in active) {
      if (repair.technicianId > 0) {
        byTechnician.putIfAbsent(repair.technicianId, () => []).add(repair);
      }
      final code = repair.locationCode.isEmpty ? 'unknown' : repair.locationCode;
      byLocation.putIfAbsent(code, () => []).add(repair);
    }
    final techEntries = byTechnician.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    final locationEntries = byLocation.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.analytics_outlined, color: cyan),
        title: Text(tr('Натовареност на сервиза', 'Service workload'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(tr('Активни ремонти по обекти и техници', 'Active repairs by location and technician')),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            _smallMetric(tr('Активни задачи', 'Active tasks'), active.length),
            _smallMetric(tr('Без техник', 'Unassigned'), unassigned, alert: unassigned > 0),
            _smallMetric(tr('Натоварени техници', 'Busy technicians'), techEntries.length),
            _smallMetric(tr('Активни обекти', 'Active locations'), locationEntries.length),
          ]),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: Text(
            tr('Натовареност по сервизни обекти', 'Workload by service location'),
            style: const TextStyle(fontWeight: FontWeight.w600))),
          if (locationEntries.isEmpty)
            Padding(padding: const EdgeInsets.all(8), child: Text(tr('Няма активни задачи.', 'No active tasks.'))),
          ...locationEntries.map((entry) {
            final overdue = entry.value.where(_isOverdue).length;
            final free = entry.value.where((r) => r.technicianId <= 0).length;
            final title = locationNames[entry.key] ?? (entry.key == 'unknown' ? tr('Неуточнен обект', 'Unknown location') : entry.key);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storefront_outlined),
              title: Text(title),
              subtitle: Text('${entry.value.length} ${tr('активни', 'active')} · $free ${tr('без техник', 'unassigned')}${overdue > 0 ? ' · $overdue ${tr('просрочени', 'overdue')}' : ''}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: entry.key == 'unknown' ? null : () => setState(() { locationFilter = entry.key; technicianFilter = 'all'; }),
            );
          }),
          const Divider(),
          Align(alignment: Alignment.centerLeft, child: Text(
            tr('Натовареност по техници', 'Workload by technician'),
            style: const TextStyle(fontWeight: FontWeight.w600))),
          if (techEntries.isEmpty)
            Padding(padding: const EdgeInsets.all(8), child: Text(tr('Няма назначени активни задачи.', 'No assigned active tasks.'))),
          ...techEntries.map((entry) {
            final overdue = entry.value.where(_isOverdue).length;
            final name = entry.value.first.technicianName.isEmpty
                ? '${tr('Техник', 'Technician')} #${entry.key}'
                : entry.value.first.technicianName;
            final ratio = active.isEmpty ? 0.0 : (entry.value.length / active.length).clamp(0.0, 1.0).toDouble();
            return InkWell(
              onTap: () => setState(() { technicianFilter = '${entry.key}'; locationFilter = 'all'; }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.engineering_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w500))),
                    Text('${entry.value.length} ${tr('задачи', 'tasks')}', style: const TextStyle(color: cyan)),
                  ]),
                  const SizedBox(height: 5),
                  LinearProgressIndicator(value: ratio, minHeight: 6),
                  if (overdue > 0)
                    Padding(padding: const EdgeInsets.only(top: 3), child: Text(
                      '$overdue ${tr('просрочени задачи', 'overdue tasks')}',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
                ]),
              ),
            );
          }),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(
            onPressed: () => setState(() { locationFilter = 'all'; technicianFilter = 'all'; }),
            icon: const Icon(Icons.filter_alt_off),
            label: Text(tr('Изчисти филтрите', 'Clear filters')),
          )),
        ],
      ),
    );
  }

  Widget _smallMetric(String title, int value, {bool alert = false}) => SizedBox(
    width: (MediaQuery.of(context).size.width - 92) / 2,
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: [
        Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
            color: alert ? Colors.redAccent : cyan)),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
      ]),
    ),
  );

  Future<void> _copyRepairNumber(Repair repair) async {
    await Clipboard.setData(ClipboardData(text: repair.number));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('Номерът на ремонта е копиран.', 'Repair number copied.'))),
    );
  }

  String _phoneDigits(String value) => value.replaceAll(RegExp(r'[^0-9+]'), '');

  Future<void> _callCustomer(Repair repair) async {
    final phone = _phoneDigits(repair.phone);
    if (phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    final launched = await launchUrl(uri);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Не може да се отвори приложението за обаждания.', 'Could not open the phone app.'))),
      );
    }
  }

  Future<void> _messageCustomer(Repair repair) async {
    final phone = repair.phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.length < 6) return;
    final message = tr(
      'Здравейте! Свързваме се с Вас относно ремонт ${repair.number} в PCWork.',
      'Hello! We are contacting you about repair ${repair.number} at PCWork.',
    );
    final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Не може да се отвори WhatsApp.', 'Could not open WhatsApp.'))),
      );
    }
  }

  bool _isOverdue(Repair repair) {
    if (repair.dueAt.isEmpty || ['completed', 'cancelled', 'ready'].contains(repair.status)) {
      return false;
    }
    final due = DateTime.tryParse(repair.dueAt);
    return due != null && due.isBefore(DateTime.now());
  }

  Widget _metric(String title, int value, {bool alert = false}) => SizedBox(
    width: (MediaQuery.of(context).size.width - 48) / 2,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(children: [
          Text('$value', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: alert ? Colors.redAccent : cyan)),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    ),
  );

  String _priorityLabel(String p) => ({'low':tr('Нисък','Low'),'normal':tr('Нормален','Normal'),'high':tr('Висок','High'),'urgent':tr('Спешен','Urgent')}[p] ?? p);

  Future<void> _manageAssignment(Repair r) async {
    if (r.locationCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Липсва код на сервизния обект.','Repair has no service location code.'))));
      return;
    }
    setState(() => busy = true);
    List<Map<String,dynamic>> technicians = [];
    try { technicians = await widget.api.getTechnicians(widget.token, r.locationCode); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    if (!mounted) { setState(() => busy = false); return; }
    int selectedTech = technicians.any((t)=>(t['id'] as num).toInt()==r.technicianId) ? r.technicianId : 0;
    String priority = r.priority;
    final due = TextEditingController(text: r.dueAt);
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text('${tr('Разпределение','Assignment')} ${r.number}'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<int>(initialValue: technicians.any((t)=>(t['id'] as num).toInt()==selectedTech) ? selectedTech : 0,
          decoration: InputDecoration(labelText: tr('Техник','Technician')),
          items: [DropdownMenuItem(value:0,child:Text(tr('Без назначен техник','Unassigned'))), ...technicians.map((t)=>DropdownMenuItem(value:(t['id'] as num).toInt(),child:Text((t['name'] ?? t['email']).toString())))],
          onChanged:(v){if(v!=null) selectedTech=v;}),
        const SizedBox(height:10),
        DropdownButtonFormField<String>(initialValue: priority, decoration: InputDecoration(labelText: tr('Приоритет','Priority')),
          items: ['low','normal','high','urgent'].map((v)=>DropdownMenuItem(value:v,child:Text(_priorityLabel(v)))).toList(), onChanged:(v){if(v!=null) priority=v;}),
        const SizedBox(height:10), TextField(controller:due, decoration:InputDecoration(labelText:tr('Срок (ISO дата/час, по избор)','Due date/time (ISO, optional)'), hintText:'2026-11-10 17:00')),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(tr('Отказ','Cancel'))),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(tr('Запази','Save')))]));
    if (ok == true) {
      try { await widget.api.updateRepairAssignment(widget.token, r.id, technicianId:selectedTech, priority:priority, dueAt:due.text.trim()); if(mounted){reload();ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(tr('Разпределението е записано.','Assignment saved.'))));} }
      catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
    }
    due.dispose(); if(mounted) setState(()=>busy=false);
  }

  Future<void> _changeStatus(Repair r) async {
    String selected = r.status;
    final note = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx)=>AlertDialog(title: Text('${tr('Ремонт','Repair')} ${r.number}'), content: Column(mainAxisSize:MainAxisSize.min, children: [DropdownButtonFormField<String>(initialValue: selected, items: statuses.map((s)=>DropdownMenuItem(value:s, child:Text(label(s)))).toList(), onChanged:(v){ if(v!=null) selected=v; }), const SizedBox(height:12), TextField(controller:note, maxLines:3, decoration:InputDecoration(labelText:tr('Бележка към историята (по избор)','History note (optional)')))]), actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false), child:Text(tr('Отказ','Cancel'))), FilledButton(onPressed:()=>Navigator.pop(ctx,true), child:Text(tr('Запази','Save')))]));
    if (ok != true) { note.dispose(); return; }
    setState(()=>busy=true);
    try { final result = await widget.api.updateRepairStatus(widget.token, r.id, selected, note: note.text.trim()); if(mounted) { reload(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(result.pendingSync ? tr('Промяната е запазена и чака синхронизация.','Change saved and waiting to sync.') : tr('Статусът е обновен.','Status updated.')))); } }
    catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e'))); }
    finally { note.dispose(); if(mounted) setState(()=>busy=false); }
  }
}
