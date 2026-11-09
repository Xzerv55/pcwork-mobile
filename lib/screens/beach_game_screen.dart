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
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxHeight < 520 || constraints.maxWidth > constraints.maxHeight * 1.25;
          return Container(
            decoration: const BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0xFF61D7F4), Color(0xFFF7D48B), Color(0xFFE8B66B)])),
            child: Column(children: [
              Padding(
                padding: EdgeInsets.fromLTRB(compact ? 6 : 12, 6, compact ? 6 : 12, 4),
                child: Row(children: [
                  Expanded(child: _hud(tr('ТОЧКИ', 'SCORE'), '$_score', compact)),
                  const SizedBox(width: 5),
                  Expanded(child: _hud(tr('ВРЕМЕ', 'TIME'), '$_seconds', compact)),
                  const SizedBox(width: 5),
                  Expanded(child: _hud(tr('РЕКОРД', 'BEST'), '$_record', compact)),
                  if (_running) IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 42, height: 42),
                    onPressed: _togglePause,
                    icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      color: const Color(0xFF17364B), size: 30),
                  ),
                ]),
              ),
              Expanded(child: Center(child: LayoutBuilder(builder: (context, boardConstraints) {
                // Keep the illustrated board at its native 16:9 ratio on every device.
                final boardWidth = min(boardConstraints.maxWidth, boardConstraints.maxHeight * (16 / 9));
                final boardHeight = boardWidth * (9 / 16);
                return SizedBox(width: boardWidth, height: boardHeight,
                  child: Stack(fit: StackFit.expand, children: [
                    Image.asset('assets/images/beach_game_background.png', fit: BoxFit.fill),
                    // Transparent hit targets align with the twenty castle doors.
                    Positioned(left: boardWidth * .205, top: boardHeight * .315,
                      width: boardWidth * .60, height: boardHeight * .51,
                      child: GridView.builder(
                        padding: EdgeInsets.zero,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 20,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5, crossAxisSpacing: 2, mainAxisSpacing: 2,
                          childAspectRatio: 1.0),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () => _catch(index),
                            child: Center(child: item == null ? const SizedBox.shrink() :
                              FittedBox(fit: BoxFit.contain, child: Text(item.emoji,
                                style: TextStyle(fontSize: boardWidth * .055,
                                  shadows: const [Shadow(color: Colors.black54, blurRadius: 5)])))),
                          );
                        },
                      )),
                    if (_paused || _finished || !_running)
                      Positioned.fill(child: Container(
                        color: const Color(0x990D2635),
                        child: Center(child: Card(
                          margin: const EdgeInsets.all(18),
                          child: Padding(padding: EdgeInsets.all(compact ? 12 : 20),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text(_finished ? tr('Браво!', 'Well done!') : tr('Готов ли си за игра?', 'Ready to play?'),
                                style: TextStyle(fontSize: compact ? 17 : 23, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 7),
                              Text(_finished ? tr('Точки: $_score', 'Score: $_score') :
                                tr('Хвани краставичките и цветенцата, преди да се скрият!', 'Catch the cucumbers and flowers before they hide!'),
                                textAlign: TextAlign.center, style: TextStyle(fontSize: compact ? 11 : 14)),
                              const SizedBox(height: 12),
                              FilledButton.icon(onPressed: _start,
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: Text(_finished ? tr('Играй отново', 'Play again') : tr('Започни игра', 'Start game'))),
                            ])),
                        )),
                      )),
                  ]));
              }))),
              if (!compact) Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                child: Text(tr('Докосни вратичка, когато се покаже краставичка или цвете!',
                  'Tap a gate when a cucumber or flower appears!'), textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF573A22), fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ]),
          );
        }),
      ),
    );
  }

  Widget _hud(String label, String value, bool compact) => Container(
    padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 12, vertical: compact ? 4 : 7),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .88), borderRadius: BorderRadius.circular(14)),
    child: Column(children: [
      Text(label, style: compact
          ? const TextStyle(fontSize: 7, fontWeight: FontWeight.w900, color: Color(0xFF426174))
          : const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF426174))),
      Text(value, style: compact
          ? const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF17364B))
          : const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF17364B))),
    ]),
  );
}

class _BeachItem {
  const _BeachItem(this.emoji, this.expiresAt);
  final String emoji;
  final DateTime expiresAt;
}
