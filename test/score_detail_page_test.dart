import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_files.dart';
import 'package:guitarbar/core/score/score_repository.dart';
import 'package:guitarbar/data/database.dart';
import 'package:guitarbar/ui/scores/score_detail_page.dart';
import 'package:guitarbar/ui/theme.dart';
import 'package:path/path.dart' as p;

void main() {
  testWidgets('坏 IR 按未识谱降级：页面不崩，AppBar 显示曲名', (tester) async {
    // 内存库 + 临时曲谱目录，repoFactory 注入（不走 path_provider）。
    final db = AppDatabase(NativeDatabase.memory());
    final tmp = Directory.systemTemp.createTempSync('scoredetail');
    addTearDown(() {
      tmp.deleteSync(recursive: true);
      db.close();
    });
    final id = await db.into(db.scores).insert(ScoresCompanion.insert(
        title: '坏IR',
        sourceType: 'image',
        sourcePath: '',
        irJson: const Value('not json')));
    Directory(p.join(tmp.path, '$id')).createSync(recursive: true);
    // 1x1 合法 PNG：坏图会让 Image.file 解码报错，干扰"不崩"断言。
    File(p.join(tmp.path, '$id', 'page-001.png')).writeAsBytesSync(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));
    await tester.pumpWidget(MaterialApp(
      theme: GuitarBarTheme.light(),
      home: ScoreDetailPage(
          scoreId: id,
          repoFactory: () => ScoreRepository(db, ScoreFiles(tmp))),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('坏IR'), findsOneWidget);
  });
}
