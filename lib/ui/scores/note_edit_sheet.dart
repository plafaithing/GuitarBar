import 'package:flutter/material.dart';

import '../../core/score/score_ir.dart';
import '../theme.dart';

/// 人工修正（设计文档 §5.3）：保存回写 IR，confidence 置 1 = 人工确认。
/// 不可变重建：只替换被编辑的小节，其余节点保持原实例。
ScoreIr applyNoteEdit(ScoreIr ir, int measureIndex, int noteIndex, NoteIr note) {
  final tracks = [
    for (final t in ir.tracks)
      TrackIr(
          name: t.name,
          measures: [
            for (final m in t.measures)
              if (m.index == measureIndex)
                MeasureIr(
                    index: m.index,
                    confidence: 1,
                    failed: false,
                    notes: [
                      for (var i = 0; i < m.notes.length; i++)
                        i == noteIndex ? note : m.notes[i],
                    ])
              else
                m,
          ]),
  ];
  return ScoreIr(
      version: ir.version,
      title: ir.title,
      tempo: ir.tempo,
      timeSignature: ir.timeSignature,
      tuning: ir.tuning,
      capo: ir.capo,
      tracks: tracks,
      unrecognizedPages: ir.unrecognizedPages);
}

/// failed 小节 → 重建为空小节（从"未识别"进入可编辑状态）。
ScoreIr applyMeasureClear(ScoreIr ir, int measureIndex) {
  final tracks = [
    for (final t in ir.tracks)
      TrackIr(
          name: t.name,
          measures: [
            for (final m in t.measures)
              m.index == measureIndex
                  ? MeasureIr(
                      index: m.index, confidence: 1, failed: false,
                      notes: const [])
                  : m,
          ]),
  ];
  return ScoreIr(
      version: ir.version,
      title: ir.title,
      tempo: ir.tempo,
      timeSignature: ir.timeSignature,
      tuning: ir.tuning,
      capo: ir.capo,
      tracks: tracks,
      unrecognizedPages: ir.unrecognizedPages);
}

/// 音符编辑弹层：弦/品/时值/技法快捷编辑。保存直接构造新 NoteIr
/// （copyWith 无法把 technique 置回 null）。
Future<NoteIr?> showNoteEditSheet(BuildContext ctx, NoteIr note) {
  var string = note.string;
  var fret = note.fret;
  var duration = note.duration;
  String? technique = note.technique;
  return showModalBottomSheet<NoteIr>(
    context: ctx,
    builder: (ctx) {
      final p = ctx.palette;
      return StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('编辑音符',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: p.ink)),
                const SizedBox(height: 16),
                Row(children: [
                  Text('弦', style: TextStyle(fontSize: 14, color: p.ink)),
                  const SizedBox(width: 8),
                  for (var s = 1; s <= 6; s++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                          label: Text('$s'),
                          selected: string == s,
                          onSelected: (_) => setLocal(() => string = s)),
                    ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Text('品', style: TextStyle(fontSize: 14, color: p.ink)),
                  const SizedBox(width: 8),
                  IconButton(
                      onPressed: () =>
                          setLocal(() => fret = (fret - 1).clamp(0, 24)),
                      icon: const Icon(Icons.remove_circle_outline)),
                  Text('$fret',
                      style: const TextStyle(fontSize: 18,
                          fontFeatures: [FontFeature.tabularFigures()])),
                  IconButton(
                      onPressed: () =>
                          setLocal(() => fret = (fret + 1).clamp(0, 24)),
                      icon: const Icon(Icons.add_circle_outline)),
                  const SizedBox(width: 16),
                  Text('时值(拍)',
                      style: TextStyle(fontSize: 14, color: p.ink)),
                  const SizedBox(width: 8),
                  for (final d in const [4.0, 2.0, 1.0, 0.5, 0.25])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                          label: Text(d >= 1 ? '${d.toInt()}' : '${(d * 100).toInt()}%'),
                          selected: duration == d,
                          onSelected: (_) => setLocal(() => duration = d)),
                    ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Text('技法', style: TextStyle(fontSize: 14, color: p.ink)),
                  const SizedBox(width: 8),
                  for (final t in const [
                    (null, '无'), ('h', '击'), ('p', '勾'),
                    ('s', '滑'), ('b', '弯'), ('x', '闷'), ('H', '泛'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                          label: Text(t.$2),
                          selected: technique == t.$1,
                          onSelected: (_) => setLocal(() => technique = t.$1)),
                    ),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                        ctx,
                        NoteIr(
                            beat: note.beat,
                            duration: duration,
                            string: string,
                            fret: fret,
                            technique: technique,
                            confidence: 1)),
                    child: const Text('保存'),
                  ),
                ),
              ]),
        ),
      );
    },
  );
}
