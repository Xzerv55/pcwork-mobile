import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Предлага разпределение на неназначените активни ремонти.
/// Изчислението използва реално върнатите от API ремонти и техници за обекта.
/// Не приема, че има информация за смени/отсъствия, ако такава не е предоставена от сървъра.
class TechnicianDispatchScreen extends StatefulWidget {
  const TechnicianDispatchScreen({
    super.key,
    required this.api,
    required this.token,
    required this.english,
  });

  final ApiService api;
  final String token;
  final bool english;

  @override
  State<TechnicianDispatchScreen> createState() => _TechnicianDispatchScreenState();
}

class _TechnicianDispatchScreenState extends State<TechnicianDispatchScreen> {
  late Future<_DispatchData> _future;
  bool _saving = false;
  static const _cyan = Color(0xFF21D4D8);

  String tr(String bg, String en) => widget.english ? en : bg;
  bool _active(Repair r) => !['completed', 'cancelled', 'ready'].contains(r.status);
  DateTime? _due(Repair r) => r.dueAt.isEmpty ? null : DateTime.tryParse(r.dueAt);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DispatchData> _load() async {
    final repairs = await widget.api.getRepairs(widget.token);
    final active = repairs.where(_active).toList();
    final locationCodes = active
        .where((r) => r.locationCode.trim().isNotEmpty)
        .map((r) => r.locationCode)
        .toSet();
    final techniciansByLocation = <String, List<Map<String, dynamic>>>{};
    for (final code in locationCodes) {
      try {
        techniciansByLocation[code] = await widget.api.getTechnicians(widget.token, code);
      } catch (_) {
        techniciansByLocation[code] = [];
      }
    }
    Map<int, Map<String, dynamic>> schedules = {};
    try { schedules = await widget.api.getTechnicianSchedules(widget.token); } catch (_) {}
    return _DispatchData(active, techniciansByLocation, schedules);
  }

  void _reload() => setState(() => _future = _load());

  int _techId(Map<String, dynamic> t) => (t['id'] as num?)?.toInt() ?? 0;
  String _techName(Map<String, dynamic> t) {
    final name = (t['name'] ?? t['display_name'] ?? '').toString().trim();
    return name.isNotEmpty ? name : (t['email'] ?? 'Техник #${_techId(t)}').toString();
  }

  double _weight(Repair r) {
    switch (r.priority) {
      case 'urgent': return 2.5;
      case 'high': return 1.75;
      case 'low': return 0.75;
      default: return 1;
    }
  }

  List<_Recommendation> _buildRecommendations(_DispatchData data) {
    final workload = <int, double>{};
    for (final r in data.repairs.where((r) => r.technicianId > 0)) {
      workload[r.technicianId] = (workload[r.technicianId] ?? 0) + _weight(r);
    }

    final unassigned = data.repairs.where((r) => r.technicianId <= 0).toList();
    unassigned.sort((a, b) {
      final priority = _priorityRank(b.priority).compareTo(_priorityRank(a.priority));
      if (priority != 0) return priority;
      final ad = _due(a);
      final bd = _due(b);
      if (ad != null && bd != null) return ad.compareTo(bd);
      if (ad != null) return -1;
      if (bd != null) return 1;
      return a.id.compareTo(b.id);
    });

    final recommendations = <_Recommendation>[];
    for (final repair in unassigned) {
      final candidates = data.techniciansByLocation[repair.locationCode] ?? [];
      final now = DateTime.now();
      final dueDate = _due(repair);
      final availabilityAt = dueDate == null ? now : DateTime(dueDate.year, dueDate.month, dueDate.day, now.hour, now.minute);
      final eligible = candidates.where((t) => _techId(t) > 0 && _isAvailable(_techId(t), data.schedules, availabilityAt)).toList();
      if (eligible.isEmpty) {
        recommendations.add(_Recommendation(repair, null, null, null));
        continue;
      }
      eligible.sort((a, b) {
        final load = (workload[_techId(a)] ?? 0).compareTo(workload[_techId(b)] ?? 0);
        if (load != 0) return load;
        return _techName(a).compareTo(_techName(b));
      });
      final selected = eligible.first;
      final id = _techId(selected);
      final current = workload[id] ?? 0;
      recommendations.add(_Recommendation(repair, id, _techName(selected), current));
      workload[id] = current + _weight(repair);
    }
    return recommendations;
  }

