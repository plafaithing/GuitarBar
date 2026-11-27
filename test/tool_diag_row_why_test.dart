// 行被拒原因定位工具（2026-11-27）：用户反馈"某谱 mX–mY 应该能在同一
// 行"时，在 _cases 里加一行即可——打印候选行的求解器结果（为什么被拒
// / 行宽如何分配）；被拒时把违例小节的排布终位（buildRowFlow，与渲染
// 同一个函数）dump 出来，看是哪一对在挤。
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/gp34_parser.dart';
import 'package:guitarbar/core/score/gp5_parser.dart';
import 'package:guitarbar/core/score/gtp_parser.dart';
import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/ui/scores/row_flow.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';

import 'font_setup.dart';

const _root =
    'D:/workplace/code/GuitarBar/build/windows/x64/runner/Release/data';
const _w = 904.0; // 用户窗口宽（排版宽）

/// (谱 id, 标题[= 导入时的 sourceName], 候选行的小节号[1 起]...)
const _cases = [
  (35, '伍伍慧 - Bluebird', [
    [1, 2, 3],
    [4, 5, 6, 7],
  ]),
  (63, '月下之恋', [
    [8, 9, 10, 11],
  ]),
];

ScoreIr _load(int id, String name) {
  final f = Directory('$_root/scores/$id')
      .listSync()
      .firstWhere((e) => e.path.endsWith('.gpx') ||
          e.path.endsWith('.gp5') ||
          e.path.endsWith('.gtp'));
  final bytes = File(f.path).readAsBytesSync();
  if (f.path.endsWith('.gpx')) return parseGpxBytes(bytes, sourceName: name);
  if (f.path.endsWith('.gp5')) return parseGp5Bytes(bytes);
  return parseGp34Bytes(bytes);
}

void _dumpMeasures(TabLayout layout, List<MeasureIr> measures, Set<int> ids) {
  for (final mi in ids.toList()..sort()) {
    final m = measures[mi];
    final info = layout.minInfoForTest(mi);
    final byBeat = <double, List<NoteIr>>{};
    for (final n in m.notes) {
      byBeat.putIfAbsent(n.beat, () => []).add(n);
    }
    final beats = byBeat.keys.toList()..sort();
    final sb = StringBuffer();
    for (var i = 0; i < beats.length; i++) {
      final b = beats[i];
      final d = i > 0 ? b - beats[i - 1] : 0.0;
      sb.write(i == 0 ? '[b$b' : ' | +${d.toStringAsFixed(3)}→b$b');
      sb.write(': ');
      sb.write(byBeat[b]!
          .map((n) => 's${n.string}f${n.fret}'
              '${n.grace ? 'g' : ''}${n.deco ? 'd' : ''}'
              '/${n.duration.toStringAsFixed(3)}')
          .join(','));
      sb.write(']');
    }
    // ignore: avoid_print
    print('  m${mi + 1}: 音${m.notes.length} 列${beats.length} '
        '最小宽=${info.min.toStringAsFixed(0)} '
        '行首占宽=${info.headExtra.toStringAsFixed(0)}\n     $sb');
  }
}

void _dumpFlow(TabLayout layout, List<MeasureIr> measures, List<int> members,
    List<double> widths, Set<int> bad) {
  final xOf = <int, double>{};
  final wOf = <int, double>{};
  var acc = TabLayout.leftPad;
  for (var c = 0; c < members.length; c++) {
    xOf[members[c]] = acc;
    wOf[members[c]] = widths[c];
    acc += widths[c];
  }

  double beatX(int mi, double beat) {
    final cb = layout.contentBeatsOf(mi);
    return xOf[mi]! +
        TabLayout.notePad +
        math.min(beat, cb) * (wOf[mi]! - TabLayout.notePad * 2) / cb;
  }

  final flow = buildRowFlow(
      measures: measures,
      row: members,
      notePad: TabLayout.notePad,
      graceAsNormal: layout.graceAsNormal,
      measureX: (mi) => xOf[mi]!,
      measureWidth: (mi) => wOf[mi]!,
      noteX: beatX,
      stringY: (_) => 0,
      inkHalf: TabLayout.inkHalf);
  for (final mi in bad) {
    final g = [
      for (final f in flow)
        if (f.mIdx == mi) f
    ]..sort((a, b) => a.x.compareTo(b.x));
    final sb = StringBuffer();
    for (final f in g) {
      sb.write('x=${f.x.toStringAsFixed(1)}(lin='
          '${beatX(mi, f.note.beat).toStringAsFixed(1)}) '
          'b${f.note.beat.toStringAsFixed(3)} s${f.note.string} '
          'f${f.note.fret}${f.note.grace ? 'g' : ''}${f.note.deco ? 'd' : ''} '
          '半宽=${TabLayout.inkHalf(f.note).toStringAsFixed(1)} | ');
    }
    // ignore: avoid_print
    print('     m${mi + 1} 终位: $sb');
  }
}

void main() {
  setUpAll(loadScoreFonts);
  test('row why', () {
    for (final (id, name, candidates) in _cases) {
      final ir = _load(id, name);
      final layout = TabLayout(ir);
      final measures = ir.tracks.first.measures;
      // ignore: avoid_print
      print('===== $name (id$id) @${_w.toInt()}：'
          '${layout.rowsFor(_w).length} 行 =====');
      _dumpMeasures(layout, measures, {
        for (final c in candidates)
          for (final m in c) m - 1
      });
      for (final cand in candidates) {
        final members = [for (final m in cand) m - 1];
        final sol = layout.solveRowForTest(members, _w);
        final ws = sol.widths.map((x) => x.toStringAsFixed(0)).join('/');
        // ignore: avoid_print
        print('候选 [${cand.join(",")}] → why=${sol.why} 宽=$ws');
        if (sol.why != null) {
          final fc = layout.flowCheckForTest(members, sol.widths);
          // ignore: avoid_print
          print('     终位校验: why=${fc.why} 违例小节='
              '${fc.bad.map((x) => "m${x + 1}").join(",")} '
              '缺口=${fc.need.entries.map((e) => "m${e.key + 1}:${e.value.toStringAsFixed(0)}").join(" ")}');
          _dumpFlow(layout, measures, members, sol.widths, fc.bad);
        }
      }
    }
  });
}
