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

  test('stringY：1 弦在最上（y 最小）', () {
    final l = TabLayout(ir(1));
    expect(l.stringY(1, 0), lessThan(l.stringY(6, 0)));
  });
}
