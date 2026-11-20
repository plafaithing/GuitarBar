// 一次性诊断：全量违例落盘扫描（挂靠趟序改动回归定位）。
// 与全量探针同口径但不 assert、违例逐文件追加落盘（挂了也有进度）。
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
const _outPath = r'D:\workplace\code\GuitarBar\tasks\probe_regress_out.txt';

Widget _host(ScoreIr ir, double width, double height) => MaterialApp(
      theme: GuitarBarTheme.light(),
      home: Scaffold(
        body: SizedBox(width: width, height: height, child: TabView(ir: ir)),
      ),
    );

void main() {
  setUpAll(loadScoreFonts);
  testWidgets('全量违例落盘', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final sink = File(_outPath).openSync(mode: FileMode.write);
    final files = collectScoreFiles(Directory(_root));
    var checked = 0, skipped = 0, exempted = 0, violFiles = 0;
    var t0 = DateTime.now();
    for (var fi = 0; fi < files.length; fi++) {
      final f = files[fi];
      if (fi % 100 == 0) {
        final mins = DateTime.now().difference(t0).inMinutes;
        sink.writeStringSync('# progress $fi/${files.length} min $mins\n');
      }
      final Uint8List bytes;
      try {
        bytes = Uint8List.fromList(f.readAsBytesSync());
      } catch (_) {
        skipped++;
        continue;
      }
      final ir = parseScore(bytes, f.uri.pathSegments.last);
      if (ir == null) {
        skipped++;
        continue;
      }
      // 挂靠/装饰影响面快筛：grace（挂靠趟）与 deco（dup 左移槽位）
      // 都改变排布路径——只深跑含两者的谱 + 5% 抽样对照（2026-11-20
      // dsh：deco 谱此前只吃抽样，影响面与跑批不一致）。
      var grace = 0;
      var deco = 0;
      for (final m in ir.tracks.first.measures) {
        for (final n in m.notes) {
          if (n.grace) grace++;
          if (n.deco) deco++;
        }
      }
      final layout = TabLayout(ir);
      final affected = (grace > 0 || deco > 0) && !layout.graceAsNormal;
      if (!affected && fi % 20 != 0) continue;
      for (final w in [786.0, 900.0, 1100.0, 1300.0]) {
        final contentH = layout.sizeFor(w).height;
        final h = contentH < 2400.0 ? 2400.0 : contentH + 100;
        tester.view.physicalSize = Size(w, h);
        try {
          await tester.pumpWidget(_host(ir, w, h));
          await tester.pumpAndSettle();
        } catch (e) {
          sink.writeStringSync(
              '[render挂] ${f.uri.pathSegments.last} w=$w: $e\n');
          await tester.pumpWidget(const SizedBox.shrink());
          continue;
        }
        final paintErr = tester.takeException();
        if (paintErr != null) {
          sink.writeStringSync(
              '[paint挂] ${f.uri.pathSegments.last} w=$w: $paintErr\n');
        }
        final found = findViolations(TabViewDebug.lastPaintedTexts);
        if (found.isNotEmpty &&
            (layout.hasOverfullMeasure(w) ||
                heavyWaiverScores.contains(f.uri.pathSegments.last))) {
          exempted++;
          continue;
        }
        checked++;
        if (found.isNotEmpty) {
          violFiles++;
          sink.writeStringSync(
              '[违例] ${f.uri.pathSegments.last} w=$w: ${found.length} 对\n');
          for (final v in found.take(6)) {
            sink.writeStringSync('    $v\n');
          }
        }
      }
    }
    sink.writeStringSync(
        '# 完: files=${files.length} 深跑组合=$checked 跳过=$skipped '
        '豁免=$exempted 违例文件=$violFiles '
        '用时 ${DateTime.now().difference(t0).inMinutes} 分\n');
    sink.flushSync();
    sink.closeSync();
    debugPrint('done violFiles=$violFiles');
  }, timeout: const Timeout(Duration(minutes: 30)));
}
