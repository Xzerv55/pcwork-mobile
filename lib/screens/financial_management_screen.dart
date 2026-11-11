import 'package:flutter/material.dart';
import '../services/api_service.dart';

class FinancialManagementScreen extends StatefulWidget {
  const FinancialManagementScreen({super.key, required this.api, required this.token, required this.english});
  final ApiService api;
  final String token;
  final bool english;

  @override
  State<FinancialManagementScreen> createState() => _FinancialManagementScreenState();
}

class _FinancialManagementScreenState extends State<FinancialManagementScreen> {
  bool loading = true;
  bool saving = false;
  String? error;
  Map<String, dynamic> report = {};
  List<Map<String, dynamic>> expenses = [];
  final from = TextEditingController();
  final to = TextEditingController();
  final location = TextEditingController();
  final description = TextEditingController();
  final amount = TextEditingController();
  final expenseDate = TextEditingController();
  String category = 'other';
  int? editingExpenseId;

  String tr(String bg, String en) => widget.english ? en : bg;
  String _date(DateTime value) => '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    from.text = _date(DateTime(now.year, now.month, 1));
    to.text = _date(now);
    _load();
  }

  @override
  void dispose() {
    from.dispose(); to.dispose(); location.dispose(); description.dispose(); amount.dispose(); expenseDate.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final start = DateTime.tryParse(from.text.trim());
    final end = DateTime.tryParse(to.text.trim());
    if (start == null || end == null || start.isAfter(end)) {
      setState(() { error = tr('Провери началната и крайната дата.','Check the start and end dates.'); loading = false; });
      return;
    }
    setState(() { loading = true; error = null; });
    try {
      final results = await Future.wait([
        widget.api.getFinancialReport(widget.token, from: from.text.trim(), to: to.text.trim()),
        widget.api.getFinancialExpenses(widget.token, from: from.text.trim(), to: to.text.trim()),
      ]);
      if (!mounted) return;
      setState(() {
        report = Map<String, dynamic>.from(results[0] as Map);
        expenses = results[1] as List<Map<String, dynamic>>;
        loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { error = e.toString(); loading = false; });
    }
  }

  Future<void> _selectDate(TextEditingController controller) async {
    final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2018), lastDate: DateTime(2100));
    if (picked != null) setState(() => controller.text = _date(picked));
  }

  void _setPeriod(int days) {
    final now = DateTime.now();
    final start = days == 0 ? DateTime(now.year, now.month, 1) : DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
    setState(() { from.text = _date(start); to.text = _date(now); });
    _load();
  }

  double _number(dynamic value) => double.tryParse('$value') ?? 0;
  String money(dynamic value) => '${_number(value).toStringAsFixed(2)} €';
  String _categoryName(String value) => switch (value) {
    'rent' => tr('Наем','Rent'), 'utilities' => tr('Комунални услуги','Utilities'),
    'salary' => tr('Заплати','Salaries'), 'parts' => tr('Части','Parts'),
    'transport' => tr('Транспорт','Transport'), 'marketing' => tr('Маркетинг','Marketing'),
    _ => tr('Други','Other'),
  };

  Future<void> _saveExpense() async {
    final value = double.tryParse(amount.text.trim().replaceAll(',', '.')) ?? 0;
    final date = DateTime.tryParse(expenseDate.text.trim());
    if (location.text.trim().isEmpty || description.text.trim().isEmpty || value <= 0 || date == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Попълни обект, описание, дата и валидна сума.','Enter a location, description, date and valid amount.'))));
      return;
    }
    setState(() => saving = true);
    try {
      final payload = {'description': description.text.trim(), 'amount': value, 'category': category, 'expense_date': expenseDate.text.trim()};
      if (editingExpenseId == null) {
        await widget.api.createFinancialExpense(widget.token, {...payload, 'location_code': location.text.trim()});
      } else {
        await widget.api.updateFinancialExpense(widget.token, editingExpenseId!, payload);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _expenseDialog({Map<String, dynamic>? expense}) {
    editingExpenseId = expense == null ? null : int.tryParse('${expense['id']}');
    location.text = '${expense?['location_code'] ?? ''}';
    description.text = '${expense?['description'] ?? ''}';
    amount.text = expense == null ? '' : '${expense['amount'] ?? ''}';
    category = '${expense?['category'] ?? 'other'}';
    expenseDate.text = '${expense?['expense_date'] ?? _date(DateTime.now())}';
    showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, refreshDialog) => AlertDialog(
      title: Text(expense == null ? tr('Нов разход','New expense') : tr('Редакция на разход','Edit expense')),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (expense == null) TextField(controller: location, decoration: InputDecoration(labelText: tr('Код на сервизен обект','Service location code'))),
        TextField(controller: description, maxLength: 190, decoration: InputDecoration(labelText: tr('Описание','Description'))),
        TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('Сума (€)','Amount (€)'))),
        TextField(controller: expenseDate, readOnly: true, onTap: () async { await _selectDate(expenseDate); refreshDialog(() {}); }, decoration: InputDecoration(labelText: tr('Дата','Date'), suffixIcon: const Icon(Icons.calendar_today))),
        DropdownButtonFormField<String>(
          initialValue: ['rent','utilities','salary','parts','transport','marketing','other'].contains(category) ? category : 'other',
          decoration: InputDecoration(labelText: tr('Категория','Category')),
          items: const ['rent','utilities','salary','parts','transport','marketing','other'].map((v) => DropdownMenuItem(value: v, child: Text(_categoryName(v)))).toList(),
          onChanged: (v) => refreshDialog(() => category = v ?? 'other'),
        ),
      ])),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: Text(tr('Отказ','Cancel'))),
        FilledButton(onPressed: saving ? null : _saveExpense, child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr('Запиши','Save'))),
      ],
    )));
  }

  Widget _metric(String title, dynamic value, IconData icon, {bool prominent = false}) => Card(
    elevation: 0,
    color: prominent ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 21), const SizedBox(height: 10),
      Text(title, style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 5),
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value is String ? value : money(value), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
    ])),
  );

  Widget _sectionTitle(String title, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: Row(children: [Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))), if (trailing != null) trailing]),
  );

  Widget _rankedBars(List<dynamic> rows, String labelKey, String valueKey) {
    final valid = rows.whereType<Map>().toList();
    if (valid.isEmpty) return Padding(padding: const EdgeInsets.all(12), child: Text(tr('Няма данни за избрания период.','No data for the selected period.'), style: Theme.of(context).textTheme.bodySmall));
    final maxValue = valid.fold<double>(0, (m, row) => _number(row[valueKey]) > m ? _number(row[valueKey]) : m);
    return Column(children: valid.take(8).map((row) {
      final value = _number(row[valueKey]);
      final fraction = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
      return Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text('${row[labelKey] ?? '—'}', maxLines: 1, overflow: TextOverflow.ellipsis)), Text(money(value), style: const TextStyle(fontWeight: FontWeight.w600))]),
        const SizedBox(height: 5), ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: fraction, minHeight: 7)),
      ]));
    }).toList());
  }

  @override
  Widget build(BuildContext context) {
    final totals = report['totals'] is Map ? Map<String, dynamic>.from(report['totals']) : <String, dynamic>{};
    final income = _number(totals['income']);
    final profit = _number(totals['profit']);
    final margin = income > 0 ? profit / income * 100 : 0.0;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Финансово табло','Financial dashboard')), actions: [IconButton(tooltip: tr('Обнови','Refresh'), onPressed: _load, icon: const Icon(Icons.refresh))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _expenseDialog(), icon: const Icon(Icons.add), label: Text(tr('Нов разход','New expense'))),
      body: loading ? const Center(child: CircularProgressIndicator()) : error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off_outlined, size: 42), const SizedBox(height: 12), Text(error!, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(tr('Опитай отново','Try again')))]))) : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 90), children: [
        Card(elevation: 0, color: Theme.of(context).colorScheme.surfaceContainerLow, child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () => _selectDate(from), icon: const Icon(Icons.calendar_today, size: 16), label: Text('${tr('От','From')}: ${from.text}'))), const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: () => _selectDate(to), icon: const Icon(Icons.event, size: 16), label: Text('${tr('До','To')}: ${to.text}')))]),
          const SizedBox(height: 8),
          Wrap(spacing: 7, runSpacing: 4, alignment: WrapAlignment.center, children: [
            ActionChip(label: Text(tr('Този месец','This month')), onPressed: () => _setPeriod(0)),
            ActionChip(label: Text(tr('7 дни','7 days')), onPressed: () => _setPeriod(7)),
            ActionChip(label: Text(tr('30 дни','30 days')), onPressed: () => _setPeriod(30)),
            ActionChip(label: Text(tr('90 дни','90 days')), onPressed: () => _setPeriod(90)),
          ]),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _load, icon: const Icon(Icons.filter_alt), label: Text(tr('Приложи периода','Apply period')))),
        ]))),
        GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 3 : 2, childAspectRatio: 1.55, crossAxisSpacing: 9, mainAxisSpacing: 9, children: [
          _metric(tr('Приходи','Income'), totals['income'], Icons.trending_up),
          _metric(tr('Печалба','Profit'), totals['profit'], Icons.account_balance_wallet_outlined, prominent: true),
          _metric(tr('Разходи за части','Parts cost'), totals['parts_cost'], Icons.build_outlined),
          _metric(tr('Други разходи','Other expenses'), totals['other_expenses'], Icons.receipt_long_outlined),
          _metric(tr('Общи разходи','Total costs'), totals['total_cost'], Icons.payments_outlined),
          _metric(tr('Марж','Margin'), '${margin.toStringAsFixed(1)}%', Icons.percent),
        ]),
        _sectionTitle(tr('Приходи по сервизни обекти','Income by service location')),
        Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(12), child: _rankedBars((report['by_location'] as List?) ?? [], 'location_name', 'income'))),
        _sectionTitle(tr('Приходи по служители','Income by employees')),
        Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(12), child: _rankedBars((report['by_employee'] as List?) ?? [], 'display_name', 'income'))),
        _sectionTitle(tr('Резултат по ремонти','Repair profitability')),
        ...((report['by_repair'] as List?) ?? []).whereType<Map>().take(30).map((row) {
          final repairIncome = _number(row['income']);
          final costs = _number(row['parts_cost']) + _number(row['other_expenses']);
          final result = repairIncome - costs;
          return Card(elevation: 0, child: ListTile(
            leading: CircleAvatar(child: Icon(result >= 0 ? Icons.trending_up : Icons.trending_down)),
            title: Text('${row['repair_number'] ?? '#${row['repair_id'] ?? ''}'}'),
            subtitle: Text('${tr('Приходи','Income')}: ${money(repairIncome)}  •  ${tr('Разходи','Costs')}: ${money(costs)}'),
            trailing: Text(money(result), style: TextStyle(fontWeight: FontWeight.bold, color: result >= 0 ? Colors.green : Theme.of(context).colorScheme.error)),
          ));
        }),
        _sectionTitle(tr('Разходи по категории','Expenses by category')),
        Card(elevation: 0, child: Column(children: [
          ...((report['expenses_by_category'] as List?) ?? []).whereType<Map>().map((row) => ListTile(dense: true, title: Text(_categoryName('${row['category'] ?? 'other'}')), trailing: Text(money(row['total']), style: const TextStyle(fontWeight: FontWeight.w600)))),
          if (((report['expenses_by_category'] as List?) ?? []).isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(tr('Няма отчетени разходи.','No expenses recorded.'))),
        ])),
        _sectionTitle(tr('Регистър на разходите','Expense register'), trailing: Text('${expenses.length}', style: Theme.of(context).textTheme.labelLarge)),
        if (expenses.isEmpty) Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(16), child: Text(tr('Няма разходи за избрания период.','No expenses for the selected period.')))),
        ...expenses.map((expense) => Card(elevation: 0, child: ListTile(
          onTap: () => _expenseDialog(expense: expense),
          leading: const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
          title: Text('${expense['description'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${expense['expense_date'] ?? ''} • ${_categoryName('${expense['category'] ?? 'other'}')} • ${expense['location_code'] ?? ''}'),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(money(expense['amount']), style: const TextStyle(fontWeight: FontWeight.bold)), const Icon(Icons.edit_outlined, size: 15)]),
        ))),
        Padding(padding: const EdgeInsets.only(top: 12), child: Text(tr('Финансовите стойности са в EUR и се изчисляват от записаните сервизни дейности, складови движения и въведени разходи. Те не представляват непременно реално получени плащания.','Financial values are in EUR and are calculated from recorded service work, stock movements and entered expenses. They do not necessarily represent payments actually received.'), style: Theme.of(context).textTheme.bodySmall)),
      ])),
    );
  }
}
