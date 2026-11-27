// 一次性诊断：Prologue 展开序 dump（一房子第一遍是否在轴上）。
@Tags(['heavy'])
library;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_ir.dart';

import 'overlap_probe_lib.dart' show parseScore;

void main() {
  test('Prologue 展开序', () {
    final f = File(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores\87\source.gtp');
    final ir = parseScore(f.readAsBytesSync(), 'x')!;
    final ms = ir.tracks.first.measures;
    final out = <String>[];
    out.add('小节数=${ms.length}');
    // 结构标记：repeat/endings
    for (var i = 0; i < ms.length; i++) {
      final m = ms[i];
      final marks = <String>[];
      if (m.repeatStart) marks.add('R+');
      if (m.repeatCount > 0) marks.add('R-${m.repeatCount}');
      if (m.endings.isNotEmpty) marks.add('end${m.endings.join(',')}');
      if (m.fermatas.isNotEmpty) marks.add('F');
      if (marks.isNotEmpty) {
        out.add('m${i + 1}: ${marks.join(',')}');
      }
    }
    final order = expandMeasures(ms);
    out.add('展开序长度=${order.length}');
    out.add('展开序=${order.take(80).map((e) => e + 1).join(',')}');
    // 线性小节 40-43（一房子段）在展开轴的位置
    for (final target in [39, 40, 41, 42, 43, 0, 1, 2]) {
      final ks = [
        for (var k = 0; k < order.length; k++)
          if (order[k] == target) k
      ];
      out.add('线性m${target + 1} 在展开轴的位置 k=$ks');
    }
    File(r'D:\workplace\code\GuitarBar\tasks\expand_dump.txt')
        .writeAsStringSync(out.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
