// tap 语义诊断：gpif XML 全量 LeftHandTapped/Tapped Note 数 vs IR tap 数。
@Tags(['heavy'])
library;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/gtp_parser.dart';

void main() {
  test('tap 计数对账', () {
    final f = File(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores\83\source.gpx');
    final bytes = Uint8List.fromList(f.readAsBytesSync());
    final xml = String.fromCharCodes(gpifBytes(bytes));
    // XML 全量 Note 级 Property 计数
    final xmlLht = RegExp(r'<Property name="LeftHandTapped">')
            .allMatches(xml)
            .length +
        RegExp(r'<Property name="Tapped">').allMatches(xml).length;
    // 解析器入口（同 gtp_parser 真实路径）
    final ir = parseGpxBytes(bytes, sourceName: 'source.gpx');
    var irTap = 0;
    for (final m in ir.tracks.first.measures) {
      for (final n in m.notes) {
        if (n.tap) irTap++;
      }
    }
    final track = ir.tracks.first;
    debugPrint('xmlLht=$xmlLht irTap=$irTap '
        'measures=${track.measures.length} notes=${track.measures.fold<int>(0, (a, m) => a + m.notes.length)}');
    // tap=true 音的 string/fret 采样
    var shown = 0;
    for (var mi = 0; mi < track.measures.length && shown < 10; mi++) {
      for (final n in track.measures[mi].notes) {
        if (n.tap && shown < 10) {
          debugPrint('  m${mi + 1} b${n.beat} s${n.string} f${n.fret} '
              'ghost=${n.ghost} harmonic=${n.harmonicType}');
          shown++;
        }
      }
    }
  });
}
