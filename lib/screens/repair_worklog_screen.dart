import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../design_system/pcwork_design_system.dart';

class RepairWorklogScreen extends StatefulWidget {
  const RepairWorklogScreen({super.key, required this.api, required this.token, required this.repairId, required this.repairNumber, required this.isStaff});
  final ApiService api;
  final String token;
  final int repairId;
  final String repairNumber;
  final bool isStaff;

  @override
  State<RepairWorklogScreen> createState() => _RepairWorklogScreenState();
}

class _RepairWorklogScreenState extends State<RepairWorklogScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _entries = [];
  Map<String, dynamic> _summary = {};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await widget.api.getRepairWorklog(widget.token, widget.repairId);
      if (!mounted) return;
      setState(() { _entries = result['entries'] as List<Map<String, dynamic>>; _summary = result['summary'] as Map<String, dynamic>; _loading = false; });
    } catch (e) { if (mounted) setState(() { _error = e.toString(); _loading = false; }); }
  }

  String _typeLabel(String type) => switch (type) {
    'diagnostic' => 'Диагностика', 'work' => 'Извършена работа', 'part' => 'Резервна част', 'payment' => 'Плащане', 'warranty' => 'Гаранция', _ => type,
  };
  IconData _typeIcon(String type) => switch (type) {
    'diagnostic' => Icons.search, 'work' => Icons.build, 'part' => Icons.memory, 'payment' => Icons.payments, 'warranty' => Icons.verified_user, _ => Icons.receipt_long,
  };
  String _money(dynamic value) => '${(value is num ? value : num.tryParse('$value') ?? 0).toStringAsFixed(2)} €';

  Future<void> _addEntry() async {
    final description = TextEditingController();
    final quantity = TextEditingController(text: '1');
    final price = TextEditingController(text: '0');
    String type = 'work';
    String warrantyDate = '';
    bool visible = true;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: const Text('Добави запис към ремонта'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'Тип запис'), items: const [DropdownMenuItem(value: 'diagnostic', child: Text('Диагностика')), DropdownMenuItem(value: 'work', child: Text('Извършена работа')), DropdownMenuItem(value: 'part', child: Text('Резервна част')), DropdownMenuItem(value: 'payment', child: Text('Плащане')), DropdownMenuItem(value: 'warranty', child: Text('Гаранция'))], onChanged: (v) => refresh(() => type = v ?? 'work')),
          const SizedBox(height: 10), TextField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'Описание', hintText: 'Напр. смяна на вентилатор')),
          if (type != 'warranty') ...[
            const SizedBox(height: 10), if (type != 'payment') TextField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Количество')),
            const SizedBox(height: 10), TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: type == 'payment' ? 'Сума на плащането (€)' : 'Единична цена (€)')),
          ] else ...[
            const SizedBox(height: 10), OutlinedButton.icon(onPressed: () async { final now = DateTime.now(); final date = await showDatePicker(context: context, initialDate: now, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 10)); if (date != null) refresh(() => warrantyDate = '${date.year.toString().padLeft(4,'0')}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}'); }, icon: const Icon(Icons.calendar_month), label: Text(warrantyDate.isEmpty ? 'Край на гаранцията (по желание)' : warrantyDate)),
          ],
          const SizedBox(height: 8), SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Видимо за клиента'), value: visible, onChanged: (v) => refresh(() => visible = v)),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отказ')), FilledButton(onPressed: () { final qty = double.tryParse(quantity.text.replaceAll(',', '.')) ?? 1; final unit = double.tryParse(price.text.replaceAll(',', '.')) ?? 0; if (description.text.trim().isEmpty || (type != 'warranty' && (qty <= 0 || unit < 0)) || (type == 'payment' && unit <= 0)) return; Navigator.pop(dialogContext, {'entry_type': type, 'description': description.text.trim(), 'quantity': type == 'payment' ? 1 : qty, 'unit_price': unit, 'amount': unit, 'warranty_until': warrantyDate, 'visible_to_customer': visible}); }, child: const Text('Добави'))],
      )),
    );
    description.dispose(); quantity.dispose(); price.dispose();
    if (payload == null || !mounted) return;
    setState(() => _saving = true);
    try { await widget.api.addRepairWorklogEntry(widget.token, widget.repairId, payload); await _load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Неуспешен запис: $e'))); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: PCWorkColors.midnight,
    appBar: AppBar(title: Text('Сервизен дневник · ${widget.repairNumber}', style: const TextStyle(fontWeight: FontWeight.w800)), actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))]),
    floatingActionButton: widget.isStaff ? FloatingActionButton.extended(onPressed: _saving ? null : _addEntry, icon: const Icon(Icons.add), label: const Text('Добави запис')) : null,
    body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton(onPressed: _load, child: const Text('Опитай отново'))]))) : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
      PCWorkGlassPanel(glow: true, borderColor: PCWorkColors.cyan.withValues(alpha: .38), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Expanded(child: Text('Диагностика, работа и части', style: TextStyle(color: PCWorkColors.textPrimary, fontWeight: FontWeight.w800))), Text(_money(_summary['subtotal']), style: const TextStyle(color: PCWorkColors.textPrimary, fontWeight: FontWeight.w900))]), const SizedBox(height: 10), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Платено', style: TextStyle(color: PCWorkColors.textSecondary)), Text(_money(_summary['paid']), style: const TextStyle(color: PCWorkColors.textSecondary))]), const Divider(height: 22, color: Color(0x334B7199)), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Остатък', style: TextStyle(color: PCWorkColors.textPrimary, fontWeight: FontWeight.w900)), Text(_money(_summary['balance']), style: const TextStyle(fontWeight: FontWeight.w900, color: PCWorkColors.cyan, fontSize: 18))]), if ((_summary['latest_warranty_until'] ?? '').toString().isNotEmpty) Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 9), child: Text('Гаранция до: ${_summary['latest_warranty_until']}', style: const TextStyle(color: PCWorkColors.success, fontSize: 12, fontWeight: FontWeight.w700))))])),
      if (_entries.isEmpty) const PCWorkGlassPanel(padding: EdgeInsets.all(24), child: Column(children: [PCWorkGlowIcon(icon: Icons.receipt_long_rounded, color: PCWorkColors.textMuted), SizedBox(height: 10), Text('Все още няма записи в сервизния дневник.', textAlign: TextAlign.center, style: TextStyle(color: PCWorkColors.textSecondary))])),
      ..._entries.map((entry) { final type = (entry['entry_type'] ?? '').toString(); final total = entry['total']; final warranty = (entry['warranty_until'] ?? '').toString(); final accent = type == 'diagnostic' ? PCWorkColors.violet : type == 'payment' ? PCWorkColors.success : PCWorkColors.cyan; return Padding(padding: const EdgeInsets.only(bottom: 9), child: PCWorkGlassPanel(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10), borderColor: accent.withValues(alpha: .28), child: ListTile(contentPadding: EdgeInsets.zero, leading: PCWorkGlowIcon(icon: _typeIcon(type), color: accent, size: 42, iconSize: 20), title: Text(_typeLabel(type), style: const TextStyle(color: PCWorkColors.textPrimary, fontWeight: FontWeight.w800)), subtitle: Text([entry['description']?.toString() ?? '', if ((entry['quantity'] as num? ?? 1) > 1) 'Количество: ${entry['quantity']}', if (warranty.isNotEmpty) 'Гаранция до: $warranty', entry['created_at']?.toString() ?? ''].where((v) => v.isNotEmpty).join('\n'), style: const TextStyle(color: PCWorkColors.textSecondary, fontSize: 11, height: 1.4)), isThreeLine: true, trailing: (type == 'part' || type == 'work' || type == 'diagnostic' || type == 'payment') ? Text(_money(total), style: TextStyle(color: accent, fontWeight: FontWeight.w900)) : null))); }),
    ])),
  );
}
