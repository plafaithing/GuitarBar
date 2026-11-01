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

  /// 打开级联下拉选一项（key=字段 Key，item=菜单项文本）。
  Future<void> pickDropdown(WidgetTester tester,
      {required String key, required String item}) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  testWidgets('默认浏览模式：级联下拉选根音 C 出指法卡', (tester) async {
    await pumpPage(tester);
    // 默认即浏览（2026-11-01 走查）：级联下拉选根音 C → C 大三指法卡。
    await pickDropdown(tester, key: 'chord-root', item: 'C');
    expect(find.byType(Card), findsWidgets);
    // 卡片标和弦名（走查需求）。
    expect(find.text('C'), findsWidgets);
  });

  testWidgets('浏览模式：换子类到小三 → 输入框同步 Cm', (tester) async {
    await pumpPage(tester);
    await pickDropdown(tester, key: 'chord-root', item: 'C');
    // 子类下拉选"小三（m）"。
    await pickDropdown(tester, key: 'chord-type', item: '小三（m）');
    // 名字写回输入框：切回输入模式可见（浏览模式下输入行互斥隐藏）。
    await tester.tap(find.text('输入'));
    await tester.pumpAndSettle();
    expect(find.text('Cm'), findsOneWidget);
  });

  testWidgets('浏览模式：未选根音时提示，不显示指法卡', (tester) async {
    await pumpPage(tester);
    expect(find.textContaining('选定根音后显示指法'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });
}
