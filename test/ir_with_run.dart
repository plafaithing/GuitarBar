// 共享测试 IR：连排 IR（m1 含 runLen 个 16 分连排音，其余小节 1 音）。
import 'package:guitarbar/core/score/score_ir.dart';

ScoreIr irWithRun(int runLen) => ScoreIr(
      version: 1,
      title: 'T',
      tempo: 90,
      timeSignature: '4/4',
      tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
      capo: 0,
      tracks: [
        TrackIr(name: 'T', measures: [
          for (var m = 0; m < 6; m++)
            MeasureIr(
              index: m,
              confidence: 0.9,
              failed: false,
              notes: [
                if (m == 1)
                  for (var k = 0; k < runLen; k++)
                    NoteIr(beat: 0.5 + k * 0.25, duration: 0.25,
                        string: 1, fret: 12, technique: null)
                else
                  NoteIr(beat: 0, duration: 1, string: 1, fret: 0,
                      technique: null),
              ],
            ),
        ]),
      ],
    );
