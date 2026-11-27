// 一次性诊断：三轮探针最后 7 处违例（Paganini grace 对 + 狩猎曲泛音
// 三连 w=900 临界行宽）。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';
import 'package:guitarbar/ui/scores/tab_view.dart';
import 'package:guitarbar/ui/theme.dart';

import 'font_setup.dart';
import 'overlap_probe_lib.dart';

void _dumpBand(double y, double x0, double x1, {String tag = ''}) {
  final band = TabViewDebug.lastFlow
      .where((f) => (f.y - y).abs() < 10 && f.x >= x0 && f.x <= x1)
      .toList()
    ..sort((a, b) => a.x.compareTo(b.x));
  debugPrint('--- [$tag] y=$y x∈[$x0,$x1] flow（${band.length}）---');
  for (final f in band) {
    debugPrint('  m${f.mIdx + 1} b${f.note.beat.toStringAsFixed(3)} '
        's${f.note.string} f${f.note.fret} '
        '"${TabLayout.tabLabel(f.note)}" x=${f.x.toStringAsFixed(1)} '
        'ink=${(TabLayout.inkHalf(f.note) * 2).toStringAsFixed(1)} '
        '${f.note.grace ? "grace" : ""}');
  }
}

Future<void> _diag(
  WidgetTester tester,
  String match,
  double w,
  double y,
  double x0,
  double x1,
) async {
  tester.view.devicePixelRatio = 1.0;
  for (final f in collectScoreFiles(Directory(r'D:\Guitar\158吉他谱电子版大全'))) {
    if (!f.path.contains(match)) continue;
    final ir = parseScore(Uint8List.fromList(f.readAsBytesSync()), 'x');
    if (ir == null) continue;
    final layout = TabLayout(ir);
    final h = layout.sizeFor(w).height + 100;
    tester.view.physicalSize = Size(w, h);
    await tester.pumpWidget(MaterialApp(
      theme: GuitarBarTheme.light(),
      home: Scaffold(
          body: SizedBox(width: w, height: h, child: TabView(ir: ir))),
    ));
    await tester.pumpAndSettle();
    debugPrint('### ${f.uri.pathSegments.last} w=$w');
    final hit = TabViewDebug.lastFlow
        .where((fl) => (fl.y - y).abs() < 10 && fl.x >= x0 && fl.x <= x1)
        .toList();
    if (hit.isNotEmpty) {
      final mIdx = hit.first.mIdx;
      final (r, c) = layout.locate(mIdx, w);
      final row = layout.rowsFor(w)[r];
      final avail = w - 32.0;
      final rowW = avail / row.length;
      debugPrint('行$r col$c rowW=${rowW.toStringAsFixed(0)} '
          '小节=$row');
      debugPrint('rowOverfull=${layout.rowOverfull(row, layout.rowWidthsForTest(row, 906))}');
      debugPrint('hasOverfull(900)=${layout.hasOverfullMeasure(900)}');
      final rows = layout.rowsFor(w);
      for (var rr = 0; rr < rows.length; rr++) {
        debugPrint('  行$rr rowOverfull=${layout.rowOverfull(rows[rr], layout.rowWidthsForTest(rows[rr], 906))}');
      }
    }
    _dumpBand(y, x0, x1, tag: match);
    return;
  }
  debugPrint('未找到 $match');
}

void main() {
  setUpAll(loadScoreFonts);
  testWidgets('诊断最后 7 处', (tester) async {
    addTearDown(tester.view.reset);
    await _diag(tester, 'il carnevale di Venezia', 900, 444, 200, 340);
    await _diag(tester, '狩猎曲(1)', 900, 696, 280, 440);
  }, timeout: const Timeout(Duration(minutes: 8)));
}
