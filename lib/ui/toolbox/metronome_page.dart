import 'package:flutter/material.dart';

import '../../audio/metronome_engine.dart';
import '../../audio/sound_engine.dart';
import '../../ui/theme.dart';

class MetronomePage extends StatefulWidget {
  const MetronomePage({super.key});
  @override
  State<MetronomePage> createState() => _MetronomePageState();
}

class _MetronomePageState extends State<MetronomePage> {
  late final MetronomeEngine _engine = MetronomeEngine(SoundEngine.I);
  final _taps = <DateTime>[];

  static const _timeSigs = [(2, '2/4'), (3, '3/4'), (4, '4/4'), (6, '6/8')];
  static const _subs = [(1, '四分'), (2, '八分'), (3, '三连音'), (4, '十六分')];

  @override
  void dispose() {
    _engine.stop(); // Task 11 审查要求：离开页面必须停引擎
    super.dispose();
  }

  Future<void> _toggle() async {
    _engine.running ? await _engine.stop() : await _engine.start();
    setState(() {});
  }

  void _tap() {
    _taps.add(DateTime.now());
    if (_taps.length > 8) _taps.removeAt(0);
    final bpm = bpmFromTaps(_taps);
    if (bpm > 0) {
      setState(() => _engine.cfg = MetronomeConfig(
          bpm: bpm.clamp(30, 300).toDouble(),
          beatsPerBar: _engine.cfg.beatsPerBar,
          subdivision: _engine.cfg.subdivision));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cfg = _engine.cfg;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        // 拍点指示灯：小节头 dataHue、正拍 ink、非活动 rule（数据元素着色）
        ValueListenableBuilder<int>(
          valueListenable: _engine.currentTick,
          builder: (_, tick, _) {
            final beatInBar =
                tick < 0 ? -1 : (tick ~/ cfg.subdivision) % cfg.beatsPerBar;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < cfg.beatsPerBar; i++)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == beatInBar
                            ? (i == 0 ? palette.dataHue : palette.ink)
                            : palette.rule,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(cfg.bpm.toStringAsFixed(0),
            style: Theme.of(context).textTheme.displaySmall
                ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        Text('BPM', style: TextStyle(fontSize: 12, color: palette.muted)),
        Slider(
          value: cfg.bpm,
          min: 30,
          max: 300,
          onChanged: _engine.running
              ? null
              : (v) => setState(() => _engine.cfg = MetronomeConfig(
                  bpm: v,
                  beatsPerBar: cfg.beatsPerBar,
                  subdivision: cfg.subdivision)),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          OutlinedButton.icon(
              onPressed: _tap,
              icon: const Icon(Icons.back_hand, size: 16),
              label: const Text('Tap 点速')),
          const SizedBox(width: 12),
          FilledButton(
              onPressed: _toggle,
              child: Text(_engine.running ? '停止' : '开始')),
        ]),
        const SizedBox(height: 16),
        // 拍号与细分：同排两个下拉
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          DropdownButton<int>(
            value: cfg.beatsPerBar,
            items: [
              for (final (b, l) in _timeSigs)
                DropdownMenuItem(value: b, child: Text(l))
            ],
            onChanged: (b) => setState(() => _engine.cfg = MetronomeConfig(
                bpm: cfg.bpm, beatsPerBar: b!, subdivision: cfg.subdivision)),
          ),
          const SizedBox(width: 24),
          DropdownButton<int>(
            value: cfg.subdivision,
            items: [
              for (final (s, l) in _subs)
                DropdownMenuItem(value: s, child: Text(l))
            ],
            onChanged: (s) => setState(() => _engine.cfg = MetronomeConfig(
                bpm: cfg.bpm, beatsPerBar: cfg.beatsPerBar, subdivision: s!)),
          ),
        ]),
      ]),
    );
  }
}
