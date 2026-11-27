// 一次性诊断：三谱弧线口径复验（回滚解耦门 + tap 右端弧）——
// Prologue/Promise tie 弧候选（旧门口径）应回落、tap 短弧对应出现。
@Tags(['heavy'])
library;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';
import 'package:guitarbar/ui/scores/tab_view.dart';
import 'package:guitarbar/ui/theme.dart';

import 'font_setup.dart';
import 'overlap_probe_lib.dart' show parseScore;

void main() {
  setUpAll(loadScoreFonts);
  testWidgets('三谱弧线口径', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    final specs = <(String, int, String)>[
      ('Prologue', 84, 'gtp'),
      ('Promise', 85, 'gp5'),
      ('LAS', 83, 'gpx'),
    ];
    for (final (name, dir, ext) in specs) {
      final f = File(
          'D:\\workplace\\code\\GuitarBar\\build\\windows\\x64\\runner\\Release\\data\\scores\\$dir\\source.$ext');
      if (!f.existsSync()) {
        debugPrint('$name: 文件不存在 $dir');
        continue;
      }
      final ir = parseScore(f.readAsBytesSync(), f.uri.pathSegments.last);
      if (ir == null) {
        debugPrint('$name: 解析 null');
        continue;
      }
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
      // tie 弧候选（渲染旧门口径：tieStart 纯 tie + 两端可见 + 同小节）
      var tieArcs = 0;
      final sorted = [...flow]..sort((a, b) {
          final c = a.mIdx.compareTo(b.mIdx);
          if (c != 0) return c;
          final cb = a.note.beat.compareTo(b.note.beat);
          if (cb != 0) return cb;
          return a.note.string.compareTo(b.note.string);
        });
      bool vis(n) =>
          n.hopoStart ||
          n.slide != null ||
          n.vibrato ||
          n.trill ||
          n.bend != null ||
          n.beat <= 1e-9;
      for (var i = 0; i < sorted.length; i++) {
        final n = sorted[i].note;
        if (!n.tieStart || n.hopoStart || n.legatoStart) continue;
        for (var j = i + 1; j < sorted.length; j++) {
          final p = sorted[j].note;
          if (p.string != n.string) continue;
          if (sorted[j].mIdx != sorted[i].mIdx) break;
          // 渲染门口径（2026-11-19 修）：tieEnd 端可见即可（origin 端
          // 数字天然显示——LAS m34 制谱基准 实测 2→(2) 实证）。
          if (vis(p)) tieArcs++;
          break;
        }
      }
      // tap 短弧对（右端 tap + 同弦紧邻 + 拍距 ≤0.25）
      var tapArcs = 0;
      for (var i = 1; i < sorted.length; i++) {
        final cur = sorted[i].note, prev = sorted[i - 1].note;
        if (!cur.tap) continue;
        if (cur.string != prev.string) continue;
        if (cur.beat - prev.beat > 0.25 + 1e-9) continue;
        tapArcs++;
      }
      debugPrint('$name: tieStart总数=${flow.where((f) => f.note.tieStart).length} '
          'tie弧候选(旧门)=$tieArcs tap短弧对=$tapArcs');
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
