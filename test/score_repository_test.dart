import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
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

/// PdfRasterizer 的测试替身：renderPages 直接抛错（触发导入失败清理路径）。
class ThrowingRasterizer implements PdfRasterizer {
  @override
  final double dpi = 200;
  @override
  Future<List<Uint8List>> renderPages(File pdf) async => throw StateError('boom');
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

  test('listScores 过滤回收站、软删保文件、purge 真删（2026-11-05 语义）',
      () async {
    final a = await repo.importScore(
        title: 'A', source: File('${tmp.path}/a.jpg')..writeAsBytesSync(tinyPng()));
    await repo.importScore(
        title: 'B', source: File('${tmp.path}/b.jpg')..writeAsBytesSync(tinyPng()));
    final list = await repo.listScores();
    expect(list.map((e) => e.title), ['B', 'A']);
    // 软删：主列表消失、回收站出现、文件保留（可恢复）。
    await repo.deleteScore(a.id);
    expect(await repo.listScores().then((l) => l.map((e) => e.id)),
        isNot(contains(a.id)));
    expect(await repo.listRecycleBin().then((l) => l.map((e) => e.id)),
        contains(a.id));
    expect(repo.files.pagePngs(a.id), isNotEmpty);
    // 恢复：回主列表。
    await repo.restoreScore(a.id);
    expect(await repo.listScores().then((l) => l.map((e) => e.id)),
        contains(a.id));
    // 彻底删除：行与文件全清。
    await repo.purgeScore(a.id);
    expect(await repo.listScores().then((l) => l.map((e) => e.id)),
        isNot(contains(a.id)));
    expect(repo.files.pagePngs(a.id), isEmpty);
  });

  test('不支持的扩展名抛 ArgumentError', () async {
    final f = File('${tmp.path}/c.txt')..writeAsBytesSync([1]);
    expect(() => repo.importScore(title: 'x', source: f), throwsArgumentError);
  });

  test('importFiles 批量：返回成功数、开始+结束各回调一次、失败不中断', () async {
    // dsh 复测 P1/P3 守卫：开始前也要回调（大 PDF 不冻结进度）、回调
    // 自身异常不进失败计数、失败文件不中断批次、返回值=成功数。
    final ok1 = File('${tmp.path}/f1.png')..writeAsBytesSync(tinyPng());
    final bad = File('${tmp.path}/f2.txt')..writeAsBytesSync([1]);
    final ok2 = File('${tmp.path}/f3.png')..writeAsBytesSync(tinyPng());
    final calls = <(int, int, String, String?)>[];
    final ok = await repo.importFiles([ok1, bad, ok2],
        onProgress: (done, total, name, error) =>
            calls.add((done, total, name, error)));
    expect(ok, 2);
    expect(await repo.listScores(), hasLength(2));
    // 每文件 2 次回调（开始前 + 结束后），共 6 次；顺序与输入一致。
    expect(calls.map((c) => c.$3), ['f1', 'f1', 'f2', 'f2', 'f3', 'f3']);
    // 开始回调 error 恒 null；结束回调仅失败文件带错误。
    expect(calls[0].$4, isNull); // f1 开始
    expect(calls[1].$4, isNull); // f1 结束成功
    expect(calls[2].$4, isNull); // f2 开始
    expect(calls[3].$4, isNotNull); // f2 结束失败
    expect(calls[4].$4, isNull); // f3 开始（失败未中断）
    expect(calls[5].$4, isNull); // f3 结束成功
  });

  test('导入失败：行与文件双清理', () async {
    final failing =
        ScoreRepository(db, ScoreFiles(tmp), rasterizer: ThrowingRasterizer());
    final pdf = File('${tmp.path}/boom.pdf')..writeAsBytesSync([1, 2, 3]);
    await expectLater(
        failing.importScore(title: '坏', source: pdf), throwsStateError);
    // 行已删：库里查无此曲谱。
    expect(await failing.listScores(), isEmpty);
    // 文件已清：base 下无任何曲谱目录（boom.pdf 是用户源文件，不属于清理范围）。
    expect(tmp.listSync().whereType<Directory>(), isEmpty);
  });