  bool _isAvailable(int id, Map<int, Map<String, dynamic>> schedules, DateTime at) {
    final schedule = schedules[id];
    if (schedule == null) return true; // No configured schedule: preserve legacy assignment behavior.
    final absences = (schedule['absences'] as List? ?? []).map((e) => e.toString()).toSet();
    final dateKey = '${at.year.toString().padLeft(4, '0')}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
    if (absences.contains(dateKey)) return false;
    final days = (schedule['working_days'] as List? ?? []).map((e) => int.tryParse(e.toString()) ?? 0).toSet();
    if (!days.contains(at.weekday)) return false;
    final start = TimeOfDay.fromDateTime(at);
    final startText = (schedule['start_time'] ?? '09:00').toString().split(':');
    final endText = (schedule['end_time'] ?? '18:00').toString().split(':');
    final startMinutes = (int.tryParse(startText[0]) ?? 9) * 60 + (int.tryParse(startText[1]) ?? 0);
    final endMinutes = (int.tryParse(endText[0]) ?? 18) * 60 + (int.tryParse(endText[1]) ?? 0);
    final currentMinutes = start.hour * 60 + start.minute;
    return currentMinutes >= startMinutes && currentMinutes < endMinutes;
  }

  Future<void> _editSchedule(int technicianId, String technicianName, Map<String, dynamic>? current) async {
    final days = ((current?['working_days'] as List?) ?? [1, 2, 3, 4, 5]).map((e) => int.tryParse(e.toString()) ?? 0).where((e) => e > 0).toSet();
    final absences = TextEditingController(text: ((current?['absences'] as List?) ?? []).join(', '));
    final start = TextEditingController(text: (current?['start_time'] ?? '09:00').toString());
    final end = TextEditingController(text: (current?['end_time'] ?? '18:00').toString());
    const dayNames = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'];
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
      title: Text(tr('График: $technicianName', 'Schedule: $technicianName')),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Работни дни', 'Working days')),
        Wrap(spacing: 2, children: List.generate(7, (i) => FilterChip(label: Text(widget.english ? ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][i] : dayNames[i]), selected: days.contains(i + 1), onSelected: (v) => refresh(() { v ? days.add(i + 1) : days.remove(i + 1); })))),
        TextField(controller: start, decoration: InputDecoration(labelText: tr('Начало (ЧЧ:ММ)', 'Start (HH:MM)'))),
        TextField(controller: end, decoration: InputDecoration(labelText: tr('Край (ЧЧ:ММ)', 'End (HH:MM)'))),
        TextField(controller: absences, maxLines: 3, decoration: InputDecoration(labelText: tr('Отсъствия – дати YYYY-MM-DD, разделени със запетая', 'Absence dates YYYY-MM-DD, comma separated'), hintText: '2026-12-24, 2026-12-25')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('Отказ', 'Cancel'))), FilledButton(onPressed: () => Navigator.pop(dialogContext, {'working_days': days.toList()..sort(), 'start_time': start.text.trim(), 'end_time': end.text.trim(), 'absences': absences.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()}), child: Text(tr('Запази', 'Save')))],
    )));
    absences.dispose(); start.dispose(); end.dispose();
    if (result == null) return;
    try {
      await widget.api.saveTechnicianSchedule(widget.token, technicianId, result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Графикът е запазен.', 'Schedule saved.'))));
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Неуспешно записване:', 'Save failed:')} $e')));
    }
  }

  int _priorityRank(String p) => const {'urgent': 4, 'high': 3, 'normal': 2, 'low': 1}[p] ?? 2;

  Future<void> _assign(_Recommendation recommendation) async {
    final techId = recommendation.technicianId;
    if (techId == null || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.api.updateRepairAssignment(
        widget.token,
        recommendation.repair.id,
        technicianId: techId,
        priority: recommendation.repair.priority,
        dueAt: recommendation.repair.dueAt,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Ремонтът е назначен на ${recommendation.technicianName}.', 'Repair assigned to ${recommendation.technicianName}.')),
      ));
      setState(() => _future = _load());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Грешка при назначаване:', 'Assignment failed:')} $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _assignAll(List<_Recommendation> recommendations) async {
    final ready = recommendations.where((r) => r.technicianId != null).toList();
    if (ready.isEmpty || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Потвърди разпределянето', 'Confirm dispatch')),
        content: Text(tr(
          'Ще бъдат назначени ${ready.length} ремонта според текущата натовареност. Да продължа ли?',
          '${ready.length} repairs will be assigned based on current workload. Continue?',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Отказ', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Назначи', 'Assign'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    var success = 0;
    var failed = 0;
    for (final item in ready) {
      try {
        await widget.api.updateRepairAssignment(
          widget.token,
          item.repair.id,
          technicianId: item.technicianId!,
          priority: item.repair.priority,
          dueAt: item.repair.dueAt,
        );
        success++;
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _future = _load();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
      tr('Назначени: $success · Неуспешни: $failed', 'Assigned: $success · Failed: $failed'),
    )));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr('Разпределяне на ремонти', 'Technician dispatch')),
      actions: [IconButton(onPressed: _saving ? null : _reload, icon: const Icon(Icons.refresh))],
    ),
    body: FutureBuilder<_DispatchData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('${tr('Грешка при зареждане:', 'Could not load data:')} ${snapshot.error}'),
          ));
        }
        final data = snapshot.data!;
        final recommendations = _buildRecommendations(data);
        final assignable = recommendations.where((r) => r.technicianId != null).length;
        final noTech = recommendations.length - assignable;
        final loads = <int, int>{};
        for (final r in data.repairs.where((r) => r.technicianId > 0)) {
          loads[r.technicianId] = (loads[r.technicianId] ?? 0) + 1;
        }
        return RefreshIndicator(
          onRefresh: () async { final f = _load(); setState(() => _future = f); await f; },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Интелигентно разпределяне', 'Smart workload dispatch'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(tr('Препоръките се изчисляват по сервизен обект, текущ брой активни ремонти и приоритет. Назначаването се потвърждава от администратора.', 'Recommendations use service location, current active repair workload and priority. The administrator confirms assignments.')),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _metric(tr('Активни ремонти', 'Active repairs'), data.repairs.length),
                    _metric(tr('За назначаване', 'Unassigned'), recommendations.length),
                    _metric(tr('С препоръка', 'Assignable'), assignable),
                    _metric(tr('Без техник за обекта', 'No eligible technician'), noTech),
                  ]),
                  if (assignable > 0) ...[
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: FilledButton.icon(
                      onPressed: _saving ? null : () => _assignAll(recommendations),
                      icon: const Icon(Icons.auto_awesome),
                      label: Text(tr('Потвърди всички препоръки ($assignable)', 'Confirm all recommendations ($assignable)')),
                    )),
                  ],
                ]),
              )),
              const SizedBox(height: 12),
              Text(tr('Текуща натовареност на техниците', 'Current technician workload'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              ..._workloadCards(data, loads),
              const SizedBox(height: 12),
              Text(tr('Предложения за назначаване', 'Assignment recommendations'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              if (recommendations.isEmpty)
                Card(child: Padding(padding: const EdgeInsets.all(18), child: Text(tr('Няма неназначени активни ремонти.', 'There are no unassigned active repairs.'))))
              else
                ...recommendations.map(_recommendationCard),
              const SizedBox(height: 14),
              Text(tr('Графици и отсъствия се управляват от администратора. Техници без индивидуален график запазват досегашното поведение и се оценяват само по обект и натовареност.', 'Schedules and absences are managed by an administrator. Technicians without an individual schedule retain the previous behavior and are evaluated by location and workload.'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60)),
            ],
          ),
        );
      },
    ),
  );

  Widget _metric(String title, int count) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(color: _cyan.withValues(alpha: .10), borderRadius: BorderRadius.circular(10), border: Border.all(color: _cyan.withValues(alpha: .25))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$count', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _cyan)), Text(title, style: const TextStyle(fontSize: 11))]),
  );

  List<Widget> _workloadCards(_DispatchData data, Map<int, int> loads) {
    final techs = <int, Map<String, dynamic>>{};
    for (final list in data.techniciansByLocation.values) {
      for (final tech in list) {
        final id = _techId(tech);
        if (id > 0) techs[id] = tech;
      }
    }
    if (techs.isEmpty) return [Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(tr('Няма достъпни данни за техници в тези обекти.', 'No technician data is available for these locations.'))))];
    final entries = techs.entries.toList()..sort((a, b) => (loads[a.key] ?? 0).compareTo(loads[b.key] ?? 0));
    final maxLoad = entries.fold<int>(1, (m, e) => (loads[e.key] ?? 0) > m ? loads[e.key]! : m);
    return entries.map((entry) {
      final count = loads[entry.key] ?? 0;
      return Card(child: ListTile(
        leading: CircleAvatar(child: Text(_techName(entry.value).isNotEmpty ? _techName(entry.value)[0].toUpperCase() : '?')),
        title: Text(_techName(entry.value)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: LinearProgressIndicator(value: count / maxLoad, color: count == maxLoad && count > 0 ? Colors.orangeAccent : _cyan, backgroundColor: Colors.white12)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$count ${tr('задачи', 'jobs')}', style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(tooltip: tr('Настрой график', 'Edit schedule'), icon: const Icon(Icons.schedule), onPressed: _saving ? null : () => _editSchedule(entry.key, _techName(entry.value), data.schedules[entry.key])),
        ]),
      ));
    }).toList();
  }

  Widget _recommendationCard(_Recommendation item) {
    final repair = item.repair;
    final due = _due(repair);
    return Card(
      child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(repair.number, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))), _priorityChip(repair.priority)]),
        const SizedBox(height: 4),
        Text('${repair.device} ${repair.model}'.trim()),
        if (repair.customer.isNotEmpty) Text(repair.customer, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 4),
        Row(children: [const Icon(Icons.storefront_outlined, size: 16), const SizedBox(width: 5), Expanded(child: Text(repair.location.isEmpty ? repair.locationCode : repair.location))]),
        if (due != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${tr('Срок', 'Due')}: ${_formatDate(due)}', style: TextStyle(color: due.isBefore(DateTime.now()) ? Colors.redAccent : Colors.white70))),
        const SizedBox(height: 8),
        if (item.technicianId == null)
          Text(repair.locationCode.isEmpty
              ? tr('Ремонтът няма зададен сервизен обект. Попълнете обекта преди назначаване.', 'This repair has no service location. Set its location before assigning it.')
              : tr('Няма техник с права за този сервизен обект. Проверете настройките на служителите в WordPress.', 'No technician is authorized for this service location. Check staff permissions in WordPress.'), style: const TextStyle(color: Colors.orangeAccent))
        else
          Row(children: [
            const Icon(Icons.recommend_outlined, color: _cyan),
            const SizedBox(width: 6),
            Expanded(child: Text('${tr('Препоръчан техник', 'Recommended technician')}: ${item.technicianName}\n${tr('Текущо натоварване преди назначаване', 'Current workload before assignment')}: ${item.loadBefore?.toStringAsFixed(1) ?? '0'}', style: const TextStyle(fontSize: 13))),
            FilledButton(onPressed: _saving ? null : () => _assign(item), child: Text(tr('Назначи', 'Assign'))),
          ]),
      ])),
    );
  }

  Widget _priorityChip(String p) {
    final color = p == 'urgent' ? Colors.redAccent : p == 'high' ? Colors.orangeAccent : _cyan;
    final text = {'urgent': tr('Спешен', 'Urgent'), 'high': tr('Висок', 'High'), 'low': tr('Нисък', 'Low')}[p] ?? tr('Нормален', 'Normal');
    return Chip(label: Text(text, style: const TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact, side: BorderSide(color: color.withValues(alpha: .6)), backgroundColor: color.withValues(alpha: .12));
  }

  String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

class _DispatchData {
  const _DispatchData(this.repairs, this.techniciansByLocation, this.schedules);
  final List<Repair> repairs;
  final Map<String, List<Map<String, dynamic>>> techniciansByLocation;
  final Map<int, Map<String, dynamic>> schedules;
}

class _Recommendation {
  const _Recommendation(this.repair, this.technicianId, this.technicianName, this.loadBefore);
  final Repair repair;
  final int? technicianId;
  final String? technicianName;
  final double? loadBefore;
}
