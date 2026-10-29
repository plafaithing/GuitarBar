import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/pdf_raster.dart';
import 'package:guitarbar/core/score/score_files.dart';
import 'package:guitarbar/core/score/score_repository.dart';
import 'package:guitarbar/data/database.dart';
import 'package:image/image.dart' as imgpkg;

/// PdfRasterizer 的测试替身：固定返回两页假 PNG。
class FakeRasterizer implements PdfRasterizer {
  @override
  final double dpi = 200;
  @override
  Future<List<Uint8List>> renderPages(File pdf) async =>
      [Uint8List.fromList([1]), Uint8List.fromList([2])];
}

/// 生成合法 1×1 PNG 字节（normalizeImage 需要可解码图片）。
Uint8List tinyPng() {
  final img = imgpkg.Image(width: 1, height: 1);
  return Uint8List.fromList(imgpkg.encodePng(img));
}

void main() {
  late Directory tmp;
  late AppDatabase db;
  late ScoreRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('scorerepo');
    db = AppDatabase(NativeDatabase.memory());
    repo = ScoreRepository(db, ScoreFiles(tmp), rasterizer: FakeRasterizer());
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('导入图片：落库 + 原图 + 单页图', () async {
    final img = File('${tmp.path}/a.png')..writeAsBytesSync(tinyPng());
    final row = await repo.importScore(title: '小星星', source: img);
    expect(row.sourceType, 'image');
    expect(row.irJson, isNull);
    expect(repo.files.pagePngs(row.id).length, 1);
    expect(repo.files.sourceFile(row.id, row.sourcePath).existsSync(), isTrue);
  });

  test('导入 PDF：两页页图', () async {
    final pdf = File('${tmp.path}/b.pdf')..writeAsBytesSync([1, 2, 3]);
    final row = await repo.importScore(title: '练习曲', source: pdf);
    expect(row.sourceType, 'pdf');
    expect(repo.files.pagePngs(row.id).length, 2);
  });

  test('listScores 按创建时间倒序、deleteScore 清库清文件', () async {
    final a = await repo.importScore(
        title: 'A', source: File('${tmp.path}/a.jpg')..writeAsBytesSync(tinyPng()));
    await repo.importScore(
        title: 'B', source: File('${tmp.path}/b.jpg')..writeAsBytesSync(tinyPng()));
    final list = await repo.listScores();
    expect(list.map((e) => e.title), ['B', 'A']);
    await repo.deleteScore(a.id);
    expect(await repo.listScores().then((l) => l.map((e) => e.id)),
        isNot(contains(a.id)));
    expect(repo.files.pagePngs(a.id), isEmpty);
  });

  test('不支持的扩展名抛 ArgumentError', () async {
    final f = File('${tmp.path}/c.txt')..writeAsBytesSync([1]);
    expect(() => repo.importScore(title: 'x', source: f), throwsArgumentError);
  });
}
