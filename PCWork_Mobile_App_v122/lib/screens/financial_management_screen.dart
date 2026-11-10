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
  String? error;
  Map<String, dynamic> report = {};
  List<Map<String, dynamic>> expenses = [];
  final from = TextEditingController();
  final to = TextEditingController();
  final location = TextEditingController();
  final description = TextEditingController();
  final amount = TextEditingController();
  String category = 'other';
  bool saving = false;
  String tr(String bg, String en) => widget.english ? en : bg;

  @override
  void initState() { super.initState(); final now=DateTime.now(); from.text='${now.year}-${now.month.toString().padLeft(2,'0')}-01'; to.text='${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}'; _load(); }
  @override
  void dispose() { from.dispose(); to.dispose(); location.dispose(); description.dispose(); amount.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { loading=true; error=null; });
    try {
      final results=await Future.wait([
        widget.api.getFinancialReport(widget.token,from:from.text,to:to.text),
        widget.api.getFinancialExpenses(widget.token,from:from.text,to:to.text),
      ]);
      if(!mounted)return;
      setState(() { report=Map<String,dynamic>.from(results[0] as Map); expenses=(results[1] as List<Map<String,dynamic>>); loading=false; });
    } catch(e) { if(mounted)setState(() { error=e.toString();loading=false; }); }
  }

  Future<void> _addExpense() async {
    if(location.text.trim().isEmpty||description.text.trim().isEmpty||(double.tryParse(amount.text.replaceAll(',','.'))??0)<=0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(tr('Попълни обект, описание и валидна сума.','Enter location, description and a valid amount.')))); return;
    }
    setState(()=>saving=true);
    try {
      await widget.api.createFinancialExpense(widget.token, {'location_code':location.text.trim(),'description':description.text.trim(),'amount':double.parse(amount.text.replaceAll(',','.')),'category':category,'expense_date':DateTime.now().toIso8601String().substring(0,10)});
      description.clear();amount.clear();if(mounted)Navigator.of(context).pop();
      await _load();
    } catch(e) { if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString()))); }
    finally { if(mounted)setState(()=>saving=false); }
  }

  void _expenseDialog() {
    showDialog(context:context,builder:(ctx)=>AlertDialog(
      title:Text(tr('Нов разход','New expense')),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:location,decoration:InputDecoration(labelText:tr('Код на сервизен обект','Service location code'))),
        TextField(controller:description,decoration:InputDecoration(labelText:tr('Описание','Description'))),
        TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:tr('Сума (лв.)','Amount (BGN)'))),
        DropdownButtonFormField<String>(initialValue:category,decoration:InputDecoration(labelText:tr('Категория','Category')),items:const ['rent','utilities','salary','parts','transport','marketing','other'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState(()=>category=v??'other')),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(tr('Отказ','Cancel'))),FilledButton(onPressed:saving?null:_addExpense,child:Text(tr('Запиши','Save')))],
    ));
  }

  String money(dynamic v) => '${(double.tryParse('$v')??0).toStringAsFixed(2)} лв.';
  Widget metric(String title,dynamic value) => Card(child:ListTile(title:Text(title),trailing:Text(money(value),style:const TextStyle(fontWeight:FontWeight.bold))));
  @override
  Widget build(BuildContext context) {
    final totals=(report['totals'] is Map)?Map<String,dynamic>.from(report['totals']):<String,dynamic>{};
    return Scaffold(appBar:AppBar(title:Text(tr('Финанси','Finances')),actions:[IconButton(onPressed:_load,icon:const Icon(Icons.refresh))]),floatingActionButton:FloatingActionButton.extended(onPressed:_expenseDialog,icon:const Icon(Icons.add),label:Text(tr('Разход','Expense'))),body:loading?const Center(child:CircularProgressIndicator()):error!=null?Center(child:Padding(padding:const EdgeInsets.all(20),child:Text(error!))):RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.all(12),children:[
      Row(children:[Expanded(child:TextField(controller:from,decoration:InputDecoration(labelText:tr('От дата','From')))),const SizedBox(width:8),Expanded(child:TextField(controller:to,decoration:InputDecoration(labelText:tr('До дата','To')))),IconButton(onPressed:_load,icon:const Icon(Icons.search))]),
      metric(tr('Приходи','Income'),totals['income']),metric(tr('Разходи за части','Parts cost'),totals['parts_cost']),metric(tr('Други разходи','Other expenses'),totals['other_expenses']),metric(tr('Общи разходи','Total costs'),totals['total_cost']),metric(tr('Печалба','Profit'),totals['profit']),
      const SizedBox(height:12),Text(tr('По сервизни обекти','By locations'),style:Theme.of(context).textTheme.titleMedium),
      ...((report['by_location'] as List?)??[]).whereType<Map>().map((r)=>ListTile(title:Text('${r['location_name']??r['location_code']??''}'),trailing:Text(money(r['income'])))),
      Text(tr('По служители','By employees'),style:Theme.of(context).textTheme.titleMedium),
      ...((report['by_employee'] as List?)??[]).whereType<Map>().map((r)=>ListTile(title:Text('${r['display_name']??'—'}'),trailing:Text(money(r['income'])))),
      Text(tr('По ремонти','By repairs'),style:Theme.of(context).textTheme.titleMedium),
      ...((report['by_repair'] as List?)??[]).whereType<Map>().map((r)=>ListTile(title:Text('${r['repair_number']??r['repair_id']??''}'),subtitle:Text('${tr('Приходи','Income')}: ${money(r['income'])} • ${tr('Части','Parts')}: ${money(r['parts_cost'])} • ${tr('Други','Other')}: ${money(r['other_expenses'])}'),trailing:Text(money((double.tryParse('${r['income']}')??0)-(double.tryParse('${r['parts_cost']}')??0)-(double.tryParse('${r['other_expenses']}')??0))))),
      Text(tr('Разходи по категории','Expenses by category'),style:Theme.of(context).textTheme.titleMedium),
      ...((report['expenses_by_category'] as List?)??[]).whereType<Map>().map((r)=>ListTile(title:Text('${r['category']??''}'),trailing:Text(money(r['total'])))),
      Text(tr('Разходи','Expenses'),style:Theme.of(context).textTheme.titleMedium),
      ...expenses.map((e)=>ListTile(title:Text('${e['description']??''}'),subtitle:Text('${e['expense_date']??''} • ${e['category']??''} • ${e['location_code']??''}'),trailing:Text(money(e['amount'])))),
    ])));
  }
}
