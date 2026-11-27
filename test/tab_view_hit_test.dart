import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';
import 'package:guitarbar/ui/scores/tab_view.dart';
import 'package:guitarbar/ui/theme.dart';

import 'font_setup.dart';

/// 命中测试坐标按 TabLayout 公开常量推算（测试视口 800×600）：
/// 折行规则（2026-11-09 音列密度驱动）：13 音/小节 → 每行 3 小节
///（perRow=3）；noteX = leftPad + col*measureWidth + notePad +
/// beat*(measureWidth-2*notePad)/beatsPerBeat；
/// stringY = row*(rowHeight+rowGap) + topPad + (string-1)*stringGap。
const double _rowHeight =
    TabLayout.topPad + 5 * TabLayout.stringGap + TabLayout.bottomPad; // 138

// 测试 IR 均为 4/4：measureWidth（实例 getter）= 4 * pxPerBeat。

/// 小节 [index] 在 [row] 行 [col] 列时 beat=0 音符的内容坐标 x。
/// noteX 含 notePad 净空（拍位 0 音符不压小节左竖线）。
/// 2026-11-12 铁律改判：每行最多 5 小节（CLAUDE.md 折行铁律）→
/// **perRow=5**（9 音一位数谱宽校验放行，密度档封顶 5），
/// 行宽 = (800-32)/5 均分。
/// **注意（2026-11-27）**：perRow=5 已不成立——近似同列铁律后 9 音/
/// 小节谱实际 4 小节/行；下方推算坐标仅对 col 0（行首小节，x 与行宽
/// 无关）有效，其余用例一律取真实渲染位置（lastFlow / TabLayout）。
const double _rowWidth = (800.0 - 2 * 16) / 5; // avail/perRow
double _noteX(int col) =>
    TabLayout.leftPad +
    col * _rowWidth +
    TabLayout.notePad;

/// [row] 行 1 弦的内容坐标 y。
double _rowTop(int row) => row * (_rowHeight + TabLayout.rowGap) + TabLayout.topPad;

ScoreIr makeIr(int measureCount, {Set<int> failed = const {}}) => ScoreIr(
      version: 1,
      title: 'T',
      tempo: 90,
      timeSignature: '4/4',
      tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
      capo: 0,
      tracks: [
        TrackIr(name: '主旋律', measures: [
          for (var i = 0; i < measureCount; i++)
            MeasureIr(
              index: i,
              confidence: 0.9,
              failed: failed.contains(i),
              // failed 小节 notes 恒空（Task 10/11 契约）。
              // 折行规则（2026-11-12 铁律封顶 5）：9 音/小节 → 5/行；
              // 本套坐标假设 perRow=5（9 音）。
              notes: failed.contains(i)
                  ? const []
                  : [
                      NoteIr(beat: 0, duration: 1, string: 1, fret: 3,
                          technique: null),
                      for (var b = 0; b < 8; b++)
                        NoteIr(
                            beat: 0.45 + b * 0.45,
                            duration: 0.45,
                            string: 2,
                            fret: (b % 4) + 1),
                    ],
            ),
        ]),
      ],
    );

Future<void> pumpTab(
  WidgetTester tester,
  ScoreIr ir, {
  void Function(int, int, NoteIr)? onNoteTap,
  void Function(int)? onFailedTap,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: GuitarBarTheme.light(),
    home: Scaffold(
      body: TabView(ir: ir, onNoteTap: onNoteTap, onFailedTap: onFailedTap),
    ),
  ));
}

void main() {
  setUpAll(loadScoreFonts);
  testWidgets('未滚动点击音符：回调正确的 measureIndex/noteIndex', (tester) async {
    (int, int, NoteIr)? hit;
    await pumpTab(tester, makeIr(1), onNoteTap: (m, i, n) => hit = (m, i, n));
    // 小节 0 音符（beat 0 / 1 弦）：内容 (16, 28)，未滚动时即视口坐标。
    await tester.tapAt(Offset(_noteX(0), _rowTop(0)));
    expect(hit?.$1, 0);
    expect(hit?.$2, 0);
  });

  testWidgets('滚动后点击同一音符：内容坐标仍命中', (tester) async {
    (int, int, NoteIr)? hit;
    await pumpTab(tester, makeIr(18, failed: {0, 4}),
        onNoteTap: (m, i, n) => hit = (m, i, n));
    tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position
        .jumpTo(100);
    await tester.pump();
    // 点在小节 7 首音（beat 0 / 1 弦）的**实际渲染位置**（lastFlow 内容
    // 坐标，与 paint 同源——铁律「命中与渲染位置一致」）。旧版按
    // perRow=5 均分推算坐标：2026-11-25 近似同列铁律后 9 音/小节谱
    // 5 小节/行拍距仅 15px 被正确拒行（实际 4 小节/行），坐标失效。
    // 本用例验证的是滚动偏移换算，不是折行规则。滚动 100 → 视口 y-100。
    final f = TabViewDebug.lastFlow
        .firstWhere((e) => e.mIdx == 7 && e.note.string == 1);
    await tester.tapAt(Offset(f.x, f.y - 100));
    expect(hit?.$1, 7);
    expect(hit?.$2, 0);
  });

  testWidgets('滚动后点击 failed 小节：命中所在行而非同列其他行', (tester) async {
    int? failedHit;
    (int, int, NoteIr)? noteHit;
    // 取第 2 行首小节 m：与第 0 行首小节（failed）**同列不同行**——
    // 无行纵向校验时会先错命中第 0 行的小节 0。m 由真实折行求出并
    // 断言前提（折行规则演进不影响本用例的验证目标：行级消歧）。
    // 空的 failed 小节更轻，标 failed 后可能被第 0 行吸收——反复取
    // "当前第 2 行首"直到不动点（行首最多 5 小节，必收敛）。
    var failed = <int>{0};
    var m = -1;
    for (var i = 0; i < 8; i++) {
      m = TabLayout(makeIr(18, failed: failed)).rowsFor(800)[1][0];
      failed.add(m);
    }
    final ir = makeIr(18, failed: failed);
    final layout = TabLayout(ir);
    final (row, col) = layout.locate(m, 800);
    final (row0, col0) = layout.locate(0, 800);
    expect(row, greaterThan(row0), reason: '前提：m 须在第 0 行之后');
    expect(col, col0, reason: '前提：m 须与小节 0 同列');
    await pumpTab(tester, ir,
        onNoteTap: (mm, i, n) => noteHit = (mm, i, n),
        onFailedTap: (mm) => failedHit = mm);
    tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position
        .jumpTo(100);
    await tester.pump();
    // 小节 m（failed）中心：滚动 → 视口 y-100。
    await tester.tapAt(Offset(
        layout.measureX(m, 800) + layout.measureWidthAt(m, 800) / 2,
        row * (_rowHeight + TabLayout.rowGap) +
            TabLayout.topPad +
            (5 * TabLayout.stringGap) / 2 -
            100));
    expect(failedHit, m);
    expect(noteHit, isNull);
  });
}
