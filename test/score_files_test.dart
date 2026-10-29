import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/image_normalize.dart';
import 'package:guitarbar/core/score/score_files.dart';
import 'package:image/image.dart' as imgpkg;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('scorefiles'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('saveSourceImage 与 pagePngs 往返', () async {
    // baseDir 即最终父目录，镜像真实调用方传 <support>/scores。
    final scoresDir = Directory('${tmp.path}${Platform.pathSeparator}scores');
    final files = ScoreFiles(scoresDir);
    final src = File('${tmp.path}/in.jpg')..writeAsBytesSync([1, 2, 3]);
    final saved = await files.saveSourceImage(5, src, 'jpg');
    expect(saved.path,
        endsWith('scores${Platform.pathSeparator}5${Platform.pathSeparator}source.jpg'));
    expect(saved.readAsBytesSync(), [1, 2, 3]);

    await files.savePagePngs(5, [
      Uint8List.fromList([9, 9]),
      Uint8List.fromList([8, 8]),
    ]);
    final pages = files.pagePngs(5);
    expect(pages.length, 2);
    expect(pages[0].path, contains('page-001.png'));
    expect(pages[1].path, contains('page-002.png'));

    // sourcePath 目录段只是元数据，实际文件在 <base>/<id>/ 下。
    expect(files.sourceFile(5, 'scores/5/source.jpg').existsSync(), isTrue);

    await files.delete(5);
    expect(files.pagePngs(5), isEmpty);
    expect(File(saved.path).existsSync(), isFalse);
  });

  test('normalizeImage：小图重编码为原尺寸 PNG，大图缩到上限', () async {
    final small = Uint8List.fromList(
        imgpkg.encodePng(imgpkg.Image(width: 100, height: 80)));
    final smallOut = await normalizeImage(small);
    // 输出须是合法 PNG 且保持原尺寸（重编码后字节不必与输入相等）。
    final smallDecoded = imgpkg.decodePng(smallOut)!;
    expect(smallDecoded.width, 100);
    expect(smallDecoded.height, 80);

    final big = Uint8List.fromList(
        imgpkg.encodePng(imgpkg.Image(width: 5000, height: 2500)));
    final out = await normalizeImage(big);
    final decoded = imgpkg.decodeImage(out)!;
    expect(decoded.width, 4096);
    expect(decoded.height, 2048);
  });

  test('normalizeImage：垃圾字节抛 FormatException', () async {
    expect(() => normalizeImage(Uint8List.fromList([1, 2, 3])),
        throwsFormatException);
  });

  test('normalizeImage：截断 GIF 抛 FormatException', () async {
    final truncatedGif =
        Uint8List.fromList([...('GIF89a'.codeUnits), 1, 2, 3, 4]);
    expect(() => normalizeImage(truncatedGif), throwsFormatException);
  });
}