  test('导入图片文件夹：多图合成多页、sourcePath 为空标记', () async {
    final d = Directory('${tmp.path}/曲谱文件夹')..createSync();
    File('${d.path}/p2.jpg').writeAsBytesSync(tinyPng());
    File('${d.path}/p1.jpg').writeAsBytesSync(tinyPng());
    final row = await repo.importImages(
        title: 'Like a star',
        images: [File('${d.path}/p1.jpg'), File('${d.path}/p2.jpg')]);
    expect(row.sourceType, 'image');
    expect(row.sourcePath, '');
    expect(repo.files.pagePngs(row.id).length, 2);
    // 混入非图片扩展名：实现按扩展名校验拒绝。
    expect(
        () => repo.importImages(
            title: 'x',
            images: [File('${d.path}/notes.txt')..writeAsBytesSync([1])]),
        throwsArgumentError);
  });

  test('导入图片失败：行与文件双清理', () async {
    // 合法扩展名 + 坏字节：normalizeImage 抛 FormatException 触发清理路径。
    final good = File('${tmp.path}/good.jpg')..writeAsBytesSync(tinyPng());
    final bad = File('${tmp.path}/bad.jpg')..writeAsBytesSync([1, 2, 3]);
    await expectLater(
        repo.importImages(title: '坏', images: [good, bad]),
        throwsFormatException);
    // 行已删：库里查无此曲谱。
    expect(await repo.listScores(), isEmpty);
    // 文件已清：base 下无任何曲谱目录。
    expect(tmp.listSync().whereType<Directory>(), isEmpty);
  });

  test('导入坏 gpx：FormatException 触发行与文件双清理', () async {
    // 非法字节存成 .gpx：parseGpxBytes 抛 FormatException 触发既有 catch
    // 双清理（坏 gpx 也走 saveSourceImage 归档，目录须一并清掉）。
    final f = File('${tmp.path}/bad.gpx')..writeAsBytesSync([1, 2, 3, 4]);
    await expectLater(
        repo.importScore(title: '坏', source: f), throwsFormatException);
    // 行已删：库里查无此曲谱。
    expect(await repo.listScores(), isEmpty);
    // 文件已清：base 下无任何曲谱目录。
    expect(tmp.listSync().whereType<Directory>(), isEmpty);
  });

  test('导入真实 gpx：解析入库已识谱 + 原文件归档', () async {
    // 好路径用真实文件守卫（与 gtp_parser_test 同款 skip 模式）：
    // 合成最小 gpx fixture 太重，确定性解析已由 gtp_parser_test 覆盖。
    final src = File(r'D:\Guitar\月下之恋.gpx');
    if (!src.existsSync()) {
      markTestSkipped('真实 gpx 文件不存在');
      return;
    }
    final row = await repo.importScore(title: '月下の恋', source: src);
    expect(row.sourceType, 'gtp');
    // 解析即入库：irJson 非空且含 62 小节（与 gtp_parser_test 对账一致）。
    expect(row.irJson, isNotNull);
    final ir = jsonDecode(row.irJson!) as Map<String, dynamic>;
    expect(((ir['tracks'] as List).first as Map<String, dynamic>)['measures'],
        hasLength(62));
    expect(row.tuning, 'E2,A2,D3,G3,B3,E4');
    // 无页图：GTP 行不生成 page-*.png。
    expect(repo.files.pagePngs(row.id), isEmpty);
    // 原文件归档：scores/<id>/source.gpx 落盘。
    final archived = repo.files.sourceFile(row.id, row.sourcePath);
    expect(archived.existsSync(), isTrue);
    expect(row.sourcePath, endsWith('source.gpx'));
  });

  test('同名导入自动改名：Windows 语义（名 → 名 (2) → 名 (3)）', () async {
    final f1 = File('${tmp.path}/a.png')..writeAsBytesSync(tinyPng());
    // 两份同名源文件（不同路径同文件名）。
    final sub = Directory('${tmp.path}/sub')..createSync();
    final f2 = File('${sub.path}/a.png')..writeAsBytesSync(tinyPng());
    final f3 = File('${sub.path}/b.png')..writeAsBytesSync(tinyPng());
    final r1 = await repo.importScore(title: '名', source: f1);
    final r2 = await repo.importScore(title: '名', source: f2);
    final r3 = await repo.importScore(title: '名', source: f3);
    expect(r1.title, '名');
    expect(r2.title, '名 (2)');
    expect(r3.title, '名 (3)');
    // 删掉 (2) 后再导入 → 补空位拿回 (2)。
    final rows = await repo.listScores();
    await repo.deleteScore(rows.firstWhere((r) => r.title == '名 (2)').id);
    final f4 = File('${sub.path}/c.png')..writeAsBytesSync(tinyPng());
    final r4 = await repo.importScore(title: '名', source: f4);
    expect(r4.title, '名 (2)');
  });
}
