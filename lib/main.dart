import 'dart:async';

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
import 'screens/chatway_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/shop_screen.dart';

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
  final Set<int> _visitedTabs = <int>{0};
  String apiUrl = defaultApi;
  bool apiReady = false;
  bool checkingApi = false;
  String? apiMessage;
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
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadSettings();
    if (!mounted) return;
    // Do not make the server health check a startup dependency.
    // Restore the account immediately; the status check runs independently.
    unawaited(_checkApi(silent: true));
    await _restoreSession();
  }

  Future<void> _restoreSession() async {
    try { final t = await auth.token; if (t != null) { final u = await auth.me(); if (mounted) setState(() { signedInUser = u; });
      unawaited(_enablePush(t)); } } catch (_) { if (mounted) setState(() => signedInUser = null); }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      apiUrl = prefs.getString('pcwork_api_url') ?? defaultApi;
      english = prefs.getBool('pcwork_english') ?? false;
      staffPreview = prefs.getBool('pcwork_staff_preview') ?? false;
    });
  }

  Future<void> _savePreference(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
  }

  Future<void> _saveApiUrl(String value) async {
    final cleaned = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(cleaned);
    if (uri == null || uri.host.isEmpty || uri.scheme != 'https') {
      throw Exception(tr('Въведете валиден адрес, започващ с https://', 'Enter a valid https:// URL.'));
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pcwork_api_url', cleaned);
    setState(() { apiUrl = cleaned; apiReady = false; });
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

  Future<void> _enablePush([String? knownToken]) async {
    final bearer = knownToken ?? await auth.token;
    if (bearer == null || bearer.isEmpty) return;
    await push.register(bearer, onForeground: (title, body) {
      if (!mounted) return;
      _messengerKey.currentState?.showSnackBar(SnackBar(content: Text('$title — $body')));
      if (mounted) setState(() => repairsFuture = _loadRepairsFuture());
    }, onOpened: () {
      if (mounted) _selectTab(1);
    });
  }

  void _selectTab(int index) {
    if (index < 0 || index > 5) return;
    setState(() {
      tab = index;
      _visitedTabs.add(index);
      if (index == 1 && repairsFuture == null && signedInUser != null) {
        repairsFuture = _loadRepairsFuture();
      }
    });
  }

  Widget _tabContent(int index) {
    switch (index) {
      case 0: return _home();
      case 1: return _repairs();
      case 2: return ShopScreen(api: api, tokenProvider: () => auth.token, english: english);
      case 3: return ChatwayScreen(api: api, tokenProvider: () => auth.token, sessionKey: signedInUser?.id ?? 0);
      case 4: return _booking();
      case 5: return _profile();
      default: return const SizedBox.shrink();
    }
  }

  @override
  void dispose() { repairSearch.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final labels = [tr('Начало', 'Home'), tr('Ремонти', 'Repairs'), tr('Магазин', 'Shop'), tr('Чат', 'Chat'), tr('Записване', 'Booking'), tr('Профил', 'Profile')];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      title: 'PCWork',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'NotoSans',
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: cyan, brightness: Brightness.dark).copyWith(
          primary: cyan, secondary: const Color(0xFF9B7BFF), surface: const Color(0xFF151F2E),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A101A),
        cardColor: const Color(0xFF151F2E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A101A), foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent, elevation: 0, centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF151F2E), elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: Color(0xFF26364A))),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: const Color(0xFF111B29),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF2A3A50))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF2A3A50))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: cyan, width: 1.5)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF0E1724), indicatorColor: cyan.withValues(alpha: .16),
          elevation: 0, labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 11, fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? cyan : const Color(0xFF8796AA),
          )),
        ),
        filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
          backgroundColor: cyan, foregroundColor: const Color(0xFF061319),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        )),
      ),
      home: Scaffold(
        appBar: AppBar(
          title: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 40, padding: const EdgeInsets.all(2), decoration: BoxDecoration(color: const Color(0xFF111B29), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF21D4D8).withValues(alpha: .28))), child: Image.asset('assets/images/LogoPCwork.png', width: 36, height: 36, fit: BoxFit.contain)),
            const SizedBox(width: 10), const Text('PCWork', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .2)),
            const SizedBox(width: 9), Container(width: 5, height: 5, decoration: const BoxDecoration(color: cyan, shape: BoxShape.circle)),
            const SizedBox(width: 8), Flexible(child: Text(labels[tab], overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0xFF93A4B8), fontWeight: FontWeight.w500))),
          ]),
          actions: [
            IconButton(tooltip: tr('Език', 'Language'), onPressed: () { setState(() => english = !english); _savePreference('pcwork_english', english); }, icon: const Icon(Icons.language_rounded)),
            IconButton(tooltip: tr('Настройки', 'Settings'), onPressed: _showSettings, icon: const Icon(Icons.tune_rounded)),
          ],
        ),
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0D1826), Color(0xFF0A101A), Color(0xFF0B111B)])),
          child: IndexedStack(index: tab, children: List<Widget>.generate(6, (index) => _visitedTabs.contains(index) ? _tabContent(index) : const SizedBox.shrink())),
        ),
        bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: _selectTab, destinations: [
          NavigationDestination(icon: const Icon(Icons.grid_view_rounded), selectedIcon: const Icon(Icons.grid_view_rounded), label: labels[0]),
          NavigationDestination(icon: const Icon(Icons.handyman_outlined), selectedIcon: const Icon(Icons.handyman_rounded), label: labels[1]),
          NavigationDestination(icon: const Icon(Icons.storefront_outlined), selectedIcon: const Icon(Icons.storefront_rounded), label: labels[2]),
          NavigationDestination(icon: const Icon(Icons.forum_outlined), selectedIcon: const Icon(Icons.forum_rounded), label: labels[3]),
          NavigationDestination(icon: const Icon(Icons.calendar_month_outlined), selectedIcon: const Icon(Icons.calendar_month_rounded), label: labels[4]),
          NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: labels[5]),
        ]),
      ),
    );
  }

  Widget _home() => ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 28), children: [
    Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF123B4A), Color(0xFF17283D), Color(0xFF24233E)]),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF2B7180).withValues(alpha: .55)),
        boxShadow: [BoxShadow(color: cyan.withValues(alpha: .10), blurRadius: 30, spreadRadius: -8, offset: const Offset(0, 12))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 52, height: 52, padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(16)), child: Image.asset('assets/images/LogoPCwork.png', fit: BoxFit.contain)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PCWORK SERVICE', style: TextStyle(color: cyan.withValues(alpha: .95), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.8)),
            Text(tr('Технологиите. В сигурни ръце.', 'Technology. In safe hands.'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ])),
          const Icon(Icons.auto_awesome_rounded, color: Color(0xFFB49BFF), size: 23),
        ]),
        const SizedBox(height: 23),
        Text(tr('Сервиз от ново поколение.', 'Next-generation device care.'), style: const TextStyle(fontSize: 25, height: 1.16, fontWeight: FontWeight.w800, letterSpacing: -.5)),
        const SizedBox(height: 9),
        Text(tr('Компютри • Лаптопи • PlayStation', 'Computers • Laptops • PlayStation'), style: const TextStyle(color: Color(0xFFC3D1E0), fontSize: 13)),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => _selectTab(4), icon: const Icon(Icons.calendar_month_rounded), label: Text(tr('Запази час за сервиз', 'Book a service appointment')))),
      ]),
    ),
    const SizedBox(height: 22),
    if (signedInUser == null) _homeSignInCard() else _homeAccountDashboard(),
    const SizedBox(height: 8),
    Row(children: [
      Expanded(child: _quickCard(Icons.qr_code_2_rounded, tr('Моите ремонти', 'My repairs'), () => _selectTab(1))),
      const SizedBox(width: 12),
      Expanded(child: _quickCard(Icons.support_agent_rounded, tr('Онлайн поддръжка', 'Live support'), () => _selectTab(3))),
    ]),
    const SizedBox(height: 21),
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(tr('Състояние на услугите', 'Service status'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: const Color(0xFF21D4D8).withValues(alpha: .10), borderRadius: BorderRadius.circular(30)), child: Text(tr('LIVE', 'LIVE'), style: const TextStyle(color: cyan, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1))),
    ]),
    const SizedBox(height: 7),
    Card(child: Padding(padding: const EdgeInsets.all(15), child: Row(children: [
      Container(width: 42, height: 42, decoration: BoxDecoration(color: (apiReady ? Colors.greenAccent : Colors.orangeAccent).withValues(alpha: .12), borderRadius: BorderRadius.circular(14)), child: Icon(apiReady ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, color: apiReady ? Colors.greenAccent : Colors.orangeAccent)),
      const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr('PCWork сървър', 'PCWork server'), style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text(apiMessage ?? tr('Проверка на връзката…', 'Checking connection…'), style: const TextStyle(color: Color(0xFF93A4B8), fontSize: 12))])),
      IconButton(onPressed: _checkApi, icon: const Icon(Icons.refresh_rounded, color: cyan)),
    ]))),
    const SizedBox(height: 16),
    Text(tr('Бърз достъп', 'Quick access'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
    const SizedBox(height: 6),
    _infoTile(Icons.verified_user_outlined, tr('Гаранция и условия на сервиза', 'Warranty and service terms')),
    _infoTile(Icons.location_on_outlined, tr('Сервизни обекти', 'Service locations')),
  ]);

  Widget _quickCard(IconData icon, String label, VoidCallback onTap) => Card(child: InkWell(borderRadius: BorderRadius.circular(22), onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18), child: Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: cyan.withValues(alpha: .11), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: cyan, size: 23)), const SizedBox(width: 10), Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))), const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFF71849A))]))));
  Widget _infoTile(IconData icon, String label) => Card(child: ListTile(leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: cyan.withValues(alpha: .10), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: cyan, size: 20)), title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)), trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF71849A))));

  Widget _repairs() {
    if (signedInUser == null) { return ListView(padding: const EdgeInsets.all(20), children: [
      Text(tr('Проследяване на ремонт', 'Repair tracking'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12), Text(tr('Влезте в профила си, за да видите ремонтите, историята и актуалния им статус.', 'Sign in to see your repairs, history and current status.')),
      const SizedBox(height: 16), FilledButton.icon(onPressed: () => _selectTab(5), icon: const Icon(Icons.login), label: Text(tr('Вход / Регистрация', 'Sign in / Register'))),
    ]); }
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
          DropdownButtonFormField<String>(initialValue: repairStatusFilter, decoration: InputDecoration(labelText: tr('Филтър по статус','Filter by status'), border: const OutlineInputBorder()), items: [DropdownMenuItem(value:'all', child:Text(tr('Всички статуси','All statuses'))), ...['received','diagnostics','waiting_approval','in_repair','ready','completed','cancelled'].map((v)=>DropdownMenuItem(value:v,child:Text(_statusLabel(v))))], onChanged:(v)=>setState(()=>repairStatusFilter=v ?? 'all')),
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


  Future<void> _changeRepairStatus(Repair repair, BuildContext sheetContext) async {
    final noteController = TextEditingController();
    const statuses = ['received', 'diagnostics', 'waiting_approval', 'in_repair', 'ready', 'completed', 'cancelled'];
    var selected = repair.status;
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(tr('Промяна на статуса', 'Update repair status')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selected,
                decoration: InputDecoration(labelText: tr('Нов статус', 'New status')),
                items: statuses.map((status) => DropdownMenuItem(
                  value: status,
                  child: Text(_statusLabel(status)),
                )).toList(),
                onChanged: (value) {
                  if (value != null) refresh(() => selected = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: tr('Бележка към историята (по желание)', 'History note (optional)'),
                  hintText: tr('Напр. извършена диагностика…', 'E.g. diagnostics completed…'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('Отказ', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(tr('Запази', 'Save'))),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) {
      noteController.dispose();
      return;
    }
    final token = await auth.token;
    if (token == null) {
      noteController.dispose();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Сесията е изтекла. Влезте отново.', 'Session expired. Please sign in again.'))));
      return;
    }
    try {
      await api.updateRepairStatus(token, repair.id, selected, note: noteController.text.trim());
      noteController.dispose();
      if (!mounted || !sheetContext.mounted) return;
      Navigator.of(sheetContext).pop();
      setState(() => repairsFuture = _loadRepairsFuture());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Статусът на ремонта е обновен.', 'Repair status updated.'))));
    } catch (e) {
      noteController.dispose();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Неуспешна промяна:', 'Update failed:')} $e')));
    }
  }

  void _showRepairDetails(Repair repair) async {
    final token = await auth.token;
    if (token == null || !mounted) return;
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => FutureBuilder<Repair>(future: api.getRepair(token, repair.id), builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
      if (snap.hasError) return SizedBox(height: 220, child: Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('${snap.error}'))));
      final r = snap.data!;
      final isStaff = signedInUser!.roles.any((role) => ['administrator','pcwork_staff','shop_manager','editor'].contains(role));
      return SizedBox(height: MediaQuery.of(ctx).size.height * .78, child: ListView(padding: const EdgeInsets.all(22), children: [Text(r.number.isEmpty ? 'PCW-${r.id}' : r.number, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Wrap(spacing: 8, children: [Chip(label: Text(_statusLabel(r.status))), if (isStaff) Chip(avatar: const Icon(Icons.flag_outlined, size: 16), label: Text(_priorityLabel(r.priority)))]), _detailRow(tr('Устройство','Device'), '${r.device} ${r.model}'), _detailRow(tr('Сервизен обект','Service location'), r.location), _detailRow(tr('Проблем','Reported issue'), r.problem), if (r.dueAt.isNotEmpty) _detailRow(tr('Краен срок','Due date'), _formatDate(r.dueAt)), if (isStaff && r.technicianName.isNotEmpty) _detailRow(tr('Отговорен техник','Assigned technician'), r.technicianName), if (isStaff && !['completed','cancelled'].contains(r.status)) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => _changeRepairStatus(r, ctx), icon: const Icon(Icons.sync_alt_rounded), label: Text(tr('Промени статуса на ремонта','Update repair status'))))), OutlinedButton.icon(onPressed: () => _shareRepair(r), icon: const Icon(Icons.share_outlined), label: Text(tr('Сподели информация за ремонта','Share repair information'))), OutlinedButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: r.number.isEmpty ? 'PCW-${r.id}' : r.number)); if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Номерът е копиран.','Repair number copied.')))); }, icon: const Icon(Icons.copy), label: Text(tr('Копирай номер','Copy repair number'))), OutlinedButton.icon(onPressed: () { Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => RepairProtocolScreen(repairNumber: r.number.isEmpty ? 'PCW-${r.id}' : r.number, device: '${r.device} ${r.model}'.trim(), location: r.location, problem: r.problem, status: _statusLabel(r.status), createdAt: r.createdAt, baseUrl: apiUrl, token: token, repairId: r.id, canEmail: isStaff))); }, icon: const Icon(Icons.qr_code_2), label: Text(tr('Сервизен протокол · QR · PDF','Service protocol · QR · PDF'))),
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
      FilledButton.icon(onPressed: authBusy ? null : () => _openAuthScreen(register: false), icon: const Icon(Icons.login), label: Text(tr('Вход с имейл', 'Sign in with email'))),
      OutlinedButton.icon(onPressed: authBusy ? null : () => _openAuthScreen(register: true), icon: const Icon(Icons.person_add_alt_1), label: Text(tr('Създай профил', 'Create account'))),
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
          DropdownButtonFormField<ServiceLocation>(initialValue: selected, isExpanded: true, decoration: InputDecoration(labelText: tr('Сервизен обект', 'Service location'), border: const OutlineInputBorder()), items: options.map((l) => DropdownMenuItem(value: l, child: Text(l.name))).toList(), onChanged: (v) => setSheet(() => selected = v)),
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

  Future<void> _openAuthScreen({required bool register}) async {
    final user = await Navigator.of(context).push<AuthUser>(
      MaterialPageRoute(
        builder: (_) => AuthScreen(
          baseUrl: apiUrl,
          english: english,
          initialRegister: register,
        ),
      ),
    );
    if (!mounted || user == null) return;
    final bearer = await auth.token;
    setState(() {
      signedInUser = user;
      repairsFuture = _loadRepairsFuture();
      tab = 5;
      _visitedTabs.add(5);
    });
    if (bearer != null && bearer.isNotEmpty) await _enablePush(bearer);
    if (mounted) {
      _message(tr('Успешен вход в PCWork.', 'Successfully signed in to PCWork.'));
    }
  }

  Widget _homeSignInCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: cyan.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.lock_open_rounded, color: cyan),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Влез в своя профил', 'Sign in to your account'),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(
                      tr('Проследявай ремонтите и поръчките си.', 'Track your repairs and orders.'),
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: tr('Вход', 'Sign in'),
                onPressed: () => _openAuthScreen(register: false),
                icon: const Icon(Icons.arrow_forward_rounded, color: cyan),
              ),
            ],
          ),
        ),
      );

  Widget _homeAccountDashboard() {
    final future = repairsFuture;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dashboard_customize_outlined, color: cyan),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    tr('Здравей, ${signedInUser?.name ?? ''}', 'Welcome, ${signedInUser?.name ?? ''}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: () => _selectTab(1),
                  child: Text(tr('Ремонти', 'Repairs')),
                ),
              ],
            ),
            if (future == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => _selectTab(1), icon: const Icon(Icons.build_outlined), label: Text(tr('Зареди моите ремонти', 'Load my repairs')))),
              )
            else FutureBuilder<List<Repair>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: LinearProgressIndicator(minHeight: 3),
                  );
                }
                if (snapshot.hasError) {
                  return Row(
                    children: [
                      const Expanded(child: Text('Неуспешно зареждане на ремонтите.', style: TextStyle(color: Colors.white60, fontSize: 12))),
                      IconButton(
                        tooltip: tr('Опитай отново', 'Retry'),
                        onPressed: () => setState(() => repairsFuture = _loadRepairsFuture()),
                        icon: const Icon(Icons.refresh, color: cyan),
                      ),
                    ],
                  );
                }
                final rows = snapshot.data ?? const <Repair>[];
                final active = rows.where((r) => !['completed', 'cancelled'].contains(r.status)).length;
                final ready = rows.where((r) => r.status == 'ready').length;
                return Row(
                  children: [
                    Expanded(child: _repairMetric(tr('Всички', 'Total'), rows.length)),
                    Expanded(child: _repairMetric(tr('Активни', 'Active'), active)),
                    Expanded(child: _repairMetric(tr('Готови', 'Ready'), ready)),
                  ],
                );
              },
            ),
            if (signedInUser?.roles.any((role) => ['administrator', 'pcwork_staff', 'shop_manager', 'editor'].contains(role)) ?? false)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openStaffDashboard,
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  label: Text(tr('Служебно табло', 'Staff dashboard')),
                ),
              ),
          ],
        ),
      ),
    );
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

  void _message(String value) { if (!mounted) return; _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(value))); }
}
