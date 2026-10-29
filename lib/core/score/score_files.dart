import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// 曲谱文件层：原谱文件 + 规范化页图都存在 `<base>/<id>/` 下。
/// 原图 `source.<ext>` 永不改动；page-001.png 起为查看与识谱共用的页图。
class ScoreFiles {
  ScoreFiles(this.baseDir);
  final Directory baseDir;

  Directory dirFor(int id) => Directory(p.join(baseDir.path, '$id'));

  Future<File> saveSourceImage(int id, File src, String ext) async {
    final dir = dirFor(id);
    await dir.create(recursive: true);
    return src.copy(p.join(dir.path, 'source.$ext'));
  }

  Future<void> savePagePngs(int id, List<Uint8List> pngs) async {
    final dir = dirFor(id);
    await dir.create(recursive: true);
    for (var i = 0; i < pngs.length; i++) {
      await File(p.join(dir.path, 'page-${(i + 1).toString().padLeft(3, '0')}.png'))
          .writeAsBytes(pngs[i], flush: true);
    }
  }

  /// 页图列表（按页序）；无页图返回空。
  List<File> pagePngs(int id) {
    final dir = dirFor(id);
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('page-'))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  }

  File sourceFile(int id, String sourcePath) =>
      File(p.join(baseDir.path, sourcePath));

  Future<void> delete(int id) async {
    final dir = dirFor(id);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}
