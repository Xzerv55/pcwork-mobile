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
    final location = widget.location;
    final panel = BoxDecoration(
      color: const Color(0xFF0D1B35).withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: cyan.withValues(alpha: 0.48), width: 1.1),
      boxShadow: [BoxShadow(color: cyan.withValues(alpha: 0.10), blurRadius: 18, spreadRadius: 1)],
    );
    final muted = TextStyle(color: Colors.white.withValues(alpha: 0.72));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(children: [
              Image.asset('assets/images/pcwork_booking_hero.webp', height: 176, width: double.infinity, fit: BoxFit.cover),
              Container(height: 176, decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight,
                  colors: [const Color(0xFF061329).withValues(alpha: 0.97), const Color(0xFF061329).withValues(alpha: 0.70), Colors.transparent]),
                border: Border.all(color: cyan.withValues(alpha: 0.65)),
              )),
              Positioned.fill(child: Padding(padding: const EdgeInsets.all(18), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(tr('ЗАПИСВАНЕ НА ЧАС', 'BOOK AN APPOINTMENT'), style: TextStyle(color: cyan, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(tr('Твоят сервиз.\nТвоето време.', 'Your service.\nYour time.'), style: const TextStyle(fontSize: 25, height: 1.08, fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(tr('Избери услуга и удобен свободен час.', 'Choose a service and a convenient time.'), style: muted),
                ],
              ))),
            ]),
          ),
          const SizedBox(height: 16),
          Container(decoration: panel, padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Icon(Icons.storefront_rounded, color: cyan, size: 22), const SizedBox(width: 9), Expanded(child: Text(tr('Сервизен обект', 'Service location'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
              TextButton(onPressed: widget.onChooseLocation, child: Text(tr('Промени', 'Change')))]),
            Text(location?.name ?? tr('Не е избран сервизен обект', 'No service location selected'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(location?.address ?? tr('Изберете обект, за да видите свободните часове.', 'Choose a location to see available times.'), style: muted),
          ])),
          if (loading) const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))
          else if (error != null) Container(margin: const EdgeInsets.only(top: 14), decoration: panel, padding: const EdgeInsets.all(14), child: Text(error!, style: const TextStyle(color: Colors.orangeAccent)))
          else ...[
            const SizedBox(height: 16),
            Container(decoration: panel, padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('01  ИЗБЕРИ УСЛУГА', '01  SELECT A SERVICE'), style: TextStyle(color: cyan, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: serviceId, isExpanded: true,
                decoration: InputDecoration(filled: true, fillColor: const Color(0xFF071329), prefixIcon: const Icon(Icons.build_circle_outlined, color: cyan), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cyan.withValues(alpha: 0.35))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cyan.withValues(alpha: 0.35)))),
                items: services.map((s) => DropdownMenuItem<int>(value: int.tryParse('${s['id']}'), child: Text('${s['name']} · ${s['duration']} мин.'))).toList(),
                onChanged: (v) async { setState(() => serviceId = v); await _loadSlots(); },
              ),
              const SizedBox(height: 18),
              Text(tr('02  ИЗБЕРИ ДАТА', '02  SELECT A DATE'), style: TextStyle(color: cyan, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              InkWell(onTap: _chooseDate, borderRadius: BorderRadius.circular(15), child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(color: const Color(0xFF071329), borderRadius: BorderRadius.circular(15), border: Border.all(color: cyan.withValues(alpha: 0.42))),
                child: Row(children: [const Icon(Icons.calendar_month_rounded, color: cyan, size: 25), const SizedBox(width: 12), Expanded(child: Text(_displayDate(_dateKey(selectedDate)), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))), const Icon(Icons.chevron_right, color: cyan)]),
              )),
              const SizedBox(height: 18),
              Row(children: [Text(tr('03  СВОБОДНИ ЧАСОВЕ', '03  AVAILABLE TIMES'), style: TextStyle(color: cyan, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w800)), const Spacer(), if (slots.isNotEmpty) Text('${slots.length} ${tr('свободни', 'available')}', style: muted.copyWith(fontSize: 11))]),
              const SizedBox(height: 10),
              if (location == null) Text(tr('Първо изберете сервизен обект.', 'Please choose a service location first.'), style: muted)
              else if (slots.isEmpty) Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF071329), borderRadius: BorderRadius.circular(14)), child: Text(tr('Няма свободни часове за избраната дата. Опитайте друга дата.', 'No available times for this date. Try another date.'), style: muted))
              else Wrap(spacing: 9, runSpacing: 9, children: slots.map((slot) {
                final start = '${slot['start']}'; final selected = selectedStart == start;
                return ChoiceChip(label: Text('${slot['label']}'), selected: selected,
                  onSelected: (_) => setState(() => selectedStart = start),
                  backgroundColor: const Color(0xFF071329), selectedColor: cyan,
                  side: BorderSide(color: selected ? cyan : cyan.withValues(alpha: 0.35)),
                  labelStyle: TextStyle(color: selected ? const Color(0xFF04101F) : Colors.white, fontWeight: FontWeight.w700));
              }).toList()),
            ])),
            const SizedBox(height: 14),
            Container(decoration: panel, padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('04  ДЕТАЙЛИ ЗА УСТРОЙСТВОТО', '04  DEVICE DETAILS'), style: TextStyle(color: cyan, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextField(controller: deviceController, decoration: InputDecoration(filled: true, fillColor: const Color(0xFF071329), prefixIcon: const Icon(Icons.devices_other, color: cyan), labelText: tr('Устройство / модел (по желание)', 'Device / model (optional)'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)))),
              const SizedBox(height: 10),
              TextField(controller: issueController, maxLines: 3, decoration: InputDecoration(filled: true, fillColor: const Color(0xFF071329), prefixIcon: const Padding(padding: EdgeInsets.only(bottom: 42), child: Icon(Icons.description_outlined, color: cyan)), alignLabelWithHint: true, labelText: tr('Описание на проблема (по желание)', 'Describe the issue (optional)'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)))),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, height: 54, child: DecoratedBox(
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF00D8E8), Color(0xFF176BFF), Color(0xFF8B35FF)]), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: cyan.withValues(alpha: 0.24), blurRadius: 18)]),
                child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: submitting || selectedStart == null || location == null ? null : _book,
                  icon: submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.event_available_rounded),
                  label: Text(tr('ПОТВЪРДИ ЗАПИСВАНЕТО', 'CONFIRM APPOINTMENT'), style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5))),
              )),
            ])),
          ],
          const SizedBox(height: 24),
          Row(children: [const Icon(Icons.event_note_rounded, color: cyan), const SizedBox(width: 8), Text(tr('Моите резервации', 'My appointments'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]),
          const SizedBox(height: 10),
          if (bookings.isEmpty) Container(decoration: panel, padding: const EdgeInsets.all(16), child: Text(tr('Нямате записани часове или трябва да влезете в профила си.', 'No appointments yet, or sign in to view your bookings.'), style: muted))
          else ...bookings.map((b) {
            final status = '${b['status']}';
            return Container(margin: const EdgeInsets.only(bottom: 9), decoration: panel, child: ListTile(
              leading: Icon(status == 'cancelled' ? Icons.event_busy : Icons.event_available, color: status == 'cancelled' ? Colors.orange : cyan),
              title: Text('${b['service_name'] ?? tr('Сервизна услуга', 'Service')} · ${_displayDate(b['starts_at'])}'),
              subtitle: Text('${b['location_name'] ?? ''}\n${tr('Статус', 'Status')}: $status', maxLines: 3), isThreeLine: true,
              trailing: status == 'confirmed' ? IconButton(tooltip: tr('Отмени', 'Cancel'), onPressed: () => _cancel(b), icon: const Icon(Icons.cancel_outlined)) : null,
            ));
          }),
        ],
      ),
    );
  }
}
