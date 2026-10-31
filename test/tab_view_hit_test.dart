import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';
import 'package:guitarbar/ui/scores/tab_view.dart';
import 'package:guitarbar/ui/theme.dart';

/// 命中测试坐标按 TabLayout 公开常量推算（测试视口 800×600）：
/// perRow = ((800-32+0)/(192+0)).floor() = 4 小节/行（小节合并后 gap=0）；
/// noteX = leftPad + col*(measureWidth+measureGap) + beat*pxPerBeat；
/// stringY = row*(rowHeight+rowGap) + topPad + (string-1)*stringGap。
const double _rowHeight =
    TabLayout.topPad + 5 * TabLayout.stringGap + TabLayout.bottomPad; // 138

// 测试 IR 均为 4/4：measureWidth（实例 getter）= 4 * pxPerBeat。
const double _measureWidth = 4 * TabLayout.pxPerBeat;

/// 小节 [index] 在 [row] 行 [col] 列时 beat=0 音符的内容坐标 x。
double _noteX(int col) =>
    TabLayout.leftPad + col * (_measureWidth + TabLayout.measureGap);

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
              notes: failed.contains(i)
                  ? const []
                  : const [
                      NoteIr(beat: 0, duration: 1, string: 1, fret: 3,
                          technique: null),
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
    await pumpTab(tester, makeIr(18, failed: {0, 6}),
        onNoteTap: (m, i, n) => hit = (m, i, n));
    tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position
        .jumpTo(100);
    await tester.pump();
    // 小节 9（row 2 col 1，perRow=4）音符：内容 (208, 356)，滚动 100 →
    // 视口 (208, 256)。
    await tester.tapAt(Offset(_noteX(1), _rowTop(2) - 100));
    expect(hit?.$1, 9);
    expect(hit?.$2, 0);
  });

  testWidgets('滚动后点击 failed 小节：命中所在行而非同列其他行', (tester) async {
    int? failedHit;
    (int, int, NoteIr)? noteHit;
    // perRow=4：小节 8 在 row 2 col 0，与小节 0（row 0 col 0）同列。
    await pumpTab(tester, makeIr(18, failed: {0, 8}),
        onNoteTap: (m, i, n) => noteHit = (m, i, n),
        onFailedTap: (m) => failedHit = m);
    tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position
        .jumpTo(100);
    await tester.pump();
    // 小节 8（row 2 col 0，failed）中心：内容 (112, 401)，滚动 → 视口 (112, 301)。
    // 小节 0 与其同列且同为 failed：无行纵向校验时会先错命中第 0 行的小节 0。
    await tester.tapAt(Offset(
        _noteX(0) + _measureWidth / 2,
        _rowTop(2) + (5 * TabLayout.stringGap) / 2 - 100));
    expect(failedHit, 8);
    expect(noteHit, isNull);
  });
}
