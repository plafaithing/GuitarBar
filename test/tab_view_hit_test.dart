import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';
import 'package:guitarbar/ui/scores/tab_view.dart';
import 'package:guitarbar/ui/theme.dart';

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
    // 折行（5/行）：小节 7（row 1 col 2）音符：
    // 内容 (noteX(2), rowTop(1))，滚动 100 → 视口 y-100。
    await tester.tapAt(Offset(_noteX(2), _rowTop(1) - 100));
    expect(hit?.$1, 7);
    expect(hit?.$2, 0);
  });

  testWidgets('滚动后点击 failed 小节：命中所在行而非同列其他行', (tester) async {
    int? failedHit;
    (int, int, NoteIr)? noteHit;
    // perRow=5：小节 4 在 row 0 col 4——与小节 0（row 0 col 0）同**行**。
    // 小节 5 占 row 1 col 0（正常），failed 的小节 6 落 row 1 col 1
    // （与其小节 0 同列）。
    await pumpTab(tester, makeIr(18, failed: {0, 6}),
        onNoteTap: (m, i, n) => noteHit = (m, i, n),
        onFailedTap: (m) => failedHit = m);
    tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position
        .jumpTo(100);
    await tester.pump();
    // 小节 6（row 1 col 1，failed）中心：滚动 → 视口 y-100。
    // 小节 0 与其同列且同为 failed：无行纵向校验时会先错命中第 0 行的小节 0。
    await tester.tapAt(Offset(
        _noteX(1) + _rowWidth / 2,
        _rowTop(1) + (5 * TabLayout.stringGap) / 2 - 100));
    expect(failedHit, 6);
    expect(noteHit, isNull);
  });
}
