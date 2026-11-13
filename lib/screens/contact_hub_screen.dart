import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'pcwork_chat_screen.dart';
import 'admin_pcwork_chat_screen.dart';

/// First-party PCWork chat connected to the authenticated WordPress account.
class ContactHubScreen extends StatelessWidget {
  const ContactHubScreen({super.key, required this.api, required this.tokenProvider, required this.sessionKey, required this.english, required this.isDarkTheme, required this.isActive, this.isAdministrator = false, this.canUploadFiles = false});
  final ApiService api;
  final Future<String?> Function() tokenProvider;
  final int sessionKey;
  final bool english;
  final bool isDarkTheme;
  final bool isActive;
  final bool isAdministrator;
  final bool canUploadFiles;

  String tr(String bg, String en) => english ? en : bg;

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 5),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isAdministrator ? tr('Клиентски разговори', 'Customer conversations') : tr('Чат', 'Chat'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          Text(isAdministrator ? tr('Отговаряй на съобщенията на клиентите.', 'Reply to customer messages.') : tr('Свържи се директно с екипа на PCWork.', 'Message the PCWork team directly.'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: isDarkTheme ? Colors.white60 : Colors.black54)),
        ])),
        if (isAdministrator) const Icon(Icons.support_agent_rounded, size: 22, color: Color(0xFF20CBD0)),
      ]),
    ),
    Expanded(child: isAdministrator
      ? AdminPCWorkChatScreen(api: api, tokenProvider: tokenProvider, sessionKey: sessionKey, english: english, isDarkTheme: isDarkTheme, isActive: isActive)
      : PCWorkChatScreen(api: api, tokenProvider: tokenProvider, sessionKey: sessionKey, english: english, isDarkTheme: isDarkTheme, isActive: isActive, canUploadFiles: canUploadFiles)),
  ]);
}
