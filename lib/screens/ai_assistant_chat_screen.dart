import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AiAssistantChatScreen extends StatefulWidget {
  const AiAssistantChatScreen({super.key, required this.api, required this.token, required this.english, this.staffMode = false});
  final ApiService api;
  final String token;
  final bool english;
  final bool staffMode;
  @override
  State<AiAssistantChatScreen> createState() => _AiAssistantChatScreenState();
}

class _AiAssistantChatScreenState extends State<AiAssistantChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _sending = false;
  String tr(String bg, String en) => widget.english ? en : bg;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? suppliedText]) async {
    final text = (suppliedText ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _sending = true;
    });
    _toBottom();
    try {
      // Keep the most recent conversation turns to avoid oversized requests.
      final history = _messages.length > 31 ? _messages.sublist(_messages.length - 31) : _messages;
      final answer = await widget.api.sendAiMessage(
        widget.token,
        history.map((m) => Map<String, String>.from(m)).toList(),
      );
      if (!mounted) return;
      setState(() => _messages.add({'role': 'assistant', 'content': answer}));
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add({
        'role': 'assistant',
        'content': '${tr('Не успях да получа отговор: ', 'I could not get a response: ')}${e.toString().replaceFirst('Exception: ', '')}',
      }));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _toBottom();
      }
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _openDiagnosticBuilder() async {
    final device = TextEditingController();
    final model = TextEditingController();
    final symptoms = TextEditingController();
    final history = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final prompt = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(18, 4, 18, MediaQuery.of(sheetContext).viewInsets.bottom + 18),
        child: StatefulBuilder(builder: (context, refresh) => Form(
          key: formKey,
          child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('Структурирана диагностика', 'Structured diagnostics'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text(tr('Опиши устройството и симптомите. Асистентът ще предложи последователни безопасни проверки.', 'Describe the device and symptoms. The assistant will suggest a sequence of safe checks.'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 14),
              TextFormField(controller: device, decoration: InputDecoration(labelText: tr('Тип устройство *', 'Device type *'), hintText: 'PS5, лаптоп, настолен компютър'), validator: (v) => (v ?? '').trim().isEmpty ? tr('Въведи тип устройство.', 'Enter a device type.') : null),
              const SizedBox(height: 9),
              TextFormField(controller: model, decoration: InputDecoration(labelText: tr('Марка и модел', 'Brand and model'))),
              const SizedBox(height: 9),
              TextFormField(controller: symptoms, minLines: 3, maxLines: 5, decoration: InputDecoration(labelText: tr('Симптоми и грешки *', 'Symptoms and errors *'), hintText: tr('Какво се случва? Кога започва проблемът?', 'What happens? When did the problem start?')), validator: (v) => (v ?? '').trim().isEmpty ? tr('Опиши симптомите.', 'Describe the symptoms.') : null),
              const SizedBox(height: 9),
              TextFormField(controller: history, minLines: 2, maxLines: 3, decoration: InputDecoration(labelText: tr('Предишни ремонти и направени проверки', 'Previous repairs and checks'))),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  final value = [
                    tr('Направи структурирана техническа диагностика на следното устройство:', 'Prepare a structured technical diagnosis for this device:'),
                    '${tr('Устройство', 'Device')}: ${device.text.trim()}',
                    if (model.text.trim().isNotEmpty) '${tr('Марка/модел', 'Brand/model')}: ${model.text.trim()}',
                    '${tr('Симптоми', 'Symptoms')}: ${symptoms.text.trim()}',
                    if (history.text.trim().isNotEmpty) '${tr('Предишни ремонти/проверки', 'Previous repairs/checks')}: ${history.text.trim()}',
                    tr('Дай вероятни причини, подреди проверките от най-безопасните и лесни към по-сложните, посочи нужните инструменти и измервания, предупреди за рискове и кажи какви резултати биха потвърдили или отхвърлили всяка хипотеза. Не представяй предположение като сигурна диагноза.', 'List likely causes, order checks from safest and easiest to more complex, identify tools and measurements, flag risks, and explain what results would confirm or reject each hypothesis. Do not present assumptions as a confirmed diagnosis.'),
                  ].join('\n');
                  Navigator.pop(sheetContext, value);
                },
                icon: const Icon(Icons.manage_search_rounded),
                label: Text(tr('Изпрати за анализ', 'Send for analysis')),
              )),
            ],
          )),
        )),
      ),
    );
    device.dispose(); model.dispose(); symptoms.dispose(); history.dispose();
    if (prompt != null && mounted) await _send(prompt);
  }

  Widget _suggestion(String label, IconData icon, String prompt) => ActionChip(
    avatar: Icon(icon, size: 17, color: const Color(0xFF21D4D8)),
    label: Text(label),
    onPressed: _sending ? null : () => _send(prompt),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr('PCWork AI асистент', 'PCWork AI Assistant')),
      actions: [
        if (_messages.isNotEmpty) IconButton(
          tooltip: tr('Изчисти разговора', 'Clear conversation'),
          onPressed: _sending ? null : () => setState(_messages.clear),
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
      ],
    ),
    body: Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        color: const Color(0xFF102C3A),
        child: Row(children: [
          const Icon(Icons.auto_awesome, color: Color(0xFF21D4D8), size: 28),
          const SizedBox(width: 10),
          Expanded(child: Text(
            widget.staffMode
                ? tr('Сервизен режим: диагностика, измервания, ремонтни процедури и подбор на части. Проверявай критичните стойности по документацията на производителя.', 'Service mode: diagnostics, measurements, repair procedures and parts selection. Verify critical values against manufacturer documentation.')
                : tr('Помощ за устройства, симптоми и услуги на PCWork. Не споделяй пароли или платежни данни.', 'Help with devices, symptoms and PCWork services. Do not share passwords or payment details.'),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          )),
        ]),
      ),
      if (_messages.isEmpty) Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 26, 18, 14),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.support_agent_rounded, size: 58, color: Color(0xFF21D4D8)),
          const SizedBox(height: 12),
          Text(tr('Здравей! С какво мога да помогна?', 'Hello! How can I help?'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 7),
          Text(tr('Избери готова тема или опиши въпроса си.', 'Choose a topic or describe your question.'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 18),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            _suggestion(tr('Диагностика', 'Diagnostics'), Icons.manage_search_rounded, tr('Как да подходя към диагностика на устройство, което не се включва? Дай безопасна последователност от проверки.', 'How should I diagnose a device that will not power on? Give a safe sequence of checks.')),
            _suggestion(tr('Прегряване', 'Overheating'), Icons.thermostat_rounded, tr('Какви са възможните причини за прегряване и как да ги проверя безопасно?', 'What can cause overheating and how can I check safely?')),
            _suggestion(tr('Подбор на части', 'Parts selection'), Icons.memory_rounded, tr('Помогни ми да проверя съвместимостта на резервни части. Каква информация ти е необходима?', 'Help me verify replacement-part compatibility. What information do you need?')),
            _suggestion(tr('Профилактика', 'Maintenance'), Icons.cleaning_services_outlined, tr('Създай контролен списък за профилактика на игрова конзола.', 'Create a maintenance checklist for a game console.')),
            if (widget.staffMode) _suggestion(tr('Оценка на ремонт', 'Repair estimate'), Icons.calculate_outlined, tr('Какви данни са нужни за реалистична предварителна оценка на ремонт и труд?', 'What information is needed for a realistic preliminary repair and labor estimate?')),
          ]),
          if (widget.staffMode) ...[
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _openDiagnosticBuilder, icon: const Icon(Icons.assignment_turned_in_outlined), label: Text(tr('Създай диагностичен протокол', 'Build a diagnostic brief')))),
          ],
        ]),
      )) else Expanded(child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(14),
        itemCount: _messages.length + (_sending ? 1 : 0),
        itemBuilder: (context, index) {
          if (_sending && index == _messages.length) return const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))));
          final message = _messages[index];
          final mine = message['role'] == 'user';
          return Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .84),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(color: mine ? const Color(0xFF164B5B) : Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
              child: SelectableText(message['content'] ?? '', style: TextStyle(color: mine ? Colors.white : null, height: 1.35)),
            ),
          );
        },
      )),
      if (_messages.isNotEmpty && widget.staffMode) Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _sending ? null : _openDiagnosticBuilder, icon: const Icon(Icons.playlist_add_check_rounded, size: 18), label: Text(tr('Нова структурирана диагностика', 'New structured diagnosis')))),
      ),
      SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(children: [
          Expanded(child: TextField(controller: _input, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(), decoration: InputDecoration(hintText: tr('Напиши въпрос…', 'Ask a question…'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)))),
          const SizedBox(width: 8),
          IconButton.filled(onPressed: _sending ? null : _send, icon: const Icon(Icons.send_rounded)),
        ]),
      )),
    ]),
  );
}
