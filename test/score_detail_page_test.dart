import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_files.dart';
import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/core/score/score_repository.dart';
import 'package:guitarbar/data/database.dart';
import 'package:guitarbar/ui/scores/score_detail_page.dart';
import 'package:guitarbar/ui/scores/source_viewer.dart';
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

  testWidgets('已识谱：谱面顶部信息条显示调弦/Capo/曲速', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final tmp = Directory.systemTemp.createTempSync('scoredetail');
    addTearDown(() {
      tmp.deleteSync(recursive: true);
      db.close();
    });
    final ir = ScoreIr(
        version: 1,
        title: 'T',
        tempo: 90,
        timeSignature: '4/4',
        tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
        capo: 3,
        tracks: [
          TrackIr(name: '主旋律', measures: [
            const MeasureIr(index: 0, confidence: 0.9, failed: false, notes: [
              NoteIr(beat: 0, duration: 1, string: 1, fret: 0,
                  technique: null, confidence: null),
            ]),
          ]),
        ]);
    final id = await db.into(db.scores).insert(ScoresCompanion.insert(
        title: '有IR',
        sourceType: 'image',
        sourcePath: '',
        irJson: Value(jsonEncode(ir.toJson()))));
    Directory(p.join(tmp.path, '$id')).createSync(recursive: true);
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
    // 标准调弦命中内置预设名 Standard（_tuningLabel 预设匹配）。
    // Capo 标注已移到谱面 capo:N 文字（信息条去重，2026-11-08）。
    expect(find.text('调弦 Standard · 90 BPM'), findsOneWidget);
  });

  // GTP 全屏（13.4）：谱面直接占满，无右侧查看器/TabBar/识谱按钮。
  ScoreIr gtpIr() => ScoreIr(
      version: 1,
      title: 'T',
      tempo: 90,
      timeSignature: '4/4',
      tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
      capo: 0,
      tracks: [
        TrackIr(name: '主旋律', measures: [
          const MeasureIr(index: 0, confidence: 0, failed: false, notes: [
            NoteIr(beat: 0, duration: 1, string: 1, fret: 0,
                technique: null, confidence: null),
          ]),
        ]),
      ]);

  Future<int> insertGtp(AppDatabase db) => db.into(db.scores).insert(
      ScoresCompanion.insert(
          title: 'GTP谱',
          sourceType: 'gtp',
          sourcePath: '',
          irJson: Value(jsonEncode(gtpIr().toJson()))));

  Future<void> pumpDetail(WidgetTester tester, AppDatabase db, Directory tmp,
          int id) =>
      tester.pumpWidget(MaterialApp(
        theme: GuitarBarTheme.light(),
        home: ScoreDetailPage(
            scoreId: id,
            repoFactory: () => ScoreRepository(db, ScoreFiles(tmp))),
      ));

  testWidgets('GTP 全屏：窄屏无查看器与 TabBar，识谱按钮已移除', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final tmp = Directory.systemTemp.createTempSync('scoredetail');
    addTearDown(() {
      tmp.deleteSync(recursive: true);
      db.close();
    });
    final id = await insertGtp(db);
    await pumpDetail(tester, db, tmp, id);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SourceViewer), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byIcon(Icons.document_scanner_outlined), findsNothing);
    // 谱面信息条直接显示（capo 0 不出 Capo 段）
    expect(find.text('调弦 Standard · 90 BPM'), findsOneWidget);
  });

  testWidgets('GTP 全屏：宽屏同样不显示右侧查看器', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase(NativeDatabase.memory());
    final tmp = Directory.systemTemp.createTempSync('scoredetail');
    addTearDown(() {
      tmp.deleteSync(recursive: true);
      db.close();
    });
    final id = await insertGtp(db);
    await pumpDetail(tester, db, tmp, id);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SourceViewer), findsNothing);
    expect(find.text('调弦 Standard · 90 BPM'), findsOneWidget);
  });
}
