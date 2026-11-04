import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/database.dart';
import 'gp5_parser.dart';
import 'gtp_parser.dart';
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

  /// 默认路径工厂：曲谱根 = `<数据根>/scores`（2026-11-03 迁移，与
  /// SQLite 共用 resolveDataRoot 的候选链与兜底——Defender 对无签名
  /// exe 封锁 C:\Users 全域写，exe 旁 data 目录兜底）。历史
  /// AppData\...\scores 存在则一次性迁入（保曲谱文件）。
  static Future<ScoreRepository> createDefault(AppDatabase db) async {
    final root = await resolveDataRoot();
    final scoresRoot = Directory(p.join(root.path, 'scores'));
    // 一次性迁移历史曲谱文件（AppData → 数据根）。**跨盘迁移用复制**
    ///（C:→D: 的 renameSync 会抛跨卷异常）。
    final legacyDir = await getApplicationSupportDirectory();
    final legacyRoot = Directory(p.join(legacyDir.path, 'scores'));
    try {
      if (legacyRoot.existsSync()) {
        for (final e in legacyRoot.listSync()) {
          if (e is! Directory) continue;
          final name = p.basename(e.path);
          final dest = Directory(p.join(scoresRoot.path, name));
          if (dest.existsSync()) continue; // 已迁过
          for (final f in e.listSync(recursive: true)) {
            if (f is! File) continue;
            final rel = p.relative(f.path, from: e.path);
            final df = File(p.join(dest.path, rel));
            df.parent.createSync(recursive: true);
            f.copySync(df.path);
          }
        }
      }
    } catch (_) {} // 迁移失败（源不可读）：新库照常工作
    return ScoreRepository(db, ScoreFiles(scoresRoot));
  }

  /// 支持的曲谱图片扩展名（小写、无点）：repository 校验与 UI 文件夹过滤共用。
  static const imageExts = ['png', 'jpg', 'jpeg', 'webp'];

  // createdAt 默认值是秒级 CURRENT_TIMESTAMP，同秒导入需按 id 倒序稳定裁决。
  Future<List<Score>> listScores() =>
      (_db.select(_db.scores)
            ..orderBy([
              (s) => OrderingTerm.desc(s.createdAt),
              (s) => OrderingTerm.desc(s.id),
            ]))
          .get();

  /// 单行读取（详情页用）。
  Future<Score?> getScore(int id) =>
      (_db.select(_db.scores)..where((s) => s.id.equals(id)))
          .getSingleOrNull();

  /// 导入：插行拿 id → 原图落盘 → 生成页图（PDF 逐页转 PNG / 图片规范化单页）。
  Future<Score> importScore({required String title, required File source}) async {
    final ext = p.extension(source.path).replaceFirst('.', '').toLowerCase();
    final isPdf = ext == 'pdf';
    // GTP 系：gpx（GP6/7 容器）与 gp5（Guitar Pro 5 二进制）。
    final isGtp = ext == 'gpx' || ext == 'gp5';
    if (!isPdf && !isGtp && !imageExts.contains(ext)) {
      throw ArgumentError('不支持的曲谱文件类型: .$ext');
    }
    final id = await _db.into(_db.scores).insert(ScoresCompanion.insert(
        title: title,
        sourceType: isPdf ? 'pdf' : isGtp ? 'gtp' : 'image',
        sourcePath: ''));
    try {
      final saved = await files.saveSourceImage(id, source, ext);
      final rel = 'scores/$id/${p.basename(saved.path)}';
      if (isGtp) {
        // GTP 精确导入（设计 §13.3）：解析即入库，confidence 全 null
        // （确定性数据无 AI 置信度）；无页图（谱面就是数据本身）。
        final bytes = await source.readAsBytes();
        final ir =
            ext == 'gp5' ? parseGp5Bytes(bytes) : parseGpxBytes(bytes);
        await (_db.update(_db.scores)..where((s) => s.id.equals(id))).write(
            ScoresCompanion(
                irJson: Value(jsonEncode(ir.toJson())),
                tuning: Value(ir.tuning.join(',')),
                sourcePath: Value(rel)));
        return await (_db.select(_db.scores)..where((s) => s.id.equals(id)))
            .getSingle();
      }
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

  /// 批量导入（2026-11-03 走查三件套）：多文件逐个 importScore（每文件
  /// 独立曲谱条目，标题取文件名去扩展名），返回成功条数。onProgress 参数
  /// =（已完成数, 总数, 当前文件名, 失败信息?）——**开始处理每个文件前
  /// 也回调一次**（dsh 复测 P1：大 PDF 转图期间进度不冻结在上一个文件），
  /// 失败不中断批次（结果汇总由调用方展示）。回调移出 try：回调自身
  /// 抛异常不会被误计成导入失败。
  Future<int> importFiles(
    List<File> sources, {
    void Function(int done, int total, String name, String? error)? onProgress,
  }) async {
    var ok = 0;
    for (var i = 0; i < sources.length; i++) {
      final f = sources[i];
      final name = p.basename(f.path).replaceFirst(RegExp(r'\.[^.]+$'), '');
      onProgress?.call(i, sources.length, name, null); // 开始前
      String? error;
      try {
        await importScore(title: name, source: f);
        ok++;
      } catch (e) {
        error = e.toString();
      }
      onProgress?.call(i + 1, sources.length, name, error); // 结束后
    }
    return ok;
  }

  /// 自然排序比较：数字段按数值、文本段按字典序（大小写不敏感）。
  /// 用于多图文件名排序（谱例-2 应在谱例-10 前）。
  static int naturalCompare(String a, String b) {
    var i = 0, j = 0;
    while (i < a.length && j < b.length) {
      final ca = a[i], cb = b[j];
      final da = _isDigit(ca), db = _isDigit(cb);
      if (da && db) {
        var si = i;
        while (i < a.length && _isDigit(a[i])) {
          i++;
        }
        var sj = j;
        while (j < b.length && _isDigit(b[j])) {
          j++;
        }
        // 不用 int.parse：20+ 位数字段会抛 FormatException 且调用方（UI 排序）
        // 无兜底。等价方案：去前导零后先比长度、再逐位字典序——无前导零的
        // 等长数字串字典序即数值序；去零时至少保留一位（'007'=='7'）。
        String strip(String s, int from, int to) {
          var start = from;
          while (start < to - 1 && s.codeUnitAt(start) == 0x30) {
            start++;
          }
          return s.substring(start, to);
        }
        final ra = strip(a, si, i), rb = strip(b, sj, j);
        final c = ra.length != rb.length
            ? ra.length.compareTo(rb.length)
            : ra.compareTo(rb);
        if (c != 0) return c;
      } else {
        final c = ca.toLowerCase().compareTo(cb.toLowerCase());
        if (c != 0) return c;
        i++;
        j++;
      }
    }
    return (a.length - i).compareTo(b.length - j);
  }

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

  /// 导入图片文件夹：多张图片按给定顺序合成一份多页曲谱。
  /// 页图即规范化源（原谱留在用户文件夹，不拷贝）；sourcePath 留空标记
  /// "无单一原谱文件"。
  /// 规模边界：全部页图先入内存再落盘，50+ 张大文件夹留待边规范化边写。
  Future<Score> importImages(
      {required String title, required List<File> images}) async {
    if (images.isEmpty) {
      throw ArgumentError('图片列表为空');
    }
    for (final f in images) {
      final ext = p.extension(f.path).replaceFirst('.', '').toLowerCase();
      if (!imageExts.contains(ext)) {
        throw ArgumentError('不支持的曲谱文件类型: .$ext');
      }
    }
    final id = await _db.into(_db.scores).insert(ScoresCompanion.insert(
        title: title, sourceType: 'image', sourcePath: ''));
    try {
      final pages = <Uint8List>[];
      for (final f in images) {
        pages.add(await normalizeImage(await f.readAsBytes()));
      }
      await files.savePagePngs(id, pages);
      return await (_db.select(_db.scores)..where((s) => s.id.equals(id)))
          .getSingle();
    } catch (_) {
      // 与 importScore 同款：失败不留半成品。
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

  /// 链接备注回写（2026-11-03 走查三件套）：null = 清除备注。
  Future<void> updateNoteUrl(int id, String? url) async {
    await (_db.update(_db.scores)..where((s) => s.id.equals(id))).write(
        ScoresCompanion(
            noteUrl: Value(url), updatedAt: Value(DateTime.now())));
  }

  /// 重命名回写（2026-11-03 用户需求）：非空/无空格/同类型唯一性校验
  /// 由 UI 层负责（需要全列表上下文，repo 不重复查库）。
  Future<void> updateTitle(int id, String title) async {
    await (_db.update(_db.scores)..where((s) => s.id.equals(id))).write(
        ScoresCompanion(title: Value(title), updatedAt: Value(DateTime.now())));
  }
}
