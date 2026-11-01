import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';

ScoreIr ir(int measureCount) => ScoreIr(
      version: 1, title: 'T', tempo: 90, timeSignature: '4/4',
      tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], capo: 0,
      tracks: [
        TrackIr(name: '主旋律', measures: [
          for (var i = 0; i < measureCount; i++)
            MeasureIr(index: i, confidence: 0.9, failed: false, notes: const []),
        ]),
      ],
    );

void main() {
  test('beatsPerBar 从拍号解析', () {
    expect(TabLayout(ir(1)).beatsPerBar, 4);
  });

  test('measureWidth = 拍数 × pxPerBeat', () {
    final l = TabLayout(ir(1));
    expect(l.measureWidth, 4 * TabLayout.pxPerBeat);
  });

  test('rowsFor：宽度放得下 3 行 1 行，放不下换行', () {
    final l = TabLayout(ir(5));
    final wide = l.measureWidth * 3 +
        TabLayout.measureGap * 2 + TabLayout.leftPad * 2 + 100;
    final rows = l.rowsFor(wide);
    expect(rows.map((r) => r.length), [3, 2]);

    final rows2 = l.rowsFor(l.measureWidth + TabLayout.leftPad * 2);
    expect(rows2.map((r) => r.length), [1, 1, 1, 1, 1]);
  });

  test('noteX 随 beat 线性（含 notePad 净空，两侧收窄均分）', () {
    final l = TabLayout(ir(1));
    final wide = l.measureWidth + TabLayout.leftPad * 2;
    final x0 = l.noteX(0, 0.0, wide);
    final x1 = l.noteX(0, 1.0, wide);
    // 拍距 = 小节宽两侧各让 notePad 后均分（2026-11-01 竖线避让）。
    expect(x0 - TabLayout.leftPad, TabLayout.notePad);
    expect(
        x1 - x0, (l.measureWidth - TabLayout.notePad * 2) / l.beatsPerBar);
    // 拍位 0 与末拍都不压小节竖线：音符中心离线 ≥ notePad - 数字半宽。
    final xLast = l.noteX(0, l.beatsPerBar.toDouble(), wide);
    expect(xLast - TabLayout.leftPad, lessThanOrEqualTo(l.measureWidth - TabLayout.notePad));
  });

  test('自适应行密度：同弦连排 ≥6 的小节所在行降为 2 小节/行', () {
    // m1 全 16 分连排 16 音（≥6 阈值）：需要宽 > 标准宽 256 → 降密度；
    // 普通小节行保持 3。
    ScoreIr irWithDense() => ScoreIr(
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
                      // 16 分连排（0 起每 0.25 拍一个）
                      for (var k = 0; k < 16; k++)
                        NoteIr(beat: k * 0.25, duration: 0.25,
                            string: 1, fret: 12, technique: null)
                    else
                      NoteIr(beat: 0, duration: 1, string: 1, fret: 0,
                          technique: null),
                  ],
                ),
            ]),
          ],
        );
    final l = TabLayout(irWithDense());
    final wide = l.measureWidth * 3 + TabLayout.leftPad * 2;
    final rows = l.rowsFor(wide);
    // m1（16 连排 ≥8）所在行小节数 < 3（降密度）；普通小节行保持 3。
    final denseRow = rows.firstWhere((r) => r.contains(1));
    expect(denseRow.length, lessThan(3));
    // 密集行的小节更宽：行级拍距拉大，连排间隔 > 标准行。
    final denseRowW = l.measureWidthAt(1, wide);
    expect(denseRowW, greaterThan(l.measureWidth));
    // 密集小节内 16 分相邻音符 x 间距 ≥ 两位数字宽（连排可辨认）。
    final x0 = l.noteX(1, 0.0, wide);
    final x1 = l.noteX(1, 0.25, wide);
    expect(x1 - x0, greaterThanOrEqualTo(18.0));
  });

  test('6 连排（=阈值）降行密度；5 连排（<阈值）保持 3 小节/行', () {
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
    final wide = TabLayout(irWithRun(6)).measureWidth * 3 +
        TabLayout.leftPad * 2;
    // 6 连排（m71 "12×6" 场景，=阈值）→ 所在行降密度。
    final denseRows = TabLayout(irWithRun(6)).rowsFor(wide);
    expect(
        denseRows.firstWhere((r) => r.contains(1)).length, lessThan(3));
    // 5 连排（<阈值）→ 全部行 3 小节。
    final shortRows = TabLayout(irWithRun(5)).rowsFor(wide);
    expect(shortRows.map((r) => r.length), everyElement(3));
  });

  test('stringY：1 弦在最上（y 最小）', () {
    final l = TabLayout(ir(1));
    expect(l.stringY(1, 0), lessThan(l.stringY(6, 0)));
  });
}
