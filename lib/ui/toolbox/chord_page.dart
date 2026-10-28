import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/sound_engine.dart';
import '../../audio/synth.dart';
import '../../core/music/chord_parser.dart';
import '../../core/music/fingering.dart';
import '../../state/tuning_state.dart';
import '../../ui/theme.dart';

class ChordPage extends StatefulWidget {
  const ChordPage({super.key});
  @override
  State<ChordPage> createState() => _ChordPageState();
}

class _ChordPageState extends State<ChordPage> {
  final _input = TextEditingController(text: 'Am7');
  List<ChordVoicing> _voicings = [];
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    SoundEngine.I.init().then((_) {
      if (mounted) setState(() => _ready = true);
    }).onError((_, _) {
      // 音频初始化失败：_ready 保持 false，试听按钮维持禁用。
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _search() {
    final state = context.read<TuningState>();
    try {
      final c = parseChord(_input.text);
      _voicings = FingeringGenerator(state.current.strings)
          .generate(rootPc: c.rootPc, toneClasses: chordToneClasses(c));
      _error = null;
    } on ArgumentError catch (e) {
      _voicings = [];
      _error = e.message?.toString() ?? '解析失败';
    }
    setState(() {});
  }

  Future<void> _play(ChordVoicing v, PlayMode mode) async {
    final state = context.read<TuningState>();
    final pcm = voicingPcm(state.current.strings, v.frets, mode, a4: state.a4);
    final src = await SoundEngine.I.loadPcm(pcm);
    SoundEngine.I.play(src);
    // 播完（琶音最长约 2.3s）后释放音源；连点各自短生命周期，不累积音源。
    final ms = (pcm.length / 44100 * 1000).round() + 200;
    unawaited(Future<void>.delayed(Duration(milliseconds: ms))
        .then((_) => SoundEngine.I.disposeSource(src)));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              decoration: const InputDecoration(
                  labelText: '输入和弦名（如 Am7、F#m7b5）'),
              onSubmitted: (_) => _search(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _search, child: const Text('查询')),
        ]),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_error!, style: TextStyle(color: palette.negative))),
        Expanded(
          child: ListView.builder(
            itemCount: _voicings.length,
            itemBuilder: (_, i) {
              final v = _voicings[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    SizedBox(
                        width: 220,
                        height: 180,
                        child: CustomPaint(
                            painter: _ChordPainter(
                                frets: v.frets,
                                preferLowFret: i == 0,
                                palette: palette))),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      FilledButton.tonal(
                          onPressed:
                              _ready ? () => _play(v, PlayMode.pluckAll) : null,
                          child: const Text('同时')),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                          onPressed:
                              _ready ? () => _play(v, PlayMode.arpeggio) : null,
                          child: const Text('琶音')),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                          onPressed: _ready
                              ? () => _play(v, PlayMode.strumDown)
                              : null,
                          child: const Text('下扫')),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                          onPressed: _ready
                              ? () => _play(v, PlayMode.strumUp)
                              : null,
                          child: const Text('上扫')),
                    ]),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _ChordPainter extends CustomPainter {
  _ChordPainter(
      {required this.frets, required this.preferLowFret, required this.palette});
  final List<int?> frets;
  final bool preferLowFret;
  final GuitarBarPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final fretted = frets.whereType<int>().where((f) => f > 0).toList();
    final minFret = preferLowFret || fretted.isEmpty
        ? 1
        : math.max(1, fretted.reduce((a, b) => a < b ? a : b));
    const visibleFrets = 5;
    final line = Paint()
      ..color = palette.ink
      ..strokeWidth = 1.5;
    final left = 30.0, right = size.width - 10;
    final top = 40.0, gap = (size.height - top - 10) / visibleFrets;
    final stringGap = (right - left) / 5;
    for (var s = 0; s < 6; s++) {
      final x = left + stringGap * s;
      canvas.drawLine(Offset(x, top), Offset(x, top + gap * visibleFrets), line);
    }
    for (var f = 0; f <= visibleFrets; f++) {
      final y = top + gap * f;
      canvas.drawLine(
          Offset(left, y),
          Offset(right, y),
          f == 0
              ? (Paint()
                ..color = palette.ink
                ..strokeWidth = 4)
              : line);
    }
    if (!preferLowFret && fretted.isNotEmpty) {
      final tp = TextPainter(
          text: TextSpan(
              text: '$minFret品',
              style: TextStyle(fontSize: 12, color: palette.muted)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(2, top + gap * 0.5));
    }
    final dot = Paint()..color = palette.dataHue;
    for (var s = 0; s < 6; s++) {
      final f = frets[s];
      final x = left + stringGap * s;
      if (f == null) {
        canvas.drawLine(
            Offset(x - 5, 22),
            Offset(x + 5, 32),
            Paint()
              ..color = palette.negative
              ..strokeWidth = 2);
        canvas.drawLine(
            Offset(x - 5, 32),
            Offset(x + 5, 22),
            Paint()
              ..color = palette.negative
              ..strokeWidth = 2);
      } else if (f == 0) {
        canvas.drawCircle(Offset(x, 27), 5, Paint()..color = palette.positive);
      } else {
        final row = f - minFret;
        if (row >= 0 && row < visibleFrets) {
          canvas.drawCircle(Offset(x, top + gap * (row + 0.5)), 9, dot);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ChordPainter oldDelegate) =>
      oldDelegate.frets != frets || oldDelegate.palette != palette;
}
