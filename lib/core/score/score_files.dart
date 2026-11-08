import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// 曲谱文件层：原谱文件 + 规范化页图都存在 `<base>/<id>/` 下。
/// 原图 `source.<ext>` 永不改动；page-001.png 起为查看与识谱共用的页图。
///
/// 回收站（2026-11-08 用户定案）：软删曲谱的文件目录**整体挪到**
/// `<base>/del/<id>/`（数据目录 /data 下的 del 子目录），恢复挪回；
/// 彻底删除只清 del 侧。保留 7 天（repository.recycleTtl）。
class ScoreFiles {
  ScoreFiles(this.baseDir);
  final Directory baseDir;

  Directory dirFor(int id) => Directory(p.join(baseDir.path, '$id'));

  /// 回收站目录：`<base>/del/<id>/`。
  Directory recycleDirFor(int id) =>
      Directory(p.join(baseDir.path, 'del', '$id'));

  /// id 当前实际所在目录：回收站侧存在用之，否则主目录（可能都不存在）。
  Directory resolveDir(int id) {
    final rec = recycleDirFor(id);
    if (rec.existsSync()) return rec;
    return dirFor(id);
  }

  Future<File> saveSourceImage(int id, File src, String ext) async {
    final dir = dirFor(id);
    await dir.create(recursive: true);
    return src.copy(p.join(dir.path, 'source.$ext'));
  }

  /// 批量写入页图（page-001.png 起按页序编号）。
  /// 不清理既有页图（调用方约定只在导入时写一次）。
  Future<void> savePagePngs(int id, List<Uint8List> pngs) async {
    final dir = dirFor(id);
    await dir.create(recursive: true);
    for (var i = 0; i < pngs.length; i++) {
      await File(p.join(dir.path, 'page-${(i + 1).toString().padLeft(3, '0')}.png'))
          .writeAsBytes(pngs[i], flush: true);
    }
  }

  /// 页图列表（按页序）；无页图返回空。软删中的 id 自动读 del 侧。
  List<File> pagePngs(int id) {
    final dir = resolveDir(id);
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('page-'))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  }

  /// 按行对象定位原谱：sourcePath 的目录段（`scores/<id>/`）只是相对应用
  /// 支持目录的元数据（导出 zip 用），实际文件在 `<base>/<id>/` 下
  ///（软删中则在 del 侧）。
  File sourceFile(int id, String sourcePath) =>
      File(p.join(resolveDir(id).path, p.basename(sourcePath)));

  /// 软删：文件目录整体挪入回收站侧 `del/<id>/`（同盘 rename 原子）。
  /// 主目录不存在（理论上不该）静默返回。
  Future<void> moveToRecycle(int id) async {
    final from = dirFor(id);
    if (!from.existsSync()) return;
    final to = recycleDirFor(id);
    await to.parent.create(recursive: true);
    if (to.existsSync()) await to.delete(recursive: true);
    await from.rename(to.path);
  }

  /// 恢复：从回收站侧挪回主目录。
  Future<void> restoreFromRecycle(int id) async {
    final from = recycleDirFor(id);
    if (!from.existsSync()) return;
    final to = dirFor(id);
    if (to.existsSync()) await to.delete(recursive: true);
    await from.rename(to.path);
  }

  /// 彻底删除（双位置兜底：正常在 del 侧；历史软删数据兼容主目录）。
  Future<void> delete(int id) async {
    for (final dir in [recycleDirFor(id), dirFor(id)]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  }
}
