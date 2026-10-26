import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/mic_pitch_stream.dart';
import '../../core/music/builtin_tunings.dart';
import '../../core/music/note.dart';
import '../../core/music/tuning.dart';
import '../../state/tuning_state.dart';
import '../../ui/theme.dart';

enum _TunerMode { guitar, chromatic }

class TunerPage extends StatefulWidget {
  const TunerPage({super.key});
  @override
  State<TunerPage> createState() => _TunerPageState();
}

class _TunerPageState extends State<TunerPage> {
  _TunerMode _mode = _TunerMode.guitar;
  int? _lockedString;
  bool _micOn = false;
  double? _freq;
  StreamSubscription<double?>? _sub;
  final _mic = MicPitchStream();

  @override
  void dispose() {
    _sub?.cancel();
    unawaited(_mic.dispose()); // 页面销毁必须停麦
    super.dispose();
  }

  Future<void> _toggleMic() async {
    if (_micOn) {
      await _sub?.cancel();
      _sub = null;
      await _mic.stop();
      _micOn = false;
      _freq = null;
    } else {
      try {
        final stream = await _mic.start();
        _sub = stream.listen(
          (f) {
            if (mounted) setState(() => _freq = f);
          },
          // 错误契约（见 MicPitchStream）：错误原样转发、结束时收到 done。
          onError: (Object _) {
            if (mounted) setState(() => _freq = null);
          },
          onDone: () {
            if (mounted) {
              _micOn = false;
              setState(() {});
            }
          },
        );
        _micOn = true;
      } on StateError catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }
    setState(() {});
  }

  (int, int)? _nearestString() {
    if (_freq == null) return null;
    final strings = context.read<TuningState>().current.strings;
    final a4 = context.read<TuningState>().a4;
    int best = -1, bestCents = 1 << 30;
    for (var i = 0; i < strings.length; i++) {
      final c = centsOff(_freq!, strings[i].frequency(a4));
      if (c.abs() < bestCents.abs()) {
        bestCents = c;
        best = i;
      }
    }
    return (best, bestCents);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TuningState>();
    int cents = 0;
    Note? targetNote;
    if (_freq != null) {
      if (_mode == _TunerMode.chromatic) {
        targetNote =
            Note(69 + (12 * math.log(_freq! / state.a4) / math.ln2).round());
        cents = centsOff(_freq!, targetNote.frequency(state.a4));
      } else {
        final idx = _lockedString ?? (_nearestString()?.$1 ?? -1);
        if (idx >= 0) {
          targetNote = state.current.strings[idx];
          cents = centsOff(_freq!, targetNote.frequency(state.a4));
        }
      }
    }
    final inTune = _freq != null && cents.abs() <= 3;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Row(children: [
          SegmentedButton<_TunerMode>(
            segments: const [
              ButtonSegment(value: _TunerMode.guitar, label: Text('吉他模式')),
              ButtonSegment(value: _TunerMode.chromatic, label: Text('半音调音器')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const Spacer(),
          IconButton(
              onPressed: () => _showA4Dialog(context, state),
              tooltip: 'A4 参考音高',
              icon: Text('A4=${state.a4.toStringAsFixed(0)}',
                  style: TextStyle(
                      fontSize: 14,
                      color: GuitarBarColors.muted,
                      fontFeatures: const [FontFeature.tabularFigures()]))),
          IconButton(
              onPressed: () => _showPresetSheet(context, state),
              tooltip: '调弦预设',
              icon: const Icon(Icons.list)),
          FilledButton(
              onPressed: _toggleMic,
              child: Text(_micOn ? '停止' : '开始调音')),
        ]),
        const Spacer(),
        // displayLarge 未在主题字阶落角色（M3 默认 57px），按主题契约用 KPI 角色 displaySmall。
        Text(targetNote?.label(flats: _preferFlats(targetNote)) ?? '--',
            style: Theme.of(context).textTheme.displaySmall),
        Text(_freq == null ? '未检测到声音' : '${_freq!.toStringAsFixed(1)} Hz',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        SizedBox(
            width: 280, height: 120,
            child: CustomPaint(painter: _NeedlePainter(cents.toDouble(), inTune))),
        Text('${cents.abs()} 音分 ${cents > 0 ? '偏高' : cents < 0 ? '偏低' : ''}',
            style: TextStyle(
                fontSize: 18,
                color: inTune ? GuitarBarColors.positive : GuitarBarColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()])),
        const Spacer(),
        if (_mode == _TunerMode.guitar)
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < 6; i++)
                ChoiceChip(
                  label: Text('${6 - i}弦 ${state.current.strings[i].name}'),
                  selected: _lockedString == i,
                  onSelected: (sel) =>
                      setState(() => _lockedString = sel ? i : null),
                ),
            ],
          ),
      ]),
    );
  }

  bool _preferFlats(Note n) =>
      ['A#', 'C#', 'D#', 'F#', 'G#'].contains(n.name.substring(0, n.name.length - 1));

  void _showA4Dialog(BuildContext context, TuningState state) {
    double v = state.a4;
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('A4 参考音高'),
      content: StatefulBuilder(builder: (context, setD) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${v.toStringAsFixed(1)} Hz'),
          Slider(value: v, min: 430, max: 450, divisions: 40,
              label: v.toStringAsFixed(1),
              onChanged: (x) => setD(() => v = x)),
        ],
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () { state.setA4(v); Navigator.pop(context); },
            child: const Text('确定')),
      ],
    ));
  }

  void _showPresetSheet(BuildContext context, TuningState state) {
    showModalBottomSheet(context: context, builder: (_) => _PresetSheet(state: state));
  }
}

