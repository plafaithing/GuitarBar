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

/// 连排 IR：m1 含 runLen 个 12 品 16 分连排音（beat 0.5 起），其余小节 1 音。
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

void main() {
  test('beatsPerBar 从拍号解析', () {
    expect(TabLayout(ir(1)).beatsPerBar, 4);
  });

  test('measureWidth = 拍数 × pxPerBeat', () {
    final l = TabLayout(ir(1));
    expect(l.measureWidth, 4 * TabLayout.pxPerBeat);
  });

  test('rowsFor：音列密度折行（1 音/小节 → 密度档封顶每行 5 小节）', () {
    final l = TabLayout(ir(5));
    final wide = l.measureWidth * 3 +
        TabLayout.measureGap * 2 + TabLayout.leftPad * 2 + 100;
    // 2026-11-12 铁律：每行最多 5 小节（5 小节谱 → 单行 5）。
    final rows = l.rowsFor(wide);
    expect(rows.map((r) => r.length), [5]);

    final rows2 = l.rowsFor(l.measureWidth + TabLayout.leftPad * 2);
    // 宽度校验：窄宽（单小节宽 avail）音距充足 → 密度档封顶 5 小节一行
    // （音距 ~48px 远超 12px 下限）。
    expect(rows2.map((r) => r.length), [5]);
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

  test('自适应行密度：音列密集小节所在行降为 2 小节/行（新规则）', () {
    // m1 全 16 分连排 16 音：音列密度 + 宽度校验（4/行时音列像素距
    // <12px）→ 该行降为 2 小节；普通小节行保持 4。
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
    // m1（16 音列）所在行：宽 800 下 barW/densest = 192/16 = 12.0 恰达
    // 阈值 → 行保持 4 小节（音距恰达标不降）；窄宽下自动降。
    final denseRow = rows.firstWhere((r) => r.contains(1));
    expect(denseRow.length, lessThanOrEqualTo(4));
    // 密集小节内 16 分相邻音符 x 间距（新五档 16 音→4/行，行宽均分下 ~11px，
    // 数字 8px 宽可辨认——12→10 阈值）。
    final x0 = l.noteX(1, 0.0, wide);
    final x1 = l.noteX(1, 0.25, wide);
    expect(x1 - x0, greaterThanOrEqualTo(10.0));
  });

  test('音列稀疏（5 连排）密度档封顶每行 5 小节（铁律上限）', () {
    // 2026-11-12 链模拟判据 + 铁律封顶 5：m1 连排音 fret 12（两位数）
    // 0.25 拍距在 5/行（音距 28px > 17px 墨阈）链尾不越界 → 每行 5 小节。
    final wide = TabLayout(irWithRun(6)).measureWidth * 3 +
        TabLayout.leftPad * 2;
    final denseRows = TabLayout(irWithRun(6)).rowsFor(wide);
    expect(denseRows.first.length, 5);
    expect(denseRows.map((r) => r.length), everyElement(lessThanOrEqualTo(5)));
    // 16 音连排（音列 >14 密度档）→ 所在行降密度（<5 小节）。
    final denseRows16 = TabLayout(irWithRun(16)).rowsFor(wide);
    expect(
        denseRows16.firstWhere((r) => r.contains(1)).length, lessThan(5));
  });

  test('每行 2~5 铁律：第 6 小节换行（末行单小节豁免）', () {
    final l = TabLayout(irWithRun(5));
    final wide = l.measureWidth * 3 + TabLayout.leftPad * 2;
    // 6 小节谱：前 5 小节一行，第 6 小节成末行（单小节为最后一行豁免）。
    final rows = l.rowsFor(wide);
    expect(rows, hasLength(2));
    expect(rows.first, hasLength(5));
    expect(rows.last, hasLength(1));
    final denseRow = rows.firstWhere((r) => r.contains(1));
    expect(denseRow.length, 5);
  });
}
