// 一次性诊断（dsh 复核 2026-11-20 dup deco 分支）：
// 静态全库普查——① b0/近线 deco（beat*bpm<18 → 左界钳制路径，可能与
// 本体同列贴印）；② 同弦@beat 多 deco（k≥2 → 本体落位 nx-(k-1)*step
// ≠ nx，同拍对齐破坏）；③ deco+宽 label 本体（1+half(deco)+half(main)
// >18 → 本体右漂）。渲染终位抽查——含 deco 谱 × 多行宽：同拍跨弦
// 内部对齐（非 deco 音 max-min x）、deco-本体左右序、探针双判据复跑。
@Tags(['heavy'])
library;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';
import 'package:guitarbar/ui/scores/tab_view.dart';
import 'package:guitarbar/ui/theme.dart';

import 'font_setup.dart';
import 'overlap_probe_lib.dart';

void main() {
  setUpAll(loadScoreFonts);
  testWidgets('deco 形态普查 + 终位对齐抽查', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;

    final dirs = <Directory>[
      Directory(r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores'),
      Directory(r'D:\Guitar\158吉他谱电子版大全'),
    ];
    final files = <File>[];
    for (final d in dirs) {
      if (d.existsSync()) files.addAll(collectScoreFiles(d));
    }

    var scoresWithDeco = 0;
    var clampRisk = 0; // b0/近线 deco（静态：beat=0 或 narrow-bpm 近线）
    var multiDeco = 0;
    var widePair = 0;
    var maxWideDrift = 0.0;
    final wideDriftHist = <String, int>{};
    final decoScores = <File>[];

    for (final f in files) {
      final ScoreIr? ir;
      try {
        ir = parseScore(f.readAsBytesSync(), f.uri.pathSegments.last);
      } catch (_) {
        continue;
      }
      if (ir == null || ir.tracks.isEmpty) continue;
      final ms = ir.tracks.first.measures;
      var hasDeco = false;
      for (final m in ms) {
        final decoCnt = <String, int>{};
        for (final n in m.notes) {
          if (!n.deco) continue;
          hasDeco = true;
          if (n.beat.abs() < 1e-6) {
            clampRisk++;
            debugPrint('[b0 deco] ${f.uri.pathSegments.last} '
                'm${m.index + 1} s${n.string} fret${n.fret}');
          }
          final k = '${n.string}@${n.beat.toStringAsFixed(3)}';
          decoCnt[k] = (decoCnt[k] ?? 0) + 1;
          final main = m.notes.firstWhere(
              (o) =>
                  !o.deco &&
                  o.string == n.string &&
                  (o.beat - n.beat).abs() < 1e-6,
              orElse: () => n);
          final hd = TabLayout.inkHalf(n);
          final hm = TabLayout.inkHalf(main);
          if (1.0 + hd + hm > 18.0) {
            widePair++;
            final drift = (1.0 + hd + hm) - 18.0;
            if (drift > maxWideDrift) maxWideDrift = drift;
            final bucket = drift < 0.5
                ? '<0.5'
                : drift < 1.0
                    ? '0.5-1'
                    : drift < 3.0
                        ? '1-3'
                        : '>=3';
            wideDriftHist[bucket] = (wideDriftHist[bucket] ?? 0) + 1;
            if (drift >= 1.0) {
              debugPrint('[宽对大] ${f.uri.pathSegments.last} '
                  'm${m.index + 1} s${n.string} b${n.beat.toStringAsFixed(3)} '
                  'decoHalf=${hd.toStringAsFixed(1)} '
                  'mainHalf=${hm.toStringAsFixed(1)} '
                  '本体右漂=${drift.toStringAsFixed(1)}');
            }
          }
        }
        for (final e in decoCnt.entries) {
          if (e.value >= 2) {
            multiDeco++;
            debugPrint('[多deco] ${f.uri.pathSegments.last} '
                'm${m.index + 1} ${e.key} ×${e.value}');
          }
        }
      }
      if (hasDeco) {
        scoresWithDeco++;
        decoScores.add(f);
      }
    }
    debugPrint('库文件=${files.length} 含deco谱=$scoresWithDeco '
        'b0deco=$clampRisk 多deco串=$multiDeco 宽对=$widePair '
        '最大宽对漂移=${maxWideDrift.toStringAsFixed(2)} '
        '漂移分布=$wideDriftHist');
    if (const bool.fromEnvironment('skipRender', defaultValue: true)) {
      // dsh 复核二轮：渲染段已跑过（证据见 11-20 会话记录），此处仅静态普查。
      return;
    }

    // —— 渲染终位抽查（含 deco 谱 × 多行宽）——
    var alignViol = 0;
    var probeViol = 0;
    var clampFired = 0;
    var minDecoGap = double.infinity;
    for (final f in decoScores) {
      final ScoreIr? ir;
      try {
        ir = parseScore(f.readAsBytesSync(), f.uri.pathSegments.last);
      } catch (_) {
        continue;
      }
      if (ir == null || ir.tracks.isEmpty) continue;
      final layout = TabLayout(ir);
      for (final w in [786.0, 900.0, 1100.0, 1300.0]) {
        final h = layout.sizeFor(w).height + 100;
        tester.view.physicalSize = Size(w, h);
        await tester.pumpWidget(MaterialApp(
          theme: GuitarBarTheme.light(),
          home: Scaffold(
              body: SizedBox(width: w, height: h, child: TabView(ir: ir))),
        ));
        await tester.pumpAndSettle();
        final flow = TabViewDebug.lastFlow;
        // ① 同拍跨弦内部对齐（非 deco 非 grace）：max-min x ≤ 0.5
        final groups = <String, List<TabFlowDebug>>{};
        for (final fl in flow) {
          if (fl.note.deco || fl.note.grace) continue;
          groups.putIfAbsent(
              '${fl.mIdx}@${fl.note.beat.toStringAsFixed(4)}', () => []).add(fl);
        }
        groups.forEach((k, g) {
          if (g.length < 2) return;
          final xs = g.map((e) => e.x).toList()..sort();
          if (xs.last - xs.first > 0.5) {
            alignViol++;
            debugPrint('[同拍错列] ${f.uri.pathSegments.last} w=$w $k '
                'spread=${(xs.last - xs.first).toStringAsFixed(1)} '
                '(${g.map((e) => 's${e.note.string}@${e.x.toStringAsFixed(1)}').join(' ')})');
          }
        });
        // ② deco-本体序与净空：deco.x ≤ 本体.x；墨净空统计
        for (final fl in flow) {
          if (!fl.note.deco) continue;
          final partner = flow.where((o) =>
              !o.note.deco &&
              !o.note.grace &&
              o.mIdx == fl.mIdx &&
              o.note.string == fl.note.string &&
              (o.note.beat - fl.note.beat).abs() < 1e-6);
          for (final p in partner) {
            if (fl.x > p.x + 0.5) {
              alignViol++;
              debugPrint('[deco反超] ${f.uri.pathSegments.last} w=$w '
                  'm${fl.mIdx + 1} s${fl.note.string} '
                  'b${fl.note.beat.toStringAsFixed(3)} '
                  'deco=${fl.x.toStringAsFixed(1)} main=${p.x.toStringAsFixed(1)}');
            }
            final gap = p.x -
                fl.x -
                TabLayout.inkHalf(fl.note) -
                TabLayout.inkHalf(p.note);
            if (gap < minDecoGap) minDecoGap = gap;
          }
          // ③ 左界钳制触发统计（nx-18 < mx+notePad → 钳到界=本体同列风险）
          final nx = layout.noteX(fl.mIdx, fl.note.beat, w);
          final bound =
              layout.measureX(fl.mIdx, w) + TabLayout.notePad;
          if (nx - 18.0 < bound) {
            clampFired++;
            debugPrint('[钳制触发] ${f.uri.pathSegments.last} w=$w '
                'm${fl.mIdx + 1} s${fl.note.string} '
                'b${fl.note.beat.toStringAsFixed(3)} '
                'decoX=${fl.x.toStringAsFixed(1)} bound=${bound.toStringAsFixed(1)} '
                'mainX=${partner.isEmpty ? -1.0 : partner.first.x.toStringAsFixed(1)}');
          }
        }
        // ④ 探针双判据复跑（墨盒相交 + 不同拍咬合/倒置）
        final painted = TabViewDebug.lastPaintedTexts;
        final v1 = findViolations(painted);
        final v2 = findBeatColumnViolations(flow);
        if (v1.isNotEmpty || v2.isNotEmpty) {
          probeViol += v1.length + v2.length;
          for (final v in [...v1.take(10), ...v2.take(10)]) {
            debugPrint('[探针] ${f.uri.pathSegments.last} w=$w $v');
          }
        }
      }
      await tester.pumpWidget(Container());
    }
    debugPrint('终位抽查：同拍错列/deco反超=$alignViol 探针违例=$probeViol '
        '钳制触发=$clampFired deco-本体最小墨净空='
        '${minDecoGap == double.infinity ? '-' : minDecoGap.toStringAsFixed(1)}');
  }, timeout: const Timeout(Duration(minutes: 25)));
}
