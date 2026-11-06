import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'chatway_screen.dart';

/// The in-app support destination. Chaty has been removed; the home screen
/// now exposes direct phone, Viber, Messenger and TikTok contact actions.
class ContactHubScreen extends StatelessWidget {
  const ContactHubScreen({super.key, required this.api, required this.tokenProvider, required this.sessionKey, required this.english});
  final ApiService api;
  final Future<String?> Function() tokenProvider;
  final int sessionKey;
  final bool english;

  String tr(String bg, String en) => english ? en : bg;

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Онлайн поддръжка', 'Online support'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text(tr('Свържи се с нашия екип чрез чата на живо.', 'Connect with our team using live chat.'), style: const TextStyle(color: Colors.white70)),
      ]),
    ),
    Expanded(child: ChatwayScreen(api: api, tokenProvider: tokenProvider, sessionKey: sessionKey, english: english)),
  ]);
}
