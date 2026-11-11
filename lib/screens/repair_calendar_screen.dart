import 'package:flutter/material.dart';
import '../services/api_service.dart';

class RepairCalendarScreen extends StatefulWidget {
  const RepairCalendarScreen({super.key, required this.api, required this.token, required this.english});
  final ApiService api;
  final String token;
  final bool english;

  @override
  State<RepairCalendarScreen> createState() => _RepairCalendarScreenState();
}

class _RepairCalendarScreenState extends State<RepairCalendarScreen> {
  static const cyan = Color(0xFF21D4D8);
  late DateTime month;
  late DateTime selectedDay;
  late Future<List<Repair>> future;
  bool showUnscheduled = false;
  bool saving = false;

  String tr(String bg, String en) => widget.english ? en : bg;
  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);
  DateTime? _due(Repair repair) => repair.dueAt.isEmpty ? null : DateTime.tryParse(repair.dueAt);
  bool _active(Repair repair) => !['completed', 'cancelled', 'ready'].contains(repair.status);
  String _dateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = DateTime(now.year, now.month);
    selectedDay = _day(now);
    future = widget.api.getRepairs(widget.token, forceRefresh: true);
  }

  void _reload() => setState(() => future = widget.api.getRepairs(widget.token, forceRefresh: true));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr('Календар на ремонтите', 'Repair calendar')),
      actions: [IconButton(onPressed: _reload, tooltip: tr('Обнови', 'Refresh'), icon: const Icon(Icons.refresh))],
    ),
    body: FutureBuilder<List<Repair>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('${tr('Грешка при зареждане:', 'Loading error:')} ${snapshot.error}'),
          ));
        }
        final repairs = snapshot.data ?? <Repair>[];
        final active = repairs.where(_active).toList();
        final scheduled = active.where((r) => _due(r) != null).toList();
        final unscheduled = active.where((r) => _due(r) == null).toList();
        final dayRepairs = showUnscheduled
            ? unscheduled
            : scheduled.where((r) => _day(_due(r)!) == selectedDay).toList();
        if (!showUnscheduled) {
          dayRepairs.sort((a, b) => _due(a)!.compareTo(_due(b)!));
        }

        return RefreshIndicator(
          onRefresh: () async { final request = widget.api.getRepairs(widget.token, forceRefresh: true); setState(() => future = request); await request; },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(children: [
                  Image.asset('assets/images/pcwork_diagnostics_hero.webp', height: 142, width: double.infinity, fit: BoxFit.cover),
                  Container(height: 142, decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight,
                      colors: [const Color(0xFF061329).withValues(alpha: 0.96), const Color(0xFF061329).withValues(alpha: 0.62), Colors.transparent]),
                    border: Border.all(color: cyan.withValues(alpha: 0.55)),
                  )),
                  Positioned.fill(child: Padding(padding: const EdgeInsets.all(16), child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(tr('PCWORK SERVICE CONTROL', 'PCWORK SERVICE CONTROL'), style: TextStyle(color: cyan, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 7),
                      Text(tr('Контрол на ремонтите', 'Repair control center'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Colors.white)),
                      Text(tr('График • срокове • натоварване', 'Schedule • deadlines • workload'), style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 12)),
                    ],
                  ))),
                ]),
              ),
              const SizedBox(height: 14),
              _summary(active.length, scheduled.length, unscheduled.length),
              const SizedBox(height: 14),
              _monthHeader(),
              const SizedBox(height: 8),
              _calendarGrid(scheduled),
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(tr('Избран ден', 'Selected day')), icon: const Icon(Icons.event)),
                  ButtonSegment(value: true, label: Text('${tr('Без график', 'Unscheduled')} (${unscheduled.length})'), icon: const Icon(Icons.event_busy)),
                ],
                selected: {showUnscheduled},
                onSelectionChanged: (values) => setState(() => showUnscheduled = values.first),
              ),
              const SizedBox(height: 10),
              Text(
                showUnscheduled ? tr('Ремонти без зададен срок', 'Repairs without a due date') : '${tr('Ремонти за', 'Repairs for')} ${_formatDate(selectedDay)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (dayRepairs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Column(children: [
                    Icon(showUnscheduled ? Icons.event_available : Icons.event_busy, size: 42, color: Colors.grey),
                    const SizedBox(height: 8),
                    Text(showUnscheduled ? tr('Всички активни ремонти имат срок.', 'All active repairs are scheduled.') : tr('Няма ремонти за избрания ден.', 'No repairs for the selected day.')),
                  ]),
                )
              else
                ...dayRepairs.map(_repairCard),
            ],
          ),
        );
      },
    ),
  );

  Widget _summary(int active, int scheduled, int unscheduled) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        _summaryCell(tr('Активни', 'Active'), active, cyan),
        _summaryCell(tr('С график', 'Scheduled'), scheduled, Colors.greenAccent),
        _summaryCell(tr('Без срок', 'Unscheduled'), unscheduled, unscheduled > 0 ? Colors.orangeAccent : cyan),
      ]),
    ),
  );

  Widget _summaryCell(String label, int value, Color color) => Expanded(child: Column(children: [
    Text('$value', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
    Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
  ]));

  Widget _monthHeader() {
    const monthsBg = ['Януари','Февруари','Март','Април','Май','Юни','Юли','Август','Септември','Октомври','Ноември','Декември'];
    const monthsEn = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    final title = '${(widget.english ? monthsEn : monthsBg)[month.month - 1]} ${month.year}';
    return Row(children: [
      IconButton(onPressed: () => setState(() { month = DateTime(month.year, month.month - 1); }), icon: const Icon(Icons.chevron_left)),
      Expanded(child: Center(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))),
      IconButton(onPressed: () => setState(() { month = DateTime(month.year, month.month + 1); }), icon: const Icon(Icons.chevron_right)),
      IconButton(onPressed: () => setState(() { final now = DateTime.now(); month = DateTime(now.year, now.month); selectedDay = _day(now); showUnscheduled = false; }), tooltip: tr('Днес', 'Today'), icon: const Icon(Icons.today)),
    ]);
  }

  Widget _calendarGrid(List<Repair> scheduled) {
    const weekdaysBg = ['П','В','С','Ч','П','С','Н'];
    const weekdaysEn = ['M','T','W','T','F','S','S'];
    final first = DateTime(month.year, month.month, 1);
    final offset = first.weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((offset + daysInMonth + 6) ~/ 7) * 7;
    final counts = <String, int>{};
    for (final repair in scheduled) {
      final due = _due(repair);
      if (due != null) counts.update(_dateKey(due), (v) => v + 1, ifAbsent: () => 1);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          Row(children: List.generate(7, (i) => Expanded(child: Center(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text((widget.english ? weekdaysEn : weekdaysBg)[i], style: const TextStyle(fontWeight: FontWeight.bold, color: cyan)),
          ))))),
          ...List.generate(cells ~/ 7, (week) => Row(children: List.generate(7, (weekday) {
            final dayNumber = week * 7 + weekday - offset + 1;
            if (dayNumber < 1 || dayNumber > daysInMonth) return const Expanded(child: SizedBox(height: 48));
            final date = DateTime(month.year, month.month, dayNumber);
            final selected = _day(date) == selectedDay;
            final count = counts[_dateKey(date)] ?? 0;
            final today = _day(date) == _day(DateTime.now());
            return Expanded(child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() { selectedDay = _day(date); showUnscheduled = false; }),
              child: Container(
                height: 48,
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: selected ? cyan.withValues(alpha: 0.22) : null,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: selected ? cyan : today ? cyan.withValues(alpha: 0.45) : Colors.transparent),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('$dayNumber', style: TextStyle(fontWeight: selected || today ? FontWeight.bold : FontWeight.normal)),
                  if (count > 0) Container(
                    margin: const EdgeInsets.only(top: 2), width: 5, height: 5,
                    decoration: const BoxDecoration(color: cyan, shape: BoxShape.circle),
                  ),
                ]),
              ),
            ));
          }))),
        ]),
      ),
    );
  }

  Widget _repairCard(Repair repair) {
    final due = _due(repair);
    final overdue = due != null && due.isBefore(DateTime.now()) && _active(repair);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(repair.number.isEmpty ? '№${repair.id}' : repair.number, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            if (overdue) Chip(label: Text(tr('Просрочен', 'Overdue'), style: const TextStyle(fontSize: 11)), backgroundColor: Colors.red.withValues(alpha: 0.15)),
          ]),
          Text([repair.customer, repair.device, repair.model].where((v) => v.trim().isNotEmpty).join(' · ')),
          const SizedBox(height: 5),
          Row(children: [
            const Icon(Icons.schedule, size: 17, color: cyan),
            const SizedBox(width: 5),
            Text(due == null ? tr('Без зададен срок', 'No due date') : _formatDateTime(due)),
          ]),
          if (repair.technicianName.isNotEmpty || repair.technicianId > 0)
            Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
              const Icon(Icons.engineering_outlined, size: 17), const SizedBox(width: 5),
              Expanded(child: Text(repair.technicianName.isEmpty ? '${tr('Техник', 'Technician')} #${repair.technicianId}' : repair.technicianName)),
            ])),
          if (repair.location.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
              const Icon(Icons.storefront_outlined, size: 17), const SizedBox(width: 5), Expanded(child: Text(repair.location)),
            ])),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(
            onPressed: saving ? null : () => _scheduleRepair(repair),
            icon: const Icon(Icons.edit_calendar),
            label: Text(tr('Промени графика', 'Change schedule')),
          )),
        ]),
      ),
    );
  }

  Future<void> _scheduleRepair(Repair repair) async {
    final initial = _due(repair) ?? DateTime.now().add(const Duration(hours: 1));
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _day(initial),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: tr('Избери краен срок', 'Select due date'),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (pickedTime == null || !mounted) return;
    final due = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);
    setState(() => saving = true);
    try {
      await widget.api.updateRepairAssignment(
        widget.token,
        repair.id,
        technicianId: repair.technicianId,
        priority: repair.priority,
        dueAt: '${_dateKey(due)} ${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}:00',
      );
      if (!mounted) return;
      setState(() { selectedDay = _day(due); month = DateTime(due.year, due.month); showUnscheduled = false; future = widget.api.getRepairs(widget.token, forceRefresh: true); });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Графикът е запазен.', 'Schedule saved.'))));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Грешка при запис:', 'Could not save schedule:')} $error')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  String _formatDateTime(DateTime date) => '${_formatDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
