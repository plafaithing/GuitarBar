// 折行普适性验证（2026-11-27 闭环求解器版）：全库 157 谱 × 904 宽——
// 1) 总行数 / 非末行单小节行；单小节行的强制原因直方图
// 2) 点名曲（月下之恋/Bluebird/Distance/LSA）前几行分布
// 3) 相邻行对"贪心漏合并"复核：A∪B 经求解器可解的行对数（应为 0）
// 数据源：DB 未删 GTP 谱（app 同款路径 + 标题 sourceName）+ D:\Guitar
// 顶层 + 指弹独奏库 139 份（魔数路由，错标自愈）。
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/gp5_parser.dart';
import 'package:guitarbar/core/score/gp34_parser.dart';
import 'package:guitarbar/core/score/gtp12_parser.dart';
import 'package:guitarbar/core/score/gtp_parser.dart';
import 'package:guitarbar/core/score/score_ir.dart';
import 'dart:convert';
import 'package:guitarbar/ui/scores/tab_layout.dart';

import 'font_setup.dart';

const _root =
    'D:/workplace/code/GuitarBar/build/windows/x64/runner/Release/data';
const _guitarRoot = 'D:/Guitar';
const _soloDir = '$_guitarRoot/158吉他谱电子版大全/gtp格式-吉他谱全集/'
    'gtp格式指弹独奏谱';
const _exts = ['.gpx', '.gp5', '.gp3', '.gp4', '.gtp', '.gp'];

String? _gpBinaryFlavor(List<int> bytes) {
  if (bytes.length < 31) return null;
  final head4 = latin1.decode(bytes.sublist(0, 4));
  if (head4 == 'BCFZ' || head4.startsWith('PK')) return 'gpx';
  final size = bytes[0];
  final raw = latin1.decode(bytes.sublist(1, 31));
  final version =
      (size < 1 ? '' : raw.substring(0, size < 30 ? size : 30)).trim();
  if (version.contains('GUITARE') ||
      version.contains('GUITAR PRO v1') ||
      version.contains('v2.20') ||
      version.contains('v2.21')) {
    return 'gtp12';
  }
  if (version.contains('v3.') || version.contains('v4.') ||
      version.contains('L4.')) {
    return 'gp34';
  }
  if (version.contains('v5.')) return 'gp5';
  return null;
}

ScoreIr? _parseFile(String path, {required String sourceName}) {
  final bytes = File(path).readAsBytesSync();
  return switch (_gpBinaryFlavor(bytes)) {
    'gtp12' => parseGtp12Bytes(bytes),
    'gp34' => parseGp34Bytes(bytes),
    'gp5' => parseGp5Bytes(bytes),
    'gpx' => parseGpxBytes(bytes, sourceName: sourceName),
    _ => null,
  };
}

int _barLimit(int density) =>
    density > 32 ? 2 : density > 20 ? 3 : density > 14 ? 4 : 5;

void main() {
  setUpAll(loadScoreFonts);
  const w = 904.0;
  test('fold scan v4 (solver)', () {
    final dbList = (jsonDecode(
            File('tasks/_db_scores.json').readAsStringSync())
        as List);
    final named = {35: 'Bluebird', 63: '月下之恋', 72: 'Distance', 99: 'LSA'};

    final cases = <(String, String, int?)>[];
    for (final e in dbList) {
      final id = (e as Map)['id'] as int;
      final title = e['title'] as String;
      final f = Directory('$_root/scores/$id')
          .listSync()
          .firstWhere((x) => _exts.any(
              (ext) => x.path.toLowerCase().endsWith(ext)));
      cases.add((f.path, title, named.containsKey(id) ? id : null));
    }
    for (final parent in [_guitarRoot, _soloDir]) {
      for (final e in Directory(parent).listSync()) {
        if (e is File &&
            _exts.any((ext) => e.path.toLowerCase().endsWith(ext))) {
          cases.add((e.path, e.uri.pathSegments.last, null));
        }
      }
    }

    var totalRows = 0;
    var soloRows = 0;
    var parseFail = 0;
    var scores = 0;
    final forcedWhy = <String, int>{}; // 非末行单小节行的强制拒因
    var missedMerge = 0; // A∪B 可解但贪心未合并（应为 0）
    final missed = <String>[];
    final rowHist = <int, int>{}; // 每行小节数直方图

    for (final (path, name, namedId) in cases) {
      ScoreIr? ir;
      try {
        ir = _parseFile(path, sourceName: name);
      } catch (_) {
        ir = null;
      }
      if (ir == null || ir.tracks.isEmpty || ir.tracks.first.measures.isEmpty) {
        parseFail++;
        continue;
      }
      scores++;
      final measures = ir.tracks.first.measures;
      final layout = TabLayout(ir);
      final rows = layout.rowsFor(w);
      totalRows += rows.length;
      for (final r in rows) {
        rowHist[r.length] = (rowHist[r.length] ?? 0) + 1;
      }
      for (var r = 0; r + 1 < rows.length; r++) {
        if (rows[r].length == 1) {
          soloRows++;
          final nxt = rows[r + 1].first;
          final why = layout.solveRowForTest([rows[r].first, nxt], w).why;
          forcedWhy[why ?? '?'] = (forcedWhy[why ?? '?'] ?? 0) + 1;
        }
        // 贪心漏合并复核
        final merged = [...rows[r], ...rows[r + 1]];
        if (merged.length > 5) continue;
        var maxCols = 0;
        for (final mi in merged) {
          maxCols = math.max(
              maxCols, measures[mi].notes.map((n) => n.beat).toSet().length);
        }
        if (_barLimit(maxCols) < merged.length) continue;
        if (layout.solveRowForTest(merged, w).why == null) {
          missedMerge++;
          if (missed.length < 10) {
            missed.add('$name 行${r + 1}+${r + 2}=${merged.join(",")} 可合并');
          }
        }
      }
      if (namedId != null) {
        final sb = StringBuffer();
        for (var r = 0; r < rows.length && r < 7; r++) {
          final ws = [
            for (final mi in rows[r])
              layout.measureWidthAt(mi, w).toStringAsFixed(0)
          ];
          sb.write('r${r + 1}=[${rows[r].join(",")}]'
              '{${ws.join("/")}} ');
        }
        // ignore: avoid_print
        print('== $name (id=$namedId) ${rows.length} 行: $sb');
      }
    }

    // ignore: avoid_print
    print('谱 $scores 份（解析失败 $parseFail）；总行数 $totalRows；'
        '非末行单小节行 $soloRows');
    // ignore: avoid_print
    print('每行小节数直方图: $rowHist');
    // ignore: avoid_print
    print('非末行单小节行的强制拒因（与下行首并 2 小节）: $forcedWhy');
    // ignore: avoid_print
    print('贪心漏合并行对: $missedMerge');
    for (final m in missed) {
      // ignore: avoid_print
      print('  [MISSED] $m');
    }
  });
}
