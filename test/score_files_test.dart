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

    await files.delete(5);
    expect(files.pagePngs(5), isEmpty);
    expect(File(saved.path).existsSync(), isFalse);
  });

  test('normalizeImage：小图原样返回，大图缩到上限', () async {
    final small = Uint8List.fromList(
        imgpkg.encodePng(imgpkg.Image(width: 100, height: 80)));
    expect((await normalizeImage(small)).length, small.length);

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
}
