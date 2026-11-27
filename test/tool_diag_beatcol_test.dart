// 一次性诊断：LAS 全谱"不同拍同列"量化（用户新铁律）——跨弦不同拍
// 对中心 dx < 6px（视觉一列）与倒置（晚拍在早拍左）两类。
@Tags(['heavy'])
library;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/gtp_parser.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';
import 'package:guitarbar/ui/scores/tab_view.dart';
import 'package:guitarbar/ui/theme.dart';

import 'font_setup.dart';
import 'overlap_probe_lib.dart';

void main() {
  setUpAll(loadScoreFonts);
  testWidgets('LAS 不同拍同列扫描', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    final f = File(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores\83\source.gpx');
    final ir = parseGpxBytes(f.readAsBytesSync(), sourceName: 'source.gpx');
    final layout = TabLayout(ir);
    final w = 900.0;
    final h = layout.sizeFor(w).height + 100;
    tester.view.physicalSize = Size(w, h);
    await tester.pumpWidget(MaterialApp(
      theme: GuitarBarTheme.light(),
      home: Scaffold(
          body: SizedBox(width: w, height: h, child: TabView(ir: ir))),
    ));
    await tester.pumpAndSettle();
    final flow = TabViewDebug.lastFlow;
    final found = findBeatColumnViolations(flow);
    debugPrint('咬合/倒置=${found.length} 对');
    for (final v in found.take(20)) {
      debugPrint('  $v');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
