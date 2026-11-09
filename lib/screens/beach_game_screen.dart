import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BeachGameScreen extends StatefulWidget {
  const BeachGameScreen({super.key, required this.english});
  final bool english;

  @override
  State<BeachGameScreen> createState() => _BeachGameScreenState();
}

class _BeachGameScreenState extends State<BeachGameScreen> {
  static const _recordKey = 'pcwork_beach_game_record_v1';
  final Random _random = Random();
  final Map<int, _BeachItem> _items = {};
  Timer? _clock;
  int _seconds = 60;
  int _score = 0;
  int _record = 0;
  bool _running = false;
  bool _finished = false;
  bool _paused = false;
  DateTime _nextSpawn = DateTime.now();

  String tr(String bg, String en) => widget.english ? en : bg;

  @override
  void initState() {
    super.initState();
    _loadRecord();
  }

  Future<void> _loadRecord() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _record = prefs.getInt(_recordKey) ?? 0);
  }

  void _start() {
    _clock?.cancel();
    setState(() {
      _items.clear();
      _seconds = 60;
      _elapsedMs = 0;
      _score = 0;
      _running = true;
      _finished = false;
      _paused = false;
      _nextSpawn = DateTime.now();
    });
    _clock = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  void _tick() {
    if (!mounted || !_running || _paused) return;
    final now = DateTime.now();
    setState(() {
      _items.removeWhere((_, item) => item.expiresAt.isBefore(now));
      if (now.isAfter(_nextSpawn) && _items.length < 7) {
        final empty = List<int>.generate(20, (i) => i).where((i) => !_items.containsKey(i)).toList();
        if (empty.isNotEmpty) {
          final slot = empty[_random.nextInt(empty.length)];
          _items[slot] = _BeachItem(_random.nextBool() ? '🥒' : '🌸', now.add(const Duration(milliseconds: 1500)));
        }
        _nextSpawn = now.add(Duration(milliseconds: 350 + _random.nextInt(850)));
      }
    });
    if (now.millisecondsSinceEpoch % 1000 < 270) {
      // The visible countdown is derived from the round start, avoiding timer drift.
    }
    if (_seconds > 0) {
      _elapsedMs += 250;
      if (_elapsedMs >= 1000) {
        _elapsedMs -= 1000;
        setState(() => _seconds--);
      }
    }
    if (_seconds <= 0) _finish();
  }

  int _elapsedMs = 0;

  Future<void> _finish() async {
    _clock?.cancel();
    final best = max(_record, _score).toInt();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_recordKey, best);
    if (!mounted) return;
    setState(() {
      _record = best;
      _running = false;
      _finished = true;
      _items.clear();
    });
  }

  void _catch(int index) {
    if (!_running || _paused || !_items.containsKey(index)) return;
    setState(() {
      _items.remove(index);
      _score += 1;
    });
  }

  void _togglePause() {
    if (!_running) return;
    setState(() => _paused = !_paused);
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Плажно приключение', 'Beach Adventure'))),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF8DE4F2), Color(0xFFF5D88D), Color(0xFFE7B96D)]),
        ),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Row(children: [
                _hud(tr('ТОЧКИ', 'SCORE'), '$_score'),
                const Spacer(),
                _hud(tr('ВРЕМЕ', 'TIME'), '$_seconds'),
                const Spacer(),
                _hud(tr('РЕКОРД', 'BEST'), '$_record'),
                if (_running) IconButton(onPressed: _togglePause, icon: Icon(_paused ? Icons.play_arrow : Icons.pause, color: const Color(0xFF17364B))),
              ]),
            ),
            Expanded(
              child: Stack(children: [
                Positioned.fill(child: CustomPaint(painter: _BeachBackdropPainter())),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 20,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5, crossAxisSpacing: 7, mainAxisSpacing: 9, childAspectRatio: 1.05),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return GestureDetector(
                        onTap: () => _catch(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          decoration: BoxDecoration(
                            color: const Color(0xFFB96D37),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(color: const Color(0xFF75401F), width: 3),
                            boxShadow: const [BoxShadow(color: Color(0x553B2414), blurRadius: 4, offset: Offset(0, 3))],
                          ),
                          child: Center(child: item == null
                            ? Container(width: 25, height: 30, decoration: BoxDecoration(color: const Color(0xFF57331F), borderRadius: BorderRadius.circular(20)))
                            : Text(item.emoji, style: const TextStyle(fontSize: 30))),
                        ),
                      );
                    },
                  ),
                ),
                if (_paused || _finished || !_running)
                  Positioned.fill(child: Container(
                    color: const Color(0x880D2635),
                    child: Center(child: Card(
                      margin: const EdgeInsets.all(28),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_finished ? tr('Браво!', 'Well done!') : tr('Готов ли си за игра?', 'Ready to play?'),
                            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 8),
                          Text(_finished ? tr('Точки: $_score', 'Score: $_score') :
                            tr('Хвани краставичките и цветенцата, преди да се скрият!', 'Catch the cucumbers and flowers before they hide!'),
                            textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton.icon(onPressed: _start,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(_finished ? tr('Играй отново', 'Play again') : tr('Започни игра', 'Start game'))),
                        ]),
                      ),
                    )),
                  )),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(tr('Докосни вратичка, когато се покаже краставичка или цвете!', 'Tap a gate when a cucumber or flower appears!'),
                textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF573A22), fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _hud(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .88), borderRadius: BorderRadius.circular(14)),
    child: Column(children: [
      Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF426174))),
      Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF17364B))),
    ]),
  );
}

class _BeachItem {
  const _BeachItem(this.emoji, this.expiresAt);
  final String emoji;
  final DateTime expiresAt;
}

class _BeachBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sand = Paint()..color = const Color(0xFFE7BC73);
    canvas.drawRect(Offset.zero & size, sand);
    final castle = Paint()..color = const Color(0xFFF4D69A);
    final outline = Paint()..color = const Color(0xFFB77A42)..style = PaintingStyle.stroke..strokeWidth = 4;
    final rect = Rect.fromLTWH(size.width * .07, size.height * .08, size.width * .86, size.height * .82);
    final path = Path()..moveTo(rect.left, rect.bottom)..lineTo(rect.left, rect.top + 35)
      ..lineTo(rect.left + 35, rect.top + 35)..lineTo(rect.left + 35, rect.top)
      ..lineTo(rect.left + 75, rect.top)..lineTo(rect.left + 75, rect.top + 35)
      ..lineTo(rect.right - 75, rect.top + 35)..lineTo(rect.right - 75, rect.top)
      ..lineTo(rect.right - 35, rect.top)..lineTo(rect.right - 35, rect.top + 35)
      ..lineTo(rect.right, rect.top + 35)..lineTo(rect.right, rect.bottom)..close();
    canvas.drawPath(path, castle);
    canvas.drawPath(path, outline);
    final sea = Paint()..color = const Color(0xFF55C5D9);
    canvas.drawRect(Rect.fromLTWH(0, size.height * .91, size.width, size.height * .09), sea);
    final ball = Paint()..color = const Color(0xFFE76F51);
    canvas.drawCircle(Offset(size.width * .10, size.height * .93), 12, ball);
    final shell = Paint()..color = const Color(0xFFFFF0CE);
    canvas.drawCircle(Offset(size.width * .87, size.height * .93), 9, shell);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
