import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/sound_engine.dart';
import '../../audio/synth.dart';
import '../../core/music/note.dart';
import '../../core/music/scale.dart';
import '../../state/tuning_state.dart';
import '../../ui/theme.dart';

class FretboardPage extends StatefulWidget {
  const FretboardPage({super.key});
  @override
  State<FretboardPage> createState() => _FretboardPageState();
}

class _FretboardPageState extends State<FretboardPage> {
  int _rootPc = 9; // A
  ScaleType _scale = ScaleType.minorPentatonic;
  bool _showSolfege = false;
  final _player = SoundEngine.I;
  bool _ready = false;

  static const _frets = 12;
  static const _pcNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

  @override
  void initState() {
    super.initState();
    _player.init().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  Future<void> _tapCell(TuningState state, int stringIdx, int fret) async {
    final midi = state.current.strings[stringIdx].midi + fret;
    if (_ready) {
      final src = await _player.loadPcm(pluck(Note(midi).frequency(state.a4)));
      _player.play(src);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TuningState>();
    final palette = context.palette;
    final grid = fretboardGrid(state.current.strings, _rootPc, _scale, frets: _frets);
    final majorPcs = scalePitchClasses(_rootPc, ScaleType.major);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          DropdownButton<int>(
            value: _rootPc,
            items: [
              for (var pc = 0; pc < 12; pc++)
                DropdownMenuItem(value: pc, child: Text(_pcNames[pc]))
            ],
            onChanged: (v) => setState(() => _rootPc = v!),
          ),
          const SizedBox(width: 16),
          DropdownButton<ScaleType>(
            value: _scale,
            items: [
              for (final s in ScaleType.values)
                DropdownMenuItem(value: s, child: Text(s.label))
            ],
            onChanged: (s) => setState(() => _scale = s!),
          ),
          const SizedBox(width: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('音名')),
              ButtonSegment(value: true, label: Text('唱名')),
            ],
            selected: {_showSolfege},
            onSelectionChanged: (s) => setState(() => _showSolfege = s.first),
          ),
        ]),
        Text('调弦：${state.current.name}',
            style: TextStyle(fontSize: 12, color: palette.muted)),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final cellW = c.maxWidth / (_frets + 1);
            final cellH = (c.maxHeight - 20) / 6;
            return GestureDetector(
              onTapUp: (d) {
                final fret = ((d.localPosition.dx) ~/ cellW) - 1;
                final str = (d.localPosition.dy ~/ cellH).clamp(0, 5);
                if (fret >= 0 && fret <= _frets) unawaited(_tapCell(state, str, fret));
              },
              child: CustomPaint(
                size: Size(c.maxWidth, c.maxHeight),
                painter: _FretboardPainter(
                    grid: grid,
                    cellW: cellW,
                    cellH: cellH,
                    showSolfege: _showSolfege,
                    rootPc: _rootPc,
                    majorPcs: majorPcs,
                    palette: palette),
              ),
            );
          }),
        ),
      ]),
    );
  }
}

class _FretboardPainter extends CustomPainter {
  _FretboardPainter(
      {required this.grid,
      required this.cellW,
      required this.cellH,
      required this.showSolfege,
      required this.rootPc,
      required this.majorPcs,
      required this.palette});
  final List<List<int?>> grid;
  final double cellW, cellH;
  final bool showSolfege;
  final int rootPc;
  final List<int> majorPcs;
  final GuitarBarPalette palette;

  static const _pcNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

  @override
  void paint(Canvas canvas, Size size) {
    final inScalePaint = Paint()..color = palette.dataHue.withValues(alpha: 0.85);
    final rootPaint = Paint()..color = palette.positive;
    final linePaint = Paint()
      ..color = palette.border
      ..strokeWidth = 1;
    for (var f = 0; f <= 12; f++) {
      final x = cellW * (f + 1);
      canvas.drawLine(Offset(x, 0), Offset(x, cellH * 6), linePaint);
    }
    for (var s = 0; s < 6; s++) {
      canvas.drawLine(Offset(0, cellH * (s + 0.5)),
          Offset(size.width, cellH * (s + 0.5)), linePaint);
    }
    for (var s = 0; s < 6; s++) {
      for (var f = 0; f <= 12; f++) {
        final midi = grid[s][f];
        if (midi == null) continue;
        final isRoot = midi % 12 == rootPc;
        final cx = cellW * (f + 0.5) + cellW / 2;
        final cy = cellH * (s + 0.5);
        canvas.drawCircle(Offset(cx, cy), math.min(cellW, cellH) * 0.36,
            isRoot ? rootPaint : inScalePaint);
        final label = showSolfege
            ? (majorPcs.contains(midi % 12)
                ? solfege[majorPcs.indexOf(midi % 12)]
                : _pcNames[midi % 12])
            : _pcNames[midi % 12];
        final tp = TextPainter(
            text: TextSpan(
                text: label,
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
            textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
      }
    }
    for (final f in const [3, 5, 7, 9, 12]) {
      final tp = TextPainter(
          text: TextSpan(text: '$f', style: TextStyle(fontSize: 10, color: palette.muted)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(cellW * (f + 1) - tp.width / 2, size.height - 14));
    }
  }

  @override
  bool shouldRepaint(_FretboardPainter oldDelegate) => true;
}
