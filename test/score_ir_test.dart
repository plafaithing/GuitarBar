import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_ir.dart';

ScoreIr sample() => ScoreIr(
      version: 1,
      title: '小星星',
      tempo: 90,
      timeSignature: '4/4',
      tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
      capo: 0,
      tracks: [
        TrackIr(name: '主旋律', measures: [
          MeasureIr(index: 0, confidence: 0.92, failed: false, notes: [
            NoteIr(beat: 0, duration: 1, string: 1, fret: 3,
                technique: null, confidence: 0.95),
          ]),
          MeasureIr(index: 1, confidence: 0, failed: true, notes: const []),
        ]),
      ],
      unrecognizedPages: const [2],
    );

void main() {
  test('IR JSON 往返无损', () {
    final a = sample();
    final b = ScoreIr.fromJson(jsonDecode(jsonEncode(a.toJson())));
    expect(b, a);
  });

  test('failed 小节序列化保留 failed 与空 notes', () {
    final m = sample().tracks[0].measures[1];
    final back = MeasureIr.fromJson(jsonDecode(jsonEncode(m.toJson())));
    expect(back.failed, isTrue);
    expect(back.notes, isEmpty);
    expect(back.confidence, 0);
  });

  test('unrecognizedPages 往返', () {
    expect(sample().toJson()['unrecognizedPages'], [2]);
  });

  test('fromJson 空对象走全兜底', () {
    final ir = ScoreIr.fromJson(const {});
    expect(ir.version, 1);
    expect(ir.title, '未命名');
    expect(ir.tempo, 90);
    expect(ir.timeSignature, '4/4');
    expect(ir.tuning, isEmpty);
    expect(ir.capo, 0);
    expect(ir.tracks, isEmpty);
    expect(ir.unrecognizedPages, isEmpty);
  });

  test('== 字段不同则不等，相等则 hashCode 一致', () {
    final a = sample();
    final b = sample();
    expect(b, a);
    expect(b.hashCode, a.hashCode);

    final c = ScoreIr(
        version: a.version,
        title: '别的歌',
        tempo: a.tempo,
        timeSignature: a.timeSignature,
        tuning: a.tuning,
        capo: a.capo,
        tracks: a.tracks,
        unrecognizedPages: a.unrecognizedPages);
    expect(c, isNot(a));
  });

  test('copyWith 改 fret 后其余字段不变', () {
    final n = sample().tracks[0].measures[0].notes[0];
    final m = n.copyWith(fret: 5);
    expect(m.fret, 5);
    expect(m.beat, n.beat);
    expect(m.duration, n.duration);
    expect(m.string, n.string);
    expect(m.technique, n.technique);
    expect(m.confidence, n.confidence);
  });
}
