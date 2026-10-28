import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/music/tuning.dart';
import 'package:guitarbar/data/database.dart' hide TuningPreset;
import 'package:guitarbar/state/tuning_state.dart';
import 'package:guitarbar/ui/theme.dart';
import 'package:guitarbar/ui/tuner/preset_sheet.dart';

void main() {
  late AppDatabase db;
  late TuningState state;
  final selected = <TuningPreset>[];

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    state = TuningState(db);
    await state.load();
    selected.clear();
  });
  tearDown(() => db.close());

  Future<void> pumpSheet(WidgetTester tester, {bool dark = false}) async {
    await tester.pumpWidget(MaterialApp(
      theme: dark ? GuitarBarTheme.dark() : GuitarBarTheme.light(),
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 420,
            height: 600,
            child: PresetSheet(
              state: state,
              onSelect: (t) => selected.add(t),
              onCreate: () {},
              onDuplicate: (t) => selected.add(t),
              onDelete: (t) => selected.add(t),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('当前预设只有一个勾，且第一个内置项默认选中', (tester) async {
    await pumpSheet(tester);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(state.current.id, 'builtin-Standard');
    expect(find.text('Standard'), findsOneWidget);
  });

  testWidgets('默认只展开「自定义」与当前预设所在组', (tester) async {
    await pumpSheet(tester);
    // 当前预设是 Standard（标准/降调组）：该组可见。
    expect(find.text('Standard'), findsOneWidget);
    // Drop 组默认收起：组标题在，里面的预设不在。
    expect(find.text('Drop'), findsOneWidget);
    expect(find.text('Drop D'), findsNothing);
    expect(find.text('DADGAD'), findsNothing);
  });

  testWidgets('点分组标题可以展开 / 收起', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('Drop'));
    await tester.pumpAndSettle();
    expect(find.text('Drop D'), findsOneWidget);

    await tester.tap(find.text('Drop'));
    await tester.pumpAndSettle();
    expect(find.text('Drop D'), findsNothing);
  });

  testWidgets('点击预设行 → 回调拿到该预设', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('Drop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drop D'));
    await tester.pumpAndSettle();
    expect(selected.single.name, 'Drop D');
  });

  testWidgets('内置行菜单只有「复制」，自定义行菜单只有「删除」', (tester) async {
    await state.addCustom('我的 Open C', ['C2', 'G2', 'C3', 'G3', 'C4', 'E4']);
    await pumpSheet(tester);

    // 自定义行（列表最上方）的「更多」。
    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pumpAndSettle();
    expect(find.text('删除这个预设'), findsOneWidget);
    expect(find.text('复制为新预设'), findsNothing);
    await tester.tapAt(const Offset(20, 20)); // 关菜单
    await tester.pumpAndSettle();

    // 内置行（Standard 所在行）的「更多」。
    await tester.tap(find.byIcon(Icons.more_horiz).at(1));
    await tester.pumpAndSettle();
    expect(find.text('复制为新预设'), findsOneWidget);
    expect(find.text('删除这个预设'), findsNothing);
  });

  testWidgets('渲染预览图（浅/深色，供人工比对）', (tester) async {
    await state.addCustom('我的 Open C', ['C2', 'G2', 'C3', 'G3', 'C4', 'E4']);
    await state.addCustom('练习用 Drop D', ['D2', 'A2', 'D3', 'G3', 'B3', 'E4']);
    final dir = Directory('${Directory.systemTemp.path}/guitarbar-shots');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    tester.view.physicalSize = const Size(760, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final dark in const [false, true]) {
      final key = GlobalKey();
      final theme = dark ? GuitarBarTheme.dark() : GuitarBarTheme.light();
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: theme.scaffoldBackgroundColor,
                width: 560,
                height: 700,
                child: Center(
                  child: SizedBox(
                    width: 420,
                    height: 600,
                    child: PresetSheet(
                      state: state,
                      onSelect: (_) {},
                      onCreate: () {},
                      onDuplicate: (_) {},
                      onDelete: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image =
          await tester.runAsync(() => boundary.toImage(pixelRatio: 2.0));
      final bytes = await tester
          .runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
      try {
        File('${dir.path}/preset-${dark ? 'dark' : 'light'}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      } on FileSystemException {
        // 只读环境跳过写图，测试本身不做断言。
      }
      image!.dispose();
    }
  });
}
