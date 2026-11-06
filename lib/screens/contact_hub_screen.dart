import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'chatway_screen.dart';
import 'chaty_screen.dart';

class ContactHubScreen extends StatelessWidget {
  const ContactHubScreen({super.key, required this.api, required this.tokenProvider, required this.sessionKey});
  final ApiService api;
  final Future<String?> Function() tokenProvider;
  final int sessionKey;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    const Text('Свържи се с PCWork', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 6),
    const Text('Избери удобен канал за връзка с нашия екип.', style: TextStyle(color: Colors.white70)),
    const SizedBox(height: 18),
    _ContactCard(icon: Icons.forum_outlined, title: 'Chaty – бутони за контакт', subtitle: 'WhatsApp, Messenger, Viber, Telegram, телефон и другите активирани канали от сайта.', color: const Color(0xFF21D4D8), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Контактни бутони')) , body: ChatyScreen(api: api))))),
    const SizedBox(height: 12),
    _ContactCard(icon: Icons.support_agent, title: 'Chatway – онлайн поддръжка', subtitle: 'Разговор на живо с екипа на PCWork.', color: const Color(0xFF9B7BFF), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Онлайн поддръжка')), body: ChatwayScreen(api: api, tokenProvider: tokenProvider, sessionKey: sessionKey))))),
  ]);
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});
  final IconData icon; final String title; final String subtitle; final Color color; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(child: InkWell(borderRadius: BorderRadius.circular(22), onTap: onTap, child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [Container(width: 54, height: 54, decoration: BoxDecoration(color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: color, size: 28)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 5), Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 13))])), const Icon(Icons.chevron_right)]))));
}
