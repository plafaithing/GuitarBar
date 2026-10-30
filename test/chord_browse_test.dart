import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/data/database.dart';
import 'package:guitarbar/state/tuning_state.dart';
import 'package:guitarbar/ui/theme.dart';
import 'package:guitarbar/ui/toolbox/chord_page.dart';
import 'package:provider/provider.dart';

void main() {
  Future<void> pumpPage(WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final tuning = TuningState(db);
    // 预设加载完成再挂页面（对齐 preset_sheet_test 的先例）。
    await tuning.load();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<TuningState>.value(value: tuning),
      ],
      child: MaterialApp(
          theme: GuitarBarTheme.light(), home: const ChordPage()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('浏览模式：切到浏览 → 选根音 C 出指法卡', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('浏览'));
    await tester.pumpAndSettle();
    // 默认三和弦/大三 + 选根音 C → C 大三至少 1 个指法。
    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsWidgets);
  });

  testWidgets('浏览模式：换子类到小三 → 输入框同步 Cm', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('浏览'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('小三'));
    await tester.pumpAndSettle();
    // 名字写回输入框：切回输入模式可见（浏览模式下输入行互斥隐藏）。
    await tester.tap(find.text('输入'));
    await tester.pumpAndSettle();
    expect(find.text('Cm'), findsOneWidget);
  });

  testWidgets('浏览模式：未选根音时提示，不显示指法卡', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('浏览'));
    await tester.pumpAndSettle();
    expect(find.text('选定根音后显示指法'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });
}
