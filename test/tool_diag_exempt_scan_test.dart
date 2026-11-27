// 全库豁免盲区扫描（2026-11-27，heavy）：常驻/全量重叠探针对
// 「折行被迫压缩的谱」与「含 grace 行的谱」只计数不判罚（结构性豁免）。
// 本扫描把被豁免的**真实墨重叠**量化出来，按豁免原因分两类：
//   forced = 存在被迫的单小节行（行宽已给满，结构性极限）
//   graceOnly = 所有行都被求解器判为干净，仅因含 grace 被豁免
//               → 这类是求解器没覆盖到的重叠（标注 vs 数字等）
// 并给出各类的文字对类型分布。4 桶并行，同全量探针。
@Tags(['heavy'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';
import 'package:guitarbar/ui/scores/tab_view.dart';
import 'package:guitarbar/ui/theme.dart';

import 'font_setup.dart';
import 'overlap_probe_lib.dart';

const _root = r'D:\Guitar\158吉他谱电子版大全';
const _buckets = 4;

Widget _host(ScoreIr ir, double width, double height) => MaterialApp(
      theme: GuitarBarTheme.light(),
      home: Scaffold(
        body: SizedBox(width: width, height: height, child: TabView(ir: ir)),
      ),
    );

void _bucket(int bucket, List<File> allFiles) {
  testWidgets('豁免盲区扫描 桶$bucket/$_buckets', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final files = allFiles.where((f) => f.path.hashCode % _buckets == bucket).toList();
    var judged = 0, forcedCombos = 0, graceCombos = 0;
    var forcedPairs = 0, gracePairs = 0, judgedPairs = 0;
    final forcedTypes = <String, int>{};
    final graceTypes = <String, int>{};
    final graceFiles = <String, int>{};
    for (final f in files) {
      final Uint8List bytes;
      try {
        bytes = Uint8List.fromList(f.readAsBytesSync());
      } catch (_) {
        continue;
      }
      final ir = parseScore(bytes, f.uri.pathSegments.last);
      if (ir == null) continue;
      final layout = TabLayout(ir);
      final name = f.uri.pathSegments.last;
      for (final w in [786.0, 900.0, 1100.0, 1300.0]) {
        final contentH = layout.sizeFor(w).height;
        final h = contentH < 2400.0 ? 2400.0 : contentH + 100;
        tester.view.physicalSize = Size(w, h);
        try {
          await tester.pumpWidget(_host(ir, w, h));
          await tester.pumpAndSettle();
        } catch (_) {
          await tester.pumpWidget(const SizedBox.shrink());
          continue;
        }
        tester.takeException();
        final found = findViolations(TabViewDebug.lastPaintedTexts);
        final rows = layout.rowsFor(w);
        final forced = rows.any((r) => layout.rowOverfull(r, [
              for (final mi in r) layout.measureWidthAt(mi, w)
            ]));
        if (!layout.hasOverfullMeasure(w)) {
          judged++;
          judgedPairs += found.length;
          continue;
        }
        final types = forced ? forcedTypes : graceTypes;
        if (forced) {
          forcedCombos++;
          forcedPairs += found.length;
        } else {
          graceCombos++;
          gracePairs += found.length;
          if (found.isNotEmpty) {
            graceFiles[name] = (graceFiles[name] ?? 0) + found.length;
          }
        }
        for (var i = 0; i < found.length && i < 400; i++) {
          final m = RegExp(r'"([^"]*)"@\([0-9.,]+\).*× "([^"]*)"@')
              .firstMatch(found[i]);
          if (m == null) continue;
          final key = [m.group(1)!, m.group(2)!]..sort();
          types[key.join(' × ')] = (types[key.join(' × ')] ?? 0) + 1;
        }
      }
    }
    String top(Map<String, int> m, int n) {
      final e = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return e.take(n).map((x) => '${x.value}×${x.key}').join('；');
    }

    // ignore: avoid_print
    print('豁免扫描[桶$bucket]：${files.length} 文件；判罚组合 $judged'
        '（违例 $judgedPairs 处）；豁免组合：被迫行 $forcedCombos'
        '（$forcedPairs 对）/ 仅 grace $graceCombos（$gracePairs 对）');
    // ignore: avoid_print
    print('  被迫行类型 top: ${top(forcedTypes, 12)}');
    // ignore: avoid_print
    print('  仅grace类型 top: ${top(graceTypes, 12)}');
    final gf = graceFiles.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    // ignore: avoid_print
    print('  仅grace有重叠的谱 ${gf.length} 份，前 12: '
        '${gf.take(12).map((x) => '${x.value}×${x.key}').join('；')}');
  }, timeout: const Timeout(Duration(minutes: 25)));
}

void main() {
  setUpAll(loadScoreFonts);
  final allFiles = collectScoreFiles(Directory(_root));
  if (allFiles.isEmpty) {
    test('豁免盲区扫描：样本库不存在，跳过', () {
      markTestSkipped('样本库不存在: $_root');
    });
    return;
  }
  for (var b = 0; b < _buckets; b++) {
    _bucket(b, allFiles);
  }
}
