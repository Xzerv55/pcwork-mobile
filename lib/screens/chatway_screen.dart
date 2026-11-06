import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/api_service.dart';

class ChatwayScreen extends StatefulWidget {
  const ChatwayScreen({super.key, required this.api, required this.tokenProvider, required this.sessionKey});
  final ApiService api;
  final Future<String?> Function() tokenProvider;
  final int sessionKey;

  @override
  State<ChatwayScreen> createState() => _ChatwayScreenState();
}

class _ChatwayScreenState extends State<ChatwayScreen> {
  late Future<Uri?> _chatUrl;
  WebViewController? _controller;
  int _progress = 0;
  bool _webViewStarted = false;
  String? _webError;
  Uri? _lastUrl;
  Timer? _navigationTimer;
  Timer? _widgetCheckTimer;

  @override
  void initState() {
    super.initState();
    _chatUrl = _loadChatUrl();
  }

  @override
  void didUpdateWidget(covariant ChatwayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionKey != widget.sessionKey) {
      _reload();
    }
  }

  Future<Uri?> _loadChatUrl() async {
    final token = await widget.tokenProvider().timeout(const Duration(seconds: 5));
    return widget.api.getChatwayUrl(token: token).timeout(const Duration(seconds: 18));
  }

  Future<void> _reload() async {
    setState(() {
      _webError = null;
      _lastUrl = null;
      _navigationTimer?.cancel();
      _widgetCheckTimer?.cancel();
      _progress = 0;
      _chatUrl = _loadChatUrl();
      _controller = null;
      _webViewStarted = false;
    });
  }

  void _openWebView(Uri url) {
    _lastUrl = url;
    _navigationTimer?.cancel();
    _navigationTimer = Timer(const Duration(seconds: 28), () {
      if (mounted && _progress < 100) setState(() => _webError = 'Връзката с чат страницата отне твърде дълго. Провери интернет връзката и опитай отново.');
    });
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B1220))
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
          if (value >= 100) _navigationTimer?.cancel();
        },
        onPageFinished: (_) {
          _navigationTimer?.cancel();
          if (!mounted) return;
          setState(() => _progress = 100);
          _widgetCheckTimer?.cancel();
          _widgetCheckTimer = Timer(const Duration(seconds: 13), () async {
            final activeController = _controller;
            if (!mounted || activeController == null || _webError != null) return;
            try {
              final result = await activeController.runJavaScriptReturningResult(r"typeof window.$chatway !== 'undefined'");
              final ready = result == true || result.toString().toLowerCase() == 'true';
              if (!ready && mounted) setState(() => _webError = 'Страницата се отвори, но Chatway не зареди своя чат модул. Провери дали скриптът на Chatway не е блокиран от кеширане, защитна стена или оптимизатор на JavaScript.');
            } catch (_) {
              if (mounted) setState(() => _webError = 'Не успяхме да проверим зареждането на Chatway. Опитай отново.');
            }
          });
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            setState(() => _webError = error.description);
          }
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          final host = uri.host.toLowerCase();
          final internal = host == 'pcwork-bg.com' ||
              host == 'www.pcwork-bg.com' ||
              host == 'chatway.app' ||
              host.endsWith('.chatway.app');
          if (internal) return NavigationDecision.navigate;
          if (uri.scheme == 'https' || uri.scheme == 'mailto' || uri.scheme == 'tel') {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(url);
    setState(() => _controller = controller);
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _widgetCheckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uri?>(
      future: _chatUrl,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _messageState(
            icon: Icons.cloud_off_rounded,
            title: 'Чатът не може да бъде зареден',
            message: '${snapshot.error}',
            action: 'Опитай отново',
          );
        }
        final url = snapshot.data;
        if (url == null) {
          return _messageState(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Chatway още не е свързан',
            message: 'В WordPress отвори PCWork Mobile → Интеграции → Chatway. Включи интеграцията и въведи Installation ID. За история на разговорите включи и Visitor Verification в Chatway и добави Security Key в настройките на PCWork. Запази настройките и опитай отново.',
            action: 'Провери отново',
          );
        }
        if (!_webViewStarted) {
          _webViewStarted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _controller == null) _openWebView(url);
          });
        }
        if (_webError != null) {
          return _messageState(
            icon: Icons.wifi_off_rounded,
            title: 'Проблем при зареждането на Chatway',
            message: _webError!,
            action: 'Презареди',
          );
        }
        return Column(children: [
          if (_progress < 100)
            LinearProgressIndicator(value: _progress == 0 ? null : _progress / 100),
          Expanded(child: _controller == null
              ? const Center(child: CircularProgressIndicator())
              : WebViewWidget(controller: _controller!)),
        ]);
      },
    );
  }

  Widget _messageState({required IconData icon, required String title, required String message, required String action}) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(26),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF151F2E),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFF26374B)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF21D4D8).withValues(alpha: .12),
              ),
              child: Icon(icon, color: const Color(0xFF21D4D8), size: 34),
            ),
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF9AAABD), height: 1.5)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(action),
            ),
            if (_lastUrl != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => launchUrl(_lastUrl!, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_browser_rounded),
                label: const Text('Отвори чата в браузър'),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