class _NeedlePainter extends CustomPainter {
  _NeedlePainter(this.cents, this.inTune);
  final double cents;
  final bool inTune;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - 8;
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = GuitarBarColors.border;
    final clamped = cents.clamp(-50.0, 50.0);
    final angle = clamped / 50 * (math.pi / 3); // ±60°
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        math.pi + math.pi / 6, 2 * math.pi / 3, false, arcPaint);
    final needlePaint = Paint()
      ..strokeWidth = 3
      ..color = inTune ? GuitarBarColors.positive : GuitarBarColors.ink;
    final tip = Offset(center.dx + radius * math.sin(angle),
        center.dy - radius * math.cos(angle));
    canvas.drawLine(center, tip, needlePaint);
    for (final c in const [-50, -25, 0, 25, 50]) {
      final a = c / 50 * (math.pi / 3);
      final p1 = Offset(center.dx + (radius - 10) * math.sin(a),
          center.dy - (radius - 10) * math.cos(a));
      final p2 = Offset(center.dx + radius * math.sin(a),
          center.dy - radius * math.cos(a));
      canvas.drawLine(p1, p2, Paint()..color = GuitarBarColors.controlBorder);
    }
  }

  @override
  bool shouldRepaint(_NeedlePainter old) =>
      old.cents != cents || old.inTune != inTune;
}

class _PresetSheet extends StatelessWidget {
  const _PresetSheet({required this.state});
  final TuningState state;

  @override
  Widget build(BuildContext context) {
    final groups = TuningGroup.values;
    return SafeArea(
      child: SizedBox(
        height: 480,
        child: ListView(
          children: [
            for (final g in groups)
              if (g != TuningGroup.custom || state.custom.isNotEmpty)
                ExpansionTile(
                  initiallyExpanded: state.current.group == g,
                  title: Text(g.label),
                  children: [
                    for (final t in [
                      ...builtinTunings.where((x) => x.group == g),
                      if (g == TuningGroup.custom) ...state.custom
                    ])
                      ListTile(
                        title: Text(t.name),
                        subtitle: Text(t.strings.map((n) => n.name).join(' ')),
                        selected: state.current.id == t.id,
                        onTap: () {
                          state.select(t);
                          Navigator.pop(context);
                        },
                        trailing: g == TuningGroup.custom
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () {
                                  state.deleteCustom(t);
                                  Navigator.pop(context);
                                })
                            : IconButton(
                                icon: const Icon(Icons.copy),
                                tooltip: '复制为新预设',
                                onPressed: () => _showEditor(context, state,
                                    base: t)),
                      ),
                    if (g == TuningGroup.custom)
                      ListTile(
                        leading: const Icon(Icons.add),
                        title: const Text('新建自定义调弦'),
                        onTap: () => _showEditor(context, state),
                      ),
                  ],
                ),
          ],
        ),
      ),
    );
  }

  void _showEditor(BuildContext context, TuningState state,
      {TuningPreset? base}) {
    var name = base != null ? '${base.name} 副本' : '新调弦';
    var picked = List<Note>.from(base?.strings ??
        [Note.parse('E2'), Note.parse('A2'), Note.parse('D3'),
         Note.parse('G3'), Note.parse('B3'), Note.parse('E4')]);
    final allNotes = [for (var m = 28; m <= 88; m++) Note(m)];
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: TextFormField(
                  initialValue: name,
                  onChanged: (v) => name = v,
                  decoration: const InputDecoration(labelText: '预设名称')),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 6; i++)
                      DropdownButtonFormField<Note>(
                        // Flutter 3.47：value 已弃用，改用 initialValue。
                        initialValue: picked[i],
                        decoration: InputDecoration(labelText: '${6 - i} 弦'),
                        items: [
                          for (final n in allNotes)
                            DropdownMenuItem(value: n, child: Text(n.name))
                        ],
                        onChanged: (n) => picked[i] = n!,
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () {
                      state.addCustom(name, picked.map((n) => n.name).toList());
                      Navigator.pop(context);
                    },
                    child: const Text('保存')),
              ],
            ));
  }
}
