import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../design_system/pcwork_design_system.dart';

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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? PCWorkColors.textSecondary : const Color(0xFF607187);
    final foreground = dark ? PCWorkColors.textPrimary : const Color(0xFF172033);
    final panelTint = dark ? Colors.white.withValues(alpha: .045) : const Color(0xFFF7FAFD);
    return Container(
      decoration: BoxDecoration(gradient: dark ? PCWorkEffects.background : const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFFF7F9FC), Color(0xFFF0F4F9), Color(0xFFEAF0F6)],
      )),
      child: RefreshIndicator(
        color: PCWorkColors.cyan,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
          children: [
            PCWorkGlassPanel(
              glow: true,
              padding: const EdgeInsets.all(20),
              gradient: dark ? const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xE51B4773), Color(0xD20B1835), Color(0xCC26165A)],
              ) : const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFFE3F5FA), Color(0xFFF2F5FC), Color(0xFFEDEBFA)],
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('PCWORK • BOOKING', 'PCWORK • BOOKING'), style: TextStyle(color: dark ? PCWorkColors.cyan : const Color(0xFF087F83), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.8)),
                  const SizedBox(height: 9),
                  Text(tr('Запази своя час.', 'Book your service.'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: foreground)),
                  const SizedBox(height: 7),
                  Text(tr('Избери услуга и удобно време. Ние ще се погрижим за устройството ти.', 'Choose a service and a convenient time. We will take care of your device.'), style: TextStyle(color: muted, height: 1.4)),
                ])),
                const SizedBox(width: 12),
                ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.asset('assets/images/pcwork_booking_hero.webp', width: 88, height: 88, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const PCWorkGlowIcon(icon: Icons.calendar_month_rounded, size: 66, iconSize: 34, color: PCWorkColors.cyan))),
              ]),
            ),
            const SizedBox(height: 16),
            PCWorkGlassPanel(
              glow: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _sectionHeading(Icons.storefront_rounded, tr('Сервизен център', 'Service center')),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: panelTint, borderRadius: BorderRadius.circular(18), border: Border.all(color: PCWorkColors.electricBlue.withValues(alpha: .28))),
                  child: Row(children: [
                    const PCWorkGlowIcon(icon: Icons.location_on_rounded, size: 44, iconSize: 22),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(location?.name ?? tr('Не е избран обект', 'No location selected'), style: TextStyle(fontWeight: FontWeight.w800, color: foreground)),
                      if ((location?.address ?? '').isNotEmpty) Text(location!.address, style: TextStyle(color: muted, fontSize: 12)),
                      if (location == null) Text(tr('Избери обект, за да видиш свободните часове.', 'Choose a location to view available times.'), style: TextStyle(color: muted, fontSize: 12)),
                    ])),
                    TextButton(onPressed: widget.onChooseLocation, child: Text(tr('Промени', 'Change'))),
                  ]),
                ),
                const SizedBox(height: 18),
                _sectionHeading(Icons.build_circle_outlined, tr('Избери услуга', 'Choose a service')),
                const SizedBox(height: 9),
                if (loading) const Center(child: Padding(padding: EdgeInsets.all(22), child: CircularProgressIndicator()))
                else if (error != null) _errorPanel(error!)
                else ...[
                  DropdownButtonFormField<int>(
                    initialValue: serviceId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      filled: true, fillColor: panelTint,
                      prefixIcon: const Icon(Icons.miscellaneous_services_rounded, color: PCWorkColors.cyan),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: PCWorkColors.electricBlue.withValues(alpha: .3))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: PCWorkColors.electricBlue.withValues(alpha: .25))),
                    ),
                    items: services.map((s) => DropdownMenuItem<int>(value: int.tryParse('${s['id']}'), child: Text('${s['name']} · ${s['duration']} мин.'))).toList(),
                    onChanged: (v) async { setState(() => serviceId = v); await _loadSlots(); },
                  ),
                  const SizedBox(height: 18),
                  _sectionHeading(Icons.event_rounded, tr('Дата и свободен час', 'Date and available time')),
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _chooseDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                      decoration: BoxDecoration(gradient: dark ? const LinearGradient(colors: [Color(0x4421D4D8), Color(0x332C66C9)]) : const LinearGradient(colors: [Color(0xFFDDF7F5), Color(0xFFE0EAFB)]), borderRadius: BorderRadius.circular(18), border: Border.all(color: PCWorkColors.cyan.withValues(alpha: .48))),
                      child: Row(children: [const PCWorkGlowIcon(icon: Icons.calendar_today_rounded, size: 42, iconSize: 20, color: PCWorkColors.cyan), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr('ИЗБРАНА ДАТА', 'SELECTED DATE'), style: TextStyle(fontSize: 10, color: dark ? PCWorkColors.cyan : const Color(0xFF087F83), letterSpacing: 1.2, fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(_displayDate(_dateKey(selectedDate)), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: foreground))])), Icon(Icons.chevron_right_rounded, color: dark ? PCWorkColors.cyan : const Color(0xFF087F83), size: 28)],),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (location == null)
                    _emptyPanel(Icons.location_searching_rounded, tr('Първо избери сервизен обект.', 'Choose a service location first.'), dark)
                  else if (slots.isEmpty)
                    _emptyPanel(Icons.event_busy_rounded, tr('Няма свободни часове за тази дата. Избери друг ден.', 'No available times on this date. Choose another day.'), dark)
                  else Wrap(spacing: 9, runSpacing: 9, children: slots.map((slot) {
                    final start = '${slot['start']}'; final selected = selectedStart == start;
                    return ChoiceChip(
                      label: Text('${slot['label']}', style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Colors.white : muted)),
                      selected: selected,
                      onSelected: (_) => setState(() => selectedStart = start),
                      selectedColor: PCWorkColors.violet,
                      backgroundColor: dark ? PCWorkColors.electricBlue.withValues(alpha: .12) : const Color(0xFFE3EDF8),
                      side: BorderSide(color: selected ? PCWorkColors.cyan : PCWorkColors.electricBlue.withValues(alpha: .35)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    );
                  }).toList()),
                  const SizedBox(height: 18),
                  _sectionHeading(Icons.devices_rounded, tr('Информация за устройството', 'Device information')),
                  const SizedBox(height: 10),
                  TextField(controller: deviceController, decoration: _fieldDecoration(tr('Устройство / модел (по желание)', 'Device / model (optional)'), Icons.laptop_mac_rounded, dark)),
                  const SizedBox(height: 10),
                  TextField(controller: issueController, maxLines: 3, decoration: _fieldDecoration(tr('Опиши накратко проблема (по желание)', 'Briefly describe the issue (optional)'), Icons.notes_rounded, dark)),
                  const SizedBox(height: 18),
                  SizedBox(width: double.infinity, child: DecoratedBox(
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [PCWorkColors.electricBlue, PCWorkColors.cyan, PCWorkColors.violet]), borderRadius: BorderRadius.circular(17), boxShadow: [BoxShadow(color: PCWorkColors.electricBlue.withValues(alpha: .25), blurRadius: 20, offset: const Offset(0, 7))]),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))),
                      onPressed: submitting || selectedStart == null || location == null ? null : _book,
                      icon: submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.bolt_rounded),
                      label: Text(tr('ПОТВЪРДИ ЗАПИСВАНЕТО', 'CONFIRM BOOKING'), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: .6)),
                    ),
                  )),
                ],
              ]),
            ),
            const SizedBox(height: 22),
            _sectionHeading(Icons.bookmark_added_rounded, tr('Моите резервации', 'My appointments')),
            const SizedBox(height: 10),
            if (bookings.isEmpty)
              _emptyPanel(Icons.event_note_rounded, tr('Все още нямаш записани часове.', 'You do not have any appointments yet.'), dark)
            else ...bookings.map((b) {
              final status = '${b['status']}';
              final active = status == 'confirmed';
              return Padding(padding: const EdgeInsets.only(bottom: 9), child: PCWorkGlassPanel(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  PCWorkGlowIcon(icon: active ? Icons.event_available_rounded : Icons.event_busy_rounded, color: active ? PCWorkColors.success : PCWorkColors.warning, size: 46),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${b['service_name'] ?? tr('Сервизна услуга', 'Service')} ', style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(_displayDate(b['starts_at']), style: TextStyle(color: muted)), Text('${b['location_name'] ?? ''} · $status', style: TextStyle(color: muted, fontSize: 12))])),
                  if (active) IconButton(onPressed: () => _cancel(b), tooltip: tr('Отмени', 'Cancel'), icon: const Icon(Icons.close_rounded, color: PCWorkColors.danger)),
                ]),
              ));
            }),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeading(IconData icon, String title) => Row(children: [
    PCWorkGlowIcon(icon: icon, size: 34, iconSize: 17, color: PCWorkColors.cyan),
    const SizedBox(width: 9),
    Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -.2))),
  ]);

  InputDecoration _fieldDecoration(String label, IconData icon, bool dark) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: PCWorkColors.cyan),
    filled: true,
    fillColor: dark ? const Color(0xFF0D192B) : const Color(0xFFF7FAFD),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: PCWorkColors.electricBlue.withValues(alpha: .22))),
  );

  Widget _emptyPanel(IconData icon, String message, bool dark) => PCWorkGlassPanel(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    child: Row(children: [Icon(icon, color: PCWorkColors.cyan, size: 25), const SizedBox(width: 12), Expanded(child: Text(message, style: TextStyle(color: dark ? PCWorkColors.textSecondary : const Color(0xFF607187))))]),
  );

  Widget _errorPanel(String message) => PCWorkGlassPanel(
    borderColor: PCWorkColors.danger.withValues(alpha: .5),
    child: Row(children: [const Icon(Icons.error_outline_rounded, color: PCWorkColors.danger), const SizedBox(width: 10), Expanded(child: Text(message))]),
  );
}
