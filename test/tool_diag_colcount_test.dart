// 不同拍同列分类计数诊断（2026-11-27 折行普适性改动的前后对照）：
// 常驻探针把「倒置」「相邻弦标签咬合」合计记档不判罚，通过时不打印。
// 本诊断按性质拆分，供改动前后对照判断是否触犯铁律「不同拍不同列」：
//   inv      倒置（晚拍画在早拍左侧 >1px）
//   near     近似同列：不同拍、任意弦、中心距 0 ≤ dx < 18（用户规则口径）
//   biteNear 相邻弦标签咬合 且 dx < 18（近似同列的子集）
//   biteWide 相邻弦标签咬合 且 dx ≥ 18（标签宽导致，中心距足够）
// 口径与 tool_overlap_probe_test 同源（probe lib、宽度、全谱高渲染）。
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

const _appDataScores =
    'D:/workplace/code/GuitarBar/build/windows/x64/runner/Release/data/scores';

Widget _host(ScoreIr ir, double width, double height) => MaterialApp(
      theme: GuitarBarTheme.light(),
      home: Scaffold(
        body: SizedBox(width: width, height: height, child: TabView(ir: ir)),
      ),
    );

/// 18px = 近似同列阈值（rowOverfullWhy 的 near-col 同口径）。
const _near = 18.0;

