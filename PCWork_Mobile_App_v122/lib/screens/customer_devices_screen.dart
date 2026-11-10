import 'package:flutter/material.dart';
import '../services/api_service.dart';

class CustomerDevicesScreen extends StatefulWidget {
  const CustomerDevicesScreen({super.key, required this.api, required this.token, required this.english});
  final ApiService api;
  final String token;
  final bool english;

  @override
  State<CustomerDevicesScreen> createState() => _CustomerDevicesScreenState();
}

class _CustomerDevicesScreenState extends State<CustomerDevicesScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _saving = false;
  String tr(String bg, String en) => widget.english ? en : bg;

  @override
  void initState() { super.initState(); _future = widget.api.getCustomerDevices(widget.token); }
  Future<void> _refresh() async { final next = widget.api.getCustomerDevices(widget.token); setState(() => _future = next); await next; }

  Future<void> _editDevice({Map<String, dynamic>? device}) async {
    final typeOptions = <String>['Лаптоп', 'Настолен компютър', 'PlayStation 5', 'PlayStation 4', 'Xbox', 'Nintendo Switch', 'Монитор', 'Телефон', 'Таблет', 'Друго'];
    final type = TextEditingController(text: (device?['device_type'] ?? 'Лаптоп').toString());
    final brand = TextEditingController(text: (device?['brand'] ?? '').toString());
    final model = TextEditingController(text: (device?['model'] ?? '').toString());
    final nickname = TextEditingController(text: (device?['nickname'] ?? '').toString());
    final serial = TextEditingController(text: (device?['serial_number'] ?? '').toString());
    final purchase = TextEditingController(text: (device?['purchase_date'] ?? '').toString());
    final notes = TextEditingController(text: (device?['notes'] ?? '').toString());
    String? error;
    final result = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
      title: Text(device == null ? tr('Добави устройство', 'Add a device') : tr('Редактирай устройство', 'Edit device')),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: typeOptions.contains(type.text) ? type.text : 'Друго', decoration: InputDecoration(labelText: tr('Тип устройство*', 'Device type*')), items: typeOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) { if (v != null) type.text = v; }),
        const SizedBox(height: 10), TextField(controller: brand, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr('Марка', 'Brand'))),
        const SizedBox(height: 10), TextField(controller: model, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr('Модел*', 'Model*'))),
        const SizedBox(height: 10), TextField(controller: nickname, decoration: InputDecoration(labelText: tr('Име / кратко описание', 'Nickname / label'), hintText: tr('Напр. Работният ми лаптоп', 'e.g. My work laptop'))),
        const SizedBox(height: 10), TextField(controller: serial, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: tr('Сериен номер', 'Serial number'), helperText: tr('Използва се за свързване със сервизната история.', 'Used to link the device to its repair history.'))),
        const SizedBox(height: 10), TextField(controller: purchase, keyboardType: TextInputType.datetime, decoration: InputDecoration(labelText: tr('Дата на покупка (ГГГГ-ММ-ДД)', 'Purchase date (YYYY-MM-DD)'), hintText: '2026-01-31')),
        const SizedBox(height: 10), TextField(controller: notes, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: tr('Бележки', 'Notes'))),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('Отказ', 'Cancel'))), FilledButton(onPressed: () {
        if (model.text.trim().isEmpty || type.text.trim().isEmpty) { setDialog(() => error = tr('Попълнете типа и модела на устройството.', 'Enter the device type and model.')); return; }
        if (purchase.text.trim().isNotEmpty && !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(purchase.text.trim())) { setDialog(() => error = tr('Датата трябва да е във формат ГГГГ-ММ-ДД.', 'Use YYYY-MM-DD for the date.')); return; }
        Navigator.pop(dialogContext, true);
      }, child: Text(tr('Запази', 'Save')))],
    )));
    if (result == true && mounted) {
      setState(() => _saving = true);
      try {
        await widget.api.saveCustomerDevice(widget.token, {
          'device_type': type.text.trim(), 'brand': brand.text.trim(), 'model': model.text.trim(),
          'nickname': nickname.text.trim(), 'serial_number': serial.text.trim(),
          'purchase_date': purchase.text.trim(), 'notes': notes.text.trim(),
        }, id: (device?['id'] as num?)?.toInt() ?? 0);
        if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Устройството е запазено.', 'Device saved.')))); await _refresh(); }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      } finally { if (mounted) setState(() => _saving = false); }
    }
    for (final c in [type, brand, model, nickname, serial, purchase, notes]) { c.dispose(); }
  }

  Future<void> _deleteDevice(Map<String, dynamic> device) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(tr('Изтриване на устройство', 'Delete device')),
      content: Text(tr('Да изтрием ли „${device['nickname']?.toString().isNotEmpty == true ? device['nickname'] : '${device['brand'] ?? ''} ${device['model'] ?? ''}'}“ от списъка ти? Сервизните записи няма да бъдат изтрити.', 'Remove this device from your list? Repair records will not be deleted.')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Отказ', 'Cancel'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Изтрий', 'Delete')))],
    ));
    if (confirmed != true) return;
    setState(() => _saving = true);
    try { await widget.api.deleteCustomerDevice(widget.token, (device['id'] as num).toInt()); await _refresh(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')))); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Моите устройства', 'My devices')), actions: [IconButton(onPressed: _saving ? null : _refresh, tooltip: tr('Обнови', 'Refresh'), icon: const Icon(Icons.refresh_rounded))]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _saving ? null : () => _editDevice(), icon: const Icon(Icons.add), label: Text(tr('Добави устройство', 'Add device'))),
    body: FutureBuilder<List<Map<String, dynamic>>>(future: _future, builder: (context, snapshot) {
      final rows = snapshot.data ?? const <Map<String, dynamic>>[];
      if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError && !snapshot.hasData) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off_outlined, size: 44), const SizedBox(height: 12), Text(tr('Не успяхме да заредим устройствата.', 'Could not load your devices.'), textAlign: TextAlign.center), const SizedBox(height: 10), FilledButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: Text(tr('Опитай отново', 'Try again')))])));
      return RefreshIndicator(onRefresh: _refresh, child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
        Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF123B4A), Color(0xFF24233E)]), borderRadius: BorderRadius.circular(20)), child: Row(children: [const Icon(Icons.devices_rounded, color: Color(0xFF21D4D8), size: 34), const SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr('Твоята техника на едно място', 'Your devices in one place'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)), const SizedBox(height: 4), Text(tr('Запази модел и сериен номер, за да намираш по-лесно сервизната история.', 'Save model and serial number to find service history more easily.'), style: const TextStyle(color: Colors.white70, fontSize: 12))]))])),
        const SizedBox(height: 14),
        if (snapshot.hasError) Card(child: ListTile(leading: const Icon(Icons.warning_amber_rounded), title: Text(tr('Показваме последно заредените данни.', 'Showing the last loaded data.')), trailing: IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)))),
        if (rows.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 18), child: Column(children: [Icon(Icons.devices_other_outlined, size: 58, color: Theme.of(context).colorScheme.outline), const SizedBox(height: 14), Text(tr('Все още нямаш добавени устройства.', 'You have not added any devices yet.'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), textAlign: TextAlign.center), const SizedBox(height: 7), Text(tr('Добави лаптоп, компютър или конзола, за да поддържаш личен списък.', 'Add a laptop, computer or console to keep your personal device list.'), textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))])),
        ...rows.map((d) => _deviceCard(d)),
        if (_saving) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
      ]));
    }),
  );

  Widget _deviceCard(Map<String, dynamic> d) {
    final title = (d['nickname'] ?? '').toString().trim();
    final name = [d['brand'], d['model']].where((v) => v != null && v.toString().trim().isNotEmpty).join(' ');
    final repairs = (d['repairs'] is List ? d['repairs'] as List : const []).whereType<Map>().toList();
    return Card(margin: const EdgeInsets.only(bottom: 12), clipBehavior: Clip.antiAlias, child: ExpansionTile(
      leading: CircleAvatar(backgroundColor: const Color(0xFF21D4D8).withValues(alpha: .13), child: Icon(_deviceIcon((d['device_type'] ?? '').toString()), color: const Color(0xFF21D4D8))),
      title: Text(title.isNotEmpty ? title : (name.isNotEmpty ? name : (d['device_type'] ?? '').toString()), style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('${d['device_type'] ?? ''}${name.isNotEmpty ? ' · $name' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
      children: [Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if ((d['serial_number'] ?? '').toString().isNotEmpty) _detail(tr('Сериен номер', 'Serial number'), d['serial_number'].toString()),
        if ((d['purchase_date'] ?? '').toString().isNotEmpty) _detail(tr('Дата на покупка', 'Purchase date'), d['purchase_date'].toString()),
        if ((d['notes'] ?? '').toString().isNotEmpty) _detail(tr('Бележки', 'Notes'), d['notes'].toString()),
        const SizedBox(height: 8), Text(tr('Сервизна история', 'Repair history'), style: const TextStyle(fontWeight: FontWeight.w800)),
        if (repairs.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(tr('Няма намерени ремонти със съвпадащ сериен номер.', 'No repairs found with a matching serial number.'), style: const TextStyle(fontSize: 12))),
        ...repairs.map((r) => ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.build_circle_outlined), title: Text((r['repair_number'] ?? 'Ремонт').toString()), subtitle: Text('${r['status'] ?? ''} · ${r['created_at'] ?? ''}'))),
        const Divider(), Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _saving ? null : () => _editDevice(device: d), icon: const Icon(Icons.edit_outlined), label: Text(tr('Редактирай', 'Edit')))), const SizedBox(width: 8), IconButton(onPressed: _saving ? null : () => _deleteDevice(d), tooltip: tr('Изтрий', 'Delete'), icon: const Icon(Icons.delete_outline, color: Colors.redAccent))]),
      ]))],
    ));
  }

  Widget _detail(String label, String value) => Padding(padding: const EdgeInsets.only(top: 5), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 125, child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12))), Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))]));
  IconData _deviceIcon(String type) { final v = type.toLowerCase(); if (v.contains('playstation') || v.contains('xbox') || v.contains('switch')) return Icons.sports_esports_outlined; if (v.contains('лаптоп')) return Icons.laptop_mac_outlined; if (v.contains('монитор')) return Icons.monitor_outlined; if (v.contains('телефон')) return Icons.phone_iphone_outlined; return Icons.computer_outlined; }
}
