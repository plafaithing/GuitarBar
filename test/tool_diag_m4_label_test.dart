// 一次性诊断：m4/m17 逐音 tabLabel 显示形态推演（对照 制谱基准 精读期望，
// 找吞数字分支）。
@Tags(['heavy'])
library;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';

import 'overlap_probe_lib.dart' show parseScore;

void main() {
  test('m4/m17 显示形态', () {
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
    final ms = ir.tracks.first.measures;
    for (final mi in [3, 16]) {
      debugPrint('--- m${mi + 1} ---');
      final sorted = [...ms[mi].notes]..sort((a, b) {
          final c = a.beat.compareTo(b.beat);
          if (c != 0) return c;
          return a.string.compareTo(b.string);
        });
      for (final n in sorted) {
        final label = TabLayout.tabLabel(n);
        debugPrint('  b${n.beat.toStringAsFixed(3)} s${n.string} f${n.fret} '
            'tieE=${n.tieEnd} tieS=${n.tieStart} anchor=${n.tieAnchor} '
            'deco=${n.deco} grace=${n.grace} slide=${n.slide} '
            '→ label="${label.isEmpty ? "<隐藏>" : label}"');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
