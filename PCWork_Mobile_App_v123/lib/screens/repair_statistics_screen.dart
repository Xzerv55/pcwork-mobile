import 'package:flutter/material.dart';
import '../services/api_service.dart';

class RepairStatisticsScreen extends StatefulWidget {
  const RepairStatisticsScreen({super.key, required this.api, required this.token, required this.english});
  final ApiService api;
  final String token;
  final bool english;
  @override
  State<RepairStatisticsScreen> createState() => _RepairStatisticsScreenState();
}

class _RepairStatisticsScreenState extends State<RepairStatisticsScreen> {
  late Future<List<Repair>> _future;
  String tr(String bg, String en) => widget.english ? en : bg;
  static const statuses = <String, String>{
    'received':'Приет', 'diagnostics':'Диагностика', 'waiting_approval':'Очаква одобрение',
    'in_repair':'В ремонт', 'ready':'Готов', 'completed':'Приключен', 'cancelled':'Отменен',
  };
  @override
  void initState() { super.initState(); _future = widget.api.getRepairs(widget.token); }
  void _reload() => setState(() => _future = widget.api.getRepairs(widget.token, forceRefresh: true));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Статистика и отчети','Statistics & reports')), actions:[IconButton(onPressed:_reload, icon:const Icon(Icons.refresh))]),
    body: FutureBuilder<List<Repair>>(
      future:_future,
      builder:(context,snapshot){
        if(snapshot.connectionState!=ConnectionState.done) return const Center(child:CircularProgressIndicator());
        if(snapshot.hasError) return Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.cloud_off_outlined,size:42),const SizedBox(height:12),Text('${tr('Неуспешно зареждане на статистиката:','Could not load statistics:')} ${snapshot.error}',textAlign:TextAlign.center),const SizedBox(height:12),FilledButton.icon(onPressed:_reload,icon:const Icon(Icons.refresh),label:Text(tr('Опитай отново','Try again')))])));
        final repairs=snapshot.data??<Repair>[];
        final counts=<String,int>{for(final key in statuses.keys) key:0};
        final locations=<String,int>{}; final technicians=<String,int>{};
        var pending=0; var overdue=0; var withHistory=0;
        final now=DateTime.now();
        for(final r in repairs){
          counts[r.status]=(counts[r.status]??0)+1;
          final loc=r.location.isNotEmpty?r.location:(r.locationCode.isNotEmpty?r.locationCode:tr('Без обект','No location'));
          locations[loc]=(locations[loc]??0)+1;
          final tech=r.technicianName.isNotEmpty?r.technicianName:(r.technicianId>0?'#${r.technicianId}':tr('Неназначен','Unassigned'));
          technicians[tech]=(technicians[tech]??0)+1;
          if(r.pendingSync) pending++;
          if(r.history.isNotEmpty) withHistory++;
          final due=DateTime.tryParse(r.dueAt);
          if(due!=null && due.isBefore(now) && !['completed','cancelled','ready'].contains(r.status)) overdue++;
        }
        locations.removeWhere((k,v)=>v==0); technicians.removeWhere((k,v)=>v==0);
        return RefreshIndicator(onRefresh:()async=>_reload(),child:ListView(padding:const EdgeInsets.all(16),children:[
          Text(tr('Общ преглед на сервизната дейност','Service activity overview'),style:Theme.of(context).textTheme.titleLarge),
          const SizedBox(height:14),
          GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:2,childAspectRatio:1.8,crossAxisSpacing:10,mainAxisSpacing:10,children:[
            _metric(tr('Всички ремонти','Total repairs'),repairs.length,Icons.build_circle_outlined),
            _metric(tr('В процес','In progress'),repairs.where((r)=>!['completed','cancelled'].contains(r.status)).length,Icons.pending_actions),
            _metric(tr('Просрочени','Overdue'),overdue,Icons.warning_amber_rounded),
            _metric(tr('Чакащи синхронизация','Pending sync'),pending,Icons.sync),
          ]),
          const SizedBox(height:22), Text(tr('Ремонти по статус','Repairs by status'),style:Theme.of(context).textTheme.titleMedium),
          const SizedBox(height:8),
          ...statuses.entries.map((e){final n=counts[e.key]??0;final ratio=repairs.isEmpty?0.0:n/repairs.length;return Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Expanded(child:Text(widget.english?({'received':'Received','diagnostics':'Diagnostics','waiting_approval':'Awaiting approval','in_repair':'In repair','ready':'Ready','completed':'Completed','cancelled':'Cancelled'}[e.key]??e.value):e.value)),Text('$n')]),const SizedBox(height:5),ClipRRect(borderRadius:BorderRadius.circular(8),child:LinearProgressIndicator(value:ratio,minHeight:8,backgroundColor:Colors.white10))]));}),
          const SizedBox(height:18), _rankSection(tr('Натоварване по сервизен обект','Repairs by service location'),locations),
          const SizedBox(height:16), _rankSection(tr('Ремонти по техник','Repairs by technician'),technicians),
          const SizedBox(height:16), Card(child:ListTile(leading:const Icon(Icons.history),title:Text(tr('Ремонти с история на действията','Repairs with activity history')),trailing:Text('$withHistory / ${repairs.length}',style:const TextStyle(fontWeight:FontWeight.bold)))),
          Padding(padding:const EdgeInsets.only(top:12),child:Text(tr('Отчетът използва наличните ремонти от WordPress API и локалния офлайн кеш. Показаните стойности се обновяват при опресняване.','This report uses repairs available from the WordPress API and local offline cache. Values update when refreshed.'),style:Theme.of(context).textTheme.bodySmall)),
        ]));
      }),
  );

  Widget _metric(String label,int value,IconData icon)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[Icon(icon,color:const Color(0xFF21D4D8),size:26),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[Text('$value',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),Text(label,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,color:Colors.white70))]))])));
  Widget _rankSection(String title,Map<String,int> values){final sorted=values.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));return Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:8),if(sorted.isEmpty) Text(tr('Няма данни','No data'),style:const TextStyle(color:Colors.white54)),...sorted.take(8).map((e)=>Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Row(children:[Expanded(child:Text(e.key,maxLines:1,overflow:TextOverflow.ellipsis)),Text('${e.value}',style:const TextStyle(fontWeight:FontWeight.bold))])))])));}
}
