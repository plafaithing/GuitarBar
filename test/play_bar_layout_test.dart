// PlayBar 三态渲染（播放/暂停/停止）+ 固定一行高回归。
// 一行高回归源自 2026-10-31 走查修复：bottomSheet 槽的宽松约束下
// Container 被拉满可用高度盖住谱面，须在 Scaffold 三种 body 形态下
// 验证 PlayBar 高 < 100。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/ui/scores/play_bar.dart';
import 'package:guitarbar/ui/theme.dart';

void main() {
  /// 底部 PlayBar 宿主（Scaffold bottomSheet 槽，同详情页形态）。
  Widget host(
    bool playing,
    bool paused, {
    bool busy = false,
    VoidCallback? onToggle,
    VoidCallback? onStop,
  }) =>
      MaterialApp(
          theme: GuitarBarTheme.light(),
          home: Scaffold(
            appBar: AppBar(title: const Text('T')),
            body: Container(color: const Color(0xFFEDEBE6)),
            bottomSheet: PlayBar(
                playing: playing,
                paused: paused,
                positionSeconds: 1.0,
                durationSeconds: 100.0,
                busy: busy,
                onToggle: onToggle ?? () {},
                onStop: onStop ?? () {}),
          ));

  IconButton stopButton(WidgetTester tester) => tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.stop));

  testWidgets('未播放：主按钮 play 图标，停止钮禁用', (tester) async {
    await tester.pumpWidget(host(false, false));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsNothing);
    expect(stopButton(tester).onPressed, isNull);
  });

  testWidgets('播放中：主按钮 pause 图标；停止钮可用并触发 onStop', (tester) async {
    var stops = 0;
    await tester.pumpWidget(host(true, false, onStop: () => stops++));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(stopButton(tester).onPressed, isNotNull);
    await tester.tap(find.byIcon(Icons.stop));
    expect(stops, 1);
  });

  testWidgets('暂停中：主按钮回 play 图标（恢复语义），停止钮仍可用', (tester) async {
    await tester.pumpWidget(host(true, true));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsNothing);
    expect(stopButton(tester).onPressed, isNotNull);
  });

  testWidgets('busy：主按钮换 spinner 且禁点', (tester) async {
    await tester.pumpWidget(host(true, false, busy: true));
    // spinner 无限转，pumpAndSettle 会超时——pump 单帧断言。
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.byType(IconButton).first)
            .onPressed,
        isNull);
    expect(stopButton(tester).onPressed, isNull);
  });

  testWidgets('一行高回归：Scaffold 三种 body 形态下均为单行（高 < 100）',
      (tester) async {
    const bar = PlayBar(
        playing: true,
        paused: false,
        positionSeconds: 1.0,
        durationSeconds: 100.0,
        onToggle: _noop,
        onStop: _noop);
    Future<double> pumpHeight(Widget body) async {
      await tester.pumpWidget(MaterialApp(
          theme: GuitarBarTheme.light(),
          home: Scaffold(
              appBar: AppBar(title: const Text('T')),
              body: body,
              bottomSheet: bar)));
      await tester.pumpAndSettle();
      return tester.getSize(find.byType(PlayBar)).height;
    }

    expect(await pumpHeight(const SizedBox.expand()), lessThan(100));
    expect(
        await pumpHeight(LayoutBuilder(builder: (ctx, box) {
          // 宽屏形态（详情页 ≥900）：谱面 + 原图并排。
          return Row(children: const [
            Expanded(child: SizedBox()),
            SizedBox(width: 360, child: SizedBox.expand()),
          ]);
        })),
        lessThan(100));
    expect(
        await pumpHeight(DefaultTabController(
          length: 2,
          child: Column(children: const [
            TabBar(tabs: [Tab(text: 'A'), Tab(text: 'B')]),
            Expanded(child: SizedBox()),
          ]),
        )),
        lessThan(100));
  });
}

void _noop() {}
