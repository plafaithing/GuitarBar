// TabView 播放跟随滚动（走查反馈 ②）+ 技法字母标注渲染冒烟（走查反馈 ③）。
// 布局推算同 tab_view_hit_test：测试视口 800×600（body 544 高），
// 4/4 每 4 小节一行（小节合并 measureGap=0）；rowHeight = 28+5*18+20 = 138，
// rowGap = 26。
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
  testWidgets('followPlayhead：播放头跳到第 14 小节（row 3）→ 自动滚动跟随',
      (tester) async {
    await tester.pumpWidget(_host(_makeIr(18),
        playheadBeat: 0, followPlayhead: true));
    await tester.pumpAndSettle();
    expect(_scrollOffset(tester), 0);
    // 小节 index 13（beat 52）在 row 3（perRow=4）：y = 3*(138+26)+28 = 520，
    // 超出初始可视窗口（[0, 544-138=406]）→ 应滚动居中，offset > 0。
    await tester.pumpWidget(_host(_makeIr(18),
        playheadBeat: 52, followPlayhead: true));
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
    const techs = ['h', 'p', 's', 'b', 'x', 'H'];    final ir = ScoreIr(
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

  testWidgets('渲染冒烟：103 小节谱 + followPlayhead 逐帧推进不抛异常',
      (tester) async {
    final ir = _makeIr(103);
    await tester.pumpWidget(_host(ir, playheadBeat: 0, followPlayhead: true));
    await tester.pumpAndSettle();
    // 模拟播放 50ms tick：逐拍推进（跨多行触发跟随滚动动画），
    // 谱面层不重绘、播放头层逐帧重录，全程无异常。
    for (var beat = 4.0; beat <= 120; beat += 4) {
      await tester.pumpWidget(
          _host(ir, playheadBeat: beat, followPlayhead: true));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 跟随滚动实际发生（beat 120 → 小节 30 → row 7，已滚出初始窗口）。
    expect(_scrollOffset(tester), greaterThan(0));
  });

  testWidgets('标注弧线系统渲染冒烟：tie/hopo/legato/shift/L.R./P.M./'
      'vibrato/ghost/tap 全标注绘制不抛异常（GP8 标注补齐）', (tester) async {
    final ir = ScoreIr(
      version: 1,
      title: 'T',
      tempo: 90,
      timeSignature: '4/4',
      tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
      capo: 0,
      tracks: [
        TrackIr(name: '主旋律', measures: [
          for (var i = 0; i < 4; i++)
            MeasureIr(
              index: i,
              confidence: 0.9,
              failed: false,
              notes: [
                // 小节 0：tie 弧线对（起点+续接端）。
                const NoteIr(beat: 0, duration: 1, string: 1, fret: 12,
                    technique: 'H', tieStart: true),
                const NoteIr(beat: 1, duration: 1, string: 1, fret: 12,
                    technique: 'H', tieEnd: true),
                // 小节 0：hopo 对（品升 H）+ letRing 段。
                const NoteIr(beat: 2, duration: 1, string: 2, fret: 0,
                    hopoStart: true),
                const NoteIr(beat: 3, duration: 1, string: 2, fret: 2,
                    hopoEnd: true, letRing: true),
                // 小节 1：letRing 续段（同弦）+ vibrato + ghost。
                const NoteIr(beat: 0, duration: 1, string: 2, fret: 4,
                    letRing: true),
                const NoteIr(beat: 1, duration: 1, string: 3, fret: 7,
                    vibrato: true),
                const NoteIr(beat: 2, duration: 1, string: 4, fret: 9,
                    ghost: true),
                // 小节 1：P.M. 连续段（跨弦）。
                const NoteIr(beat: 3, duration: 1, string: 4, fret: 1,
                    palmMute: true, technique: 'x'),
                // 小节 2：P.M. 续段 + shift 滑音 + legato 弧。
                const NoteIr(beat: 0, duration: 1, string: 5, fret: 1,
                    palmMute: true, technique: 'x'),
                const NoteIr(beat: 1, duration: 1, string: 5, fret: 3,
                    slide: 'shift'),
                const NoteIr(beat: 2, duration: 1, string: 5, fret: 5,
                    legatoStart: true, slide: 'legato'),
                const NoteIr(beat: 3, duration: 1, string: 5, fret: 7,
                    legatoEnd: true),
                // 小节 3：tap + 孤立标注（弧线无同弦后继 → 短弧兜底）。
                const NoteIr(beat: 0, duration: 1, string: 6, fret: 0,
                    tap: true),
                const NoteIr(beat: 1, duration: 1, string: 6, fret: 3,
                    tieStart: true),
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
