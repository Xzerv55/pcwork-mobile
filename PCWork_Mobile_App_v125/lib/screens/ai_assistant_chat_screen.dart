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
  void dispose() { _input.dispose(); _scroll.dispose(); super.dispose(); }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() { _messages.add({'role':'user','content':text}); _sending = true; });
    _toBottom();
    try {
      final answer = await widget.api.sendAiMessage(widget.token, _messages.map((m) => Map<String, String>.from(m)).toList());
      if (!mounted) return;
      setState(() => _messages.add({'role':'assistant','content':answer}));
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add({'role':'assistant','content':'${tr('Не успях да получа отговор: ', 'I could not get a response: ')}${e.toString().replaceFirst('Exception: ', '')}'}));
    } finally {
      if (mounted) { setState(() => _sending = false); _toBottom(); }
    }
  }

  void _toBottom() { WidgetsBinding.instance.addPostFrameCallback((_) { if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut); }); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('PCWork AI асистент', 'PCWork AI Assistant'))),
    body: Column(children: [
      Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(16, 12, 16, 14), color: const Color(0xFF102C3A), child: Row(children: [const Icon(Icons.auto_awesome, color: Color(0xFF21D4D8), size: 28), const SizedBox(width: 10), Expanded(child: Text(tr('Локален AI модел чрез LM Studio. Не споделяй пароли или платежни данни.', 'Local AI model via LM Studio. Do not share passwords or payment details.'), style: const TextStyle(color: Colors.white, fontSize: 12)))])),
      Expanded(child: _messages.isEmpty ? Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.support_agent_rounded, size: 54, color: Color(0xFF21D4D8)), const SizedBox(height: 12), Text(tr('Здравей! С какво мога да помогна?', 'Hello! How can I help?'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), const SizedBox(height: 6), Text(tr('Попитай за компютри, лаптопи, конзоли, профилактика или услугите на PCWork.', 'Ask about computers, laptops, consoles, maintenance or PCWork services.'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey))]))) : ListView.builder(controller: _scroll, padding: const EdgeInsets.all(14), itemCount: _messages.length + (_sending ? 1 : 0), itemBuilder: (context, index) {
        if (_sending && index == _messages.length) return const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))));
        final message = _messages[index]; final mine = message['role'] == 'user';
        return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .84), margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11), decoration: BoxDecoration(color: mine ? const Color(0xFF164B5B) : Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)), child: SelectableText(message['content'] ?? '', style: TextStyle(color: mine ? Colors.white : null, height: 1.35))));
      })),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), child: Row(children: [Expanded(child: TextField(controller: _input, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(), decoration: InputDecoration(hintText: tr('Напиши въпрос…', 'Ask a question…'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)))), const SizedBox(width: 8), IconButton.filled(onPressed: _sending ? null : _send, icon: const Icon(Icons.send_rounded))]))),
    ]),
  );
}
