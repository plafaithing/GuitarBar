// LAS grace 占比 + m2 grace 音流动明细（挂靠为何没生效）。
@Tags(['heavy'])
library;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/gtp_parser.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';

void main() {
  test('grace 占比与挂靠门', () {
    final f = File(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores\83\source.gpx');
    final ir = parseGpxBytes(f.readAsBytesSync(), sourceName: 'source.gpx');
    var total = 0, grace = 0;
    for (final m in ir.tracks.first.measures) {
      for (final n in m.notes) {
        total++;
        if (n.grace) grace++;
      }
    }
    debugPrint('total=$total grace=$grace 占比=${(grace / total * 100).toStringAsFixed(1)}%');
    final layout = TabLayout(ir);
    debugPrint('graceAsNormal=${layout.graceAsNormal}');
    // m2 grace 音明细
    for (final n in ir.tracks.first.measures[1].notes) {
      if (n.grace) debugPrint('m2 grace: b${n.beat} s${n.string} f${n.fret}');
    }
  });
}
