import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/ui/scores/note_edit_sheet.dart';

ScoreIr sampleIr() => ScoreIr(
      version: 1, title: 'T', tempo: 90, timeSignature: '4/4',
      tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], capo: 0,
      tracks: [
        TrackIr(name: '主旋律', measures: [
          MeasureIr(index: 0, confidence: 0.9, failed: false, notes: [
            const NoteIr(beat: 0, duration: 1, string: 1, fret: 3,
                technique: null, confidence: 0.5),
          ]),
          const MeasureIr(index: 1, confidence: 0.7, failed: false, notes: [
            NoteIr(beat: 0, duration: 1, string: 3, fret: 0,
                technique: null, confidence: 0.7),
          ]),
        ]),
      ],
    );

void main() {
  test('applyNoteEdit：按 (measure, noteIdx) 替换音符并置 confidence=1', () {
    final out = applyNoteEdit(sampleIr(), 0, 0,
        const NoteIr(beat: 0, duration: 0.5, string: 2, fret: 5,
            technique: 'h', confidence: 1));
    final n = out.tracks[0].measures[0].notes[0];
    expect(n.string, 2);
    expect(n.fret, 5);
    expect(n.duration, 0.5);
    expect(n.technique, 'h');
    expect(n.confidence, 1); // 人工确认标记
    expect(out.tracks[0].measures[0].confidence, 1); // 小节级同步人工确认
    expect(out.tracks[0].measures[0].failed, isFalse);
  });

  test('applyNoteEdit：technique 可置回 null（直接构造语义）', () {
    final ir = ScoreIr(
        version: 1, title: 'T', tempo: 90, timeSignature: '4/4',
        tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], capo: 0,
        tracks: [
          TrackIr(name: '主旋律', measures: [
            MeasureIr(index: 0, confidence: 0.9, failed: false, notes: [
              const NoteIr(beat: 0, duration: 1, string: 1, fret: 12,
                  technique: 'H', confidence: 0.8),
            ]),
          ]),
        ]);
    final out = applyNoteEdit(ir, 0, 0,
        const NoteIr(beat: 0, duration: 1, string: 1, fret: 12,
            technique: null, confidence: 1));
    expect(out.tracks[0].measures[0].notes[0].technique, isNull);
  });

  test('applyMeasureClear：failed 小节重建为空小节', () {
    final ir = ScoreIr(
        version: 1, title: 'T', tempo: 90, timeSignature: '4/4',
        tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], capo: 0,
        tracks: [
          TrackIr(name: '主旋律', measures: [
            const MeasureIr(index: 0, confidence: 0, failed: true, notes: []),
          ]),
        ]);
    final out = applyMeasureClear(ir, 0);
    expect(out.tracks[0].measures[0].failed, isFalse);
    expect(out.tracks[0].measures[0].notes, isEmpty);
    expect(out.tracks[0].measures[0].confidence, 1);
  });

  test('applyNoteEdit：被编辑小节新实例且无关小节保持原实例', () {
    final ir = sampleIr();
    final m0 = ir.tracks[0].measures[0];
    final m1 = ir.tracks[0].measures[1];
    final out = applyNoteEdit(ir, 0, 0,
        const NoteIr(beat: 0, duration: 1, string: 1, fret: 3,
            technique: null, confidence: 1));
    expect(identical(m0, out.tracks[0].measures[0]), isFalse); // 编辑小节新实例
    expect(identical(m1, out.tracks[0].measures[1]), isTrue); // 无关小节保 identity
  });
}
