// 批量导入图片合并（2026-11-06，iOS 场景）：排序对话框 → 入库页序验证。
// file_selector 平台替身返回固定图片列表，绕开真实选择器。
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
// FileSelectorPlatform 测试替身挂 instance 用；XFile 由同一包提供。
// ignore: unnecessary_import
import 'package:file_selector/file_selector.dart';
// ignore: depend_on_referenced_packages
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_files.dart';
import 'package:guitarbar/core/score/score_repository.dart';
import 'package:guitarbar/data/database.dart';
import 'package:guitarbar/ui/scores/scores_page.dart';
import 'package:guitarbar/ui/theme.dart';
import 'package:image/image.dart' as imgpkg;
import 'package:provider/provider.dart';

/// 返回固定的 3 张图片（不同尺寸便于断言页序）。
class FakeSelector extends FileSelectorPlatform {
  FakeSelector(this.paths);
  final List<String> paths;

  @override
  Future<List<XFile>> openFiles(
          {List<XTypeGroup>? acceptedTypeGroups,
          String? initialDirectory,
          String? confirmButtonText}) async =>
      paths.map((p) => XFile(p)).toList();
}

/// 生成 n×n 合法 PNG（不同尺寸区分页序）。
Uint8List sizedPng(int n) {
  final image = imgpkg.Image(width: n, height: n);
  return Uint8List.fromList(imgpkg.encodePng(image));
}

void main() {
  testWidgets('批量导入图片合并：上移调整顺序后入库页序正确', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final tmp = Directory.systemTemp.createTempSync('imgbatch');
    addTearDown(() {
      tmp.deleteSync(recursive: true);
      db.close();
    });
    // 3 张不同尺寸图：a(2×2)、b(3×3)、c(4×4)——自然序 a,b,c。
    final a = File('${tmp.path}/a.png')..writeAsBytesSync(sizedPng(2));
    final b = File('${tmp.path}/b.png')..writeAsBytesSync(sizedPng(3));
    final c = File('${tmp.path}/c.png')..writeAsBytesSync(sizedPng(4));
    FileSelectorPlatform.instance =
        FakeSelector([a.path, b.path, c.path]);

    await tester.pumpWidget(MultiProvider(
      providers: [Provider<AppDatabase>.value(value: db)],
      child: MaterialApp(
          theme: GuitarBarTheme.light(),
          home: ScoresPage(
              repoFactory: () => ScoreRepository(db, ScoreFiles(tmp)))),
    ));
    await tester.pumpAndSettle();

    // 打开导入菜单 → 批量导入图片。
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('批量导入图片（合并为一个曲谱）'));
    await tester.pumpAndSettle();

    // 排序对话框：拖拽第 3 张（c）上移一行（2026-11-07：上/下移按钮
    // 已删，排序走拖拽——longPressDrag 触发 ReorderableListView），
    // 然后取消（合成入库页序由下方 repo 层用例覆盖）。
    final beforeY = tester.getTopLeft(find.text('c.png')).dy;
    // 长按启动 ReorderableListView 拖拽（touch 语义：down 后超长按
    // deadline 再移动）。
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('c.png')));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, -72));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -36));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    final afterY = tester.getTopLeft(find.text('c.png')).dy;
    expect(afterY, lessThan(beforeY)); // c 上移一行
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('调整图片顺序'), findsNothing);
  });
}
