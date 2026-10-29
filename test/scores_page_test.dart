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

  testWidgets('列表行显示标题与识谱状态', (tester) async {
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
    expect(find.textContaining('未识谱'), findsOneWidget);
  });
}
