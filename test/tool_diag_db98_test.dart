// 分叉根因定位：DB ir_json（tasks/_db98_ir.json，app 实际加载的）vs
// 源文件新鲜解析——字段级 diff + 双方 904 宽折行对照。
// app 实测：行0=0 行1=1（m1/m2 各一行）；test 新鲜解析：行1=[1,2,3]。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/gp5_parser.dart';
import 'package:guitarbar/core/score/gp34_parser.dart';
import 'package:guitarbar/core/score/gtp_parser.dart';
import 'package:guitarbar/core/score/score_ir.dart';
import 'dart:convert';
import 'package:guitarbar/ui/scores/tab_layout.dart';

const _root =
    'D:/workplace/code/GuitarBar/build/windows/x64/runner/Release/data';

ScoreIr _parse(int id) {
  final dir = Directory('$_root/scores/$id');
  final f = dir.listSync().firstWhere((e) => e.path.endsWith('.gtp') ||
      e.path.endsWith('.gp3') ||
      e.path.endsWith('.gp5') ||
      e.path.endsWith('.gpx'));
  final bytes = File(f.path).readAsBytesSync();
  // 关键：传源文件名——Like A Star 特例修正（6弦0 beat 0.125→0.0）靠它触发，
  // 之前不传导致 test 跑的是错误 beat 的 ir（分叉调查走偏的根源）。
  final name = f.uri.pathSegments.last;
  if (f.path.endsWith('.gp5')) return parseGp5Bytes(bytes);
  if (f.path.endsWith('.gp3') || f.path.endsWith('.gp4')) {
    return parseGp34Bytes(bytes);
  }
  return parseGpxBytes(bytes, sourceName: name);
}

void _diff(Object? a, Object? b, String path, List<String> out) {
  if (a is Map && b is Map) {
    final keys = {...a.keys, ...b.keys};
    for (final k in keys) {
      _diff(a[k], b[k], '$path.$k', out);
    }
  } else if (a is List && b is List) {
    if (a.length != b.length) {
      out.add('$path: len ${a.length} vs ${b.length}');
    }
    for (var i = 0; i < a.length && i < b.length; i++) {
      _diff(a[i], b[i], '$path[$i]', out);
    }
  } else if (a != b) {
    out.add('$path: $a vs $b');
  }
}

void main() {
  test('DB ir vs fresh parse', () {
    // LSA id 动态找（用户反复重导，id 递增：98→99→…）
    var lsaId = 0;
    final dbScores = (jsonDecode(
        File('tasks/_db_scores.json').readAsStringSync()) as List);
    for (final e in dbScores) {
      final t = (e as Map)['title'] as String;
      if (t.contains('Like') && t.contains('Star')) {
        lsaId = e['id'] as int;
      }
    }
    // ignore: avoid_print
    print('lsaId=$lsaId');
    // DB json 由 tasks/_db_dump_lsa.py dump（测试环境不直连 sqlite）
    final dbMap = jsonDecode(
        File('tasks/_db_lsa_ir.json').readAsStringSync()) as Map<String, dynamic>;
    final dbIr = ScoreIr.fromJson(dbMap);
    final freshIr = _parse(lsaId);

    void printRows(String tag, ScoreIr ir) {
      final layout = TabLayout(ir);
      for (final tw in [880.0, 904.0, 940.0]) {
        final rows = layout.rowsFor(tw);
        // ignore: avoid_print
        print('$tag w=$tw: 行数=${rows.length} 行0=${rows[0].join(",")} '
            '行1=${rows.length > 1 ? rows[1].join(",") : "-"}');
      }
      final rows = layout.rowsFor(904.0);
      for (var r = 0; r < rows.length && r < 5; r++) {
        final row = rows[r];
        final w = [for (var mi in row) layout.measureWidthAt(mi, 904.0)];
        // ignore: avoid_print
        print('$tag 行$r: ${row.join(",")} 宽=${w.map((x) => x.toStringAsFixed(0)).join(",")} '
            'overfull=${layout.rowOverfull(row, w)}');
      }
    }

    printRows('DB  ', dbIr);
    printRows('FRESH', freshIr);

    // 字段级 diff（DB map vs 新鲜 toJson）
    final freshMap = freshIr.toJson();
    final diffs = <String>[];
    _diff(dbMap, freshMap, '', diffs);
    // ignore: avoid_print
    print('diff 数=${diffs.length}');
    for (var i = 0; i < diffs.length && i < 40; i++) {
      // ignore: avoid_print
      print('  DIFF ${diffs[i]}');
    }
  });
}
