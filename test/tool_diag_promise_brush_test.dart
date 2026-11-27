// 一次性诊断：Promise(75, GP5) 新方向解析清单（vs py 13 down 对照）。
// heavy：硬编码曲库 id（75→82 漂移）——诊断使命已完成（结论落盘
// tasks/promise_brush_out.txt + todo 记档），日常套件跳过。
@Tags(['heavy'])
library;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:guitarbar/core/score/gp5_parser.dart';

void main() {
  test('Promise(75) GP5 brush 清单',
      skip: '一次性诊断已完结（结论落盘 promise_brush_out.txt）；曲库 id 漂移'
          ' 75→82→已删，需用时改路径重启用', () {
    final f = File(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores\75\source.gp5');
    final ir = parseGp5Bytes(Uint8List.fromList(f.readAsBytesSync()));
    final track = ir.tracks.first;
    final out = <String>[];
    var n = 0;
    for (final m in track.measures) {
      for (final note in m.notes) {
        if (note.brush != null) {
          n++;
          out.add('源m${m.index + 1} b${note.beat.toStringAsFixed(2)} '
              's${note.string}f${note.fret} ${note.brush}');
        }
      }
    }
    out.add('总 brush=$n');
    File(r'D:\workplace\code\GuitarBar\tasks\promise75_brush_out.txt')
        .writeAsStringSync(out.join('\n'));
  });
}
