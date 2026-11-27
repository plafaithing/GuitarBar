// LSA(id95) 布局量化：行分布、每小节音距、rowOverfull 判定——
// 验证近似同列校验（12px）为什么没触发。
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
  // 必须传 sourceName：已知源数据特例修正（Like A Star 低音 beat 对齐）
  // 靠文件名触发——存储副本名是 source.gpx 不含曲名，不传则测试跑的
  // 是错误 beat 的 ir（2026-11-26 分叉调查教训）。app 导入用原始文件名，
  // 这里用曲谱目录上级无法拿到，退而传 DB 标题同款关键词。
  final name = f.uri.pathSegments.last;
  if (f.path.endsWith('.gp5')) return parseGp5Bytes(bytes);
  if (f.path.endsWith('.gp3') || f.path.endsWith('.gp4')) {
    return parseGp34Bytes(bytes);
  }
  return parseGpxBytes(bytes, sourceName: name == 'source.gpx'
      ? 'Like A Star' : name);
}

void main() {
  test('LSA layout quant', () {
    // 动态找最新未删的 Like A Star（用户反复重导，id 递增）
    var starId = 0;
    final scoresDir = Directory('$_root/scores');
    for (final dd in scoresDir.listSync()) {
      final name = dd.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final id = int.tryParse(name);
      if (id != null && id > starId) starId = id;
    }
    // ignore: avoid_print
    print('starId=$starId');
    var ir = _parse(starId);
    // json 往返（复现 app 加载路径：ir_json → fromJson）
    ir = ScoreIr.fromJson(jsonDecode(jsonEncode(ir.toJson())) as Map<String, dynamic>);
    final layout = TabLayout(ir);
    const mw = 904.0; // 用户窗口宽
    // 多宽扫描：找 m1/m2 各一行（行0=[0] 且 行1=[1]）出现的宽度
    for (final tw in [896.0, 900.0, 904.0, 906.0, 908.0, 912.0, 920.0]) {
      final tr = layout.rowsFor(tw);
      final tag = (tr.length > 1 && tr[0].length == 1 && tr[1].length == 1)
          ? ' <<< m1/m2 各一行'
          : '';
      // ignore: avoid_print
      print('w=${tw.toStringAsFixed(0)}: 行0=${tr[0].join(",")} 行1=${tr.length > 1 ? tr[1].join(",") : "-"}$tag');
    }
    final rows = layout.rowsFor(mw);
    // ignore: avoid_print
    print('starId=$starId measures=${ir.tracks.first.measures.length}  行数=${rows.length}  avail=${920 - TabLayout.leftPad * 2}');
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      final w = layout.measureWidthAt(row.first, mw);
      // ignore: avoid_print
      print('行$r: 小节=${row.join(",")}  每小节宽=${w.toStringAsFixed(0)}  '
          'overfull=${layout.rowOverfull(row, [for (var mi in row) layout.measureWidthAt(mi, mw)])}');
      for (final mi in row) {
        final notes = ir.tracks.first.measures[mi].notes;
        // 拍位间隔量化：相邻不同拍音的 noteX 差
        final beats = notes.map((n) => n.beat).toSet().toList()..sort();
        final minGap = <double>[];
        for (var i = 1; i < beats.length; i++) {
          final x0 = layout.noteX(mi, beats[i - 1], mw);
          final x1 = layout.noteX(mi, beats[i], mw);
          minGap.add(x1 - x0);
        }
        final minV = minGap.isEmpty ? 0.0 : minGap.reduce((a, b) => a < b ? a : b);
        // ignore: avoid_print
        print('  m$mi: ${notes.length}音 ${beats.length}拍列  '
            '最小拍位间隔=${minV.toStringAsFixed(1)}px  '
            'overfull=${layout.rowOverfull([mi], [w])}');
      }
    }
    // m1/m2/m3 组合量化（用户示例行）
    for (final combo in ([[0, 1], [0, 1, 2], [1, 2], [1, 2, 3], [2, 3], [2, 3, 4]])) {
      final w = layout.rowWidthsForTest(combo, mw);
      // ignore: avoid_print
      print('组合 m${combo.join(",")}: 宽=[${w.map((x) => x.toStringAsFixed(0)).join(",")}] '
          'overfull=${layout.rowOverfull(combo, w)}');
    }
    // 组合判定插桩：相邻单行小节两两合并的 rowOverfull 值
    for (var r = 0; r < rows.length; r++) {
      if (rows[r].length == 1 && r + 1 < rows.length) {
        final pair = [rows[r].first, rows[r + 1].first];
        final w = layout.rowWidthsForTest(pair, mw);
        // ignore: avoid_print
        print('合并 m${pair[0]}+m${pair[1]}: 宽=[${w.map((x) => x.toStringAsFixed(0)).join(",")}] '
            'overfull=${layout.rowOverfull(pair, w)}');
      }
    }
  });
}
