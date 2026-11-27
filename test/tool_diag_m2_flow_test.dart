// 一次性诊断：m2 s2 弦 grace(<12>)×主音(2) 排布趟序追踪——自然位
// → 挂靠位 → 终位，实锤"主音组左移甩下挂靠 grace"。
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

void main() {
  setUpAll(loadScoreFonts);
  testWidgets('m2 s2 趟序追踪', (tester) async {
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
    // 终位（paint 后）
    final flow2 = TabViewDebug.lastFlow
        .where((fl) => fl.mIdx == 1 && fl.note.string == 2)
        .toList()
      ..sort((a, b) => a.note.beat.compareTo(b.note.beat));
    final flow12 = TabViewDebug.lastFlow
        .where((fl) => (fl.mIdx == 11 || fl.mIdx == 10) &&
            fl.note.string == 2)
        .toList()
      ..sort((a, b) {
        final c = a.mIdx.compareTo(b.mIdx);
        if (c != 0) return c;
        return a.note.beat.compareTo(b.note.beat);
      });
    // 自然位
    debugPrint('=== m2 s2 弦（w=900）===');
    final mx = layout.measureX(1, w);
    final rowW = layout.measureWidthAt(1, w);
    debugPrint('m2 x=$mx rowW=${rowW.toStringAsFixed(0)} '
        'contentBeats=${layout.contentBeatsOf(1)}');
    for (final fl in flow2) {
      final natural = layout.noteX(1, fl.note.beat, w);
      debugPrint('b${fl.note.beat.toStringAsFixed(3)} '
          'label="${TabLayout.tabLabel(fl.note)}" '
          'grace=${fl.note.grace} tap=${fl.note.tap} '
          '自然位=${natural.toStringAsFixed(1)} 终位=${fl.x.toStringAsFixed(1)} '
          '偏移=${(fl.x - natural).toStringAsFixed(1)} '
          'inkHalf=${TabLayout.inkHalf(fl.note).toStringAsFixed(1)}');
    }
    // 相邻对墨距
    for (var i = 1; i < flow2.length; i++) {
      final a = flow2[i - 1], b = flow2[i];
      final gap = 1.0 + TabLayout.inkHalf(a.note) + TabLayout.inkHalf(b.note);
      debugPrint('m2 对[${TabLayout.tabLabel(a.note)}×${TabLayout.tabLabel(b.note)}] '
          'dist=${(b.x - a.x).toStringAsFixed(1)} 需≥${gap.toStringAsFixed(1)}');
    }
    for (var i = 1; i < flow12.length; i++) {
      final a = flow12[i - 1], b = flow12[i];
      final gap = 1.0 + TabLayout.inkHalf(a.note) + TabLayout.inkHalf(b.note);
      debugPrint('m10-12 对[${TabLayout.tabLabel(a.note)}(m${a.mIdx + 1}b${a.note.beat.toStringAsFixed(2)})'
          '×${TabLayout.tabLabel(b.note)}(m${b.mIdx + 1}b${b.note.beat.toStringAsFixed(2)})] '
          'a.x=${a.x.toStringAsFixed(1)} b.x=${b.x.toStringAsFixed(1)} '
          'dist=${(b.x - a.x).toStringAsFixed(1)} 需≥${gap.toStringAsFixed(1)}');
    }
    for (final fl in flow12) {
      debugPrint('m${fl.mIdx + 1} s2 b${fl.note.beat.toStringAsFixed(3)} '
          '"${TabLayout.tabLabel(fl.note)}" grace=${fl.note.grace} '
          'x=${fl.x.toStringAsFixed(1)}');
    }
    // m12 全弦 b1.125 同拍组 + 各组 maxX vs 小节右界
    final flow12all = TabViewDebug.lastFlow
        .where((fl) => fl.mIdx == 11)
        .toList()
      ..sort((a, b) {
        final cb = a.note.beat.compareTo(b.note.beat);
        if (cb != 0) return cb;
        return a.note.string.compareTo(b.note.string);
      });
    final mx12 = layout.measureX(11, w);
    final mw12 = layout.measureWidthAt(11, w);
    debugPrint('m12 mx=$mx12 mw=$mw12 右界=${(mx12 + mw12).toStringAsFixed(1)}');
    for (final fl in flow12all) {
      debugPrint('m12 all s${fl.note.string} '
          'b${fl.note.beat.toStringAsFixed(3)} '
          '"${TabLayout.tabLabel(fl.note)}" '
          'x=${fl.x.toStringAsFixed(1)} '
          '墨右=${(fl.x + TabLayout.inkHalf(fl.note)).toStringAsFixed(1)}');
    }
    debugPrint('m12 行=${layout.rowsFor(w).indexWhere((r) => r.contains(11))} '
        '行内=${layout.rowsFor(w).firstWhere((r) => r.contains(11))}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
