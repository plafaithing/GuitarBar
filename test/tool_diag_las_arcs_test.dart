// 一次性诊断：LAS(83) 弧线计数（tie 弧门后实画数 vs 制谱基准 实测 2 条）
// + 全谱重叠违例（用户报 m89/m91 音重叠未消）。
@Tags(['heavy'])
library;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/gtp_parser.dart';
import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';
import 'package:guitarbar/ui/scores/tab_view.dart';
import 'package:guitarbar/ui/theme.dart';

import 'font_setup.dart';
import 'overlap_probe_lib.dart';

void main() {
  setUpAll(loadScoreFonts);
  testWidgets('LAS 83 弧线+重叠诊断', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    final f = File(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores\83\source.gpx');
    final ir = parseScore(Uint8List.fromList(f.readAsBytesSync()), 'x')!;
    // gpif XML 落盘（LeftHandTapped 层级分析用）
    final gpifXml =
        String.fromCharCodes(gpifBytes(Uint8List.fromList(f.readAsBytesSync())));
    File(r'D:\workplace\code\GuitarBar\tasks\las83_gpif.xml')
        .writeAsStringSync(gpifXml);
    final layout = TabLayout(ir);
    // IR 层标志计数
    var tieEnd = 0, hopoEnd = 0, hopoStart = 0, slides = 0, taps = 0;
    for (final m in ir.tracks.first.measures) {
      for (final n in m.notes) {
        if (n.tieEnd) tieEnd++;
        if (n.hopoEnd) hopoEnd++;
        if (n.hopoStart) hopoStart++;
        if (n.slide != null) slides++;
        if (n.tap) taps++;
      }
    }
    debugPrint('IR: tieEnd=$tieEnd hopoS=$hopoStart hopoE=$hopoEnd '
        'slide=$slides tap=$taps measures=${ir.tracks.first.measures.length}');
    // 弧线候选重算（tab_view 弧线门口径）：tieEnd 且非 hopoEnd，前驱 =
    // 同弦且 label 可见的 tie 音对；hopo 弧 = hopoStart→同弦下一音。
    final w = 900.0;
    final h = layout.sizeFor(w).height + 100;
    tester.view.physicalSize = Size(w, h);
    await tester.pumpWidget(MaterialApp(
      theme: GuitarBarTheme.light(),
      home: Scaffold(
          body: SizedBox(width: w, height: h, child: TabView(ir: ir))),
    ));
    await tester.pumpAndSettle();
    final flow = List.of(TabViewDebug.lastFlow)
      ..sort((a, b) {
        final c = a.mIdx.compareTo(b.mIdx);
        if (c != 0) return c;
        final cb = a.note.beat.compareTo(b.note.beat);
        if (cb != 0) return cb;
        return a.note.string.compareTo(b.note.string);
      });
    // tie 弧（两端数字可见 + 同小节——tab_view 纯 tie 弧线门口径）
    var tieArcs = 0;
    final tieArcList = <String>[];
    for (var i = 0; i < flow.length; i++) {
      final n = flow[i].note;
      if (!n.tieEnd || n.hopoEnd) continue;
      if (TabLayout.tabLabel(n).isEmpty && n.beat > 1e-9) continue;
      for (var j = i - 1; j >= 0; j--) {
        final p = flow[j].note;
        if (p.beat + p.duration <= n.beat - 1e-9) break; // 时序断了
        if (p.string != n.string) continue;
        if (flow[j].mIdx != flow[i].mIdx) continue;
        if (TabLayout.tabLabel(p).isEmpty) continue;
        tieArcs++;
        tieArcList.add('m${flow[i].mIdx + 1} b${n.beat} s${n.string} '
            '${p.fret}→${n.fret}');
        break;
      }
    }
    debugPrint('tie 弧实画候选=$tieArcs');
    for (final s in tieArcList) {
      debugPrint('  $s');
    }
    // hopo 弧（hopoStart→同弦下一音）
    var hopoArcs = 0;
    for (var i = 0; i < flow.length; i++) {
      if (!flow[i].note.hopoStart) continue;
      for (var j = i + 1; j < flow.length; j++) {
        if (flow[j].note.beat > flow[i].note.beat + 4) break;
        if (flow[j].note.string != flow[i].note.string) continue;
        hopoArcs++;
        debugPrint('  hopo m${flow[i].mIdx + 1} '
            '${flow[i].note.fret}→${flow[j].note.fret}');
        break;
      }
    }
    debugPrint('hopo 弧=$hopoArcs');
    // 全谱重叠违例（探针口径双轴穿透 >1px），坐标映射 flow 取渲染小节号。
    final caps = TabViewDebug.lastPaintedTexts;
    int mOf(TabPaintedText t) {
      var best = -1;
      var bd = 1e9;
      for (final fl in TabViewDebug.lastFlow) {
        final d = (fl.x - t.centerX).abs() + (fl.y - t.centerY).abs();
        if (d < bd) {
          bd = d;
          best = fl.mIdx;
        }
      }
      return best;
    }

    final sorted2 = [...caps]..sort((a, b) => a.centerY.compareTo(b.centerY));
    final byM = <int, Set<String>>{};
    var violCount = 0;
    for (var i = 0; i < sorted2.length; i++) {
      final a = sorted2[i];
      for (var j = i + 1; j < sorted2.length; j++) {
        final b = sorted2[j];
        if (b.centerY - a.centerY >= 10) break;
        if ((a.centerX - b.centerX).abs() < a.halfW + b.halfW - 1.0 &&
            (a.centerY - b.centerY).abs() < a.halfH + b.halfH - 1.0) {
          violCount++;
          final ma = mOf(a), mb = mOf(b);
          final key = '"${a.text}"×"${b.text}" '
              'dx=${(a.centerX - b.centerX).abs().toStringAsFixed(1)} '
              'dy=${(a.centerY - b.centerY).abs().toStringAsFixed(1)} '
              '($ma,$mb)';
          byM.putIfAbsent(ma < mb ? ma : mb, () => <String>{}).add(key);
        }
      }
    }
    debugPrint('违例总数=$violCount（涉及小节 ${byM.length} 个）');
    final outLines = <String>[];
    for (final e in byM.entries) {
      outLines.add('m${e.key + 1}: ${e.value.join(' | ')}');
    }
    File(r'D:\workplace\code\GuitarBar\tasks\las83_violations.txt')
        .writeAsStringSync(outLines.join('\n'));
    for (final e in byM.entries) {
      if (e.key + 1 >= 88 && e.key + 1 <= 93) {
        debugPrint('m${e.key + 1}: ${e.value.take(5).join(' | ')}');
      }
    }
    // IR 层 tie 音对明细（4 对）：beat/string/fret/label + 前驱
    for (final m in ir.tracks.first.measures) {
      for (final n in m.notes) {
        if (!n.tieEnd) continue;
        NoteIr? prev;
        for (final p in m.notes) {
          if (identical(p, n)) break;
          if (p.string == n.string && p.beat + p.duration > n.beat - 1e-9) {
            prev = p;
          }
        }
        final prevDesc = prev == null
            ? '无(跨小节)'
            : 'f${prev.fret} b${prev.beat} label="${TabLayout.tabLabel(prev)}"';
        debugPrint('tieEnd b${n.beat} s${n.string} f${n.fret} '
            'hopoE=${n.hopoEnd} label="${TabLayout.tabLabel(n)}" '
            'prev=$prevDesc');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
