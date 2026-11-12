import 'package:flutter/material.dart';
import '../services/api_service.dart';

class RepairPartsScreen extends StatefulWidget {
  const RepairPartsScreen({super.key, required this.api, required this.token, required this.repairId, required this.repairNumber, required this.english});
  final ApiService api;
  final String token;
  final int repairId;
  final String repairNumber;
  final bool english;

  @override
  State<RepairPartsScreen> createState() => _RepairPartsScreenState();
}

class _RepairPartsScreenState extends State<RepairPartsScreen> {
  late Future<List<Map<String, dynamic>>> _stockFuture;
  late Future<List<Map<String, dynamic>>> _movementFuture;
  late Future<List<Map<String, dynamic>>> _requestsFuture;
  late Future<Map<String, dynamic>> _partsSummaryFuture;
  bool _busy = false;
  String tr(String bg, String en) => widget.english ? en : bg;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _stockFuture = widget.api.getStockItems(widget.token);
    _movementFuture = widget.api.getStockMovements(widget.token, repairId: widget.repairId, perPage: 100);
    _requestsFuture = widget.api.getRepairPartRequests(widget.token, widget.repairId);
    _partsSummaryFuture = widget.api.getRepairPartsSummary(widget.token, widget.repairId);
    if (mounted) setState(() {});
  }

  double _number(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value'.replaceAll(',', '.')) ?? 0;

  Future<void> _issuePart(List<Map<String, dynamic>> stock) async {
    final available = stock.where((item) => _number(item['quantity']) > 0).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Няма налични части за изписване.', 'No available parts to issue.'))));
      return;
    }
    int? selectedId = (available.first['id'] as num?)?.toInt();
    final quantity = TextEditingController(text: '1');
    final price = TextEditingController(text: _number(available.first['unit_cost']).toStringAsFixed(2));
    final note = TextEditingController();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
        title: Text(tr('Добави част към ремонта', 'Add part to repair')),
        content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(initialValue: selectedId, isExpanded: true, decoration: InputDecoration(labelText: tr('Артикул от склада', 'Stock item')), items: available.map((item) => DropdownMenuItem<int>(value: (item['id'] as num).toInt(), child: Text('${item['name']} · ${item['quantity']} ${item['unit'] ?? ''}', overflow: TextOverflow.ellipsis))).toList(), onChanged: (id) { setDialog(() { selectedId = id; final item = available.firstWhere((e) => (e['id'] as num).toInt() == id); price.text = _number(item['unit_cost']).toStringAsFixed(2); }); }),
          const SizedBox(height: 10), TextField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('Количество за изписване', 'Quantity to issue'))),
          const SizedBox(height: 10), TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('Продажна цена за единица (€)', 'Unit charge (€)'))),
          const SizedBox(height: 10), TextField(controller: note, maxLines: 2, decoration: InputDecoration(labelText: tr('Бележка (по желание)', 'Note (optional)'))),
          const SizedBox(height: 8), Text(tr('Изписването ще намали складовата наличност и ще се свърже с този ремонт.', 'Issuing the part reduces stock and links the movement to this repair.'), style: Theme.of(ctx).textTheme.bodySmall),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Отказ', 'Cancel'))), FilledButton(onPressed: () { final qty = _number(quantity.text); final unitPrice = _number(price.text); if (selectedId == null || qty <= 0 || unitPrice < 0) return; final item = available.firstWhere((e) => (e['id'] as num).toInt() == selectedId); if (qty > _number(item['quantity'])) return; Navigator.pop(ctx, {'id': selectedId, 'quantity': qty, 'price': unitPrice, 'note': note.text.trim(), 'item': item}); }, child: Text(tr('Изпиши и добави', 'Issue & add')))],
      )),
    );
    quantity.dispose(); price.dispose(); note.dispose();
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    final item = result['item'] as Map<String, dynamic>;
    final qty = result['quantity'] as double;
    final unitPrice = result['price'] as double;
    final description = '${item['name']} · ${qty.toStringAsFixed(2)} ${item['unit'] ?? ''}${(result['note'] as String).isEmpty ? '' : ' · ${result['note']}'}';
    try {
      await widget.api.moveStockItem(widget.token, result['id'] as int, type: 'out', quantity: qty, note: 'Ремонт ${widget.repairNumber}${(result['note'] as String).isEmpty ? '' : ' · ${result['note']}'}', repairId: widget.repairId);
      try {
        await widget.api.addRepairWorklogEntry(widget.token, widget.repairId, {'entry_type': 'part', 'description': description, 'quantity': qty, 'unit_price': unitPrice, 'amount': unitPrice, 'visible_to_customer': true});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Частта е изписана и добавена в сервизния дневник.', 'Part issued and added to the service log.'))));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Наличността е изписана, но записът в сервизния дневник не успя. Движението е запазено. ', 'Stock was issued, but the service-log entry failed. The movement is saved. ')}$e')));
      }
      if (mounted) _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Неуспешно изписване:', 'Issue failed:')} $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  Future<void> _requestPart() async {
    final name = TextEditingController(); final sku = TextEditingController();
    final quantity = TextEditingController(text: '1'); final note = TextEditingController();
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => AlertDialog(
      title: Text(tr('Заяви липсваща част', 'Request a missing part')),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: InputDecoration(labelText: tr('Наименование *', 'Part name *'))),
        TextField(controller: sku, decoration: InputDecoration(labelText: tr('Каталожен номер (по желание)', 'SKU (optional)'))),
        TextField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('Количество', 'Quantity'))),
        TextField(controller: note, maxLines: 2, decoration: InputDecoration(labelText: tr('Бележка / съвместимост', 'Note / compatibility'))),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Отказ', 'Cancel'))), FilledButton(onPressed: () { final qty = _number(quantity.text); if (name.text.trim().isEmpty || qty <= 0) return; Navigator.pop(ctx, {'item_name': name.text.trim(), 'sku': sku.text.trim(), 'quantity': qty, 'note': note.text.trim()}); }, child: Text(tr('Изпрати заявка', 'Submit request')))],
    ));
    name.dispose(); sku.dispose(); quantity.dispose(); note.dispose();
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try { await widget.api.createRepairPartRequest(widget.token, widget.repairId, result); if (mounted) { _refresh(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Заявката за част е записана.', 'Part request saved.')))); } }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Грешка:', 'Error:')} $e'))); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _editOrderDetails(Map<String, dynamic> request) async {
    final supplier = TextEditingController(text: '${request['supplier'] ?? ''}');
    final orderRef = TextEditingController(text: '${request['supplier_order_ref'] ?? ''}');
    final expected = TextEditingController(text: '${request['expected_delivery_date'] ?? ''}');
    final tracking = TextEditingController(text: '${request['tracking_number'] ?? ''}');
    final result = await showDialog<Map<String, String>>(context: context, builder: (ctx) => AlertDialog(
      title: Text(tr('Данни за доставката', 'Delivery details')),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: supplier, decoration: InputDecoration(labelText: tr('Доставчик', 'Supplier'))),
        TextField(controller: orderRef, decoration: InputDecoration(labelText: tr('Номер на поръчка', 'Purchase order reference'))),
        TextField(controller: expected, keyboardType: TextInputType.datetime, decoration: InputDecoration(labelText: tr('Очаквана дата (ГГГГ-ММ-ДД)', 'Expected date (YYYY-MM-DD)'), hintText: '2026-11-20')),
        TextField(controller: tracking, decoration: InputDecoration(labelText: tr('Номер за проследяване', 'Tracking number'))),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Отказ', 'Cancel'))), FilledButton(onPressed: () {
        final date = expected.text.trim();
        if (date.isNotEmpty && !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) return;
        Navigator.pop(ctx, {'supplier': supplier.text.trim(), 'supplier_order_ref': orderRef.text.trim(), 'expected_delivery_date': date, 'tracking_number': tracking.text.trim()});
      }, child: Text(tr('Запази', 'Save')))],
    ));
    supplier.dispose(); orderRef.dispose(); expected.dispose(); tracking.dispose();
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.updateRepairPartRequest(widget.token, (request['id'] as num).toInt(), result);
      if (mounted) { _refresh(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Данните за доставката са запазени.', 'Delivery details saved.')))); }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Грешка:', 'Error:')} $e'))); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _changeRequestStatus(Map<String, dynamic> request, String status) async {
    setState(() => _busy = true);
    try { await widget.api.updateRepairPartRequest(widget.token, (request['id'] as num).toInt(), {'status': status}); if (mounted) _refresh(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Грешка:', 'Error:')} $e'))); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _receiveRequest(Map<String, dynamic> request) async {
    final cost = TextEditingController(text: '0.00');
    final value = await showDialog<double>(context: context, builder: (ctx) => AlertDialog(
      title: Text(tr('Приеми доставената част', 'Receive delivered part')),
      content: TextField(controller: cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('Себестойност за единица (€)', 'Unit cost (€)'), helperText: tr('0 = запази текущата цена при съвпадащ артикул.', '0 = keep existing cost for a matching item.'))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Отказ', 'Cancel'))), FilledButton(onPressed: () { final v = _number(cost.text); if (v >= 0) Navigator.pop(ctx, v); }, child: Text(tr('Приеми в склада', 'Receive into stock')))],
    ));
    cost.dispose();
    if (value == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.receiveRepairPartRequest(widget.token, (request['id'] as num).toInt(), unitCost: value);
      if (mounted) { _refresh(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Частта е приета и наличността е обновена.', 'Part received and stock updated.')))); }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Грешка при приемане:', 'Receive failed:')} $e'))); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  String _requestStatus(String status) => switch (status) {
    'ordered' => tr('Поръчана', 'Ordered'), 'received' => tr('Получена', 'Received'), 'cancelled' => tr('Отказана', 'Cancelled'), _ => tr('Заявена', 'Requested'),
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${tr('Части по ремонт', 'Repair parts')} · ${widget.repairNumber}'), actions: [IconButton(onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh))]),
    body: FutureBuilder<List<Map<String, dynamic>>>(future: _stockFuture, builder: (context, stockSnap) {
      if (stockSnap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (stockSnap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${tr('Грешка при зареждане на склада:', 'Could not load stock:')} ${stockSnap.error}')));
      final stock = stockSnap.data ?? [];
      return FutureBuilder<List<Map<String, dynamic>>>(future: _movementFuture, builder: (context, moveSnap) {
        if (moveSnap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (moveSnap.hasError) return Center(child: Text('${tr('Грешка при зареждане на движенията:', 'Could not load movements:')} ${moveSnap.error}'));
        final movements = moveSnap.data ?? [];
        return RefreshIndicator(onRefresh: () async => _refresh(), child: ListView(padding: const EdgeInsets.all(14), children: [
          Card(child: ListTile(leading: const Icon(Icons.inventory_2_outlined), title: Text(tr('Резервни части за този ремонт', 'Spare parts for this repair')), subtitle: Text(tr('Изписването се свързва автоматично с ремонта и се отразява в сервизния дневник.', 'Issued parts are automatically linked to this repair and recorded in the service log.')), trailing: IconButton(onPressed: _busy ? null : () => _issuePart(stock), icon: const Icon(Icons.add_circle_outline)))),
          FutureBuilder<Map<String, dynamic>>(future: _partsSummaryFuture, builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Card(child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()));
            if (snap.hasError) return Card(child: ListTile(leading: const Icon(Icons.info_outline), title: Text(tr('Финансовата справка за частите не е налична.', 'Parts financial summary unavailable.')), subtitle: Text('${snap.error}')));
            final data = snap.data ?? {};
            final revenue = _number(data['parts_revenue']); final cost = _number(data['parts_cost']); final profit = _number(data['gross_profit']); final margin = _number(data['gross_margin_percent']);
            Widget metric(String label, double value, {bool emphasize = false}) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 4), Text('${value.toStringAsFixed(2)} €', style: TextStyle(fontWeight: emphasize ? FontWeight.bold : FontWeight.w600, fontSize: emphasize ? 17 : 15))]));
            return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Финансов резултат от частите', 'Parts financial summary'), style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 12),
              Row(children: [metric(tr('Продажна стойност', 'Billed'), revenue), const SizedBox(width: 8), metric(tr('Себестойност', 'Cost'), cost)]),
              const Divider(height: 22),
              Row(children: [metric(tr('Брутна печалба', 'Gross profit'), profit, emphasize: true), const SizedBox(width: 8), metric(tr('Марж', 'Margin'), margin)]),
              const SizedBox(height: 8), Text(tr('Изчислението включва изписаните складови части и записаните продажни стойности. Не включва труд и други разходи.', 'Calculated from issued stock parts and recorded part charges. Excludes labor and other expenses.'), style: Theme.of(context).textTheme.bodySmall),
            ])));
          }),

          if (movements.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(tr('Няма складови движения за този ремонт.', 'No stock movements for this repair yet.')))),
          ...movements.map((movement) { final delta = _number(movement['quantity_delta']); final isIn = delta >= 0; return Card(child: ListTile(leading: Icon(isIn ? Icons.call_received : Icons.call_made, color: isIn ? Colors.green : Colors.orange), title: Text('${movement['item_name'] ?? movement['name'] ?? tr('Артикул', 'Item')} · ${delta > 0 ? '+' : ''}${delta.toStringAsFixed(2)} ${movement['unit'] ?? ''}'), subtitle: Text([movement['created_at']?.toString() ?? '', movement['note']?.toString() ?? ''].where((e) => e.isNotEmpty).join('\n')), trailing: isIn ? const Icon(Icons.check_circle_outline, color: Colors.green) : const Icon(Icons.outbox_outlined))); }),
          const SizedBox(height: 18),
          Row(children: [Expanded(child: Text(tr('Заявки за липсващи части', 'Missing-part requests'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))), IconButton(onPressed: _busy ? null : _requestPart, icon: const Icon(Icons.add_circle_outline), tooltip: tr('Нова заявка', 'New request'))]),
          FutureBuilder<List<Map<String, dynamic>>>(future: _requestsFuture, builder: (context, requestSnap) {
            if (requestSnap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
            if (requestSnap.hasError) return Text('${tr('Неуспешно зареждане:', 'Could not load requests:')} ${requestSnap.error}');
            final requests = requestSnap.data ?? [];
            if (requests.isEmpty) return Padding(padding: const EdgeInsets.all(12), child: Text(tr('Няма заявени липсващи части.', 'No missing parts requested.')));
            return Column(children: requests.map((request) {
              final status = (request['status'] ?? 'requested').toString();
              return Card(child: ListTile(
                leading: Icon(status == 'received' ? Icons.inventory_rounded : status == 'ordered' ? Icons.local_shipping_outlined : Icons.shopping_cart_outlined, color: status == 'received' ? Colors.green : Colors.orange),
                title: Text('${request['item_name']} · ${_number(request['quantity']).toStringAsFixed(2)}'),
                subtitle: Text(['${tr('Статус:', 'Status:')} ${_requestStatus(status)}', if ((request['sku'] ?? '').toString().isNotEmpty) 'SKU: ${request['sku']}', if ((request['note'] ?? '').toString().isNotEmpty) request['note'].toString(), if ((request['supplier'] ?? '').toString().isNotEmpty) '${tr('Доставчик:', 'Supplier:')} ${request['supplier']}', if ((request['supplier_order_ref'] ?? '').toString().isNotEmpty) '${tr('Поръчка:', 'Order:')} ${request['supplier_order_ref']}', if ((request['expected_delivery_date'] ?? '').toString().isNotEmpty) '${tr('Очаквана доставка:', 'Expected:')} ${request['expected_delivery_date']}', if ((request['tracking_number'] ?? '').toString().isNotEmpty) '${tr('Проследяване:', 'Tracking:')} ${request['tracking_number']}'].join(' · ')),
                trailing: PopupMenuButton<String>(enabled: !_busy && status != 'cancelled' && status != 'received', onSelected: (value) { if (value == '__receive__') { _receiveRequest(request); } else if (value == '__details__') { _editOrderDetails(request); } else { _changeRequestStatus(request, value); } }, itemBuilder: (_) => [PopupMenuItem(value: '__details__', child: Text(tr('Данни за доставката', 'Delivery details'))), PopupMenuItem(value: 'requested', child: Text(tr('Заявена', 'Requested'))), PopupMenuItem(value: 'ordered', child: Text(tr('Поръчана', 'Ordered'))), if (status != 'received') PopupMenuItem(value: '__receive__', child: Text(tr('Приеми в склада', 'Receive into stock'))), PopupMenuItem(value: 'cancelled', child: Text(tr('Отказана', 'Cancelled')))], child: Chip(label: Text(_requestStatus(status)))),
              ));
            }).toList());
          }),

        ]));
      });
    }),
    floatingActionButton: FloatingActionButton.extended(onPressed: _busy ? null : () => _issuePartFromFuture(), icon: const Icon(Icons.add), label: Text(tr('Изпиши част', 'Issue part'))),
  );

  Future<void> _issuePartFromFuture() async { final rows = await _stockFuture; if (mounted) await _issuePart(rows); }
}
