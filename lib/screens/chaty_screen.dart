import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/api_service.dart';

class ChatyScreen extends StatefulWidget {
  const ChatyScreen({super.key, required this.api, required this.english});
  final ApiService api;
  final bool english;
  @override
  State<ChatyScreen> createState() => _ChatyScreenState();
}

class _ChatyScreenState extends State<ChatyScreen> {
  String tr(String bg, String en) => widget.english ? en : bg;
  late Future<Uri?> _url;
  WebViewController? _controller;
  Timer? _checkTimer;
  int _progress = 0;
  bool _started = false;
  String? _error;

  @override
  void initState() { super.initState(); _url = widget.api.getChatyUrl(); }

  void _load(Uri url) {
    // Declare before the navigation delegate so its callbacks can safely capture it.
    late final WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0A101A))
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (value) { if (mounted) setState(() => _progress = value); },
        onPageFinished: (_) {
          unawaited(controller.runJavaScript("document.documentElement.lang='${widget.english ? 'en' : 'bg'}'; document.documentElement.setAttribute('lang','${widget.english ? 'en' : 'bg'}');"));
          _checkTimer?.cancel();
          _checkTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
            if (!mounted) { timer.cancel(); return; }
            try {
              final result = await controller.runJavaScriptReturningResult("(function(){if(typeof window.launch_chaty==='function'){window.launch_chaty();return 'ready';}return 'waiting';})()");
              if (result.toString().contains('ready')) { timer.cancel(); }
              else if (timer.tick >= 24) { timer.cancel(); if (mounted) setState(() => _error = tr('Chaty е активен, но бутоните не се появиха на тази страница. Провери настройките за показване на мобилни устройства и правилата за страници в Chaty.', 'Chaty is active, but its buttons did not appear on this page. Check mobile display settings and Chaty page rules.')); }
            } catch (_) { if (timer.tick >= 24) { timer.cancel(); if (mounted) setState(() => _error = tr('Не успяхме да стартираме Chaty. Провери дали скриптът не е блокиран от кеширане или защита.', 'Could not start Chaty. Check whether caching or security settings are blocking its script.')); } }
          });
        },
        onWebResourceError: (error) { if (error.isForMainFrame == true && mounted) setState(() => _error = error.description); },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          final host = uri.host.toLowerCase();
          if (host == 'pcwork-bg.com' || host == 'www.pcwork-bg.com') return NavigationDecision.navigate;
          if (['https','http','mailto','tel','sms','whatsapp','viber','tg'].contains(uri.scheme)) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(url, headers: {'Accept-Language': widget.english ? 'en-US,en;q=0.9' : 'bg-BG,bg;q=0.9'});
    setState(() => _controller = controller);
  }

  void _retry() { setState(() { _error = null; _progress = 0; _started = false; _controller = null; _url = widget.api.getChatyUrl(); }); }

  @override
  void dispose() { _checkTimer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uri?>(
    future: _url,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return _state(tr('Chaty не може да бъде проверен', 'Chaty could not be checked'), '${snapshot.error}');
      final url = snapshot.data;
      if (url == null) return _state(tr('Chaty не е активен', 'Chaty is not active'), tr('В WordPress отвори PCWork Mobile → Интеграции → Chaty. Активирай Chaty и провери дали официалният плъгин Chaty е инсталиран и активен.', 'In WordPress, open PCWork Mobile → Integrations → Chaty. Enable Chaty and make sure the official Chaty plugin is installed and active.'));
      if (!_started) { _started = true; WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && _controller == null) _load(url); }); }
      if (_error != null) return _state(tr('Проблем при зареждането на Chaty', 'There was a problem loading Chaty'), _error!);
      return Column(children: [if (_progress < 100) LinearProgressIndicator(value: _progress == 0 ? null : _progress / 100), Expanded(child: _controller == null ? const Center(child: CircularProgressIndicator()) : WebViewWidget(controller: _controller!))]);
    },
  );

  Widget _state(String title, String message) => Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.chat_bubble_outline, size: 48, color: Color(0xFF21D4D8)), const SizedBox(height: 12), Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center), const SizedBox(height: 8), Text(message, textAlign: TextAlign.center), const SizedBox(height: 16), FilledButton.icon(onPressed: _retry, icon: const Icon(Icons.refresh), label: Text(tr('Провери отново', 'Try again')))])))));
}
