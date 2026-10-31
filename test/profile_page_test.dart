import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/data/database.dart';
import 'package:guitarbar/state/practice_timer.dart';
import 'package:guitarbar/state/theme_settings.dart';
import 'package:guitarbar/ui/profile/profile_page.dart';
import 'package:guitarbar/ui/theme.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('13.4：个人中心不再有识谱模型入口', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    PracticeTimer.init(db);
    final theme = ThemeSettingsState(db);
    await theme.load();
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<AppDatabase>.value(value: db),
      ChangeNotifierProvider<ThemeSettingsState>.value(value: theme),
      ChangeNotifierProvider<PracticeTimer>.value(value: PracticeTimer.I),
    ], child: MaterialApp(
        theme: GuitarBarTheme.light(),
        // ProfilePage 是页面内容（壳由 root 提供），测试补 Scaffold。
        home: const Scaffold(body: ProfilePage()))));
    // 固定 pump 代替 pumpAndSettle：打卡流（drift watch）在 FakeAsync 下
    // 会持续调度帧，pumpAndSettle 永不收敛（探针实测）。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('识谱模型'), findsNothing);
    // 页面本体仍完整（外观分组在）。
    expect(find.text('外观'), findsOneWidget);
    // 先卸载再推时钟：drift watch 取消订阅后会用 Timer.run 短暂保留查询
    // 缓存（drift stream_queries.dart 注释明示），不清会让 timersPending
    // 不变量在测试收尾炸掉。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
