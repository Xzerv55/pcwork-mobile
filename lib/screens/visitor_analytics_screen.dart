import 'package:flutter/material.dart';
import '../services/api_service.dart';

class VisitorAnalyticsScreen extends StatefulWidget {
  const VisitorAnalyticsScreen({super.key, required this.api, required this.token, required this.english});
  final ApiService api;
  final String token;
  final bool english;
  @override
  State<VisitorAnalyticsScreen> createState() => _VisitorAnalyticsScreenState();
}

class _VisitorAnalyticsScreenState extends State<VisitorAnalyticsScreen> {
  List<Map<String,dynamic>> _visitors = [];
  Map<String,dynamic> _data = {};
  int? _selected;
  bool _loading = true;
  bool _detailsLoading = false;
  String? _error;
  String tr(String bg, String en) => widget.english ? en : bg;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await widget.api.getVisitorAnalyticsUsers(widget.token);
      if (!mounted) return;
      setState(() { _visitors = rows; _loading = false; });
      if (rows.isNotEmpty) await _select(int.tryParse('${rows.first['user_id']}') ?? 0);
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _select(int id) async {
    if (id <= 0) return;
    setState(() { _selected = id; _data = {}; _detailsLoading = true; _error = null; });
    try {
      final result = await widget.api.getAdminChatContext(widget.token, id);
      if (mounted && _selected == id) setState(() => _data = result);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted && _selected == id) setState(() => _detailsLoading = false);
    }
  }

  String _v(dynamic value) => value == null || value.toString().trim().isEmpty ? '—' : value.toString();
  Widget _section(String title, IconData icon, List<Widget> rows) => Card(
    child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, color: const Color(0xFF21D4D8)), const SizedBox(width: 9), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)))]),
      const Divider(height: 20),
      if (rows.isEmpty) Text(tr('Няма налични данни.', 'No data available.'), style: const TextStyle(color: Colors.grey)) else ...rows,
    ])),
  );
  Widget _row(String label, dynamic value) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SizedBox(width: 112, child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey))),
    Expanded(child: SelectableText(_v(value), style: const TextStyle(fontSize: 12))),
  ]));

  @override
  Widget build(BuildContext context) {
    final profile = _data['profile'] is Map ? Map<String,dynamic>.from(_data['profile']) : <String,dynamic>{};
    final pages = _data['pages'] is Map ? Map<String,dynamic>.from(_data['pages']) : <String,dynamic>{};
    final cart = _data['cart'] is Map ? Map<String,dynamic>.from(_data['cart']) : <String,dynamic>{};
    final technical = _data['technical'] is Map ? Map<String,dynamic>.from(_data['technical']) : <String,dynamic>{};
    final items = cart['items'] is List ? (cart['items'] as List).whereType<Map>().toList() : <Map>[];
    final orders = _data['orders'] is List ? (_data['orders'] as List).whereType<Map>().toList() : <Map>[];
    final recent = pages['recent'] is List ? (pages['recent'] as List).map((e) => e.toString()).toList() : <String>[];
    return Scaffold(
      appBar: AppBar(title: Text(tr('Данни на посетителите', 'Visitor analytics')), actions: [IconButton(tooltip: tr('Обнови', 'Refresh'), onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null && _visitors.isEmpty
        ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center)))
        : Column(children: [
          if (_visitors.isNotEmpty) SizedBox(height: 76, child: ListView.separated(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), scrollDirection: Axis.horizontal, itemCount: _visitors.length, separatorBuilder: (_, __) => const SizedBox(width: 8), itemBuilder: (_, i) {
            final v = _visitors[i]; final id = int.tryParse('${v['user_id']}') ?? 0; final active = id == _selected;
            return ChoiceChip(label: Text((v['display_name'] ?? v['email'] ?? tr('Клиент', 'Customer')).toString()), selected: active, onSelected: (_) => _select(id));
          })),
          Expanded(child: _visitors.isEmpty ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(tr('Няма посетители със записано съгласие за анализ. След вход в сайта клиентът трябва да отвори „Настройки за поверителност“ и да избере „Приемам“.', 'No visitors have consented to analytics yet. After signing in to the website, a customer must open Privacy settings and choose Accept.'), textAlign: TextAlign.center))) : _detailsLoading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 18), children: [
            _section(tr('Профил и контакт', 'Profile & contact'), Icons.person_outline, [
              _row('Име', profile['name']), _row('Имейл', profile['email']), _row('Телефон', profile['phone']), _row('Статус', profile['status']),
            ]),
            _section(tr('Посещения и навигация', 'Visits & navigation'), Icons.language, [
              _row(tr('Текуща страница', 'Current page'), pages['current']), ...recent.asMap().entries.map((e) => _row('${tr('Посещение', 'Visit')} ${e.key + 1}', e.value)),
            ]),
            _section(tr('Количка', 'Shopping cart'), Icons.shopping_cart_outlined, [
              ...items.map((e) => _row('${_v(e['quantity'])} ×', e['name'])), _row(tr('Обща стойност', 'Total value'), cart['total']),
            ]),
            _section(tr('Поръчки', 'Orders'), Icons.receipt_long_outlined, [
              ...orders.map((e) => _row('#${_v(e['number'])} · ${_v(e['status'])}', '${_v(e['total'])} · ${_v(e['date'])}')),
            ]),
            _section(tr('Техническа информация', 'Technical information'), Icons.devices_other, [
              _row(tr('Държава', 'Country'), technical['country']), _row(tr('Приблизително местоположение', 'Approx. location'), technical['approx_location']), _row(tr('Устройство', 'Device'), technical['device']), _row(tr('Последно посещение', 'Last seen'), technical['last_seen']), _row(tr('Съгласие', 'Consent'), technical['consent'] == true ? tr('Дадено', 'Granted') : tr('Не е дадено', 'Not granted')),
            ]),
            if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.orange))),
          ])),
        ]),
    );
  }
}
