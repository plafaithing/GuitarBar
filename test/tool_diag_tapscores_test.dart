// 一次性诊断：全曲库 tap 谱分布 + T 谱顶形态跨谱验证（用户问"其他
// 曲谱是否通用"——列证据）。
@Tags(['heavy'])
library;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';
import 'package:guitarbar/ui/scores/tab_view.dart';
import 'package:guitarbar/ui/theme.dart';

import 'font_setup.dart';
import 'overlap_probe_lib.dart';

void main() {
  setUpAll(loadScoreFonts);
  testWidgets('全曲库 tap 谱 T 验证', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    final root = Directory(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores');
    final out = <String>[];
    var tapScores = 0;
    for (final d in root.listSync().whereType<Directory>()) {
      final files = d.listSync().whereType<File>().where((f) =>
          f.path.toLowerCase().endsWith('.gp3') ||
          f.path.toLowerCase().endsWith('.gp4') ||
          f.path.toLowerCase().endsWith('.gp5') ||
          f.path.toLowerCase().endsWith('.gtp') ||
          f.path.toLowerCase().endsWith('.gpx'));
      for (final f in files) {
        final ir = parseScore(
            Uint8List.fromList(f.readAsBytesSync()), 'x');
        if (ir == null) continue;
        var taps = 0;
        for (final m in ir.tracks.first.measures) {
          for (final n in m.notes) {
            if (n.tap) taps++;
          }
        }
        if (taps == 0) continue;
        tapScores++;
        // 渲染 T 形态 + 违例检查（3 宽抽样）
        final layout = TabLayout(ir);
        var viol = 0;
        for (final w in [900.0, 1300.0]) {
          final contentH = layout.sizeFor(w).height;
          final h = contentH < 2400.0 ? 2400.0 : contentH + 100;
          tester.view.physicalSize = Size(w, h);
          await tester.pumpWidget(MaterialApp(
            theme: GuitarBarTheme.light(),
            home: Scaffold(
                body: SizedBox(width: w, height: h, child: TabView(ir: ir))),
          ));
          await tester.pumpAndSettle();
          viol += findViolations(TabViewDebug.lastPaintedTexts)
              .where((v) => v.contains('(T)'))
              .length;
        }
        out.add('谱 ${d.uri.pathSegments.last}: tap=$taps, T违例=$viol');
      }
    }
    out.insert(0, '含 tap 的曲谱数=$tapScores（全部走同一渲染路径）');
    File(r'D:\workplace\code\GuitarBar\tasks\tap_scores_out.txt')
        .writeAsStringSync(out.join('\n'));
    debugPrint('done tapScores=$tapScores');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
