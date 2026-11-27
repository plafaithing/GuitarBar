// 折行判定与渲染同源的一致性回归（2026-11-27）：
// 折行判定（TabLayout._flowCheck）靠 buildRowFlow **预测**候选行的排布
// 终位，再在终位上校验铁律——"预测 = 渲染"是整套闭环求解的地基。本
// 测试对 app 曲库 × 多宽度，逐行取预测终位（与 _flowCheck 同式的几何
// 回调）与真实 paint 的 lastFlow 逐音比较，任何偏差即红：
// 渲染层排布改动而判定侧回调没同步、或几何回调口径漂移，都会在这里
// 暴露，而不是变成"判定放过的行渲染出来违例"。
// 重复音（同弦同拍同品）按 key 分组后排序比较（错开趟保证互异）。
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/ui/scores/row_flow.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';
import 'package:guitarbar/ui/scores/tab_view.dart';
import 'package:guitarbar/ui/theme.dart';

import 'font_setup.dart';
import 'overlap_probe_lib.dart';

const _appDataScores =
    'D:/workplace/code/GuitarBar/build/windows/x64/runner/Release/data/scores';

Widget _host(ScoreIr ir, double width, double height) => MaterialApp(
      theme: GuitarBarTheme.light(),
      home: Scaffold(
        body: SizedBox(width: width, height: height, child: TabView(ir: ir)),
      ),
    );

String _key(RowFlowNote f) => '${f.mIdx}|${f.note.beat.toStringAsFixed(4)}|'
    '${f.note.string}|${f.note.fret}|${f.note.grace ? 1 : 0}|'
    '${f.note.deco ? 1 : 0}';

/// 与 TabLayout._flowCheck 同式的候选几何（行宽列表 → 回调）。
List<RowFlowNote> _predict(TabLayout layout, List<MeasureIr> measures,
    List<int> row, List<double> widths) {
  final xOf = <int, double>{};
  final wOf = <int, double>{};
  var acc = TabLayout.leftPad;
  for (var c = 0; c < row.length; c++) {
    xOf[row[c]] = acc;
    wOf[row[c]] = widths[c];
    acc += widths[c];
  }

  double beatX(int mi, double beat) {
    final cb = layout.contentBeatsOf(mi);
    return xOf[mi]! +
        TabLayout.notePad +
        math.min(beat, cb) * (wOf[mi]! - TabLayout.notePad * 2) / cb;
  }

  return buildRowFlow(
      measures: measures,
      row: row,
      notePad: TabLayout.notePad,
      graceAsNormal: layout.graceAsNormal,
      measureX: (mi) => xOf[mi]!,
      measureWidth: (mi) => wOf[mi]!,
      noteX: beatX,
      stringY: (_) => 0,
      inkHalf: TabLayout.inkHalf);
}

void main() {
  setUpAll(loadScoreFonts);
  testWidgets('折行判定预测的排布终位 = 渲染 paint 的实际终位', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final scoresDir = Directory(_appDataScores);
    if (!scoresDir.existsSync()) {
      markTestSkipped('曲库目录不存在: $_appDataScores');
      return;
    }
    final files = collectScoreFiles(scoresDir)
        .where((f) => !f.path.contains('${Platform.pathSeparator}del${Platform.pathSeparator}'))
        .toList();
    expect(files.length, greaterThan(3), reason: '探针谱集异常偏少');
    final widths = <double>[786.0, 900.0, 1100.0, 1300.0];
    var checked = 0;
    final diffs = <String>[];
    for (final f in files) {
      final tag = f.parent.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final ir = parseScore(
          f.readAsBytesSync(), f.uri.pathSegments.last);
      if (ir == null) continue;
      final measures = ir.tracks.first.measures;
      final layout = TabLayout(ir);
      for (final w in widths) {
        final contentH = layout.sizeFor(w).height;
        final h = contentH < 2400.0 ? 2400.0 : contentH + 100;
        tester.view.physicalSize = Size(w, h);
        await tester.pumpWidget(_host(ir, w, h));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'paint 异常');
        final rendered = <String, List<double>>{};
        for (final fl in TabViewDebug.lastFlow) {
          (rendered[_key(RowFlowNote(fl.mIdx, fl.note, fl.x, fl.y))] ??= [])
              .add(fl.x);
        }
        for (final list in rendered.values) {
          list.sort();
        }
        var predicted = 0;
        for (final row in layout.rowsFor(w)) {
          final flow = _predict(
              layout, measures, row, [for (final mi in row) layout.measureWidthAt(mi, w)]);
          final byKey = <String, List<double>>{};
          for (final fl in flow) {
            (byKey[_key(fl)] ??= []).add(fl.x);
          }
          for (final e in byKey.entries) {
            final xs = e.value..sort();
            final rs = rendered[e.key];
            if (rs == null || rs.length != xs.length) {
              diffs.add('$tag w=${w.toInt()} '
                  '键 ${e.key} 预测 ${xs.length} 音 / 渲染 ${rs?.length ?? 0} 音');
              continue;
            }
            for (var i = 0; i < xs.length; i++) {
              final d = (xs[i] - rs[i]).abs();
              if (d > 0.01) {
                diffs.add('$tag w=${w.toInt()} '
                    '键 ${e.key} 预测 ${xs[i].toStringAsFixed(2)} / '
                    '渲染 ${rs[i].toStringAsFixed(2)}');
              }
            }
            predicted += xs.length;
          }
        }
        if (predicted != TabViewDebug.lastFlow.length) {
          diffs.add('$tag w=${w.toInt()} '
              '音数 预测 $predicted / 渲染 ${TabViewDebug.lastFlow.length}');
        }
        checked++;
      }
    }
    for (var i = 0; i < diffs.length && i < 20; i++) {
      // ignore: avoid_print
      print('DIFF ${diffs[i]}');
    }
    expect(diffs, isEmpty,
        reason: '折行判定的预测终位与渲染不一致 ${diffs.length} 处'
            '（判定与渲染必须同源——见 row_flow.buildRowFlow）');
    // ignore: avoid_print
    print('预测=渲染一致性：$checked 个（谱×宽度）组合逐音一致');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
