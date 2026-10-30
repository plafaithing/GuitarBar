// TabView 播放跟随滚动（走查反馈 ②）+ 技法字母标注渲染冒烟（走查反馈 ③）。
// 布局推算同 tab_view_hit_test：测试视口 800×600（body 544 高），
// 4/4 每 3 小节一行；rowHeight = 28+5*18+20 = 138，rowGap = 26。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/ui/scores/tab_view.dart';
import 'package:guitarbar/ui/theme.dart';

ScoreIr _makeIr(int measureCount, {String? technique}) => ScoreIr(
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
              failed: false,
              notes: [
                NoteIr(beat: 0, duration: 1, string: 1, fret: 3,
                    technique: technique),
              ],
            ),
        ]),
      ],
    );

Widget _host(ScoreIr ir, {double? playheadBeat, bool followPlayhead = false}) =>
    MaterialApp(
        theme: GuitarBarTheme.light(),
        home: Scaffold(
          appBar: AppBar(title: const Text('T')),
          body: TabView(
              ir: ir,
              playheadBeat: playheadBeat,
              followPlayhead: followPlayhead),
        ));

double _scrollOffset(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

void main() {
  testWidgets('followPlayhead：播放头跳到第 10 小节（row 3）→ 自动滚动跟随',
      (tester) async {
    await tester.pumpWidget(_host(_makeIr(18),
        playheadBeat: 0, followPlayhead: true));
    await tester.pumpAndSettle();
    expect(_scrollOffset(tester), 0);
    // 小节 index 9（beat 36）在 row 3：y = 3*(138+26)+69 = 561，
    // 超出初始可视窗口（[0, 544-138=406]）→ 应滚动居中，offset > 0。
    await tester.pumpWidget(_host(_makeIr(18),
        playheadBeat: 36, followPlayhead: true));
    await tester.pumpAndSettle();
    expect(_scrollOffset(tester), greaterThan(0));
  });

  testWidgets('播放头在可视窗口内：不滚动（不打断手动滚动）', (tester) async {
    await tester.pumpWidget(_host(_makeIr(18),
        playheadBeat: 0, followPlayhead: true));
    await tester.pumpAndSettle();
    // 小节 index 1（beat 4）仍在 row 0：y = 69，窗口内 → offset 保持 0。
    await tester.pumpWidget(_host(_makeIr(18),
        playheadBeat: 4, followPlayhead: true));
    await tester.pumpAndSettle();
    expect(_scrollOffset(tester), 0);
  });

  testWidgets('followPlayhead=false（默认）：播放头移动不触发滚动', (tester) async {
    await tester.pumpWidget(_host(_makeIr(18), playheadBeat: 0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_host(_makeIr(18), playheadBeat: 36));
    await tester.pumpAndSettle();
    expect(_scrollOffset(tester), 0);
  });

  testWidgets('技法标注渲染冒烟：全字母（h/p/s/b/x/H）绘制不抛异常',
      (tester) async {
    const techs = ['h', 'p', 's', 'b', 'x', 'H'];
    final ir = ScoreIr(
      version: 1,
      title: 'T',
      tempo: 90,
      timeSignature: '4/4',
      tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
      capo: 0,
      tracks: [
        TrackIr(name: '主旋律', measures: [
          for (var i = 0; i < techs.length; i++)
            MeasureIr(
              index: i,
              confidence: 0.9,
              failed: false,
              notes: [
                NoteIr(beat: 0, duration: 1, string: 2, fret: 5,
                    technique: techs[i]),
              ],
            ),
        ]),
      ],
    );
    await tester.pumpWidget(_host(ir, playheadBeat: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
