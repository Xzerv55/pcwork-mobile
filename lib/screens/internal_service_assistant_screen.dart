import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'staff_dashboard_screen.dart';
import 'ai_assistant_chat_screen.dart';
import 'technician_dispatch_screen.dart';
import 'repair_worklog_screen.dart';
import 'repair_evidence_screen.dart';

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

  void _openTechnicianDispatch() => Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => TechnicianDispatchScreen(api: widget.api, token: widget.token, english: widget.english),
  ));

  Future<void> _chooseRepairAndOpen({required bool evidence}) async {
    try {
      final repairs = await widget.api.getRepairs(widget.token, forceRefresh: true);
      if (!mounted) return;
      final eligible = repairs.where((r) => r.status != 'cancelled').toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (eligible.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Няма активни ремонти за избор.', 'There are no active repairs to select.'))));
        return;
      }
      final selected = await showDialog<Repair>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr('Избери ремонт', 'Select a repair')),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: eligible.length,
              itemBuilder: (_, index) {
                final repair = eligible[index];
                final number = repair.number.isEmpty ? 'PCW-${repair.id}' : repair.number;
                return ListTile(
                  leading: const Icon(Icons.build_circle_outlined),
                  title: Text(number),
                  subtitle: Text('${repair.device} ${repair.model}'.trim()),
                  onTap: () => Navigator.of(dialogContext).pop(repair),
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(tr('Отказ', 'Cancel')))],
        ),
      );
      if (selected == null || !mounted) return;
      final number = selected.number.isEmpty ? 'PCW-${selected.id}' : selected.number;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => evidence
          ? RepairEvidenceScreen(baseUrl: widget.api.baseUrl, token: widget.token, repairId: selected.id, repairNumber: number, isStaff: true)
          : RepairWorklogScreen(api: widget.api, token: widget.token, repairId: selected.id, repairNumber: number, isStaff: true),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Вътрешен сервизен асистент', 'Internal Service Assistant')), actions: [IconButton(onPressed: () => setState(() => _future = widget.api.getRepairs(widget.token, forceRefresh: true)), icon: const Icon(Icons.refresh))]),
    body: FutureBuilder<List<Repair>>(future: _future, builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${tr('Неуспешно зареждане на сервизните задачи:', 'Could not load service tasks:')} ${snap.error}')));
      final repairs = snap.data ?? <Repair>[];
      var active = 0;
      var unassigned = 0;
      var diagnosis = 0;
      var waiting = 0;
      var overdue = 0;
      final now = DateTime.now();
      for (final repair in repairs) {
        if (repair.status == 'completed' || repair.status == 'cancelled') continue;
        active++;
        if (repair.technicianId <= 0) unassigned++;
        if (repair.status == 'diagnostics') diagnosis++;
        if (repair.status == 'waiting_approval') waiting++;
        final due = DateTime.tryParse(repair.dueAt);
        if (due != null && due.isBefore(now)) overdue++;
      }
      final tips = <String>[];
      if (unassigned > 0) tips.add(tr('$unassigned ремонта са без назначен техник. Разпредели ги към свободен служител.', '$unassigned repairs have no assigned technician. Assign them to an available employee.'));
      if (diagnosis > 0) tips.add(tr('$diagnosis ремонта са в диагностика. Добави резултат в сервизния дневник.', '$diagnosis repairs are in diagnostics. Add findings to the worklog.'));
      if (waiting > 0) tips.add(tr('$waiting ремонта очакват одобрение от клиент.', '$waiting repairs are waiting for customer approval.'));
      if (overdue > 0) tips.add(tr('$overdue ремонта са след крайния срок. Провери приоритета и срока.', '$overdue repairs are past due. Review their priority and due date.'));
      if (tips.isEmpty) tips.add(tr('Няма критични задачи според текущите данни. Продължи с планираните ремонти.', 'No critical tasks based on current data. Continue with scheduled repairs.'));
      return RefreshIndicator(onRefresh: () async { final f = widget.api.getRepairs(widget.token, forceRefresh: true); setState(() => _future = f); await f; }, child: ListView(padding: const EdgeInsets.all(16), children: [
        Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF102C3A), Color(0xFF1B5360)]), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.support_agent_rounded, color: Color(0xFF21D4D8), size: 34), const SizedBox(height: 8), Text(tr('Сервизен контролен център', 'Service operations assistant'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19)), const SizedBox(height: 5), Text(tr('Обобщение на текущите ремонти и следващи действия за екипа.', 'Live repair overview and suggested next actions for the team.'), style: const TextStyle(color: Colors.white70))])),
        const SizedBox(height: 14), Wrap(spacing: 8, runSpacing: 8, children: [ _metric(tr('Активни', 'Active'), active, Icons.build_circle_outlined), _metric(tr('Без техник', 'Unassigned'), unassigned, Icons.person_off_outlined), _metric(tr('Диагностика', 'Diagnostics'), diagnosis, Icons.search), _metric(tr('Просрочени', 'Overdue'), overdue, Icons.warning_amber_rounded) ]),
        const SizedBox(height: 18), Text(tr('Препоръчани действия', 'Recommended actions'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8), ...tips.map((tip) => Card(child: ListTile(leading: const Icon(Icons.lightbulb_outline, color: Color(0xFFFFC857)), title: Text(tip, style: const TextStyle(fontSize: 13))))),
        const SizedBox(height: 12), Text(tr('AI помощник', 'AI assistant'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        Card(child: ListTile(leading: const Icon(Icons.auto_awesome, color: Color(0xFF21D4D8)), title: Text(tr('Попитай PCWork AI', 'Ask PCWork AI')), subtitle: Text(tr('Локален модел LM Studio за технически и сервизни въпроси', 'Local LM Studio model for technical and service questions')), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AiAssistantChatScreen(api: widget.api, token: widget.token, english: widget.english, staffMode: true))))),
        const SizedBox(height: 12), Text(tr('Работни инструменти', 'Work tools'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        Card(child: ListTile(leading: const Icon(Icons.assignment_outlined), title: Text(tr('Ремонти и статуси', 'Repairs and statuses')), subtitle: Text(tr('Списък, диагностика, статуси и клиентски данни', 'Repair list, diagnostics, statuses and customer details')), trailing: const Icon(Icons.chevron_right), onTap: _openDashboard)),
        Card(child: ListTile(leading: const Icon(Icons.engineering_outlined), title: Text(tr('Назначаване на техник', 'Technician assignment')), subtitle: Text(tr('Разпределяне на задачи и приоритети', 'Assign tasks and priorities')), trailing: const Icon(Icons.chevron_right), onTap: _openTechnicianDispatch)),
        Card(child: ListTile(leading: const Icon(Icons.receipt_long_outlined), title: Text(tr('Сервизен дневник и калкулация', 'Worklog and cost calculation')), subtitle: Text(tr('Избери ремонт, за да отвориш дневника и калкулацията', 'Select a repair to open its worklog and cost calculation')), trailing: const Icon(Icons.chevron_right), onTap: () => _chooseRepairAndOpen(evidence: false))),
        Card(child: ListTile(leading: const Icon(Icons.photo_camera_back_outlined), title: Text(tr('Снимки и доказателства', 'Photos and evidence')), subtitle: Text(tr('Избери ремонт, за да добавиш снимки и доказателства', 'Select a repair to add photos and evidence')), trailing: const Icon(Icons.chevron_right), onTap: () => _chooseRepairAndOpen(evidence: true))),
        const SizedBox(height: 10), FilledButton.icon(onPressed: _openDashboard, icon: const Icon(Icons.dashboard_customize_outlined), label: Text(tr('Отвори пълното сервизно табло', 'Open full service dashboard'))),
        const SizedBox(height: 8), const Text('PCWork Internal Service Assistant • Сървърните права се проверяват от WordPress.', style: TextStyle(color: Colors.grey, fontSize: 11)),
      ]));
    }),
  );

  Widget _metric(String label, int value, IconData icon) => SizedBox(width: 155, child: Card(child: Padding(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: const Color(0xFF21D4D8)), const SizedBox(height: 8), Text('$value', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)), Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey))]))));
}
