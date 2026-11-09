import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BeachGameScreen extends StatefulWidget {
  const BeachGameScreen({super.key, required this.english});
  final bool english;

  @override
  State<BeachGameScreen> createState() => _BeachGameScreenState();
}

class _BeachGameScreenState extends State<BeachGameScreen> {
  static const _recordKey = 'pcwork_beach_game_record_v1';
  static const int _doorCount = 10;
  // Centers of the ten illustrated doors in the supplied 928x1664 artwork.
  static const List<Offset> _doorCenters = [
    Offset(.365, .362), Offset(.635, .362),
    Offset(.365, .448), Offset(.635, .448),
    Offset(.365, .535), Offset(.635, .535),
    Offset(.365, .622), Offset(.635, .622),
    Offset(.365, .710), Offset(.635, .710),
  ];
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
  int _elapsedMs = 0;

  String tr(String bg, String en) => widget.english ? en : bg;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    _loadRecord();
  }

  Future<void> _loadRecord() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _record = prefs.getInt(_recordKey) ?? 0);
  }

  void _start() {
    _clock?.cancel();
    setState(() {
      _items.clear(); _seconds = 60; _elapsedMs = 0; _score = 0;
      _running = true; _finished = false; _paused = false;
      _nextSpawn = DateTime.now();
    });
    _clock = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  void _tick() {
    if (!mounted || !_running || _paused) return;
    final now = DateTime.now();
    setState(() {
      _items.removeWhere((_, item) => item.expiresAt.isBefore(now));
      if (now.isAfter(_nextSpawn) && _items.length < 4) {
        final empty = List<int>.generate(_doorCount, (i) => i).where((i) => !_items.containsKey(i)).toList();
        if (empty.isNotEmpty) {
          final slot = empty[_random.nextInt(empty.length)];
          _items[slot] = _BeachItem(_random.nextBool() ? '⭐' : '🐚', now.add(const Duration(milliseconds: 1450)));
        }
        _nextSpawn = now.add(Duration(milliseconds: 450 + _random.nextInt(750)));
      }
      _elapsedMs += 250;
      if (_elapsedMs >= 1000) { _elapsedMs -= 1000; _seconds--; }
    });
    if (_seconds <= 0) _finish();
  }

  Future<void> _finish() async {
    _clock?.cancel();
    final best = max(_record, _score).toInt();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_recordKey, best);
    if (!mounted) return;
    setState(() { _record = best; _running = false; _finished = true; _items.clear(); });
  }

  void _catch(int index) {
    if (!_running || _paused || !_items.containsKey(index)) return;
    setState(() { _items.remove(index); _score++; });
  }

  void _togglePause() { if (_running) setState(() => _paused = !_paused); }

  @override
  void dispose() {
    _clock?.cancel();
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return Stack(fit: StackFit.expand, children: [
            Image.asset('assets/images/beach_game_background_portrait.png', fit: BoxFit.fill),
            // The artwork's wooden back button is made functional.
            Positioned(left: w * .015, top: h * .008, width: w * .145, height: h * .075,
              child: Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(40), onTap: () => Navigator.of(context).maybePop()))),
            // Invisible hit areas exactly cover the ten doors; the background remains decorative.
            for (var i = 0; i < _doorCount; i++)
              Positioned(
                left: w * (_doorCenters[i].dx - .135),
                top: h * (_doorCenters[i].dy - .043),
                width: w * .27,
                height: h * .086,
                child: Material(color: Colors.transparent, child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => _catch(i),
                  child: Center(child: _items[i] == null ? const SizedBox.expand() : FittedBox(
                    child: Text(_items[i]!.emoji, style: const TextStyle(fontSize: 44, shadows: [Shadow(color: Colors.black87, blurRadius: 8)])),
                  )),
                )),
              ),
            // Live score and timer replace the static values printed in the artwork.
            Positioned(left: w * .265, top: h * .884, width: w * .205, height: h * .075,
              child: Center(child: Text('$_score', style: TextStyle(fontSize: min(w * .085, 34), fontWeight: FontWeight.w900, color: const Color(0xFFFFD52A), shadows: const [Shadow(color: Colors.black87, blurRadius: 4)])))),
            Positioned(left: w * .535, top: h * .884, width: w * .205, height: h * .075,
              child: Center(child: Text('$_seconds', style: TextStyle(fontSize: min(w * .085, 34), fontWeight: FontWeight.w900, color: const Color(0xFFFFD52A), shadows: const [Shadow(color: Colors.black87, blurRadius: 4)])))),
            if (_running) Positioned(right: 12, top: 10, child: Material(
              color: const Color(0xDDFFF3D5), shape: const CircleBorder(), elevation: 4,
              child: IconButton(onPressed: _togglePause, icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded), tooltip: tr('Пауза', 'Pause')),
            )),
            if (_paused || _finished || !_running)
              Positioned.fill(child: Container(color: const Color(0x660A2030), child: Center(child: Card(
                color: const Color(0xFFFFF7E5), margin: const EdgeInsets.all(28),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                child: Padding(padding: const EdgeInsets.all(22), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_paused ? tr('Играта е на пауза', 'Game paused') : _finished ? tr('Браво!', 'Well done!') : tr('Готов ли си?', 'Ready to play?'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF70401C))),
                  const SizedBox(height: 8),
                  Text(_finished ? tr('Точки: $_score  •  Рекорд: $_record', 'Score: $_score  •  Best: $_record') : tr('Докосни вратите, когато се появят звездички и миди!', 'Tap the doors when stars and shells appear!'), textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF70401C))),
                  const SizedBox(height: 14),
                  FilledButton.icon(onPressed: _paused ? _togglePause : _start, icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.play_circle_fill_rounded), label: Text(_paused ? tr('Продължи', 'Resume') : _finished ? tr('Играй отново', 'Play again') : tr('Започни игра', 'Start game'))),
                ])),
              )))),
          ]);
        }),
      ),
    );
  }
}

class _BeachItem {
  const _BeachItem(this.emoji, this.expiresAt);
  final String emoji;
  final DateTime expiresAt;
}