void main() {
  setUpAll(loadScoreFonts);
  testWidgets('同列分类计数：app 曲库 × 多行宽', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // 只取在用谱（scores/<id>/source.*，排除 scores/del/ 已删副本）。
    final files = collectScoreFiles(Directory(_appDataScores))
        .where((f) => !f.path.contains('${Platform.pathSeparator}del${Platform.pathSeparator}'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    // id 标签：app 谱取目录 id，雷区谱取文件名。
    final idOf = <String, String>{};
    for (final f in files) {
      idOf[f.path] = f.parent.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last;
    }
    // 158 库"历史雷区"（与常驻探针同名单——每轮修复引出过残类的谱）。
    const heavyRoot = 'D:/Guitar/158吉他谱电子版大全';
    const heavyNames = ['时间.gp3', 'Paganini', '狩猎曲', '第一次2'];
    if (Directory(heavyRoot).existsSync()) {
      for (final f in collectScoreFiles(Directory(heavyRoot))) {
        if (heavyNames.any(f.path.contains)) {
          if (!files.any((x) => x.path == f.path)) {
            files.add(f);
            idOf[f.path] = f.uri.pathSegments.last;
          }
        }
      }
      files.sort((a, b) => a.path.compareTo(b.path));
    }
    // ignore: avoid_print
    print('谱文件 ${files.length} 份');
    const widths = [786.0, 900.0, 1100.0, 1300.0];
    var inkTotal = 0, inkExempt = 0;
    for (final f in files) {
      final Uint8List bytes;
      try {
        bytes = Uint8List.fromList(f.readAsBytesSync());
      } catch (_) {
        continue;
      }
      final ir = parseScore(bytes, f.uri.pathSegments.last);
      if (ir == null) continue;
      final layout = TabLayout(ir);
      final id = idOf[f.path] ?? '?';
      for (final w in widths) {
        final contentH = layout.sizeFor(w).height;
        final h = contentH < 2400.0 ? 2400.0 : contentH + 100;
        tester.view.physicalSize = Size(w, h);
        try {
          await tester.pumpWidget(_host(ir, w, h));
          await tester.pumpAndSettle();
        } catch (_) {
          await tester.pumpWidget(const SizedBox.shrink());
          continue;
        }
        tester.takeException();
        final flow = TabViewDebug.lastFlow;
        // 原始墨重叠（与常驻探针同口径 findViolations，**无视结构性
        // 豁免**——探针对含 grace 行 / 被迫压缩的谱只计数不判罚，这里
        // 把被豁免的真实重叠暴露出来，防止"探针通过"说过头）。
        final ink = findViolations(TabViewDebug.lastPaintedTexts);
        final exempt = layout.hasOverfullMeasure(w);
        if (ink.isNotEmpty) inkTotal += ink.length;
        if (ink.isNotEmpty) {
          inkExempt += exempt ? ink.length : 0;
        }
        final rows = layout.rowsFor(w);
        // 单小节行内的小节（结构性极限：行宽已给满，违例不可避免）。
        final solo = {
          for (final r in rows)
            if (r.length == 1) r.first
        };
        var inv = 0, invSolo = 0, near = 0, biteNear = 0, biteWide = 0,
            nearX = 0, nearXsolo = 0;
        final nearDetail = <String>[];
        final invDetail = <String>[];
        for (var i = 0; i < flow.length; i++) {
          for (var j = i + 1; j < flow.length; j++) {
            final a = flow[i], b = flow[j];
            if (a.mIdx != b.mIdx) continue;
            if ((a.note.beat - b.note.beat).abs() < 1e-6) continue;
            final early = a.note.beat < b.note.beat ? a : b;
            final late = a.note.beat < b.note.beat ? b : a;
            final dx = late.x - early.x;
            // 非豁免对：豁免口径取 TabLayout.nearColExempt（与折行判定
            // 同一来源——亚拍错位 / 前音装饰短音）；grace 不进校验
            // （装饰音按设计贴主音旁，2026-11-25 起明确豁免）。
            final strict = !TabLayout.nearColExempt(early.note, late.note) &&
                (layout.graceAsNormal ||
                    !(early.note.grace || late.note.grace));
            // 倒置同样只数非豁免对（装饰音槽位/deco 左槽把短音画到前一拍
            // 音左侧是渲染层既有设计，规则明确豁免，不进回归指标）。
            if (dx < -1.0) {
              if (strict) {
                if (solo.contains(a.mIdx)) {
                  invSolo++;
                } else {
                  inv++;
                  if (invDetail.length < 12) {
                    invDetail.add('w${w.toInt()} m${a.mIdx + 1} '
                        'dx=${dx.toStringAsFixed(1)} '
                        'b${early.note.beat.toStringAsFixed(3)}/s${early.note.string}'
                        'f${early.note.fret}×'
                        'b${late.note.beat.toStringAsFixed(3)}/s${late.note.string}'
                        'f${late.note.fret}');
                  }
                }
              }
              continue;
            }
            final adjacent =
                (a.note.string - b.note.string).abs() == 1;
            final bite = adjacent
                ? early.x +
                    TabLayout.inkHalf(early.note) -
                    (late.x - TabLayout.inkHalf(late.note))
                : 0.0;
            // 判据与折行同源：非豁免对须 ≥ nearColNeed（按标签墨宽）；
            // 豁免对沿用 18px 仅作"近"的观察计数。
            final needX = strict
                ? TabLayout.nearColNeed(early.note, late.note)
                : _near;
            if (dx < needX) {
              near++;
              if (strict) {
                if (solo.contains(a.mIdx)) {
                  nearXsolo++;
                  continue;
                }
                nearX++;
                if (nearDetail.length < 20) {
                  final lin = layout.noteX(a.mIdx, late.note.beat, w) -
                      layout.noteX(a.mIdx, early.note.beat, w);
                  String tag(TabFlowDebug f) => 'g${f.note.grace ? 1 : 0}'
                      'd${f.note.deco ? 1 : 0}'
                      '/${f.note.duration.toStringAsFixed(3)}';
                  nearDetail.add('w${w.toInt()} m${a.mIdx + 1} dx=${dx.toStringAsFixed(1)} '
                      'need=${TabLayout.nearColNeed(early.note, late.note).toStringAsFixed(1)} '
                      'g${late.note.grace ? 1 : 0} '
                      'lin=${lin.toStringAsFixed(1)} '
                      'w=${layout.measureWidthAt(a.mIdx, w).toStringAsFixed(0)} '
                      'b${early.note.beat.toStringAsFixed(3)}/s${early.note.string}'
                      '(${tag(early)})×'
                      'b${late.note.beat.toStringAsFixed(3)}/s${late.note.string}'
                      '(${tag(late)})');
                }
              }
              if (bite > 0) biteNear++;
            } else if (bite > 0) {
              biteWide++;
            }
          }
        }
        final singles = rows.take(rows.length - 1).where((r) => r.length == 1).length;
        // nearX = 多小节行内的非豁免近似同列（本可避免——折行/加宽能消）；
        // nearXsolo = 单小节行内的（行宽已给满，结构性）。
        // ignore: avoid_print
        print('id=$id w=${w.toInt()} 行数=${rows.length} 非末行单小节=$singles '
            'inv=$inv near=$near nearX=$nearX nearXsolo=$nearXsolo '
            'biteNear=$biteNear biteWide=$biteWide '
            'inkRaw=${ink.length}${exempt ? "(豁免谱)" : ""}');
        for (final v in ink.take(4)) {
          // ignore: avoid_print
          print('    INK $v');
        }
        for (final d in invDetail) {
          // ignore: avoid_print
          print('    INV $d');
        }
        if (nearX > 0) {
          for (final d in nearDetail) {
            // ignore: avoid_print
            print('    NEAR $d');
          }
        }
      }
    }
    // ignore: avoid_print
    print('墨重叠合计：$inkTotal 对（其中落在豁免谱内 $inkExempt 对，'
        '非豁免谱 ${inkTotal - inkExempt} 对）');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
