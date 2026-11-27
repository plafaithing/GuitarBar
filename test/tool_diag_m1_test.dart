// 一次性诊断：Prologue m1-m3 音符结构 dump（beat/duration/tie/string）。
@Tags(['heavy'])
library;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';

import 'overlap_probe_lib.dart' show parseScore;

void main() {
  test('m1-m3 结构', () {
    final f = File(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores\87\source.gtp');
    final ir = parseScore(f.readAsBytesSync(), 'x')!;
    final ms = ir.tracks.first.measures;
    debugPrint('拍号=${ir.timeSignature} tempo=${ir.tempo}');
    for (final mi in [0, 1, 2, 27, 28]) {
      final m = ms[mi];
      debugPrint('--- m${mi + 1}（${m.notes.length} 音）---');
      final sorted = [...m.notes]
        ..sort((a, b) {
          final c = a.beat.compareTo(b.beat);
          if (c != 0) return c;
          return a.string.compareTo(b.string);
        });
      for (final n in sorted) {
        debugPrint('  b${n.beat.toStringAsFixed(3)} s${n.string} '
            'f${n.fret} dur=${n.duration.toStringAsFixed(3)} '
            'tieStart=${n.tieStart} tieEnd=${n.tieEnd}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
