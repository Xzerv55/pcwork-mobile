import 'package:flutter/material.dart';
import '../services/api_service.dart';

class TaskManagementScreen extends StatefulWidget {
  const TaskManagementScreen({super.key, required this.api, required this.token, required this.english});
  final ApiService api;
  final String token;
  final bool english;
  @override
  State<TaskManagementScreen> createState() => _TaskManagementScreenState();
}

class _TaskManagementScreenState extends State<TaskManagementScreen> {
  String status = 'all';
  bool overdueOnly = false;
  late Future<List<Map<String, dynamic>>> future;
  bool busy = false;
  String tr(String bg, String en) => widget.english ? en : bg;
  static const statuses = ['open', 'in_progress', 'blocked', 'completed', 'cancelled'];
  String statusLabel(String value) {
    const bg = {'open':'Отворена','in_progress':'В изпълнение','blocked':'Блокирана','completed':'Завършена','cancelled':'Отменена'};
    const en = {'open':'Open','in_progress':'In progress','blocked':'Blocked','completed':'Completed','cancelled':'Cancelled'};
    return (widget.english ? en[value] : bg[value]) ?? value;
  }
  @override
  void initState() { super.initState(); _load(); }
  void _load() { future = widget.api.getStaffTasks(widget.token, status: status, overdueOnly: overdueOnly); }
  Future<void> _refresh() async { setState(() { _load(); }); await future; }
  Future<void> _showHistory(Map<String, dynamic> task) async {
    final id = int.tryParse('${task['id']}') ?? 0;
    showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(tr('История на задачата', 'Task history')),
      content: SizedBox(width: 420, child: FutureBuilder<List<Map<String, dynamic>>>(
        future: widget.api.getRepairTaskHistory(widget.token, id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const SizedBox(height: 90, child: Center(child: CircularProgressIndicator()));
          if (snapshot.hasError) return Text('${tr('Грешка:', 'Error:')} ${snapshot.error}');
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) return Text(tr('Няма записана история.', 'No history recorded.'));
          return SizedBox(height: 300, child: ListView.separated(itemCount: rows.length, separatorBuilder: (_, __) => const Divider(), itemBuilder: (_, i) {
            final row = rows[i];
            final fields = (row['changed_fields'] is List ? (row['changed_fields'] as List).join(', ') : '');
            return ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(row['action'] == 'created' ? tr('Създадена задача', 'Task created') : tr('Промяна: $fields', 'Updated: $fields')), subtitle: Text('${row['actor_name'] ?? '—'} · ${row['created_at'] ?? ''}'));
          }));
        },
      )),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('Затвори', 'Close')))],
    ));
  }

  String _localDeadline(String value) {
    if (value.isEmpty) return '';
    final normalized = value.contains('T') ? value : value.replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse(normalized.endsWith('Z') || normalized.contains('+') ? normalized : '${normalized}Z');
    if (parsed == null) return value;
    final local = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _createTask() async {
    List<Repair> repairs;
    try { repairs = await widget.api.getRepairs(widget.token, forceRefresh: true); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Неуспешно зареждане на ремонтите:', 'Could not load repairs:')} $e'))); return; }
    repairs = repairs.where((r) => r.id > 0 && r.locationCode.isNotEmpty).toList();
    if (repairs.isEmpty) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Няма достъпни ремонти за създаване на задача.', 'No accessible repairs are available for task creation.')))); return; }

    Repair selectedRepair = repairs.first;
    List<Map<String, dynamic>> technicians = [];
    try { technicians = await widget.api.getTechnicians(widget.token, selectedRepair.locationCode); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); return; }

    final title = TextEditingController();
    final description = TextEditingController();
    final due = TextEditingController();
    int selectedAssignee = technicians.isNotEmpty ? ((technicians.first['id'] as num?)?.toInt() ?? 0) : 0;
    String priority = 'normal';
    bool loadingTechnicians = false;
    bool autoAssign = technicians.isEmpty;
    final accepted = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: Text(tr('Нова сервизна задача', 'New service task')),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<int>(value: selectedRepair.id, isExpanded: true, decoration: InputDecoration(labelText: tr('Ремонт *', 'Repair *')), items: repairs.map((r) => DropdownMenuItem(value: r.id, child: Text('${r.number.isEmpty ? '#${r.id}' : r.number} · ${r.device} ${r.model}'.trim(), overflow: TextOverflow.ellipsis))).toList(), onChanged: (id) async {
          final next = repairs.firstWhere((r) => r.id == id);
          setDialogState(() { selectedRepair = next; loadingTechnicians = true; technicians = []; selectedAssignee = 0; });
          try {
            final list = await widget.api.getTechnicians(widget.token, next.locationCode);
            setDialogState(() { technicians = list; selectedAssignee = list.isNotEmpty ? ((list.first['id'] as num?)?.toInt() ?? 0) : 0; autoAssign = list.isEmpty; loadingTechnicians = false; });
          } catch (_) { setDialogState(() { loadingTechnicians = false; }); }
        }),
        TextField(controller: title, maxLength: 190, decoration: InputDecoration(labelText: tr('Заглавие *', 'Title *'))),
        TextField(controller: description, maxLines: 2, decoration: InputDecoration(labelText: tr('Описание', 'Description'))),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('Автоматично разпределение', 'Automatic assignment')), subtitle: Text(tr('Избира служител според графика и текущата натовареност.', 'Selects staff based on schedule and current workload.')), value: autoAssign, onChanged: (v) => setDialogState(() => autoAssign = v)),
        if (loadingTechnicians) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
        else if (!autoAssign) DropdownButtonFormField<int>(value: technicians.any((t) => (t['id'] as num?)?.toInt() == selectedAssignee) ? selectedAssignee : null, isExpanded: true, decoration: InputDecoration(labelText: tr('Отговорен служител *', 'Assigned staff *')), items: technicians.map((t) => DropdownMenuItem(value: (t['id'] as num).toInt(), child: Text('${t['name'] ?? t['display_name'] ?? t['id']}'))).toList(), onChanged: (v) => setDialogState(() => selectedAssignee = v ?? 0)),
        TextField(controller: due, decoration: InputDecoration(labelText: tr('Краен срок (YYYY-MM-DD HH:MM)', 'Deadline (YYYY-MM-DD HH:MM)'))),
        DropdownButtonFormField<String>(value: priority, decoration: InputDecoration(labelText: tr('Приоритет', 'Priority')), items: [DropdownMenuItem(value:'low',child:Text(tr('Нисък','Low'))),DropdownMenuItem(value:'normal',child:Text(tr('Нормален','Normal'))),DropdownMenuItem(value:'high',child:Text(tr('Висок','High'))),DropdownMenuItem(value:'urgent',child:Text(tr('Спешен','Urgent')))], onChanged: (v) => setDialogState(() => priority = v ?? 'normal')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('Отказ','Cancel'))), FilledButton(onPressed: loadingTechnicians || (!autoAssign && selectedAssignee <= 0) ? null : () => Navigator.pop(dialogContext, true), child: Text(tr('Създай','Create')))],
    )));
    if (accepted == true) {
      if (title.text.trim().isEmpty || (!autoAssign && selectedAssignee <= 0)) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Попълни заглавие и избери служител.', 'Enter a title and select a staff member.'))));
      } else {
        try {
          final payload = <String, dynamic>{'title': title.text.trim(), 'description': description.text.trim(), 'priority': priority, 'auto_assign': autoAssign};
          if (!autoAssign) payload['assigned_user_id'] = selectedAssignee;
          if (due.text.trim().isNotEmpty) payload['due_at'] = due.text.trim();
          await widget.api.createRepairTask(widget.token, selectedRepair.id, payload);
          if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Задачата е създадена.', 'Task created.')))); setState(_load); }
        } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
      }
    }
    title.dispose(); description.dispose(); due.dispose();
  }

  Future<void> _editTask(Map<String, dynamic> task) async {
    final id = int.tryParse('${task['id']}') ?? 0;
    final locationCode = '${task['location_code'] ?? ''}';
    if (id <= 0 || locationCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Липсва информация за сервизния обект.','Service location information is missing.'))));
      return;
    }
    final title = TextEditingController(text: '${task['title'] ?? ''}');
    final description = TextEditingController(text: '${task['description'] ?? ''}');
    final due = TextEditingController(text: _localDeadline('${task['due_at'] ?? ''}'));
    List<Map<String, dynamic>> technicians = [];
    try { technicians = await widget.api.getTechnicians(widget.token, locationCode); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); title.dispose(); description.dispose(); due.dispose(); return; }
    if (!mounted) { title.dispose(); description.dispose(); due.dispose(); return; }
    int selected = int.tryParse('${task['assigned_user_id']}') ?? 0;
    if (!technicians.any((t) => (t['id'] as num?)?.toInt() == selected) && technicians.isNotEmpty) selected = (technicians.first['id'] as num).toInt();
    String priority = '${task['priority'] ?? 'normal'}';
    final accepted = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: Text(tr('Редактиране на задача','Edit task')),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, maxLength: 190, decoration: InputDecoration(labelText: tr('Заглавие *','Title *'))),
        TextField(controller: description, maxLines: 3, decoration: InputDecoration(labelText: tr('Описание','Description'))),
        DropdownButtonFormField<int>(value: technicians.any((t) => (t['id'] as num?)?.toInt() == selected) ? selected : null, decoration: InputDecoration(labelText: tr('Отговорен служител','Assigned staff')), items: technicians.map((t) => DropdownMenuItem<int>(value: (t['id'] as num).toInt(), child: Text('${t['name'] ?? t['display_name'] ?? t['id']}'))).toList(), onChanged: (v) => setDialogState(() => selected = v ?? selected)),
        TextField(controller: due, decoration: InputDecoration(labelText: tr('Краен срок (YYYY-MM-DD HH:MM)','Deadline (YYYY-MM-DD HH:MM)'))),
        DropdownButtonFormField<String>(value: ['low','normal','high','urgent'].contains(priority) ? priority : 'normal', decoration: InputDecoration(labelText: tr('Приоритет','Priority')), items: [DropdownMenuItem(value:'low',child:Text(tr('Нисък','Low'))),DropdownMenuItem(value:'normal',child:Text(tr('Нормален','Normal'))),DropdownMenuItem(value:'high',child:Text(tr('Висок','High'))),DropdownMenuItem(value:'urgent',child:Text(tr('Спешен','Urgent')))], onChanged: (v) => setDialogState(() => priority = v ?? 'normal')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('Отказ','Cancel'))), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(tr('Запази','Save')))],
    )));
    if (accepted == true) {
      if (title.text.trim().isEmpty || selected <= 0) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Заглавието и служителят са задължителни.','Title and staff are required.'))));
      } else {
        try {
          await widget.api.updateRepairTask(widget.token, id, {'title': title.text.trim(), 'description': description.text.trim(), 'assigned_user_id': selected, 'priority': priority, 'due_at': due.text.trim()});
          if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Промените са записани.','Changes saved.')))); setState(_load); }
        } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
      }
    }
    title.dispose(); description.dispose(); due.dispose();
  }

  Future<void> _setStatus(Map<String, dynamic> task, String value) async {
    setState(() => busy = true);
    try {
      await widget.api.updateRepairTask(widget.token, int.tryParse('${task['id']}') ?? 0, {'status': value});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Задачата е обновена.','Task updated.'))));
      setState(_load);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Сервизни задачи','Service tasks')), actions:[IconButton(tooltip:tr('Нова задача','New task'),onPressed:busy?null:_createTask,icon:const Icon(Icons.add_task)),IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))]),
    body: Column(children:[
      Padding(padding: const EdgeInsets.fromLTRB(16,12,16,4), child: Row(children:[
        Expanded(child: DropdownButtonFormField<String>(value: status, decoration: InputDecoration(labelText: tr('Статус','Status')), items:[DropdownMenuItem(value:'all',child:Text(tr('Всички','All'))), ...statuses.map((s)=>DropdownMenuItem(value:s,child:Text(statusLabel(s))))], onChanged:(v)=>setState((){status=v??'all';_load();}))),
        const SizedBox(width:12),
        Expanded(child: FilterChip(label: Text(tr('Само просрочени','Overdue only')), selected: overdueOnly, onSelected:(v)=>setState((){overdueOnly=v;_load();}))),
      ])),
      Expanded(child: FutureBuilder<List<Map<String,dynamic>>>(future:future,builder:(context,snap){
        if(snap.connectionState!=ConnectionState.done) return const Center(child:CircularProgressIndicator());
        if(snap.hasError) return Center(child:Padding(padding:const EdgeInsets.all(24),child:Text('${tr('Грешка при зареждане:','Loading error:')} ${snap.error}')));
        final rows=snap.data??[];
        if(rows.isEmpty) return Center(child:Text(tr('Няма задачи за избраните филтри.','No tasks match these filters.')));
        return RefreshIndicator(onRefresh:_refresh, child:ListView.separated(padding:const EdgeInsets.all(12),itemCount:rows.length,separatorBuilder:(_,__)=>const SizedBox(height:8),itemBuilder:(context,index){
          final task=rows[index]; final id=int.tryParse('${task['id']}')??0;
          final due='${task['due_at']??''}'; final parsed=DateTime.tryParse('${due.replaceFirst(' ','T') }Z')?.toLocal();
          final isOverdue=parsed!=null && parsed.isBefore(DateTime.now()) && !['completed','cancelled'].contains('${task['status']}');
          final repair='${task['repair_number']??task['repair_id']??''}';
          final device='${task['device_type']??''} ${task['device_model']??''}'.trim();
          final assignee='${task['assigned_user_name']??''}';
          return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[Expanded(child:Text('${task['title']??''}',style:Theme.of(context).textTheme.titleMedium)), if(isOverdue) const Icon(Icons.warning_amber_rounded,color:Colors.red), IconButton(tooltip:tr('Редакция','Edit'),onPressed:busy?null:()=>_editTask(task),icon:const Icon(Icons.edit_outlined)), IconButton(tooltip:tr('История','History'),onPressed:()=>_showHistory(task),icon:const Icon(Icons.history)), PopupMenuButton<String>(enabled:!busy && !['completed','cancelled'].contains('${task['status']}'), onSelected:(v)=>_setStatus(task,v), itemBuilder:(_)=>statuses.map((s)=>PopupMenuItem(value:s,child:Text(statusLabel(s)))).toList(), icon:const Icon(Icons.more_vert))]),
            if('${task['description']??''}'.isNotEmpty) Padding(padding:const EdgeInsets.only(top:4),child:Text('${task['description']}')),
            const SizedBox(height:8), Wrap(spacing:12,runSpacing:6,children:[Text('№ $repair'),if(device.isNotEmpty)Text(device),Text('${tr('Служител:','Assigned:')} ${assignee.isEmpty?'—':assignee}'),Text(statusLabel('${task['status']}')),if(due.isNotEmpty)Text('${tr('Срок:','Due:')} ${_localDeadline(due)}',style:TextStyle(color:isOverdue?Colors.red:null,fontWeight:isOverdue?FontWeight.bold:null)),if('${task['status']}'=='completed' && '${task['completed_at']??''}'.isNotEmpty)Text('${tr('Завършена:','Completed:')} ${task['completed_at']} · ${task['completed_by_name']??''}')]),
          ])));
        }));
      }))
    ]),
  );
}
