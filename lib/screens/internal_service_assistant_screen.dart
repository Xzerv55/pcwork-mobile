import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'staff_dashboard_screen.dart';

class InternalServiceAssistantScreen extends StatefulWidget {
  const InternalServiceAssistantScreen({super.key, required this.api, required this.token, required this.english});
  final ApiService api; final String token; final bool english;
  @override
  State<InternalServiceAssistantScreen> createState() => _InternalServiceAssistantScreenState();
}

class _InternalServiceAssistantScreenState extends State<InternalServiceAssistantScreen> {
  late Future<List<Repair>> _future;
  String tr(String bg, String en) => widget.english ? en : bg;
  @override
  void initState() { super.initState(); _future = widget.api.getRepairs(widget.token); }
  void _openDashboard() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StaffDashboardScreen(api: widget.api, token: widget.token, english: widget.english)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Вътрешен сервизен асистент', 'Internal Service Assistant')), actions: [IconButton(onPressed: () => setState(() => _future = widget.api.getRepairs(widget.token)), icon: const Icon(Icons.refresh))]),
    body: FutureBuilder<List<Repair>>(future: _future, builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${tr('Неуспешно зареждане на сервизните задачи:', 'Could not load service tasks:')} ${snap.error}')));
      final repairs = snap.data ?? <Repair>[];
      final open = repairs.where((r) => !['completed','cancelled'].contains(r.status)).toList();
      final unassigned = open.where((r) => r.technicianId <= 0).length;
      final diagnosis = open.where((r) => r.status == 'diagnostics').length;
      final waiting = open.where((r) => r.status == 'waiting_approval').length;
      final overdue = open.where((r) { final due = DateTime.tryParse(r.dueAt); return due != null && due.isBefore(DateTime.now()); }).length;
      final tips = <String>[];
      if (unassigned > 0) tips.add(tr('$unassigned ремонта са без назначен техник. Разпредели ги към свободен служител.', '$unassigned repairs have no assigned technician. Assign them to an available employee.'));
      if (diagnosis > 0) tips.add(tr('$diagnosis ремонта са в диагностика. Добави резултат в сервизния дневник.', '$diagnosis repairs are in diagnostics. Add findings to the worklog.'));
      if (waiting > 0) tips.add(tr('$waiting ремонта очакват одобрение от клиент.', '$waiting repairs are waiting for customer approval.'));
      if (overdue > 0) tips.add(tr('$overdue ремонта са след крайния срок. Провери приоритета и срока.', '$overdue repairs are past due. Review their priority and due date.'));
      if (tips.isEmpty) tips.add(tr('Няма критични задачи според текущите данни. Продължи с планираните ремонти.', 'No critical tasks based on current data. Continue with scheduled repairs.'));
      return RefreshIndicator(onRefresh: () async { final f = widget.api.getRepairs(widget.token); setState(() => _future = f); await f; }, child: ListView(padding: const EdgeInsets.all(16), children: [
        Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF102C3A), Color(0xFF1B5360)]), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.support_agent_rounded, color: Color(0xFF21D4D8), size: 34), const SizedBox(height: 8), Text(tr('Сервизен контролен център', 'Service operations assistant'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19)), const SizedBox(height: 5), Text(tr('Обобщение на текущите ремонти и следващи действия за екипа.', 'Live repair overview and suggested next actions for the team.'), style: const TextStyle(color: Colors.white70))])),
        const SizedBox(height: 14), Wrap(spacing: 8, runSpacing: 8, children: [ _metric(tr('Активни', 'Active'), open.length, Icons.build_circle_outlined), _metric(tr('Без техник', 'Unassigned'), unassigned, Icons.person_off_outlined), _metric(tr('Диагностика', 'Diagnostics'), diagnosis, Icons.search), _metric(tr('Просрочени', 'Overdue'), overdue, Icons.warning_amber_rounded) ]),
        const SizedBox(height: 18), Text(tr('Препоръчани действия', 'Recommended actions'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8), ...tips.map((tip) => Card(child: ListTile(leading: const Icon(Icons.lightbulb_outline, color: Color(0xFFFFC857)), title: Text(tip, style: const TextStyle(fontSize: 13))))),
        const SizedBox(height: 12), Text(tr('Работни инструменти', 'Work tools'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        Card(child: ListTile(leading: const Icon(Icons.assignment_outlined), title: Text(tr('Ремонти и статуси', 'Repairs and statuses')), subtitle: Text(tr('Списък, диагностика, статуси и клиентски данни', 'Repair list, diagnostics, statuses and customer details')), trailing: const Icon(Icons.chevron_right), onTap: _openDashboard)),
        Card(child: ListTile(leading: const Icon(Icons.engineering_outlined), title: Text(tr('Назначаване на техник', 'Technician assignment')), subtitle: Text(tr('Разпределяне на задачи и приоритети', 'Assign tasks and priorities')), trailing: const Icon(Icons.chevron_right), onTap: _openDashboard)),
        Card(child: ListTile(leading: const Icon(Icons.receipt_long_outlined), title: Text(tr('Сервизен дневник и калкулация', 'Worklog and cost calculation')), subtitle: Text(tr('Диагностика, вложени части, труд, плащания и гаранции', 'Diagnostics, parts, labor, payments and warranties')), trailing: const Icon(Icons.chevron_right), onTap: _openDashboard)),
        Card(child: ListTile(leading: const Icon(Icons.photo_camera_back_outlined), title: Text(tr('Снимки и доказателства', 'Photos and evidence')), subtitle: Text(tr('Прикачване на снимки към ремонт', 'Attach photos to a repair')), trailing: const Icon(Icons.chevron_right), onTap: _openDashboard)),
        const SizedBox(height: 10), FilledButton.icon(onPressed: _openDashboard, icon: const Icon(Icons.dashboard_customize_outlined), label: Text(tr('Отвори пълното сервизно табло', 'Open full service dashboard'))),
        const SizedBox(height: 8), const Text('PCWork Internal Service Assistant • Сървърните права се проверяват от WordPress.', style: TextStyle(color: Colors.grey, fontSize: 11)),
      ]));
    }),
  );

  Widget _metric(String label, int value, IconData icon) => SizedBox(width: 155, child: Card(child: Padding(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: const Color(0xFF21D4D8)), const SizedBox(height: 8), Text('$value', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)), Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey))]))));
}
