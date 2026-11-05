import 'package:flutter/material.dart';
import '../services/api_service.dart';

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
    appBar: AppBar(title: Text(tr('Табло на сервиза','Service dashboard')), actions: [IconButton(onPressed: reload, icon: const Icon(Icons.refresh))]),
    body: FutureBuilder<List<Repair>>(future: future, builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${tr('Грешка при зареждане:','Could not load repairs:')} ${snap.error}')));
      final all = snap.data ?? [];
      final q = search.text.toLowerCase().trim();
      final rows = all.where((r) => (filter == 'all' || r.status == filter) && (q.isEmpty || [r.number,r.customer,r.phone,r.serial,r.model,r.device].any((v) => v.toLowerCase().contains(q)))).toList();
      return RefreshIndicator(onRefresh: () async { final f = widget.api.getRepairs(widget.token); setState(() => future = f); await f; }, child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [Expanded(child: _metric(tr('Всички','All'), all.length)), Expanded(child: _metric(tr('В работа','In progress'), all.where((r)=>!['completed','cancelled','ready'].contains(r.status)).length)), Expanded(child: _metric(tr('Готови','Ready'), all.where((r)=>r.status=='ready').length))]),
        const SizedBox(height: 14), TextField(controller: search, onChanged: (_) => setState(() {}), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Търси №, клиент, телефон, сериен №…','Search no., customer, phone, serial…'), border: const OutlineInputBorder(), suffixIcon: search.text.isEmpty ? null : IconButton(onPressed: () { search.clear(); setState(() {}); }, icon: const Icon(Icons.close)))),
        const SizedBox(height: 10), DropdownButtonFormField<String>(initialValue: filter, decoration: InputDecoration(labelText: tr('Филтър по статус','Filter by status')), items: [DropdownMenuItem(value:'all', child: Text(tr('Всички статуси','All statuses'))), ...statuses.map((s)=>DropdownMenuItem(value:s, child: Text(label(s))))], onChanged: (v)=>setState(()=>filter=v ?? 'all')),
        const SizedBox(height: 12), if (rows.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(tr('Няма намерени ремонти.','No repairs found.'), textAlign: TextAlign.center)),
        ...rows.map((r) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(r.number, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))), Chip(label: Text(label(r.status))) ]),
          Text('${r.device} ${r.model}'.trim(), style: const TextStyle(color: Colors.white70)),
          if (r.customer.isNotEmpty || r.phone.isNotEmpty) Padding(padding: const EdgeInsets.only(top:5), child: Text([r.customer,r.phone].where((x)=>x.isNotEmpty).join(' · '))),
          if (r.serial.isNotEmpty) Text('${tr('Сериен №','Serial')}: ${r.serial}', style: const TextStyle(color: Colors.white60)),
          if (r.location.isNotEmpty) Text(r.location, style: const TextStyle(color: Colors.white60)),
          Text('${tr('Техник','Technician')}: ${r.technicianName.isEmpty ? tr('Не е назначен','Unassigned') : r.technicianName} · ${tr('Приоритет','Priority')}: ${_priorityLabel(r.priority)}${r.dueAt.isNotEmpty ? ' · ${tr('Срок','Due')}: ${r.dueAt}' : ''}', style: const TextStyle(color: Colors.white60)),
          if (r.problem.isNotEmpty) Padding(padding: const EdgeInsets.only(top:6), child: Text(r.problem, maxLines:2, overflow: TextOverflow.ellipsis)),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [TextButton.icon(onPressed: busy ? null : () => _manageAssignment(r), icon: const Icon(Icons.assignment_ind_outlined), label: Text(tr('Назначи техник','Assign technician'))), TextButton.icon(onPressed: busy ? null : () => _changeStatus(r), icon: const Icon(Icons.edit_outlined), label: Text(tr('Статус','Status')))])
        ]))))
      ]));
    }),
  );

  Widget _metric(String title, int value) => Card(child: Padding(padding: const EdgeInsets.symmetric(vertical:12,horizontal:8), child: Column(children: [Text('$value', style: const TextStyle(fontSize:22,fontWeight:FontWeight.bold,color:cyan)), Text(title, textAlign:TextAlign.center, style: const TextStyle(fontSize:12))])));

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
    try { await widget.api.updateRepairStatus(widget.token, r.id, selected, note: note.text.trim()); if(mounted) { reload(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(tr('Статусът е обновен.','Status updated.')))); } }
    catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e'))); }
    finally { note.dispose(); if(mounted) setState(()=>busy=false); }
  }
}
