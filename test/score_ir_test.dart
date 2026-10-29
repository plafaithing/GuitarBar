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
}
