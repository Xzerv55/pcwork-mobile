import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'chatway_screen.dart';

/// The in-app support destination for the authenticated Chatway live chat.
class ContactHubScreen extends StatelessWidget {
  const ContactHubScreen({super.key, required this.api, required this.tokenProvider, required this.sessionKey, required this.english, required this.isDarkTheme});
  final ApiService api;
  final Future<String?> Function() tokenProvider;
  final int sessionKey;
  final bool english;
  final bool isDarkTheme;

  String tr(String bg, String en) => english ? en : bg;

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Онлайн поддръжка', 'Online support'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text(tr('Свържи се с нашия екип чрез чата на живо.', 'Connect with our team using live chat.'), style: TextStyle(color: isDarkTheme ? Colors.white70 : Colors.black54)),
      ]),
    ),
    Expanded(child: ChatwayScreen(api: api, tokenProvider: tokenProvider, sessionKey: sessionKey, english: english, isDarkTheme: isDarkTheme)),
  ]);
}
