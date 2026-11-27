// 一次性对账：Prologue 全曲 tie 标志 dart 端 dump（vs py 对账——
// 定位 m2 b0 6弦3 类误标的影响范围）。输出 tasks/tie_audit_dart.txt。
@Tags(['heavy'])
library;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'overlap_probe_lib.dart' show parseScore;

void main() {
  test('tie 对账 dart 端', () {
    final dir = Directory(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores');
    final ir = dir.listSync().map((d) {
      final f = File('${d.path}\\source.gtp');
      if (!f.existsSync()) return null;
      try {
        final c = parseScore(Uint8List.fromList(f.readAsBytesSync()), 'x');
        return (c != null && c.title.contains('Prologue')) ? c : null;
      } catch (_) {
        return null;
      }
    }).firstWhere((c) => c != null)!;
    final buf = StringBuffer();
    final ms = ir.tracks.first.measures;
    for (var mi = 0; mi < ms.length; mi++) {
      for (final n in ms[mi].notes) {
        if (n.tieStart || n.tieEnd) {
          buf.writeln('m${mi + 1} b${n.beat.toStringAsFixed(3)} '
              's${n.string} f${n.fret} '
              '${n.tieStart ? 'S' : ''}${n.tieEnd ? 'E' : ''}');
        }
      }
    }
    File(r'D:\workplace\code\GuitarBar\tasks\tie_audit_dart.txt')
        .writeAsStringSync(buf.toString());
    // ignore: avoid_print
    print('dumped ${buf.toString().split('\n').length - 1} tie flags');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
