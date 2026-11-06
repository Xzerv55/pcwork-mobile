import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/api_service.dart';

class ChatyScreen extends StatefulWidget {
  const ChatyScreen({super.key, required this.api});
  final ApiService api;
  @override
  State<ChatyScreen> createState() => _ChatyScreenState();
}

class _ChatyScreenState extends State<ChatyScreen> {
  late Future<Uri?> _url;
  WebViewController? _controller;
  Timer? _checkTimer;
  int _progress = 0;
  bool _started = false;
  String? _error;

  @override
  void initState() { super.initState(); _url = widget.api.getChatyUrl(); }

  void _load(Uri url) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0A101A))
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (value) { if (mounted) setState(() => _progress = value); },
        onPageFinished: (_) {
          _checkTimer?.cancel();
          _checkTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
            if (!mounted) { timer.cancel(); return; }
            try {
              final result = await controller.runJavaScriptReturningResult("(function(){if(typeof window.launch_chaty==='function'){window.launch_chaty();return 'ready';}return 'waiting';})()");
              if (result.toString().contains('ready')) { timer.cancel(); }
              else if (timer.tick >= 24) { timer.cancel(); if (mounted) setState(() => _error = 'Chaty е активен, но бутоните не се появиха на тази страница. Провери настройките за показване на мобилни устройства и правилата за страници в Chaty.'); }
            } catch (_) { if (timer.tick >= 24) { timer.cancel(); if (mounted) setState(() => _error = 'Не успяхме да стартираме Chaty. Провери дали скриптът не е блокиран от кеширане или защита.'); } }
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
      ..loadRequest(url);
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
      if (snapshot.hasError) return _state('Chaty не може да бъде проверен', '${snapshot.error}');
      final url = snapshot.data;
      if (url == null) return _state('Chaty не е активен', 'В WordPress отвори PCWork Mobile → Интеграции → Chaty. Активирай Chaty и провери дали официалният плъгин Chaty е инсталиран и активен.');
      if (!_started) { _started = true; WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && _controller == null) _load(url); }); }
      if (_error != null) return _state('Проблем при зареждането на Chaty', _error!);
      return Column(children: [if (_progress < 100) LinearProgressIndicator(value: _progress == 0 ? null : _progress / 100), Expanded(child: _controller == null ? const Center(child: CircularProgressIndicator()) : WebViewWidget(controller: _controller!))]);
    },
  );

  Widget _state(String title, String message) => Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.chat_bubble_outline, size: 48, color: Color(0xFF21D4D8)), const SizedBox(height: 12), Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center), const SizedBox(height: 8), Text(message, textAlign: TextAlign.center), const SizedBox(height: 16), FilledButton.icon(onPressed: _retry, icon: const Icon(Icons.refresh), label: const Text('Провери отново'))])))));
}
