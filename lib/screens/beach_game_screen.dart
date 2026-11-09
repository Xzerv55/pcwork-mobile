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
  int _elapsedMs = 0;
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
        final empty = List<int>.generate(20, (i) => i)
            .where((i) => !_items.containsKey(i)).toList();
        if (empty.isNotEmpty) {
          final slot = empty[_random.nextInt(empty.length)];
          _items[slot] = _BeachItem(
            _random.nextBool() ? '🥒' : '🌸',
            now.add(const Duration(milliseconds: 1500)),
          );
        }
        _nextSpawn = now.add(Duration(milliseconds: 350 + _random.nextInt(850)));
      }
    });
    _elapsedMs += 250;
    if (_elapsedMs >= 1000) {
      _elapsedMs -= 1000;
      setState(() => _seconds--);
    }
    if (_seconds <= 0) _finish();
  }

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
      _score++;
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
      appBar: AppBar(
        title: Text(tr('Плажно приключение', 'Beach Adventure')),
        backgroundColor: const Color(0xFF087EAA),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Container(
          color: const Color(0xFF53C9E8),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 9, 9, 8),
                child: Row(
                  children: [
                    Expanded(child: _hud(Icons.star_rounded, tr('ТОЧКИ', 'SCORE'), '$_score')),
                    const SizedBox(width: 6),
                    Expanded(child: _hud(Icons.hourglass_top_rounded, tr('ВРЕМЕ', 'TIME'), '$_seconds')),
                    const SizedBox(width: 6),
                    Expanded(child: _hud(Icons.emoji_events_rounded, tr('РЕКОРД', 'BEST'), '$_record')),
                    const SizedBox(width: 5),
                    Material(
                      color: const Color(0xFFFF8B19),
                      shape: const CircleBorder(),
                      elevation: 5,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _running ? _togglePause : null,
                        child: SizedBox(
                          width: 43,
                          height: 43,
                          child: Icon(
                            _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                            color: Colors.white,
                            size: 29,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          'assets/images/beach_game_background.png',
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.high,
                        ),
                        // Transparent hit targets line up with the 5 x 4 castle doors.
                        Positioned(
                          left: constraints.maxWidth * .185,
                          top: constraints.maxHeight * .175,
                          width: constraints.maxWidth * .635,
                          height: constraints.maxHeight * .615,
                          child: GridView.builder(
                            padding: EdgeInsets.zero,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: 20,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 5,
                              crossAxisSpacing: 2,
                              mainAxisSpacing: 2,
                              childAspectRatio: .96,
                            ),
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              return GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: () => _catch(index),
                                child: Center(
                                  child: item == null
                                      ? const SizedBox.expand()
                                      : AnimatedScale(
                                          scale: 1,
                                          duration: const Duration(milliseconds: 120),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: .94),
                                              shape: BoxShape.circle,
                                              border: Border.all(color: const Color(0xFFFFC44D), width: 3),
                                              boxShadow: const [
                                                BoxShadow(color: Color(0x77000000), blurRadius: 7, offset: Offset(0, 3)),
                                              ],
                                            ),
                                            alignment: Alignment.center,
                                            child: FittedBox(
                                              child: Text(item.emoji, style: const TextStyle(fontSize: 39)),
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
                              color: const Color(0x99052D49),
                              alignment: Alignment.center,
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 28),
                                padding: const EdgeInsets.fromLTRB(22, 23, 22, 22),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFFE6A6), Color(0xFFF5B95F)],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: const Color(0xFF9A5423), width: 4),
                                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 18, offset: Offset(0, 8))],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _paused
                                          ? tr('ПАУЗА', 'PAUSED')
                                          : _finished
                                              ? tr('Браво!', 'Well done!')
                                              : tr('Готов ли си за игра?', 'Ready to play?'),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF713B16)),
                                    ),
                                    const SizedBox(height: 9),
                                    Text(
                                      _finished
                                          ? tr('Точки: $_score', 'Score: $_score')
                                          : tr('Хвани краставичките и цветенцата, преди да се скрият!', 'Catch the cucumbers and flowers before they hide!'),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF71451F)),
                                    ),
                                    const SizedBox(height: 18),
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF168A45),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 23, vertical: 13),
                                      ),
                                      onPressed: _paused ? _togglePause : _start,
                                      icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.sports_esports_rounded),
                                      label: Text(
                                        _paused
                                            ? tr('Продължи', 'Resume')
                                            : _finished
                                                ? tr('Играй отново', 'Play again')
                                                : tr('Започни игра', 'Start game'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hud(IconData icon, String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFB86B2B), Color(0xFF7D3C19)]),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFFFFD27A), width: 2),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 3))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFFFFD54F), size: 22),
            const SizedBox(width: 3),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.clip,
                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white)),
                  Text(value, style: const TextStyle(fontSize: 18, height: 1.05, fontWeight: FontWeight.w900, color: Color(0xFFFFF2C8))),
                ],
              ),
            ),
          ],
        ),
      );
}

class _BeachItem {
  const _BeachItem(this.emoji, this.expiresAt);
  final String emoji;
  final DateTime expiresAt;
}
