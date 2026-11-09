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
  late Future<Map<String, dynamic>> _loyaltyFuture;
  late Future<List<Map<String, dynamic>>> _serviceHistoryFuture;
  String tr(String bg, String en) => widget.english ? en : bg;
  @override
  void initState() { super.initState(); _future = _load(); _loyaltyFuture = widget.api.getLoyaltySummary(widget.token); _serviceHistoryFuture = widget.api.getCustomerServiceHistory(widget.token); }
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
    appBar: AppBar(title: Text(tr('Клиентски център', 'Customer center')), actions: [IconButton(tooltip: tr('Обнови', 'Refresh'), onPressed: () => setState(() { _future = _load(); _loyaltyFuture = widget.api.getLoyaltySummary(widget.token); _serviceHistoryFuture = widget.api.getCustomerServiceHistory(widget.token, forceRefresh: true); }), icon: const Icon(Icons.refresh_rounded))]),
    body: FutureBuilder<_CenterData>(future: _future, builder: (context, snapshot) {
      final data = snapshot.data;
      final active = data?.repairs.where((r) => !['completed','cancelled'].contains(r.status)).length ?? 0;
      final ready = data?.repairs.where((r) => r.status == 'ready').length ?? 0;
      return RefreshIndicator(onRefresh: () async { final next = _load(); final loyalty = widget.api.getLoyaltySummary(widget.token); final history = widget.api.getCustomerServiceHistory(widget.token, forceRefresh: true); setState(() { _future = next; _loyaltyFuture = loyalty; _serviceHistoryFuture = history; }); await next; }, child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
        Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF123B4A), Color(0xFF24233E)]), borderRadius: BorderRadius.circular(22)), child: Row(children: [const CircleAvatar(radius: 27, backgroundColor: Color(0x3321D4D8), child: Icon(Icons.person_rounded, color: Color(0xFF21D4D8), size: 30)), const SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr('Здравейте,', 'Welcome,'), style: const TextStyle(color: Colors.white70)), Text(widget.user.name.isEmpty ? widget.user.email : widget.user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 19)), Text(widget.user.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12))]))])),
        const SizedBox(height: 14),
        FutureBuilder<Map<String, dynamic>>(
          future: _loyaltyFuture,
          builder: (context, loyalty) => _loyaltyCard(loyalty),
        ),
        const SizedBox(height: 14),
        if (snapshot.connectionState == ConnectionState.waiting && data == null) const LinearProgressIndicator(),
        if (snapshot.hasError) Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(tr('Не успяхме да заредим обобщението. Издърпайте надолу за нов опит.', 'We could not load your overview. Pull down to retry.'), style: const TextStyle(color: Colors.orangeAccent)))),
        Row(children: [Expanded(child: _metric(tr('Ремонти','Repairs'), '${data?.repairs.length ?? '—'}', Icons.build_circle_outlined)), const SizedBox(width: 6), Expanded(child: _metric(tr('Активни','Active'), '$active', Icons.autorenew_rounded)), const SizedBox(width: 6), Expanded(child: _metric(tr('Готови','Ready'), '$ready', Icons.task_alt_rounded)), const SizedBox(width: 6), Expanded(child: _metric(tr('Поръчки','Orders'), '${data?.orders.length ?? '—'}', Icons.shopping_bag_outlined))]),
        const SizedBox(height: 18),
        Text(tr('Моите устройства и сервизна история', 'My devices & service history'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        FutureBuilder<List<Map<String, dynamic>>>(future: _serviceHistoryFuture, builder: (context, history) {
          if (history.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
          if (history.hasError) return Card(child: ListTile(leading: const Icon(Icons.info_outline), title: Text(tr('Историята временно не е достъпна', 'Service history is temporarily unavailable')), trailing: IconButton(onPressed: () => setState(() => _serviceHistoryFuture = widget.api.getCustomerServiceHistory(widget.token, forceRefresh: true)), icon: const Icon(Icons.refresh))));
          final rows = history.data ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) return Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(tr('Все още няма регистрирани ремонти.', 'No repairs have been registered yet.'))));
          return Column(children: rows.map((row) {
            final warranty = (row['warranty_until'] ?? '').toString();
            final activeWarranty = row['warranty_active'] == true;
            return Card(child: ListTile(leading: Icon(activeWarranty ? Icons.verified_user_outlined : Icons.devices_other, color: activeWarranty ? const Color(0xFF21D4D8) : null), title: Text('${row['device_type'] ?? ''} ${row['device_model'] ?? ''}'.trim()), subtitle: Text(['${row['repair_number'] ?? ''} · ${row['status'] ?? ''}', if (warranty.isNotEmpty) tr('Гаранция до: ', 'Warranty until: ') + warranty else tr('Няма активна гаранционна карта', 'No active warranty card')].join('\n')), isThreeLine: true, onTap: widget.onRepairs));
          }).toList());
        }),
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
  Widget _loyaltyCard(AsyncSnapshot<Map<String, dynamic>> loyalty) {
    const gold = Color(0xFFFFD76A);
    if (loyalty.connectionState == ConnectionState.waiting) {
      return Container(
        height: 176,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF17130B), Color(0xFF5A4216), Color(0xFF211A0D)]),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFD5AD55), width: 1.2),
          boxShadow: const [BoxShadow(color: Color(0x332A1C00), blurRadius: 18, offset: Offset(0, 8))],
        ),
        child: const Center(child: CircularProgressIndicator(color: gold)),
      );
    }
    if (loyalty.hasError || loyalty.data == null) {
      final details = (loyalty.error?.toString() ?? tr('Няма получени данни от сървъра.', 'No data received from the server.'))
          .replaceFirst('Exception: ', '');
      final shortDetails = details.length > 180 ? '${details.substring(0, 180)}…' : details;
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF211A0D), Color(0xFF493615)]),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFD5AD55), width: 1.2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.workspace_premium_rounded, color: gold, size: 30), SizedBox(width: 10), Expanded(child: Text('PCWORK GOLD LOYALTY', style: TextStyle(color: gold, fontWeight: FontWeight.w900, letterSpacing: 1.1, fontSize: 16)))]),
          const SizedBox(height: 10),
          Text(tr('Не успяхме да заредим златната ти карта.', 'We could not load your gold loyalty card.'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(shortDetails, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(
            onPressed: () => setState(() => _loyaltyFuture = widget.api.getLoyaltySummary(widget.token)),
            icon: const Icon(Icons.refresh_rounded, color: gold),
            label: Text(tr('Опитай отново', 'Try again'), style: const TextStyle(color: gold, fontWeight: FontWeight.w800)),
          )),
        ]),
      );
    }

    final data = loyalty.data!;
    final points = int.tryParse('${data['points'] ?? 0}') ?? 0;
    final next = int.tryParse('${data['next_tier_points'] ?? 500}') ?? 500;
    final remaining = int.tryParse('${data['points_to_next'] ?? (next - points)}') ?? (next - points);
    final progress = next <= 0 ? 1.0 : (points / next).clamp(0.0, 1.0);
    final tier = '${data['tier'] ?? 'Start'}';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF100E0A), Color(0xFF493613), Color(0xFFB88932), Color(0xFF39270D)], stops: [0, .35, .72, 1]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFFDF91), width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x665A3B08), blurRadius: 22, spreadRadius: 1, offset: Offset(0, 9))],
      ),
      child: Stack(children: [
        Positioned(right: -22, top: -25, child: Icon(Icons.workspace_premium_rounded, size: 150, color: Colors.white.withValues(alpha: .055))),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 42, height: 42, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFFFF0B8), Color(0xFFD49A32)]), boxShadow: [BoxShadow(color: Color(0x66502F00), blurRadius: 8)]), child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFF392609), size: 27)),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('PCWORK', style: TextStyle(color: gold, fontWeight: FontWeight.w900, letterSpacing: 2.2, fontSize: 17)),
              Text(tr('КАРТА ЗА ЛОЯЛНОСТ', 'LOYALTY MEMBERSHIP'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1.15, fontSize: 10)),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: const Color(0x33FFF0B8), borderRadius: BorderRadius.circular(30), border: Border.all(color: const Color(0x99FFE5A0))), child: Text(tier.toUpperCase(), style: const TextStyle(color: gold, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: .8))),
          ]),
          const SizedBox(height: 20),
          Text('$points', style: const TextStyle(color: Color(0xFFFFF4D2), fontSize: 42, height: 1, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(tr('НАТРУПАНИ ТОЧКИ', 'POINTS BALANCE'), style: const TextStyle(color: gold, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          const SizedBox(height: 17),
          ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: progress, minHeight: 9, backgroundColor: Colors.white24, color: const Color(0xFFFFE29A))),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: Text(remaining > 0 ? tr('Още $remaining точки до следващото ниво', '$remaining points to the next tier') : tr('Достигнато е най-високото ниво!', 'Highest tier reached!'), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))), Text(tr('1 € = 1 т.', '1 € = 1 pt'), style: const TextStyle(color: gold, fontSize: 10, fontWeight: FontWeight.w800))]),
          const SizedBox(height: 13),
          Row(children: [const Icon(Icons.lock_rounded, color: Color(0xFFFFE29A), size: 13), const SizedBox(width: 5), Text(tr('ПЕРСОНАЛНА КЛИЕНТСКА КАРТА', 'PERSONAL MEMBER CARD'), style: const TextStyle(color: Colors.white70, fontSize: 9, letterSpacing: 1.1, fontWeight: FontWeight.w700)), const Spacer(), const Icon(Icons.stars_rounded, color: Color(0xFFFFE29A), size: 17)]),
        ]),
      ]),
    );
  }

  Widget _metric(String label, String value, IconData icon) => Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8), child: Column(children: [Icon(icon, color: const Color(0xFF21D4D8)), const SizedBox(height: 7), Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.grey))])));
  Widget _action(IconData icon, String title, String subtitle, VoidCallback onTap) => Card(child: ListTile(leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFF21D4D8).withValues(alpha: .12), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: const Color(0xFF21D4D8))), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)), trailing: const Icon(Icons.chevron_right_rounded), onTap: onTap));
}

class _CenterData { const _CenterData(this.repairs, this.orders); final List<Repair> repairs; final List<Map<String, dynamic>> orders; }
