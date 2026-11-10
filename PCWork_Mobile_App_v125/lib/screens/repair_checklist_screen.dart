import 'package:flutter/material.dart';
import '../services/api_service.dart';

class RepairChecklistScreen extends StatefulWidget {
  const RepairChecklistScreen({super.key, required this.api, required this.token, required this.repairId, required this.repairNumber, required this.isStaff});
  final ApiService api;
  final String token;
  final int repairId;
  final String repairNumber;
  final bool isStaff;
  @override
  State<RepairChecklistScreen> createState() => _RepairChecklistScreenState();
}

class _RepairChecklistScreenState extends State<RepairChecklistScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final data = await widget.api.getRepairChecklist(widget.token, widget.repairId);
      if (!mounted) return;
      setState(() { _items = data['items'] as List<Map<String, dynamic>>; _loading = false; });
    } catch (e) { if (mounted) setState(() { _error = e.toString(); _loading = false; }); }
  }
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.api.saveRepairChecklist(widget.token, widget.repairId, _items);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Контролният списък е записан.')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Неуспешен запис: $e'))); }
    finally { if (mounted) setState(() => _saving = false); }
  }
  @override
  Widget build(BuildContext context) {
    final checked = _items.where((item) => item['checked'] == true).length;
    return Scaffold(
      appBar: AppBar(title: Text('Контролен списък · ${widget.repairNumber}'), actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))]),
      bottomNavigationBar: widget.isStaff && !_loading ? SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined), label: const Text('Запази проверките')))) : null,
      body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton(onPressed: _load, child: const Text('Опитай отново'))]))) : ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Готовност на ремонта', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 10), LinearProgressIndicator(value: _items.isEmpty ? 0 : checked / _items.length, minHeight: 8), const SizedBox(height: 8), Text('$checked от ${_items.length} проверки изпълнени')]))),
        if (!widget.isStaff) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Това е информационен преглед. Промените се извършват от сервизния екип.')),
        ..._items.asMap().entries.map((entry) { final index = entry.key; final item = entry.value; return Card(child: CheckboxListTile(value: item['checked'] == true, onChanged: widget.isStaff ? (value) => setState(() => _items[index] = {...item, 'checked': value == true}) : null, title: Text((item['label'] ?? '').toString()), subtitle: (item['updated_at'] ?? '').toString().isEmpty ? null : Text((item['updated_at'] ?? '').toString()), controlAffinity: ListTileControlAffinity.leading)); }),
      ]),
    );
  }
}
