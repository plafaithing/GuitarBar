// 一次性诊断：Prologue m4/m17 装饰音排布验证（重叠探针 + 拍列扫描——
// 用户报"滑音结束音与其他拍音同拍"。装饰音进排布后验挂靠/拍列/重叠）。
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

import 'font_setup.dart' show loadScoreFonts;
import 'overlap_probe_lib.dart';

Widget _host(ScoreIr ir, double width, double height) => MaterialApp(
      theme: GuitarBarTheme.light(),
      home: Scaffold(
        body: SizedBox(width: width, height: height, child: TabView(ir: ir)),
      ),
    );

void main() {
  setUpAll(loadScoreFonts);
  testWidgets('m4/m17 装饰音排布探针', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // 曲库 id 频繁漂移（87→90）：动态按标题找 Prologue。
    final dir = Directory(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores');
    ScoreIr? ir;
    for (final d in dir.listSync()) {
      final f = File('${d.path}\\source.gtp');
      if (!f.existsSync()) continue;
      final cand =
          parseScore(Uint8List.fromList(f.readAsBytesSync()), 'x');
      if (cand != null && cand.title.contains('Prologue')) {
        ir = cand;
        break;
      }
    }
    if (ir == null) throw StateError('Prologue not found in library');
    for (final w in [786.0, 1100.0]) {
      final contentH = TabLayout(ir).sizeFor(w).height;
      tester.view.physicalSize = Size(w, contentH < 2400 ? 2400 : contentH + 100);
      await tester.pumpWidget(_host(ir, w, contentH < 2400 ? 2400 : contentH + 100));
      await tester.pumpAndSettle();
      final viol = findViolations(TabViewDebug.lastPaintedTexts);
      final beatCol = findBeatColumnViolations(TabViewDebug.lastFlow);
      debugPrint('w=$w violations=${viol.length} beatCol=${beatCol.length}');
      // m4/m17 的 flow 定位（装饰音挂靠形态目检）。
      for (final fd in TabViewDebug.lastFlow) {
        if (fd.mIdx == 3 || fd.mIdx == 16) {
          debugPrint('  m${fd.mIdx + 1} b${fd.note.beat} s${fd.note.string} '
              'f${fd.note.fret} grace=${fd.note.grace} tieE=${fd.note.tieEnd} '
              'x=${fd.x.toStringAsFixed(1)}');
        }
      }
      for (final v in viol.take(8)) {
        debugPrint('  [viol] $v');
      }
      for (final v in beatCol.take(8)) {
        debugPrint('  [beatcol] $v');
      }
      // m4/m17 实际 painted 数字（x 升序——渲染实况对照）。
      final painted = TabViewDebug.lastPaintedTexts
          .where((t) =>
              (t.centerX > 560 && t.centerX < 800) ||
              (t.centerX > 960 && t.centerX < 1200))
          .toList()
        ..sort((a, b) => a.centerX.compareTo(b.centerX));
      for (final t in painted.take(30)) {
        debugPrint('  [painted] "${t.text}" @${t.centerX.toStringAsFixed(0)},'
            '${t.centerY.toStringAsFixed(0)}');
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
