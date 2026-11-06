import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'chatway_screen.dart';
import 'chaty_screen.dart';

/// A single contact destination that contains both the official Chaty channels
/// and the Chatway live-support widget. The app navigation remains one item.
class ContactHubScreen extends StatefulWidget {
  const ContactHubScreen({super.key, required this.api, required this.tokenProvider, required this.sessionKey, required this.english});
  final ApiService api;
  final Future<String?> Function() tokenProvider;
  final int sessionKey;
  final bool english;

  @override
  State<ContactHubScreen> createState() => _ContactHubScreenState();
}

class _ContactHubScreenState extends State<ContactHubScreen> {
  int selected = 0;
  String tr(String bg, String en) => widget.english ? en : bg;

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Свържи се с PCWork', 'Contact PCWork'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text(tr('Всички канали за връзка са събрани на едно място.', 'All contact channels are available in one place.'), style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment<int>(value: 0, icon: const Icon(Icons.forum_outlined), label: Text(tr('Контактни бутони', 'Contact channels'))),
            ButtonSegment<int>(value: 1, icon: const Icon(Icons.support_agent), label: Text(tr('Чат на живо', 'Live chat'))),
          ],
          selected: {selected},
          onSelectionChanged: (value) => setState(() => selected = value.first),
        ),
      ]),
    ),
    Expanded(
      child: selected == 0
          ? ChatyScreen(api: widget.api, english: widget.english)
          : ChatwayScreen(api: widget.api, tokenProvider: widget.tokenProvider, sessionKey: widget.sessionKey, english: widget.english),
    ),
  ]);
}
