import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'pcwork_chat_screen.dart';

/// First-party PCWork support chat connected to the authenticated WordPress account.
class ContactHubScreen extends StatelessWidget {
  const ContactHubScreen({super.key, required this.api, required this.tokenProvider, required this.sessionKey, required this.english, required this.isDarkTheme, required this.isActive});
  final ApiService api;
  final Future<String?> Function() tokenProvider;
  final int sessionKey;
  final bool english;
  final bool isDarkTheme;
  final bool isActive;

  String tr(String bg, String en) => english ? en : bg;

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Онлайн поддръжка', 'Online support'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text(tr('Свържи се директно с екипа на PCWork. Историята на разговора се запазва в профила ти.', 'Chat directly with the PCWork team. Your conversation history is saved to your account.'), style: TextStyle(color: isDarkTheme ? Colors.white70 : Colors.black54)),
      ]),
    ),
    Expanded(child: PCWorkChatScreen(api: api, tokenProvider: tokenProvider, sessionKey: sessionKey, english: english, isDarkTheme: isDarkTheme, isActive: isActive)),
  ]);
}
