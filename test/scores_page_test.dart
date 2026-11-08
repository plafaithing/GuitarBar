import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_files.dart';
import 'package:guitarbar/core/score/score_repository.dart';
import 'package:guitarbar/data/database.dart';
import 'package:guitarbar/ui/scores/scores_page.dart';
import 'package:guitarbar/ui/theme.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  // 每用例独立环境：内存库 + 临时曲谱目录。
  (AppDatabase, Directory) makeEnv() {
    final db = AppDatabase(NativeDatabase.memory());
    final tmp = Directory.systemTemp.createTempSync('scorespage');
    addTearDown(() {
      tmp.deleteSync(recursive: true);
      db.close();
    });
    return (db, tmp);
  }

  // 页面自带 Scaffold 壳（MaterialApp home 直挂，测试壳分叉会掩盖缺壳问题）。
  Future<void> pumpPage(WidgetTester tester, AppDatabase db, Directory tmp) =>
      tester.pumpWidget(MultiProvider(
        providers: [Provider<AppDatabase>.value(value: db)],
        child: MaterialApp(
            theme: GuitarBarTheme.light(),
            home: ScoresPage(
                repoFactory: () => ScoreRepository(db, ScoreFiles(tmp)))),
      ));

  testWidgets('空态显示导入引导', (tester) async {
    final (db, tmp) = makeEnv();
    await pumpPage(tester, db, tmp);
    await tester.pumpAndSettle();
    expect(find.text('还没有曲谱，点右上角导入图片或 PDF'), findsOneWidget);
  });

  testWidgets('列表行显示标题与查看器状态', (tester) async {
    final (db, tmp) = makeEnv();
    // 直接插行 + 同步造一张页图；不走 importScore——真实异步文件 IO
    // 在 FakeAsync 测试区会挂死。
    final id = await db.into(db.scores).insert(ScoresCompanion.insert(
        title: '测试曲', sourceType: 'image', sourcePath: 'scores/1/source.png'));
    Directory(p.join(tmp.path, '$id')).createSync(recursive: true);
    File(p.join(tmp.path, '$id', 'page-001.png')).writeAsBytesSync([0]);
    await pumpPage(tester, db, tmp);
    await tester.pumpAndSettle();
    expect(find.text('测试曲'), findsOneWidget);
    expect(find.textContaining('查看器'), findsOneWidget);
  });

  // 重命名（2026-11-03 用户需求）：保存时校验非空/无空格/同类型唯一。
  // 对话框输入框要限定在 AlertDialog 内——页面背后还有搜索框 TextField。
  Finder dialogField(WidgetTester tester) => find.descendant(
      of: find.byType(AlertDialog), matching: find.byType(TextField));

  Future<void> seedTwo(WidgetTester tester, AppDatabase db) async {
    await db.into(db.scores).insert(ScoresCompanion.insert(
        title: '甲曲', sourceType: 'image', sourcePath: ''));
    await db.into(db.scores).insert(ScoresCompanion.insert(
        title: '乙曲', sourceType: 'image', sourcePath: ''));
  }

  // 重命名入口（三点菜单已删）：长按行 → 卡片浮层 → 卡内编辑钮。
  // 固定帧 pump（页面内持续动画会让 pumpAndSettle 超时）。
  Future<void> openRenameViaCard(WidgetTester tester, String title) async {
    await tester.longPress(find.text(title).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('重命名'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('重命名：同类型重名自动递增（2026-11-07 语义）', (tester) async {
    final (db, tmp) = makeEnv();
    await seedTwo(tester, db);
    await pumpPage(tester, db, tmp);
    await tester.pumpAndSettle();
    // 列表按拼音首字母分组排序：第一行是甲曲（jia → J 组）。改成乙曲
    //（撞名）→ 自动递增保存为「乙曲 (1)」。
    await openRenameViaCard(tester, '甲曲');
    await tester.enterText(dialogField(tester), '乙曲');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('乙曲 (1)'), findsOneWidget);
    final rows = await db.select(db.scores).get();
    expect(rows.where((r) => r.title == '乙曲 (1)'), hasLength(1));
    expect(rows.where((r) => r.title == '乙曲'), hasLength(1)); // 原名仍在
  });

  testWidgets('重命名：内部空格允许、两侧空格 trim 后保存', (tester) async {
    final (db, tmp) = makeEnv();
    await seedTwo(tester, db);
    await pumpPage(tester, db, tmp);
    await tester.pumpAndSettle();
    // 乙曲行：内部空格合法；两侧空格 trim 掉。
    await openRenameViaCard(tester, '乙曲');
    await tester.enterText(dialogField(tester), '  乙 曲  ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('乙 曲'), findsOneWidget); // trim 后显示，无错误拦截
  });

  testWidgets('重命名：合法名字保存生效', (tester) async {
    final (db, tmp) = makeEnv();
    await seedTwo(tester, db);
    await pumpPage(tester, db, tmp);
    await tester.pumpAndSettle();
    await openRenameViaCard(tester, '甲曲');
    await tester.enterText(dialogField(tester), '甲曲_v2');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('甲曲_v2'), findsOneWidget);
    final rows = await db.select(db.scores).get();
    expect(rows.firstWhere((r) => r.title == '甲曲_v2').title, '甲曲_v2');
  });
}
