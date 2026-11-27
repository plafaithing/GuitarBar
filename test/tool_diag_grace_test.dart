// 一次性诊断：Like A Star.gpx（79）——tie/hopo 计数 + m89/m91 重叠实测。
// heavy：硬编码曲库 id（79→80 漂移，2026-11-18 实锤）——诊断使命已完成
// （结论落盘 tasks/las_diag_out.txt；动态扫描版 tool_gpx_prop_scan_test
// 取代），日常套件跳过，改谱名 id 后按需复用。
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
  // skip=true：一次性诊断已完结（结论落盘 las_diag_out.txt）；曲库 id
  // 漂移 79→80→已删，需用时改路径后去掉 skip 重启用。
  testWidgets('诊断 LAS gpx',
      skip: true, (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    const w = 786.0;
    final f = File(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores\79\source.gpx');
    final ir = parseScore(Uint8List.fromList(f.readAsBytesSync()), 'x')!;
    final track = ir.tracks.first;
    final out = <String>[];
    var ties = 0, tieS = 0, hopoS = 0, hopoE = 0, slides = 0, graces = 0;
    for (final m in track.measures) {
      for (final n in m.notes) {
        if (n.tieEnd) ties++;
        if (n.tieStart) tieS++;
        if (n.hopoStart) hopoS++;
        if (n.hopoEnd) hopoE++;
        if (n.slide != null) slides++;
        if (n.grace) graces++;
      }
    }
    out.add('总音=${track.measures.fold<int>(0, (s, m) => s + m.notes.length)} '
        '小节=${track.measures.length} tieEnd=$ties tieStart=$tieS '
        'hopoS=$hopoS hopoE=$hopoE slide=$slides grace=$graces');
    // 渲染 + m89/m91（渲染序）重叠实测
    final layout = TabLayout(ir);
    final h = layout.sizeFor(w).height + 100;
    tester.view.physicalSize = Size(w, h);
    await tester.pumpWidget(MaterialApp(
      theme: GuitarBarTheme.light(),
      home: Scaffold(
          body: SizedBox(width: w, height: h, child: TabView(ir: ir))),
    ));
    await tester.pumpAndSettle();
    // 重叠实测：同弦相邻音对 dx < 1+墨半+墨半-1
    final flow = TabViewDebug.lastFlow;
    final byString = <int, List<TabFlowDebug>>{};
    for (final fl in flow) {
      byString.putIfAbsent(fl.note.string, () => []).add(fl);
    }
    var overlaps = 0;
    byString.forEach((s, list) {
      final sorted = list..sort((a, b) => a.x.compareTo(b.x));
      for (var i = 1; i < sorted.length; i++) {
        final a = sorted[i - 1], b = sorted[i];
        final gapNeed = 1.0 +
            TabLayout.inkHalf(a.note) +
            TabLayout.inkHalf(b.note);
        final dx = b.x - a.x;
        if (dx < gapNeed - 1 && (b.note.beat - a.note.beat).abs() > 1e-9) {
          overlaps++;
          if (overlaps <= 8) {
            out.add('[叠] m${a.mIdx + 1}/m${b.mIdx + 1} s$s '
                'f${a.note.fret}@b${a.note.beat.toStringAsFixed(2)} ↔ '
                'f${b.note.fret}@b${b.note.beat.toStringAsFixed(2)} '
                'dx=${dx.toStringAsFixed(1)} 需=${gapNeed.toStringAsFixed(1)}');
          }
        }
      }
    });
    out.add('同弦相邻重叠对=$overlaps');
    // m89/m91（渲染序）音列
    for (final mi in [88, 90]) {
      final notes = flow.where((fl) => fl.mIdx == mi).toList()
        ..sort((a, b) => a.x.compareTo(b.x));
      out.add('--- 渲染m${mi + 1}（${notes.length} 音）---');
      for (final fl in notes.take(14)) {
        out.add('  b${fl.note.beat.toStringAsFixed(2)} '
            's${fl.note.string}f${fl.note.fret} '
            'x=${fl.x.toStringAsFixed(1)} '
            '"${fl.note.tieEnd && !fl.note.hopoEnd ? '(tie)' : (fl.note.hopoStart ? 'H起' : '')}"');
      }
    }
    File(r'D:\workplace\code\GuitarBar\tasks\las_diag_out.txt')
        .writeAsStringSync(out.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
