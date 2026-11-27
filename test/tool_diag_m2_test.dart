// "2"×"<12>" 重叠根因：m2 两个音的 IR 来源（同 beat 同 string？）
@Tags(['heavy'])
library;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/gtp_parser.dart';

void main() {
  test('m2 音清单', () {
    final f = File(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores\83\source.gpx');
    final bytes = Uint8List.fromList(f.readAsBytesSync());
    final ir = parseGpxBytes(bytes, sourceName: 'source.gpx');
    for (final mi in [0, 1, 2, 6, 7]) {
      final m = ir.tracks.first.measures[mi];
      debugPrint('--- m${mi + 1} ---');
      for (final n in m.notes) {
        debugPrint('  b${n.beat.toStringAsFixed(3)} s${n.string} f${n.fret} '
            'tap=${n.tap} tech=${n.technique} ghost=${n.ghost} '
            'grace=${n.grace} dur=${n.duration.toStringAsFixed(3)}');
      }
    }
  });
}
