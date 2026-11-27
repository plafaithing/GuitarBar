// 一次性诊断：Prologue m4/m17 滑音结构 dump（用户报：滑音漏掉/丢音/
// 滑音结束音与其他拍同拍）。已完结（结论落 todo 深夜四节 + 装饰音 IR
// 回归 test/tool_dsh_grace_ir_test.dart）；曲库 id 漂移 87→90——保留
// 脚本按需改路径复用。@Tags(['heavy'])
library;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'overlap_probe_lib.dart' show parseScore;

void main() {
  test('m4/m17 滑音结构',
      skip: '一次性诊断已完结（IR 回归见 tool_dsh_grace_ir_test）；'
          '曲库 id 漂移 87→90，需用时改路径', () {
    final f = File(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores\87\source.gtp');
    final ir = parseScore(f.readAsBytesSync(), 'x')!;
    final ms = ir.tracks.first.measures;
    for (final mi in [3, 16]) {
      final m = ms[mi];
      debugPrint('--- m${mi + 1}（${m.notes.length} 音）---');
      final sorted = [...m.notes]
        ..sort((a, b) {
          final c = a.beat.compareTo(b.beat);
          if (c != 0) return c;
          return a.string.compareTo(b.string);
        });
      for (final n in sorted) {
        debugPrint('  b${n.beat.toStringAsFixed(3)} s${n.string} f${n.fret} '
            'dur=${n.duration.toStringAsFixed(3)} '
            'slide=${n.slide} tieStart=${n.tieStart} tieEnd=${n.tieEnd} '
            'hopoS=${n.hopoStart} hopoE=${n.hopoEnd} tech=${n.technique} '
            'ghost=${n.ghost} grace=${n.grace}');
      }
    }
    // 相邻小节 m3/m5 对照（滑音链可能跨小节）。
    for (final mi in [2, 4, 15, 17]) {
      final m = ms[mi];
      debugPrint('--- 对照 m${mi + 1}（${m.notes.length} 音）---');
      final sorted = [...m.notes]..sort((a, b) => a.beat.compareTo(b.beat));
      for (final n in sorted) {
        debugPrint('  b${n.beat.toStringAsFixed(3)} s${n.string} f${n.fret} '
            'slide=${n.slide} tieS=${n.tieStart} tieE=${n.tieEnd}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
