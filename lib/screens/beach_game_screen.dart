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
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Плажно приключение', 'Beach Adventure'))),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxHeight < 700;
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF24B8E8), Color(0xFF7DE0E7), Color(0xFFFFD58A), Color(0xFFF1B765)],
                stops: [0, .34, .72, 1],
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(compact ? 7 : 14, 8, compact ? 7 : 14, 8),
                  child: Row(
                    children: [
                      Expanded(child: _hud(tr('ТОЧКИ', 'SCORE'), '$_score', Icons.stars_rounded, compact)),
                      const SizedBox(width: 7),
                      Expanded(child: _hud(tr('ВРЕМЕ', 'TIME'), '$_seconds', Icons.timer_rounded, compact)),
                      const SizedBox(width: 7),
                      Expanded(child: _hud(tr('РЕКОРД', 'BEST'), '$_record', Icons.emoji_events_rounded, compact)),
                      if (_running)
                        Padding(
                          padding: const EdgeInsets.only(left: 5),
                          child: Material(
                            color: const Color(0xFFFF9F24),
                            shape: const CircleBorder(),
                            elevation: 3,
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: _togglePause,
                              icon: Icon(
                                _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                                color: const Color(0xFF17364B),
                                size: 27,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: LayoutBuilder(builder: (context, boardConstraints) {
                      // The playfield itself is portrait (9:16); all 20 original doors
                      // remain visible in the central illustrated beach scene.
                      final boardWidth = min(
                        boardConstraints.maxWidth,
                        boardConstraints.maxHeight * (9 / 16),
                      );
                      final boardHeight = boardWidth * (16 / 9);
                      return SizedBox(
                        width: boardWidth,
                        height: boardHeight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: .88), width: 2),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF14516B).withValues(alpha: .28), blurRadius: 20, offset: const Offset(0, 9)),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.asset('assets/images/beach_game_background_portrait.png', fit: BoxFit.cover),
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [Colors.black.withValues(alpha: .02), Colors.transparent, const Color(0xFF7A3F13).withValues(alpha: .07)],
                                      stops: const [0, .55, 1],
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: boardWidth * .185,
                                top: boardHeight * .265,
                                width: boardWidth * .555,
                                height: boardHeight * .145,
                                child: GridView.builder(
                                  padding: EdgeInsets.zero,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: 20,
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 5,
                                    crossAxisSpacing: 2,
                                    mainAxisSpacing: 2,
                                    childAspectRatio: 1.72,
                                  ),
                                  itemBuilder: (context, index) {
                                    final item = _items[index];
                                    return GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onTap: () => _catch(index),
                                      child: Center(
                                        child: item == null
                                            ? const SizedBox.shrink()
                                            : FittedBox(
                                                fit: BoxFit.contain,
                                                child: Text(
                                                  item.emoji,
                                                  style: TextStyle(
                                                    fontSize: boardWidth * .055,
                                                    shadows: const [Shadow(color: Colors.black54, blurRadius: 5)],
                                                  ),
                                                ),
                                              ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              if (_paused || _finished || !_running)
                                Positioned.fill(
                                  child: Container(
                                    color: const Color(0x990D2635),
                                    child: Center(
                                      child: Card(
                                        margin: const EdgeInsets.all(18),
                                        child: Padding(
                                          padding: EdgeInsets.all(compact ? 12 : 20),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                _finished ? tr('Браво!', 'Well done!') : tr('Готов ли си за игра?', 'Ready to play?'),
                                                style: TextStyle(fontSize: compact ? 17 : 23, fontWeight: FontWeight.w900),
                                              ),
                                              const SizedBox(height: 7),
                                              Text(
                                                _finished
                                                    ? tr('Точки: $_score', 'Score: $_score')
                                                    : tr('Хвани краставичките и цветенцата, преди да се скрият!', 'Catch the cucumbers and flowers before they hide!'),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(fontSize: compact ? 11 : 14),
                                              ),
                                              const SizedBox(height: 12),
                                              FilledButton.icon(
                                                onPressed: _start,
                                                icon: const Icon(Icons.play_arrow_rounded),
                                                label: Text(_finished ? tr('Играй отново', 'Play again') : tr('Започни игра', 'Start game')),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(14, 5, 14, compact ? 9 : 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xDDFFF8E8),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFFB84D), width: 1.2),
                    ),
                    child: Text(
                      tr('Докосни вратичка, когато се покаже краставичка или цвете!', 'Tap a gate when a cucumber or flower appears!'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFF573A22),
                        fontWeight: FontWeight.w800,
                        fontSize: compact ? 10 : 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _hud(String label, String value, IconData icon, bool compact) => Container(
    padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 11, vertical: compact ? 5 : 8),
    decoration: BoxDecoration(
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFDFEFF), Color(0xFFEAF7FB)]),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color(0xFFFFFFFF), width: 1.2),
      boxShadow: [BoxShadow(color: const Color(0xFF1C6884).withValues(alpha: .18), blurRadius: 9, offset: const Offset(0, 4))],
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: compact ? 15 : 19, color: const Color(0xFF138BAA)),
        SizedBox(width: compact ? 3 : 6),
        Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 7 : 9, fontWeight: FontWeight.w900, color: const Color(0xFF426174), letterSpacing: .35)),
          Text(value, style: TextStyle(fontSize: compact ? 14 : 19, height: 1.05, fontWeight: FontWeight.w900, color: const Color(0xFF17364B))),
        ])),
      ],
    ),
  );
}

class _BeachItem {
  const _BeachItem(this.emoji, this.expiresAt);
  final String emoji;
  final DateTime expiresAt;
}
