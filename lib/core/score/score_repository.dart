import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../data/database.dart';
import 'image_normalize.dart';
import 'pdf_raster.dart';
import 'score_files.dart';

/// 曲谱库门面：DB 行 + 文件层的组合操作。UI 只经此访问曲谱。
class ScoreRepository {
  ScoreRepository(this._db, this.files, {PdfRasterizer? rasterizer})
      : rasterizer = rasterizer ?? const PdfRasterizer();

  final AppDatabase _db;
  final ScoreFiles files;
  final PdfRasterizer rasterizer;

  // createdAt 默认值是秒级 CURRENT_TIMESTAMP，同秒导入需按 id 倒序稳定裁决。
  Future<List<Score>> listScores() =>
      (_db.select(_db.scores)
            ..orderBy([
              (s) => OrderingTerm.desc(s.createdAt),
              (s) => OrderingTerm.desc(s.id),
            ]))
          .get();

  /// 导入：插行拿 id → 原图落盘 → 生成页图（PDF 逐页转 PNG / 图片规范化单页）。
  Future<Score> importScore({required String title, required File source}) async {
    final ext = p.extension(source.path).replaceFirst('.', '').toLowerCase();
    final isPdf = ext == 'pdf';
    const imageExts = ['png', 'jpg', 'jpeg', 'webp'];
    if (!isPdf && !imageExts.contains(ext)) {
      throw ArgumentError('不支持的曲谱文件类型: .$ext');
    }
    final id = await _db.into(_db.scores).insert(ScoresCompanion.insert(
        title: title, sourceType: isPdf ? 'pdf' : 'image', sourcePath: ''));
    try {
      final saved = await files.saveSourceImage(id, source, ext);
      final rel = 'scores/$id/${p.basename(saved.path)}';
      await (_db.update(_db.scores)..where((s) => s.id.equals(id)))
          .write(ScoresCompanion(sourcePath: Value(rel)));
      if (isPdf) {
        await files.savePagePngs(id, await rasterizer.renderPages(source));
      } else {
        await files.savePagePngs(
            id, [await normalizeImage(await source.readAsBytes())]);
      }
      return await (_db.select(_db.scores)..where((s) => s.id.equals(id)))
          .getSingle();
    } catch (_) {
      // 导入失败不留半成品：行与文件都要清，防孤儿文件累积。
      await (_db.delete(_db.scores)..where((s) => s.id.equals(id))).go();
      await files.delete(id);
      rethrow;
    }
  }

  Future<void> deleteScore(int id) async {
    await (_db.delete(_db.scores)..where((s) => s.id.equals(id))).go();
    await files.delete(id);
  }

  /// 识谱结果回写（Task 11 用）。
  Future<void> updateRecognition(int id,
      {required String irJson, required String tuning}) async {
    await (_db.update(_db.scores)..where((s) => s.id.equals(id))).write(
        ScoresCompanion(
            irJson: Value(irJson),
            tuning: Value(tuning),
            updatedAt: Value(DateTime.now())));
  }

  /// 人工修正后回写 IR（Task 13 用）。
  Future<void> updateIrJson(int id, String irJson) async {
    await (_db.update(_db.scores)..where((s) => s.id.equals(id))).write(
        ScoresCompanion(
            irJson: Value(irJson), updatedAt: Value(DateTime.now())));
  }
}
