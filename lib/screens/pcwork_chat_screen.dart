import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';

class PCWorkChatScreen extends StatefulWidget {
  const PCWorkChatScreen({super.key, required this.api, required this.tokenProvider, required this.sessionKey, required this.english, required this.isDarkTheme, required this.isActive, this.canUploadFiles = false});
  final ApiService api;
  final Future<String?> Function() tokenProvider;
  final int sessionKey;
  final bool english;
  final bool isDarkTheme;
  final bool isActive;
  final bool canUploadFiles;

  @override
  State<PCWorkChatScreen> createState() => _PCWorkChatScreenState();
}

class _PCWorkChatScreenState extends State<PCWorkChatScreen> with WidgetsBindingObserver {
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
  bool _loadingMessages = false;
  bool _appResumed = true;
  bool _hasOlder = false;
  bool _loadingOlder = false;
  int _oldestId = 0;
  int _pollDelaySeconds = 8;
  int _pollFailures = 0;

  String tr(String bg, String en) => widget.english ? en : bg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    });
  }

  @override
  void didChangeMetrics() {
    if (widget.isActive) _scrollToLatest();
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
    _pollTimer = null;
    if (widget.isActive && _appResumed && _token != null) {
      _pollTimer = Timer(Duration(seconds: _pollDelaySeconds), () {
        if (!_loadingMessages && !_sending) {
          unawaited(_loadMessages(silent: true));
        } else {
          _startPolling();
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (_appResumed == resumed) return;
    _appResumed = resumed;
    if (!resumed) {
      _pollTimer?.cancel();
      _pollTimer = null;
    } else if (widget.isActive) {
      _startPolling();
      unawaited(_loadMessages(silent: true, forceBottom: true));
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
        _hasOlder = false; _oldestId = 0; _pollFailures = 0; _pollDelaySeconds = 8;
        _loading = true;
        _error = null;
        unawaited(_initialize());
      } else {
        _startPolling();
        if (widget.isActive) unawaited(_loadMessages(silent: true, forceBottom: true));
      }
    }
  }

  Future<void> _loadMessages({bool silent = false, bool forceBottom = false}) async {
    final token = _token;
    if (token == null || _loadingMessages) return;
    _loadingMessages = true;
    try {
      final result = await widget.api.getChatMessages(token, afterId: _lastId);
      final rows = (result['data'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (_lastId == 0) _hasOlder = result['has_more'] == true;
      if (rows.isNotEmpty && _oldestId == 0) _oldestId = int.tryParse('${rows.first['id']}') ?? 0;
      if (!mounted) return;
      _pollFailures = 0;
      _pollDelaySeconds = rows.isNotEmpty ? 5 : (_pollDelaySeconds + 2).clamp(8, 20).toInt();
      if (rows.isNotEmpty) {
        setState(() {
          _messages.addAll(rows);
          _lastId = rows.fold<int>(_lastId, (v, row) => (int.tryParse('${row['id']}') ?? v) > v ? int.parse('${row['id']}') : v);
          _error = null;
        });
        // Keep the conversation anchored to the newest message on initial load,
        // after every incoming message and after sending a reply.
        _scrollToLatest();
      } else if (mounted && _error != null) {
        setState(() => _error = null);
      }
      if (forceBottom) _scrollToLatest();
      if (mounted && _loading) setState(() => _loading = false);
    } catch (e) {
      _pollFailures++;
      _pollDelaySeconds = min(60, 10 * (1 << min(_pollFailures - 1, 3))).toInt();
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    } finally {
      _loadingMessages = false;
      if (mounted && widget.isActive && _appResumed && _token != null) _startPolling();
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasOlder || _oldestId <= 0 || _token == null) return;
    _loadingOlder = true;
    if (mounted) setState(() {});
    final oldExtent = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final oldOffset = _scroll.hasClients ? _scroll.offset : 0.0;
    try {
      final result = await widget.api.getChatMessages(_token!, beforeId: _oldestId);
      final rows = (result['data'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (!mounted) return;
      if (rows.isNotEmpty) {
        setState(() { _messages.insertAll(0, rows); _oldestId = int.tryParse('${rows.first['id']}') ?? _oldestId; _hasOlder = result['has_more'] == true; });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent - oldExtent + oldOffset);
        });
      } else {
        setState(() => _hasOlder = false);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Неуспешно зареждане на по-стари съобщения:', 'Could not load older messages:')} $e')));
    } finally { _loadingOlder = false; if (mounted) setState(() {}); }
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

  Widget _quickPrompt(BuildContext context, String label, String value) => Padding(padding: const EdgeInsets.only(right: 7), child: ActionChip(visualDensity: VisualDensity.compact, label: Text(label, style: const TextStyle(fontSize: 11)), onPressed: () { _message.text = value; _message.selection = TextSelection.collapsed(offset: value.length); setState(() {}); }));

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _message.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDarkTheme;
    return Column(children: [
      if (_hasOlder && !_loading) Align(alignment: Alignment.center, child: TextButton.icon(onPressed: _loadingOlder ? null : _loadOlder, icon: _loadingOlder ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.history_rounded, size: 17), label: Text(tr('Зареди по-стари съобщения', 'Load older messages')))),
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
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final row = _messages[index];
                          final mine = row['sender_type'] != 'admin';
                          final text = (row['message'] ?? '').toString();
                          final image = (row['attachment_url'] ?? '').toString();
                          return Align(
                            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: GestureDetector(
                              onLongPress: text.isEmpty ? null : () async {
                                await Clipboard.setData(ClipboardData(text: text));
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Съобщението е копирано.', 'Message copied.')), duration: const Duration(seconds: 1)));
                              },
                              child: Container(
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                            ),
                          );
                        },
                      ),
      ),
      if (_error != null && _messages.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(tr('Временно няма връзка. Ще опитаме отново автоматично.', 'Connection temporarily unavailable. Retrying automatically.'), style: const TextStyle(color: Colors.orange, fontSize: 11))),
      if (_message.text.trim().isEmpty && !_loading) SizedBox(height: 42, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
        _quickPrompt(context, tr('Статус на ремонт', 'Repair status'), tr('Здравейте, бих искал/а информация за статуса на моя ремонт.', 'Hello, I would like an update on my repair status.')),
        _quickPrompt(context, tr('Оферта', 'Quote'), tr('Моля, изпратете ми оферта за ремонт.', 'Please send me a repair quote.')),
        _quickPrompt(context, tr('Записване на час', 'Book a visit'), tr('Искам да запазя час за посещение.', 'I would like to book an appointment.')),
      ])),
      Padding(
          padding: EdgeInsets.fromLTRB(7, 2, 7, MediaQuery.of(context).viewInsets.bottom > 0 ? 0 : 1),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (widget.canUploadFiles) IconButton(onPressed: _sending ? null : _pickImage, icon: const Icon(Icons.image_outlined), tooltip: tr('Добави снимка', 'Add image')),
            Expanded(child: TextField(
              controller: _message,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.send,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(isDense: true, hintText: tr('Напиши съобщение…', 'Write a message…'), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              onChanged: (_) { if (mounted) setState(() {}); },
              onSubmitted: (_) => _send(),
            )),
            const SizedBox(width: 6),
            IconButton.filled(onPressed: _sending ? null : () => _send(), icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded)),
          ]),
        ),
    ]);
  }
}
