import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/push_notification_service.dart';
import 'screens/repair_protocol_screen.dart';
import 'screens/repair_evidence_screen.dart';
import 'screens/repair_documents_screen.dart';
import 'screens/staff_dashboard_screen.dart';

void main() => runApp(const PCWorkApp());

class PCWorkApp extends StatefulWidget {
  const PCWorkApp({super.key});
  @override
  State<PCWorkApp> createState() => _PCWorkAppState();
}

class _PCWorkAppState extends State<PCWorkApp> {
  static const cyan = Color(0xFF21D4D8);
  static const defaultApi = 'https://pcwork-bg.com';
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  bool english = false;
  bool staffPreview = false;
  int tab = 0;
  String apiUrl = defaultApi;
  bool apiReady = false;
  bool checkingApi = false;
  String? apiMessage;
  List<ServiceLocation> locations = [];
  bool loadingLocations = false;
  String? locationsError;
  AuthUser? signedInUser;
  bool authBusy = false;
  Future<List<Repair>>? repairsFuture;
  final TextEditingController repairSearch = TextEditingController();
  String repairStatusFilter = 'all';

  AuthService get auth => AuthService(baseUrl: apiUrl);
  PushNotificationService get push => PushNotificationService(baseUrl: apiUrl);
  ApiService get api => ApiService(baseUrl: apiUrl);
  String tr(String bg, String en) => english ? en : bg;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try { final t = await auth.token; if (t != null) { final u = await auth.me(); if (mounted) setState(() { signedInUser = u; repairsFuture = api.getRepairs(t); });
      await _enablePush(t); } } catch (_) { if (mounted) setState(() => signedInUser = null); }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      apiUrl = prefs.getString('pcwork_api_url') ?? defaultApi;
      english = prefs.getBool('pcwork_english') ?? false;
      staffPreview = prefs.getBool('pcwork_staff_preview') ?? false;
    });
    _checkApi(silent: true);
  }

  Future<void> _savePreference(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
  }

  Future<void> _saveApiUrl(String value) async {
    final cleaned = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(cleaned);
    if (uri == null || uri.host.isEmpty || !['https', 'http'].contains(uri.scheme)) {
      throw Exception(tr('Въведете валиден адрес, започващ с https://', 'Enter a valid https:// URL.'));
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pcwork_api_url', cleaned);
    setState(() { apiUrl = cleaned; apiReady = false; locations = []; });
  }

  Future<void> _checkApi({bool silent = false}) async {
    setState(() { checkingApi = true; if (!silent) apiMessage = null; });
    try {
      await api.checkHealth();
      if (!mounted) return;
      setState(() { apiReady = true; apiMessage = tr('Връзката с PCWork сървъра е успешна.', 'Connected to the PCWork server.'); });
    } catch (e) {
      if (!mounted) return;
      setState(() { apiReady = false; apiMessage = tr('Няма връзка със сървъра: $e', 'Server connection failed: $e'); });
    } finally { if (mounted) setState(() => checkingApi = false); }
  }

  Future<void> _loadLocations() async {
    setState(() { loadingLocations = true; locationsError = null; });
    try {
      final result = await api.getLocations();
      if (!mounted) return;
      setState(() { locations = result; });
    } catch (e) { if (mounted) setState(() { locationsError = e.toString(); }); }
    finally { if (mounted) setState(() => loadingLocations = false); }
  }

  Future<void> _enablePush([String? knownToken]) async {
    final bearer = knownToken ?? await auth.token;
    if (bearer == null || bearer.isEmpty) return;
    await push.register(bearer, onForeground: (title, body) {
      if (!mounted) return;
      _messengerKey.currentState?.showSnackBar(SnackBar(content: Text('$title — $body')));
      if (mounted) setState(() => repairsFuture = _loadRepairsFuture());
    }, onOpened: () {
      if (mounted) setState(() { tab = 1; repairsFuture = _loadRepairsFuture(); });
    });
  }

  @override
  void dispose() { repairSearch.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final labels = [tr('Начало', 'Home'), tr('Ремонти', 'Repairs'), tr('Записване', 'Booking'), tr('Профил', 'Profile')];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      title: 'PCWork',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: cyan, brightness: Brightness.dark), scaffoldBackgroundColor: const Color(0xFF10151D), cardColor: const Color(0xFF1A2330), useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: Text('PCWork  ·  ${labels[tab]}'), actions: [
          IconButton(tooltip: tr('Език', 'Language'), onPressed: () { setState(() => english = !english); _savePreference('pcwork_english', english); }, icon: const Icon(Icons.language)),
          IconButton(tooltip: tr('Настройки', 'Settings'), onPressed: _showSettings, icon: const Icon(Icons.settings_outlined)),
        ]),
        body: IndexedStack(index: tab, children: [_home(), _repairs(), _booking(), _profile()]),
        bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v), destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), label: labels[0]),
          NavigationDestination(icon: const Icon(Icons.build_outlined), label: labels[1]),
          NavigationDestination(icon: const Icon(Icons.calendar_month_outlined), label: labels[2]),
          NavigationDestination(icon: const Icon(Icons.person_outline), label: labels[3]),
        ]),
      ),
    );
  }

  Widget _home() => ListView(padding: const EdgeInsets.all(20), children: [
    Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF173A46), Color(0xFF20283A)]), borderRadius: BorderRadius.circular(22)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.memory, color: cyan, size: 42), const SizedBox(height: 12),
      Text(tr('Техниката ви е в добри ръце.', 'Your devices, in good hands.'), style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8), Text(tr('Сервиз за компютри, лаптопи и PlayStation', 'PC, laptop and PlayStation service')),
      const SizedBox(height: 18), FilledButton.icon(onPressed: () => setState(() => tab = 2), icon: const Icon(Icons.add), label: Text(tr('Запази час', 'Book a service'))),
    ])),
    const SizedBox(height: 18), Row(children: [Expanded(child: _quickCard(Icons.handyman_outlined, tr('Моите ремонти', 'My repairs'), () => setState(() => tab = 1))), const SizedBox(width: 12), Expanded(child: _quickCard(Icons.storefront_outlined, tr('Сервизни обекти', 'Locations'), _showLocations))]),
    const SizedBox(height: 18), Card(child: ListTile(leading: Icon(apiReady ? Icons.cloud_done : Icons.cloud_off, color: apiReady ? Colors.greenAccent : Colors.orangeAccent), title: Text(tr('Връзка със сървъра', 'Server connection')), subtitle: Text(apiMessage ?? tr('Проверка на връзката…', 'Checking connection…')), trailing: IconButton(onPressed: _checkApi, icon: const Icon(Icons.refresh)))),
    const SizedBox(height: 12), Text(tr('Полезна информация', 'Useful information'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    _infoTile(Icons.verified_outlined, tr('Гаранция и условия на сервиза', 'Warranty and service terms')),
    _infoTile(Icons.chat_bubble_outline, tr('Връзка с поддръжката', 'Contact support')),
  ]);

  Widget _quickCard(IconData icon, String label, VoidCallback onTap) => Card(child: InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap, child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [Icon(icon, color: cyan, size: 30), const SizedBox(height: 9), Text(label, textAlign: TextAlign.center)]))));
  Widget _infoTile(IconData icon, String label) => Card(child: ListTile(leading: Icon(icon, color: cyan), title: Text(label), trailing: const Icon(Icons.chevron_right)));

  Widget _repairs() {
    if (signedInUser == null) return ListView(padding: const EdgeInsets.all(20), children: [
      Text(tr('Проследяване на ремонт', 'Repair tracking'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12), Text(tr('Влезте в профила си, за да видите ремонтите, историята и актуалния им статус.', 'Sign in to see your repairs, history and current status.')),
      const SizedBox(height: 16), FilledButton.icon(onPressed: () => setState(() => tab = 3), icon: const Icon(Icons.login), label: Text(tr('Вход / Регистрация', 'Sign in / Register'))),
    ]);
    final future = repairsFuture ??= _loadRepairsFuture();
    return RefreshIndicator(onRefresh: () async { final f = _loadRepairsFuture(); setState(() => repairsFuture = f); await f; }, child: FutureBuilder<List<Repair>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return ListView(padding: const EdgeInsets.all(24), children: [Text(tr('Неуспешно зареждане на ремонтите:', 'Could not load repairs:')), const SizedBox(height: 8), Text('${snapshot.error}'), const SizedBox(height: 12), OutlinedButton.icon(onPressed: () => setState(() => repairsFuture = _loadRepairsFuture()), icon: const Icon(Icons.refresh), label: Text(tr('Опитай отново', 'Try again')))]);
        final rows = List<Repair>.from(snapshot.data ?? [])..sort((a, b) => _repairDate(b.createdAt).compareTo(_repairDate(a.createdAt)));
        final query = repairSearch.text.trim().toLowerCase();
        final filtered = rows.where((r) => (repairStatusFilter == 'all' || r.status == repairStatusFilter) && (query.isEmpty || [r.number,r.device,r.model,r.serial,r.location].any((v) => v.toLowerCase().contains(query)))).toList();
        final active = rows.where((r) => !['completed','cancelled'].contains(r.status)).length;
        final ready = rows.where((r) => r.status == 'ready').length;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text(tr('Моите ремонти', 'My repairs'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: _repairMetric(tr('Всички','Total'), rows.length)), Expanded(child: _repairMetric(tr('Активни','Active'), active)), Expanded(child: _repairMetric(tr('Готови','Ready'), ready))]),
          const SizedBox(height: 12),
          TextField(controller: repairSearch, onChanged: (_) => setState(() {}), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Търси номер, устройство или модел','Search number, device or model'), border: const OutlineInputBorder(), suffixIcon: repairSearch.text.isEmpty ? null : IconButton(onPressed: () { repairSearch.clear(); setState(() {}); }, icon: const Icon(Icons.close)))),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: repairStatusFilter, decoration: InputDecoration(labelText: tr('Филтър по статус','Filter by status'), border: const OutlineInputBorder()), items: [DropdownMenuItem(value:'all', child:Text(tr('Всички статуси','All statuses'))), ...['received','diagnostics','waiting_approval','in_repair','ready','completed','cancelled'].map((v)=>DropdownMenuItem(value:v,child:Text(_statusLabel(v))))], onChanged:(v)=>setState(()=>repairStatusFilter=v ?? 'all')),
          const SizedBox(height: 12),
          if (filtered.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(rows.isEmpty ? tr('Все още няма ремонти, свързани с профила ви.','There are no repairs linked to your account yet.') : tr('Няма ремонти, отговарящи на търсенето.','No repairs match your search.'), textAlign: TextAlign.center)),
          ...filtered.map((r) => Card(child: ListTile(leading: CircleAvatar(child: Icon(r.status == 'ready' ? Icons.check_circle_outline : Icons.build, color: cyan)), title: Text(r.number.isEmpty ? 'Ремонт #${r.id}' : r.number), subtitle: Text([r.device, r.model, _statusLabel(r.status)].where((v) => v.isNotEmpty).join(' · ')), trailing: const Icon(Icons.chevron_right), onTap: () => _showRepairDetails(r))))
        ]);
      },
    ));
  }

  DateTime _repairDate(String value) => DateTime.tryParse(value)?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);

  String _formatDate(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d.$m.${date.year}';
  }

  String _priorityLabel(String value) {
    const bg = {'low': 'Нисък', 'normal': 'Нормален', 'high': 'Висок', 'urgent': 'Спешен'};
    const en = {'low': 'Low', 'normal': 'Normal', 'high': 'High', 'urgent': 'Urgent'};
    return (english ? en[value] : bg[value]) ?? value;
  }

  Future<void> _shareRepair(Repair repair) async {
    final number = repair.number.isEmpty ? 'PCW-${repair.id}' : repair.number;
    final text = [
      'PCWork – ${tr('Информация за ремонт', 'Repair information')}',
      '${tr('Номер', 'Number')}: $number',
      '${tr('Устройство', 'Device')}: ${repair.device} ${repair.model}'.trim(),
      '${tr('Статус', 'Status')}: ${_statusLabel(repair.status)}',
      if (repair.location.isNotEmpty) '${tr('Сервизен обект', 'Service location')}: ${repair.location}',
      if (repair.dueAt.isNotEmpty) '${tr('Краен срок', 'Due date')}: ${_formatDate(repair.dueAt)}',
      'https://pcwork-bg.com',
    ].join('\n');
    await Share.share(text, subject: 'PCWork $number');
  }

  Widget _repairMetric(String title, int value) => Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6), child: Column(children: [Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cyan)), Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))])));

  Future<List<Repair>> _loadRepairsFuture() async {
    final token = await auth.token;
    if (token == null) throw Exception(tr('Сесията е изтекла. Влезте отново.', 'Session expired. Please sign in again.'));
    return api.getRepairs(token);
  }

  String _statusLabel(String s) {
    const bg = {'received':'Приет','diagnostics':'Диагностика','waiting_approval':'Очаква одобрение','in_repair':'В ремонт','ready':'Готов','completed':'Приключен','cancelled':'Отменен'};
    const en = {'received':'Received','diagnostics':'Diagnostics','waiting_approval':'Awaiting approval','in_repair':'In repair','ready':'Ready','completed':'Completed','cancelled':'Cancelled'};
    return (english ? en[s] : bg[s]) ?? s;
  }

  void _showRepairDetails(Repair repair) async {
    final token = await auth.token;
    if (token == null || !mounted) return;
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => FutureBuilder<Repair>(future: api.getRepair(token, repair.id), builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
      if (snap.hasError) return SizedBox(height: 220, child: Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('${snap.error}'))));
      final r = snap.data!;
      final isStaff = signedInUser!.roles.any((role) => ['administrator','pcwork_staff','shop_manager','editor'].contains(role));
      return SizedBox(height: MediaQuery.of(ctx).size.height * .78, child: ListView(padding: const EdgeInsets.all(22), children: [Text(r.number.isEmpty ? 'PCW-${r.id}' : r.number, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Wrap(spacing: 8, children: [Chip(label: Text(_statusLabel(r.status))), if (isStaff) Chip(avatar: const Icon(Icons.flag_outlined, size: 16), label: Text(_priorityLabel(r.priority)))]), _detailRow(tr('Устройство','Device'), '${r.device} ${r.model}'), _detailRow(tr('Сервизен обект','Service location'), r.location), _detailRow(tr('Проблем','Reported issue'), r.problem), if (r.dueAt.isNotEmpty) _detailRow(tr('Краен срок','Due date'), _formatDate(r.dueAt)), if (isStaff && r.technicianName.isNotEmpty) _detailRow(tr('Отговорен техник','Assigned technician'), r.technicianName), OutlinedButton.icon(onPressed: () => _shareRepair(r), icon: const Icon(Icons.share_outlined), label: Text(tr('Сподели информация за ремонта','Share repair information'))), OutlinedButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: r.number.isEmpty ? 'PCW-${r.id}' : r.number)); if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Номерът е копиран.','Repair number copied.')))); }, icon: const Icon(Icons.copy), label: Text(tr('Копирай номер','Copy repair number'))), OutlinedButton.icon(onPressed: () { Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => RepairProtocolScreen(repairNumber: r.number.isEmpty ? 'PCW-${r.id}' : r.number, device: '${r.device} ${r.model}'.trim(), location: r.location, problem: r.problem, status: _statusLabel(r.status), createdAt: r.createdAt, baseUrl: apiUrl, token: token, repairId: r.id, canEmail: isStaff))); }, icon: const Icon(Icons.qr_code_2), label: Text(tr('Сервизен протокол · QR · PDF','Service protocol · QR · PDF'))),
        OutlinedButton.icon(onPressed: () async { Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => RepairEvidenceScreen(baseUrl: apiUrl, token: token, repairId: r.id, repairNumber: r.number, isStaff: signedInUser!.roles.any((role) => ['administrator','pcwork_staff','shop_manager'].contains(role))))); }, icon: const Icon(Icons.photo_camera_back_outlined), label: Text(tr('Снимки и подписи','Photos & signatures'))), OutlinedButton.icon(onPressed: () { Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => RepairDocumentsScreen(baseUrl: apiUrl, token: token, repairId: r.id, repairNumber: r.number))); }, icon: const Icon(Icons.folder_open_outlined), label: Text(tr('Преглед на документите','View repair documents'))), const Divider(height: 28), Text(tr('Етап на ремонта','Repair progress'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), _repairProgress(r.status), const Divider(height: 24), Text(tr('История на ремонта','Repair history'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), if (r.history.isEmpty) Text(tr('Няма записана история.','No history recorded yet.')), ...r.history.map((h) => ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.circle, size: 10, color: cyan), title: Text(_statusLabel(h.status)), subtitle: Text([if (signedInUser!.roles.any((role) => ['administrator','pcwork_staff','shop_manager','editor'].contains(role)) && h.note.isNotEmpty) h.note, h.createdAt].where((x)=>x.isNotEmpty).join(' · '))))]));
    }));
  }

  Widget _repairProgress(String status) {
    const steps = ['received','diagnostics','waiting_approval','in_repair','ready','completed'];
    final index = steps.indexOf(status);
    if (status == 'cancelled') return Chip(avatar: const Icon(Icons.cancel_outlined), label: Text(_statusLabel(status)));
    return Column(children: steps.asMap().entries.map((entry) {
      final active = index >= entry.key;
      return Row(children: [Icon(active ? Icons.check_circle : Icons.radio_button_unchecked, color: active ? cyan : Colors.white30, size: 19), const SizedBox(width: 10), Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text(_statusLabel(entry.value), style: TextStyle(color: active ? Colors.white : Colors.white54, fontWeight: entry.key == index ? FontWeight.bold : FontWeight.normal)))), if (entry.key == index) Chip(label: Text(tr('Текущ етап','Current')))]);
    }).toList());
  }

  Widget _detailRow(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 125, child: Text(label, style: const TextStyle(color: Colors.white60))), Expanded(child: Text(value.isEmpty ? '—' : value))]));

  Widget _booking() => ListView(padding: const EdgeInsets.all(20), children: [
    Text(tr('Записване на час за сервиз', 'Book a service appointment'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)), const SizedBox(height: 10),
    Text(tr('Изберете обект и отворете формата за резервации на PCWork.', 'Choose a location and open the PCWork booking form.')),
    const SizedBox(height: 16), FilledButton.icon(onPressed: _showLocations, icon: const Icon(Icons.location_on_outlined), label: Text(tr('Избери сервизен обект', 'Choose a location'))),
    const SizedBox(height: 10), OutlinedButton.icon(onPressed: _openBookly, icon: const Icon(Icons.open_in_browser), label: Text(tr('Отвори онлайн резервации', 'Open online booking'))),
    const SizedBox(height: 12), Text(tr('Резервацията използва Bookly страницата на сайта. Директно записване в приложението ще бъде добавено след потвърждаване на наличния Bookly API модул.', 'Booking currently uses the website’s Bookly page. Native in-app booking will follow after confirming the installed Bookly API module.')),
  ]);

  Widget _profile() => ListView(padding: const EdgeInsets.all(20), children: [
    CircleAvatar(radius: 38, child: Icon(signedInUser == null ? Icons.person_outline : Icons.verified_user, size: 40, color: cyan)),
    const SizedBox(height: 14),
    Text(signedInUser?.name ?? tr('Вашият PCWork профил', 'Your PCWork account'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
    const SizedBox(height: 6),
    Text(signedInUser?.email ?? tr('Влезте или създайте профил, за да виждате ремонтите си.', 'Sign in or create an account to access your repairs.')),
    if (signedInUser != null) ...[
      const SizedBox(height: 12), Card(child: ListTile(leading: const Icon(Icons.badge_outlined, color: cyan), title: Text(tr('Тип профил', 'Account type')), subtitle: Text(signedInUser!.roles.join(', ')))),
      const SizedBox(height: 12), FilledButton.icon(onPressed: _refreshProfile, icon: const Icon(Icons.refresh), label: Text(tr('Обнови профила', 'Refresh profile'))),
      OutlinedButton.icon(onPressed: _logout, icon: const Icon(Icons.logout), label: Text(tr('Изход', 'Sign out'))),
    ] else ...[
      const SizedBox(height: 18),
      FilledButton.icon(onPressed: authBusy ? null : () => _showAuthDialog(register: false), icon: const Icon(Icons.login), label: Text(tr('Вход с имейл', 'Sign in with email'))),
      OutlinedButton.icon(onPressed: authBusy ? null : () => _showAuthDialog(register: true), icon: const Icon(Icons.person_add_alt_1), label: Text(tr('Създай профил', 'Create account'))),
      const SizedBox(height: 10),
      Text(tr('Телефон/SMS входът ще бъде включен след избор и конфигуриране на SMS доставчик. Не въвеждайте SMS кодове в тази версия.', 'Phone/SMS sign-in will be enabled after selecting and configuring an SMS provider. Do not enter SMS codes in this version.'), style: const TextStyle(color: Colors.white60)),
    ],
    if (signedInUser != null && signedInUser!.roles.any((r) => ['administrator', 'pcwork_staff', 'shop_manager', 'editor'].contains(r))) ...[
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: _openStaffDashboard, icon: const Icon(Icons.dashboard_outlined), label: Text(tr('Отвори служебното табло', 'Open staff dashboard'))),
      const SizedBox(height: 8),
      FilledButton.icon(onPressed: _showIntakeForm, icon: const Icon(Icons.add_box_outlined), label: Text(tr('Приеми ново устройство', 'Register device intake'))),
      const SizedBox(height: 8),
      Text(tr('Достъпът за запис се проверява допълнително от WordPress според служебните права и сервизния обект.', 'WordPress separately verifies staff permissions and location access.'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
    ],
    const SizedBox(height: 18), OutlinedButton.icon(onPressed: _showSettings, icon: const Icon(Icons.settings), label: Text(tr('Настройки на приложението', 'App settings'))),
  ]);

  Future<void> _openStaffDashboard() async {
    final token = await auth.token;
    if (token == null || !mounted) { _message(tr('Влезте със служебен профил.','Sign in with a staff account.')); return; }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => StaffDashboardScreen(api: api, token: token, english: english)));
  }

  void _showIntakeForm() async {
    final token = await auth.token;
    if (token == null) { _message(tr('Влезте със служебен профил.', 'Sign in with a staff account.')); return; }
    List<ServiceLocation> options;
    try { options = await api.getLocations(); }
    catch (e) { _message('${tr('Неуспешно зареждане на обектите:', 'Could not load locations:')} $e'); return; }
    if (!mounted) return;
    final customerEmail = TextEditingController();
    final customerName = TextEditingController();
    final customerPhone = TextEditingController();
    final deviceType = TextEditingController(text: 'Лаптоп');
    final model = TextEditingController();
    final serial = TextEditingController();
    final problem = TextEditingController();
    final condition = TextEditingController();
    final accessories = TextEditingController();
    final notes = TextEditingController();
    ServiceLocation? selected = options.isNotEmpty ? options.first : null;
    bool saving = false;
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
      Widget field(TextEditingController c, String label, {int lines = 1, TextInputType? type}) => Padding(padding: const EdgeInsets.only(bottom: 11), child: TextField(controller: c, maxLines: lines, keyboardType: type, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())));
      return Padding(padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.of(ctx).viewInsets.bottom + 18), child: SizedBox(height: MediaQuery.of(ctx).size.height * .82, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(tr('Прием на устройство', 'Device intake'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold))), IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close))]),
        Text(tr('Създава се ремонт с уникален номер и начален статус „Приет“.', 'Creates a repair with a unique number and initial “Received” status.'), style: const TextStyle(color: Colors.white60)),
        const SizedBox(height: 12),
        Expanded(child: ListView(children: [
          DropdownButtonFormField<ServiceLocation>(value: selected, isExpanded: true, decoration: InputDecoration(labelText: tr('Сервизен обект', 'Service location'), border: const OutlineInputBorder()), items: options.map((l) => DropdownMenuItem(value: l, child: Text(l.name))).toList(), onChanged: (v) => setSheet(() => selected = v)),
          const SizedBox(height: 12), field(customerEmail, 'Имейл на клиент*', type: TextInputType.emailAddress),
          field(customerName, 'Име на клиент'), field(customerPhone, 'Телефон', type: TextInputType.phone),
          const Divider(height: 24), field(deviceType, 'Тип устройство*'), field(model, 'Марка и модел*'), field(serial, 'Сериен номер'),
          field(problem, 'Описание на проблема*', lines: 3), field(condition, 'Външно състояние', lines: 3),
          field(accessories, 'Комплектовка / аксесоари', lines: 2), field(notes, 'Вътрешни бележки', lines: 2),
        ])),
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: saving ? null : () async {
          if (selected == null || selected!.code.isEmpty || customerEmail.text.trim().isEmpty || deviceType.text.trim().isEmpty || model.text.trim().isEmpty || problem.text.trim().isEmpty) { _message(tr('Изберете обект с код и попълнете задължителните полета със звезда.', 'Choose a coded location and complete all required fields.')); return; }
          setSheet(() => saving = true);
          try {
            final created = await api.createRepair(token, {
              'customer_email': customerEmail.text.trim(), 'customer_name': customerName.text.trim(), 'customer_phone': customerPhone.text.trim(),
              'location_code': selected!.code, 'location_name': selected!.name,
              'device_type': deviceType.text.trim(), 'device_model': model.text.trim(), 'serial_number': serial.text.trim(),
              'problem_description': problem.text.trim(), 'external_condition': condition.text.trim(), 'accessories': accessories.text.trim(), 'intake_notes': notes.text.trim(),
            });
            if (ctx.mounted) Navigator.pop(ctx);
            setState(() => repairsFuture = _loadRepairsFuture());
            _message('${tr('Ремонтът е регистриран:', 'Repair created:')} ${created['repair_number'] ?? ''}');
          } catch (e) { _message('${tr('Грешка при приемане:', 'Intake failed:')} $e'); setSheet(() => saving = false); }
        }, icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save), label: Text(saving ? tr('Записване…', 'Saving…') : tr('Създай сервизен протокол', 'Create repair record')))),
      ])));
    }));
  }

  Future<void> _refreshProfile() async {
    setState(() => authBusy = true);
    try { final u = await auth.me(); if (mounted) setState(() { signedInUser = u; repairsFuture = _loadRepairsFuture(); }); }
    catch (e) { _message('$e'); if (mounted) setState(() => signedInUser = null); }
    finally { if (mounted) setState(() => authBusy = false); }
  }

  Future<void> _logout() async { final bearer = await auth.token; if (bearer != null) await push.unregister(bearer); await auth.logout(); if (mounted) setState(() { signedInUser = null; repairsFuture = null; }); }

  void _showAuthDialog({required bool register}) {
    final name = TextEditingController(); final email = TextEditingController(); final password = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(register ? tr('Регистрация', 'Create account') : tr('Вход', 'Sign in')),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (register) ...[TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr('Име', 'Name'))), const SizedBox(height: 10)],
        TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
        const SizedBox(height: 10), TextField(controller: password, obscureText: true, decoration: InputDecoration(labelText: tr('Парола (минимум 10 символа)', 'Password (at least 10 characters)'))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Отказ', 'Cancel'))), FilledButton(onPressed: () async {
        if (register && password.text.length < 10) { _message(tr('Паролата трябва да е поне 10 символа.', 'Password must be at least 10 characters.')); return; }
        Navigator.pop(ctx); setState(() => authBusy = true);
        try { final u = register ? await auth.register(name.text.trim(), email.text.trim(), password.text) : await auth.login(email.text.trim(), password.text); if (mounted) { setState(() { signedInUser = u; repairsFuture = _loadRepairsFuture(); }); await _enablePush(); _message(tr('Успешен вход в PCWork.', 'Successfully signed in to PCWork.')); } }
        catch (e) { _message('$e'); }
        finally { if (mounted) setState(() => authBusy = false); }
      }, child: Text(register ? tr('Регистрирай', 'Register') : tr('Вход', 'Sign in')))],
    ));
  }

  Future<void> _openBookly() async {
    try {
      final uri = await api.getBookingUrl();
      if (uri == null) { _message(tr('Bookly не е конфигуриран. Проверете настройките в WordPress → PCWork настройки → Bookly.', 'Bookly is not configured. Check WordPress → PCWork Settings → Bookly.')); return; }
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) _message(tr('Страницата за резервации не може да бъде отворена.', 'Could not open the booking page.'));
    } catch (e) { _message('$e'); }
  }

  void _showLocations() {
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) {
      final future = api.getLocations();
      return SizedBox(height: MediaQuery.of(ctx).size.height * .65, child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Сервизни обекти', 'Service locations'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Expanded(child: FutureBuilder<List<ServiceLocation>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return Center(child: Text('${tr('Грешка при зареждане:', 'Could not load locations:')} ${snapshot.error}'));
            final rows = snapshot.data ?? [];
            if (rows.isEmpty) return Center(child: Text(tr('Няма върнати обекти от сървъра.', 'No locations were returned by the server.')));
            return ListView.builder(itemCount: rows.length, itemBuilder: (_, i) {
              final item = rows[i];
              return Card(child: ListTile(leading: const Icon(Icons.location_on_outlined, color: cyan), title: Text(item.name), subtitle: Text([item.address, item.phone].where((v) => v.isNotEmpty).join('\n')), trailing: const Icon(Icons.chevron_right)));
            });
          },
        )),
      ])));
    });
  }

  void _showSettings() {
    final controller = TextEditingController(text: apiUrl);
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => Padding(padding: EdgeInsets.fromLTRB(22, 22, 22, MediaQuery.of(ctx).viewInsets.bottom + 22), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Настройки на приложението', 'Application settings'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 14),
      TextField(controller: controller, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'WordPress API URL', hintText: 'https://pcwork-bg.com', border: OutlineInputBorder())),
      const SizedBox(height: 12), SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('Преглед като служител', 'Staff preview mode')), subtitle: Text(tr('Само визуален режим. Не предоставя служебни права.', 'Visual preview only. Does not grant staff permissions.')), value: staffPreview, onChanged: (v) { setState(() => staffPreview = v); _savePreference('pcwork_staff_preview', v); }),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('Език: Български / English', 'Language: Bulgarian / English')), value: english, onChanged: (v) { setState(() => english = v); _savePreference('pcwork_english', v); }),
      const SizedBox(height: 10), SizedBox(width: double.infinity, child: FilledButton(onPressed: () async { try { await _saveApiUrl(controller.text); if (ctx.mounted) Navigator.pop(ctx); await _checkApi(); } catch (e) { _message('$e'); } }, child: Text(tr('Запази и провери връзката', 'Save and test connection')))),
    ])));
  }

  void _showSignInInfo() => showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(tr('Вход и регистрация', 'Sign in and registration')), content: Text(tr('Екраните за вход с имейл/парола и телефон/SMS са следващият етап. Не въвеждайте парола тук, докато удостоверяването не бъде свързано със защитения API.', 'Email/password and phone/SMS sign-in screens are the next stage. Do not enter credentials here until authentication is connected to the secure API.')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]));
  void _message(String value) { if (!mounted) return; _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(value))); }
}
