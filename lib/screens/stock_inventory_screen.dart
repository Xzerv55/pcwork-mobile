import 'package:flutter/material.dart';
import '../services/api_service.dart';

class StockInventoryScreen extends StatefulWidget {
  const StockInventoryScreen({super.key, required this.api, required this.token, required this.english});
  final ApiService api;
  final String token;
  final bool english;
  @override
  State<StockInventoryScreen> createState() => _StockInventoryScreenState();
}

class _StockInventoryScreenState extends State<StockInventoryScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;
  String tr(String bg, String en) => widget.english ? en : bg;
  @override
  void initState() { super.initState(); _future = widget.api.getStockItems(widget.token); }
  void _reload() => setState(() => _future = widget.api.getStockItems(widget.token));

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final sku = TextEditingController(text: '${item?['sku'] ?? ''}');
    final name = TextEditingController(text: '${item?['name'] ?? ''}');
    final location = TextEditingController(text: '${item?['location_code'] ?? ''}');
    final qty = TextEditingController(text: '${item?['quantity'] ?? '0'}');
    final minimum = TextEditingController(text: '${item?['minimum_quantity'] ?? '0'}');
    final cost = TextEditingController(text: '${item?['unit_cost'] ?? '0'}');
    final unit = TextEditingController(text: '${item?['unit'] ?? 'бр.'}');
    final description = TextEditingController(text: '${item?['description'] ?? ''}');
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(item == null ? tr('Нов артикул', 'New item') : tr('Редакция на артикул', 'Edit item')),
      content: SizedBox(width: 440, child: Form(key: formKey, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: InputDecoration(labelText: tr('Наименование *', 'Name *')), validator: (v) => (v == null || v.trim().isEmpty) ? tr('Задължително поле', 'Required') : null),
        TextFormField(controller: sku, decoration: InputDecoration(labelText: 'SKU / Код')),
        if (item == null) TextFormField(controller: location, decoration: InputDecoration(labelText: tr('Код на сервизен обект *', 'Service location code *')), validator: (v) => (v == null || v.trim().isEmpty) ? tr('Задължително поле', 'Required') : null),
        if (item == null) TextFormField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('Начална наличност', 'Opening quantity')))
        else InputDecorator(decoration: InputDecoration(labelText: tr('Текуща наличност (променя се чрез Зареди/Изпиши)', 'Current quantity (change via Receive/Issue)')), child: Text('${item['quantity'] ?? 0} ${item['unit'] ?? ''}')),
        TextFormField(controller: minimum, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('Минимална наличност', 'Minimum quantity'))),
        TextFormField(controller: cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('Единична доставна цена', 'Unit cost'))),
        TextFormField(controller: unit, decoration: InputDecoration(labelText: tr('Мерна единица', 'Unit'))),
        TextFormField(controller: description, maxLines: 2, decoration: InputDecoration(labelText: tr('Описание', 'Description'))),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Отказ', 'Cancel'))), FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(ctx, true); }, child: Text(tr('Запази', 'Save')))],
    ));
    if (ok == true) {
      await _run(() async {
        final payload = <String, dynamic>{'sku': sku.text.trim(), 'name': name.text.trim(), 'minimum_quantity': double.tryParse(minimum.text.replaceAll(',', '.')) ?? 0, 'unit_cost': double.tryParse(cost.text.replaceAll(',', '.')) ?? 0, 'unit': unit.text.trim().isEmpty ? 'бр.' : unit.text.trim(), 'description': description.text.trim()};
        if (item == null) payload['quantity'] = double.tryParse(qty.text.replaceAll(',', '.')) ?? 0;
        if (item == null) { payload['location_code'] = location.text.trim(); await widget.api.createStockItem(widget.token, payload); }
        else { await widget.api.updateStockItem(widget.token, (item['id'] as num).toInt(), payload); }
      });
    }
    for (final c in [sku,name,location,qty,minimum,cost,unit,description]) { c.dispose(); }
  }

  Future<void> _movement(Map<String, dynamic> item, String type) async {
    final amount = TextEditingController(); final note = TextEditingController(); final repairId = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(type == 'in' ? tr('Зареждане на наличност', 'Stock received') : tr('Изписване на наличност', 'Stock issued')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [Text('${item['name']}'), TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('Количество', 'Quantity'))), TextField(controller: note, decoration: InputDecoration(labelText: tr('Бележка', 'Note'))), TextField(controller: repairId, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('ID на ремонт (по желание)', 'Repair ID (optional)')))]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Отказ', 'Cancel'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Потвърди', 'Confirm')))],
    ));
    if (ok == true) {
      final value = double.tryParse(amount.text.trim().replaceAll(',', '.')) ?? 0;
      if (value <= 0) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Въведи количество над нула.', 'Enter a quantity above zero.')))); }
      else { final linkedRepairId = int.tryParse(repairId.text.trim()); await _run(() => widget.api.moveStockItem(widget.token, (item['id'] as num).toInt(), type: type, quantity: value, note: note.text.trim(), repairId: linkedRepairId)); }
    }
    amount.dispose(); note.dispose(); repairId.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return; setState(() => _busy = true);
    try { await action(); if (mounted) { _reload(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Промяната е записана.', 'Changes saved.')))); } }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Склад и резервни части', 'Stock & spare parts')), actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _busy ? null : () => _edit(), icon: const Icon(Icons.add), label: Text(tr('Нов артикул', 'New item'))),
    body: FutureBuilder<List<Map<String, dynamic>>>(future: _future, builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${tr('Грешка:', 'Error:')} ${snap.error}')));
      final rows = snap.data ?? [];
      final low = rows.where((e) => e['low_stock'] == true).length;
      return RefreshIndicator(onRefresh: () async { final f = widget.api.getStockItems(widget.token); setState(() => _future = f); await f; }, child: ListView(padding: const EdgeInsets.fromLTRB(12,12,12,90), children: [
        Card(child: ListTile(leading: const Icon(Icons.inventory_2_outlined), title: Text(tr('Общо артикули: ${rows.length}', 'Total items: ${rows.length}')), subtitle: Text(tr('Под минимална наличност: $low', 'Below minimum stock: $low')), trailing: low > 0 ? const Icon(Icons.warning_amber_rounded, color: Colors.orange) : const Icon(Icons.check_circle_outline))),
        if (rows.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(tr('Няма добавени складови артикули.', 'No stock items yet.'))),
        ...rows.map((item) => Card(child: ListTile(
          leading: CircleAvatar(child: Icon(item['low_stock'] == true ? Icons.warning_amber_rounded : Icons.inventory_2_outlined, color: item['low_stock'] == true ? Colors.orange : null)),
          title: Text('${item['name'] ?? ''}'),
          subtitle: Text('${item['sku'] ?? ''} · ${item['location_code'] ?? ''}\n${tr('Наличност', 'Stock')}: ${item['quantity']} ${item['unit'] ?? ''} · ${tr('Минимум', 'Min')}: ${item['minimum_quantity']} · ${tr('Цена', 'Cost')}: ${item['unit_cost']}'),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'in' || v == 'out') _movement(item, v); else _edit(item); }, itemBuilder: (_) => [PopupMenuItem(value: 'in', child: Text(tr('Зареди', 'Receive'))), PopupMenuItem(value: 'out', child: Text(tr('Изпиши', 'Issue'))), PopupMenuItem(value: 'edit', child: Text(tr('Редактирай', 'Edit')))]),
          onTap: () => _edit(item),
        ))),
      ]));
    }),
  );
}
