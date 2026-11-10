import 'package:flutter/material.dart';
import '../services/api_service.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key, required this.api, required this.tokenProvider, required this.location, required this.onChooseLocation, this.english = false});
  final ApiService api;
  final Future<String?> Function() tokenProvider;
  final ServiceLocation? location;
  final VoidCallback onChooseLocation;
  final bool english;

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  static const cyan = Color(0xFF21D4D8);
  bool get en => widget.english;
  String tr(String bg, String enText) => en ? enText : bg;
  bool loading = true;
  bool submitting = false;
  String? error;
  List<Map<String, dynamic>> services = [];
  List<Map<String, dynamic>> slots = [];
  List<Map<String, dynamic>> bookings = [];
  int? serviceId;
  DateTime selectedDate = DateTime.now();
  String? selectedStart;
  final deviceController = TextEditingController();
  final issueController = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }
  @override
  void didUpdateWidget(covariant BookingScreen oldWidget) { super.didUpdateWidget(oldWidget); if (oldWidget.location?.code != widget.location?.code) _loadSlots(); }
  @override
  void dispose() { deviceController.dispose(); issueController.dispose(); super.dispose(); }
  String _dateKey(DateTime d) => '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final config = await widget.api.getBookingConfig();
      if (config['enabled'] == false) throw Exception(tr('Системата за записване е временно изключена.','The booking system is currently disabled.'));
      final list = await widget.api.getBookingServices();
      final token = await widget.tokenProvider();
      final mine = token == null || token.isEmpty ? <Map<String,dynamic>>[] : await widget.api.getMyBookings(token);
      if (!mounted) return;
      setState(() { services = list; bookings = mine; serviceId = list.isNotEmpty ? int.tryParse('${list.first['id']}') : null; loading = false; });
      await _loadSlots();
    } catch (e) { if (mounted) setState(() { error = e.toString().replaceFirst('Exception: ',''); loading = false; }); }
  }

  Future<void> _loadSlots() async {
    final location = widget.location;
    final id = serviceId;
    if (location == null || id == null) { if (mounted) setState(() { slots = []; selectedStart = null; }); return; }
    try {
      final result = await widget.api.getBookingSlots(date: _dateKey(selectedDate), locationCode: location.code.isNotEmpty ? location.code : location.name, serviceId: id);
      // Display only quarter-hour start times. The booking API must enforce the same
      // rule server-side to prevent direct requests from bypassing the UI.
      final quarterHourSlots = result.where((slot) {
        final raw = '${slot['start'] ?? ''}';
        final parsed = DateTime.tryParse(raw);
        if (parsed != null) return parsed.minute % 15 == 0;
        final match = RegExp(r'(?:^|T|\s)(\d{1,2}):(\d{2})').firstMatch(raw);
        if (match == null) return false;
        final minute = int.tryParse(match.group(2) ?? '');
        return minute != null && minute % 15 == 0;
      }).toList(growable: false);
      if (!mounted) return;
      setState(() { slots = quarterHourSlots; selectedStart = null; });
    } catch (e) { if (mounted) setState(() { slots = []; error = e.toString().replaceFirst('Exception: ',''); }); }
  }

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(context: context, initialDate: selectedDate.isBefore(DateTime.now()) ? DateTime.now() : selectedDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)), helpText: tr('Изберете дата','Choose a date'));
    if (picked == null) return;
    setState(() { selectedDate = picked; selectedStart = null; }); await _loadSlots();
  }

  Future<void> _book() async {
    final token = await widget.tokenProvider();
    if (token == null || token.isEmpty) { _notice(tr('Влезте в клиентския си профил, за да запазите час.','Sign in to your customer account to book an appointment.')); return; }
    final location = widget.location;
    if (location == null || serviceId == null || selectedStart == null) return;
    setState(() { submitting = true; error = null; });
    try {
      await widget.api.createBooking(token, {
        'service_id': serviceId,
        'location_code': location.code.isNotEmpty ? location.code : location.name,
        'location_name': location.name,
        'starts_at': selectedStart,
        'device': deviceController.text.trim(),
        'issue': issueController.text.trim(),
      });
      if (!mounted) return;
      _notice(tr('Часът е записан успешно!','Your appointment has been booked!'));
      deviceController.clear(); issueController.clear();
      setState(() { selectedStart = null; });
      await _load();
    } catch (e) { if (mounted) { setState(() { error = e.toString().replaceFirst('Exception: ',''); }); _notice(error!); await _loadSlots(); } }
    finally { if (mounted) setState(() { submitting = false; }); }
  }

  Future<void> _cancel(Map<String,dynamic> booking) async {
    final id = int.tryParse('${booking['id']}'); if (id == null) return;
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(tr('Отмяна на час','Cancel appointment')), content: Text(tr('Сигурни ли сте, че искате да отмените този час?','Are you sure you want to cancel this appointment?')), actions: [TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(tr('Назад','Back'))), FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(tr('Отмени','Cancel')))]));
    if (yes != true) return;
    try { final token=await widget.tokenProvider(); if(token==null) return; await widget.api.cancelBooking(token,id); await _load(); _notice(tr('Резервацията е отменена.','Appointment cancelled.')); }
    catch(e){_notice(e.toString().replaceFirst('Exception: ',''));}
  }
  void _notice(String message) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); }
  String _displayDate(dynamic value) { final d=DateTime.tryParse('$value'); if(d==null)return '$value'; return '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}'; }

  @override
  Widget build(BuildContext context) {
    final location=widget.location;
    return RefreshIndicator(onRefresh:_load, child: ListView(padding:const EdgeInsets.all(18), children:[
      Text(tr('Записване на час за сервиз','Book a service appointment'),style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
      const SizedBox(height:6), Text(tr('Изберете услуга, обект, дата и свободен час. Резервацията се записва директно в PCWork.','Choose a service, location, date and available time. Your booking is saved directly in PCWork.'),style:TextStyle(color:Colors.white70)),
      const SizedBox(height:14),
      Card(child:ListTile(leading:const Icon(Icons.location_on_outlined,color:cyan),title:Text(location?.name ?? tr('Не е избран сервизен обект','No service location selected')),subtitle:Text(location?.address ?? tr('Изберете обект, за да видите свободните часове.','Choose a location to see available times.')),trailing:TextButton(onPressed:widget.onChooseLocation,child:Text(tr('Промени','Change'))))),
      if(loading) const Padding(padding:EdgeInsets.all(24),child:Center(child:CircularProgressIndicator()))
      else if(error!=null) Card(child:Padding(padding:const EdgeInsets.all(14),child:Text(error!,style:const TextStyle(color:Colors.orangeAccent))))
      else ...[
        const SizedBox(height:12), Text(tr('Услуга','Service'),style:const TextStyle(fontWeight:FontWeight.bold)),
        DropdownButtonFormField<int>(value:serviceId, isExpanded:true, decoration:const InputDecoration(border:OutlineInputBorder()), items:services.map((s)=>DropdownMenuItem<int>(value:int.tryParse('${s['id']}'),child:Text('${s['name']} · ${s['duration']} мин.'))).toList(), onChanged:(v) async {setState(()=>serviceId=v); await _loadSlots();}),
        const SizedBox(height:14), Text(tr('Дата','Date'),style:const TextStyle(fontWeight:FontWeight.bold)),
        OutlinedButton.icon(onPressed:_chooseDate,icon:const Icon(Icons.calendar_month),label:Text(_displayDate(_dateKey(selectedDate)))),
        const SizedBox(height:8), Text(tr('Свободни часове','Available times'),style:const TextStyle(fontWeight:FontWeight.bold)),
        if(location==null) Text(tr('Първо изберете сервизен обект.','Please choose a service location first.'))
        else if(slots.isEmpty) Text(tr('Няма свободни часове за избраната дата. Опитайте друга дата.','No available times for this date. Try another date.'),style:const TextStyle(color:Colors.white70))
        else Wrap(spacing:8,runSpacing:8,children:slots.map((slot){final start='${slot['start']}';final selected=selectedStart==start;return ChoiceChip(label:Text('${slot['label']}'),selected:selected,onSelected:(_)=>setState(()=>selectedStart=start),selectedColor:cyan,labelStyle:TextStyle(color:selected?Colors.black:Theme.of(context).colorScheme.onSurface));}).toList()),
        const SizedBox(height:14), TextField(controller:deviceController,decoration:InputDecoration(labelText:tr('Устройство / модел (по желание)','Device / model (optional)'),border:const OutlineInputBorder())),
        const SizedBox(height:10), TextField(controller:issueController,maxLines:3,decoration:InputDecoration(labelText:tr('Описание на проблема (по желание)','Describe the issue (optional)'),border:const OutlineInputBorder())),
        const SizedBox(height:14), FilledButton.icon(onPressed:submitting||selectedStart==null||location==null?null:_book,icon:submitting?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.event_available),label:Text(tr('Потвърди записването','Confirm appointment'))),
      ],
      const SizedBox(height:24), Text(tr('Моите резервации','My appointments'),style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      if(bookings.isEmpty) Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(tr('Нямате записани часове или трябва да влезете в профила си.','No appointments yet, or sign in to view your bookings.'),style:const TextStyle(color:Colors.white70)))
      else ...bookings.map((b){final status='${b['status']}';return Card(child:ListTile(leading:Icon(status=='cancelled'?Icons.event_busy:Icons.event_available,color:status=='cancelled'?Colors.orange:cyan),title:Text('${b['service_name']??tr('Сервизна услуга','Service')} · ${_displayDate(b['starts_at'])}'),subtitle:Text('${b['location_name']??''}\n${tr('Статус','Status')}: $status',maxLines:3),isThreeLine:true,trailing:status=='confirmed'?IconButton(tooltip:tr('Отмени','Cancel'),onPressed:()=>_cancel(b),icon:const Icon(Icons.cancel_outlined)):null));}),
    ]));
  }
}
