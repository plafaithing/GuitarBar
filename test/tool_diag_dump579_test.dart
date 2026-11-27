// 通用事件 dump：哆啦A梦(id71 .gtp) m8-10 / LSA(id83) 泛音 / Flower(id57 gp5) 三连音段。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/gp34_parser.dart';
import 'package:guitarbar/core/score/gp5_parser.dart';
import 'package:guitarbar/core/score/gtp_parser.dart';
import 'package:guitarbar/core/score/score_ir.dart';

const _root =
    'D:/workplace/code/GuitarBar/build/windows/x64/runner/Release/data';

ScoreIr _parse(int id) {
  final dir = Directory('$_root/scores/$id');
  final f = dir.listSync().firstWhere((e) => e.path.endsWith('.gtp') ||
      e.path.endsWith('.gp3') ||
      e.path.endsWith('.gp5') ||
      e.path.endsWith('.gpx'));
  final bytes = File(f.path).readAsBytesSync();
  if (f.path.endsWith('.gp5')) return parseGp5Bytes(bytes);
  if (f.path.endsWith('.gp3') || f.path.endsWith('.gp4')) {
    return parseGp34Bytes(bytes);
  }
  if (f.path.endsWith('.gpx')) return parseGpxBytes(bytes);
  return parseGpxBytes(bytes); // .gtp 同通道（gtp12/gp3/4/5 探测在解析器内）
}

void _dumpSegment(ScoreIr ir, int lo, int hi, {bool harmonicOnly = false}) {
  for (final m in ir.tracks.first.measures) {
    if (m.index < lo || m.index > hi) continue;
    if (harmonicOnly && !m.notes.any((n) => n.harmonicOffset != null)) {
      continue;
    }
    // ignore: avoid_print
    print('--- m${m.index} sig=${m.timeSignature}');
    final sorted = [...m.notes]..sort((a, b) {
        final c = a.beat.compareTo(b.beat);
        if (c != 0) return c;
        return a.string.compareTo(b.string);
      });
    for (final n in sorted) {
      // ignore: avoid_print
      print('beat=${n.beat.toStringAsFixed(3)} dur=${n.duration.toStringAsFixed(3)} '
          's${n.string}f${n.fret} harm=${n.harmonicOffset?.toStringAsFixed(0) ?? "-"} '
          'hType=${n.harmonicType ?? "-"} tieS=${n.tieStart ? 1 : 0} '
          'tieE=${n.tieEnd ? 1 : 0} slide=${n.slide ?? "-"} '
          'grace=${n.grace ? 1 : 0} deco=${n.deco ? 1 : 0} tech=${n.technique ?? "-"}');
    }
  }
}

void main() {
  test('dump all', () {
    // ① LSA(id83) 泛音标记全集 + grace 泛音/主音对
    // ignore: avoid_print
    print('=== id83 LSA 泛音+grace 对（m0-m3） ===');
    _dumpSegment(_parse(95), 0, 3);
    // ② 哆啦A梦(id71) m8-10（m9 起吞音）
    // ignore: avoid_print
    print('=== id71 哆啦A梦 m8-10 ===');
    _dumpSegment(_parse(71), 8, 10);
    // ③ Flower(id57) 三连音段（beat 带 1/3 的小节）
    final ir = _parse(57);
    // ignore: avoid_print
    print('=== id57 Flower 三连音小节 ===');
    for (final m in ir.tracks.first.measures) {
      final hasTriplet = m.notes.any((n) =>
          (n.beat * 3).round() != n.beat * 3 ||
          (n.duration * 3).round() != n.duration * 3);
      if (hasTriplet) {
        // ignore: avoid_print
        print('--- m${m.index}');
        for (final n in m.notes) {
          // ignore: avoid_print
          print('beat=${n.beat.toStringAsFixed(3)} dur=${n.duration.toStringAsFixed(3)} '
              's${n.string}f${n.fret} slide=${n.slide ?? "-"} '
              'tieS=${n.tieStart ? 1 : 0} tieE=${n.tieEnd ? 1 : 0}');
        }
      }
    }
  }, skip: '一次性诊断已完结（吞音/泛音定位，2026-11-25）；曲库 id 漂移，'
      '需用时改路径');
}
