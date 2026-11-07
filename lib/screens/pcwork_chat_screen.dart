import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';

class PCWorkChatScreen extends StatefulWidget {
  const PCWorkChatScreen({super.key, required this.api, required this.tokenProvider, required this.sessionKey, required this.english, required this.isDarkTheme, required this.isActive});
  final ApiService api;
  final Future<String?> Function() tokenProvider;
  final int sessionKey;
  final bool english;
  final bool isDarkTheme;
  final bool isActive;

  @override
  State<PCWorkChatScreen> createState() => _PCWorkChatScreenState();
}

class _PCWorkChatScreenState extends State<PCWorkChatScreen> {
  final TextEditingController _message = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final List<Map<String, dynamic>> _messages = [];
  Timer? _pollTimer;
  String? _token;
  String? _error;
  int _lastId = 0;
  bool _loading = true;
  bool _sending = false;

  String tr(String bg, String en) => widget.english ? en : bg;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _token = await widget.tokenProvider();
      if (_token == null || _token!.isEmpty) throw Exception(tr('Влезте в профила си, за да използвате чата.', 'Sign in to use the chat.'));
      await _loadMessages();
      if (widget.isActive) _startPolling();
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (widget.isActive && _token != null) {
      _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadMessages(silent: true));
    }
  }

  @override
  void didUpdateWidget(covariant PCWorkChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive || oldWidget.sessionKey != widget.sessionKey) {
      if (oldWidget.sessionKey != widget.sessionKey) {
        _pollTimer?.cancel();
        _token = null;
        _lastId = 0;
        _messages.clear();
        _loading = true;
        _error = null;
        unawaited(_initialize());
      } else {
        _startPolling();
        if (widget.isActive) unawaited(_loadMessages(silent: true));
      }
    }
  }

  Future<void> _loadMessages({bool silent = false}) async {
    final token = _token;
    if (token == null) return;
    try {
      final result = await widget.api.getChatMessages(token, afterId: _lastId);
      final rows = (result['data'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (!mounted) return;
      if (rows.isNotEmpty) {
        setState(() {
          _messages.addAll(rows);
          _lastId = rows.fold<int>(_lastId, (v, row) => (int.tryParse('${row['id']}') ?? v) > v ? int.parse('${row['id']}') : v);
          _error = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
        });
      } else if (!silent && mounted) {
        setState(() => _error = null);
      }
      if (mounted && _loading) setState(() => _loading = false);
    } catch (e) {
      if (mounted && !silent) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _send({String? imageBase64, String? imageMime}) async {
    final text = _message.text.trim();
    if (_sending || (text.isEmpty && imageBase64 == null)) return;
    final token = _token;
    if (token == null) return;
    setState(() => _sending = true);
    try {
      await widget.api.sendChatMessage(token, message: text, imageBase64: imageBase64, imageMime: imageMime);
      _message.clear();
      await _loadMessages(silent: true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Съобщението не беше изпратено:', 'Message was not sent:')} $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 78, maxWidth: 1600);
      if (file == null) return;
      final bytes = await File(file.path).readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) throw Exception(tr('Изображението трябва да е до 5 MB.', 'Image must be 5 MB or smaller.'));
      final ext = file.name.toLowerCase();
      final mime = ext.endsWith('.png') ? 'image/png' : ext.endsWith('.webp') ? 'image/webp' : 'image/jpeg';
      await _send(imageBase64: base64Encode(bytes), imageMime: mime);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _message.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDarkTheme;
    return Column(children: [
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _messages.isEmpty
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.cloud_off_outlined, size: 42),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () => _loadMessages(), child: Text(tr('Опитай отново', 'Try again'))),
                  ])))
                : _messages.isEmpty
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(tr('Започнете разговор с екипа на PCWork. Ще получите отговор тук.', 'Start a conversation with the PCWork team. Replies will appear here.'), textAlign: TextAlign.center)))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final row = _messages[index];
                          final mine = row['sender_type'] != 'admin';
                          final text = (row['message'] ?? '').toString();
                          final image = (row['attachment_url'] ?? '').toString();
                          return Align(
                            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: mine ? const Color(0xFF164D59) : (dark ? const Color(0xFF1A2738) : Colors.white),
                                borderRadius: BorderRadius.circular(17),
                                border: Border.all(color: dark ? const Color(0xFF2A3B50) : const Color(0xFFE0E6ED)),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                if (text.isNotEmpty) Text(text, style: TextStyle(color: mine || dark ? Colors.white : const Color(0xFF172033))),
                                if (image.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(image, width: 220, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Text(tr('Снимката не може да се зареди.', 'Image could not be loaded.'))))),
                                const SizedBox(height: 4),
                                Text((row['created_at'] ?? '').toString(), style: TextStyle(fontSize: 10, color: mine || dark ? Colors.white60 : Colors.black54)),
                              ]),
                            ),
                          );
                        },
                      ),
      ),
      if (_error != null && _messages.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(tr('Временно няма връзка. Ще опитаме отново автоматично.', 'Connection temporarily unavailable. Retrying automatically.'), style: const TextStyle(color: Colors.orange, fontSize: 11))),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(onPressed: _sending ? null : _pickImage, icon: const Icon(Icons.image_outlined), tooltip: tr('Добави снимка', 'Add image')),
            Expanded(child: TextField(
              controller: _message,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: tr('Напиши съобщение…', 'Write a message…'), contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12)),
              onSubmitted: (_) => _send(),
            )),
            const SizedBox(width: 6),
            IconButton.filled(onPressed: _sending ? null : () => _send(), icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded)),
          ]),
        ),
      ),
    ]);
  }
}
