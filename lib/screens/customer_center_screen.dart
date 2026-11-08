import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class CustomerCenterScreen extends StatefulWidget {
  const CustomerCenterScreen({super.key, required this.api, required this.token, required this.user, required this.english, required this.onRepairs, required this.onOrders, required this.onChat, required this.onBooking, required this.onNotifications, required this.onProfile});
  final ApiService api;
  final String token;
  final AuthUser user;
  final bool english;
  final VoidCallback onRepairs, onOrders, onChat, onBooking, onNotifications, onProfile;
  @override
  State<CustomerCenterScreen> createState() => _CustomerCenterScreenState();
}

class _CustomerCenterScreenState extends State<CustomerCenterScreen> {
  late Future<_CenterData> _future;
  String tr(String bg, String en) => widget.english ? en : bg;
  @override
  void initState() { super.initState(); _future = _load(); }
  Future<_CenterData> _load() async {
    final values = await Future.wait<dynamic>([
      widget.api.getRepairs(widget.token),
      widget.api.getShopOrders(widget.token),
    ]);
    final repairs = values[0] as List<Repair>;
    final orders = values[1] as List<Map<String, dynamic>>;
    return _CenterData(repairs, orders);
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Клиентски център', 'Customer center')), actions: [IconButton(tooltip: tr('Обнови', 'Refresh'), onPressed: () => setState(() => _future = _load()), icon: const Icon(Icons.refresh_rounded))]),
    body: FutureBuilder<_CenterData>(future: _future, builder: (context, snapshot) {
      final data = snapshot.data;
      final active = data?.repairs.where((r) => !['completed','cancelled'].contains(r.status)).length ?? 0;
      final ready = data?.repairs.where((r) => r.status == 'ready').length ?? 0;
      return RefreshIndicator(onRefresh: () async { final next = _load(); setState(() => _future = next); await next; }, child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
        Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF123B4A), Color(0xFF24233E)]), borderRadius: BorderRadius.circular(22)), child: Row(children: [const CircleAvatar(radius: 27, backgroundColor: Color(0x3321D4D8), child: Icon(Icons.person_rounded, color: Color(0xFF21D4D8), size: 30)), const SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr('Здравейте,', 'Welcome,'), style: const TextStyle(color: Colors.white70)), Text(widget.user.name.isEmpty ? widget.user.email : widget.user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 19)), Text(widget.user.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12))]))])),
        const SizedBox(height: 14),
        if (snapshot.connectionState == ConnectionState.waiting && data == null) const LinearProgressIndicator(),
        if (snapshot.hasError) Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(tr('Не успяхме да заредим обобщението. Издърпайте надолу за нов опит.', 'We could not load your overview. Pull down to retry.'), style: const TextStyle(color: Colors.orangeAccent)))),
        Row(children: [Expanded(child: _metric(tr('Ремонти','Repairs'), '${data?.repairs.length ?? '—'}', Icons.build_circle_outlined)), const SizedBox(width: 6), Expanded(child: _metric(tr('Активни','Active'), '$active', Icons.autorenew_rounded)), const SizedBox(width: 6), Expanded(child: _metric(tr('Готови','Ready'), '$ready', Icons.task_alt_rounded)), const SizedBox(width: 6), Expanded(child: _metric(tr('Поръчки','Orders'), '${data?.orders.length ?? '—'}', Icons.shopping_bag_outlined))]),
        const SizedBox(height: 18), Text(tr('Моите услуги','My services'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        _action(Icons.handyman_outlined, tr('Моите ремонти','My repairs'), tr('Статус, история и документи на устройствата','Repair status, history and documents'), widget.onRepairs),
        _action(Icons.shopping_bag_outlined, tr('Моите поръчки','My orders'), tr('Поръчки и информация за доставката','Orders and delivery information'), widget.onOrders),
        _action(Icons.calendar_month_outlined, tr('Записване на час','Book an appointment'), tr('Избери удобен сервизен час','Choose a convenient service time'), widget.onBooking),
        const SizedBox(height: 12), Text(tr('Комуникация и профил','Communication & account'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        _action(Icons.chat_bubble_outline_rounded, tr('Чат с PCWork','Chat with PCWork'), tr('Свържи се директно със сервизния екип','Contact the service team directly'), widget.onChat),
        _action(Icons.notifications_active_outlined, tr('Център за известия','Notification center'), tr('История на известията и важни актуализации','Notification history and important updates'), widget.onNotifications),
        _action(Icons.manage_accounts_outlined, tr('Моят профил','My profile'), tr('Лични данни и настройки на акаунта','Personal details and account settings'), widget.onProfile),
        const SizedBox(height: 14),
        if (data != null && data.repairs.isNotEmpty) ...[Text(tr('Последен ремонт','Latest repair'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)), Card(child: ListTile(leading: const Icon(Icons.precision_manufacturing_outlined, color: Color(0xFF21D4D8)), title: Text(data.repairs.first.number.isEmpty ? 'PCW-${data.repairs.first.id}' : data.repairs.first.number), subtitle: Text('${data.repairs.first.device} ${data.repairs.first.model} · ${data.repairs.first.status}'), trailing: const Icon(Icons.chevron_right), onTap: widget.onRepairs))],
        if (data != null && data.orders.isNotEmpty) ...[const SizedBox(height: 8), Text(tr('Последна поръчка','Latest order'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)), Card(child: ListTile(leading: const Icon(Icons.receipt_long_outlined, color: Color(0xFF21D4D8)), title: Text('#${data.orders.first['number'] ?? data.orders.first['id'] ?? ''}'), subtitle: Text('${data.orders.first['status'] ?? ''} · ${data.orders.first['total'] ?? ''}'), trailing: const Icon(Icons.chevron_right), onTap: widget.onOrders))],
      ]));
    }),
  );
  Widget _metric(String label, String value, IconData icon) => Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8), child: Column(children: [Icon(icon, color: const Color(0xFF21D4D8)), const SizedBox(height: 7), Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.grey))])));
  Widget _action(IconData icon, String title, String subtitle, VoidCallback onTap) => Card(child: ListTile(leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFF21D4D8).withValues(alpha: .12), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: const Color(0xFF21D4D8))), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)), trailing: const Icon(Icons.chevron_right_rounded), onTap: onTap));
}

class _CenterData { const _CenterData(this.repairs, this.orders); final List<Repair> repairs; final List<Map<String, dynamic>> orders; }
