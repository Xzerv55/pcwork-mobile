import 'package:flutter/material.dart';

class NotificationHistoryScreen extends StatefulWidget {
  const NotificationHistoryScreen({
    super.key,
    required this.records,
    required this.english,
    required this.isDarkTheme,
    required this.onChanged,
    required this.onOpen,
  });

  final List<Map<String, dynamic>> records;
  final bool english;
  final bool isDarkTheme;
  final Future<void> Function(List<Map<String, dynamic>>) onChanged;
  final Future<void> Function(Map<String, dynamic>) onOpen;

  @override
  State<NotificationHistoryScreen> createState() => _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState extends State<NotificationHistoryScreen> {
  late List<Map<String, dynamic>> records;

  String tr(String bg, String en) => widget.english ? en : bg;

  @override
  void initState() {
    super.initState();
    records = widget.records.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  @override
  void didUpdateWidget(covariant NotificationHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.records, widget.records)) {
      records = widget.records.map((item) => Map<String, dynamic>.from(item)).toList();
    }
  }

  Future<void> _removeAt(int index) async {
    setState(() => records.removeAt(index));
    await widget.onChanged(records);
  }

  Future<void> _clearAll() async {
    if (records.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Изчисти известията?', 'Clear notifications?')),
        content: Text(tr('Всички запазени известия ще бъдат изтрити от това устройство.', 'All saved notifications will be deleted from this device.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Отказ', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Изчисти всички', 'Clear all'))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(records.clear);
    await widget.onChanged(records);
  }

  @override
  Widget build(BuildContext context) {
    final foreground = widget.isDarkTheme ? Colors.white : const Color(0xFF172033);
    final muted = widget.isDarkTheme ? Colors.white60 : Colors.black54;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Известия', 'Notifications')),
        actions: [
          if (records.isNotEmpty)
            IconButton(
              tooltip: tr('Изчисти всички', 'Clear all'),
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: records.isEmpty
          ? Center(child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.notifications_off_outlined, size: 58, color: muted),
                const SizedBox(height: 14),
                Text(tr('Все още нямате известия', 'You have no notifications yet'),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: foreground)),
                const SizedBox(height: 6),
                Text(tr('Получените известия ще се показват тук.', 'Notifications you receive will appear here.'),
                  textAlign: TextAlign.center, style: TextStyle(color: muted)),
              ]),
            ))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              itemCount: records.length,
              separatorBuilder: (_, __) => const SizedBox(height: 7),
              itemBuilder: (context, index) {
                final item = records[index];
                final title = (item['title'] ?? '').toString();
                final body = (item['body'] ?? '').toString();
                final date = DateTime.tryParse((item['received_at'] ?? '').toString());
                final dateText = date == null ? '' :
                  '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                return Dismissible(
                  key: ValueKey((item['id'] ?? '$index').toString()),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(18)),
                    child: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  onDismissed: (_) => _removeAt(index),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                      leading: Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(color: const Color(0xFF21D4D8).withValues(alpha: .13), shape: BoxShape.circle),
                        child: const Icon(Icons.notifications_active_outlined, color: Color(0xFF21D4D8)),
                      ),
                      onTap: () => widget.onOpen(item),
                      title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: foreground)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (body.isNotEmpty) Text(body, style: TextStyle(color: muted)),
                          if (dateText.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(dateText, style: TextStyle(fontSize: 11, color: muted))),
                        ]),
                      ),
                      trailing: IconButton(
                        tooltip: tr('Изтрий', 'Delete'),
                        onPressed: () => _removeAt(index),
                        icon: Icon(Icons.close_rounded, color: muted, size: 20),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
