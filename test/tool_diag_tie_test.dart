// 一次性诊断：哆啦A梦.gp3（scores 66/69）tie 解析健康检查。
// 对照 制谱基准 语义：tie 目的音必须紧跟同弦源音（中间有休止/跨小节间隔
// 即无效 tie），源音时值合并不得跨越休止。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:guitarbar/core/score/gp34_parser.dart';
import 'package:guitarbar/core/score/score_ir.dart';

void main() {
  test('哆啦A梦 tie 健康检查', () {
    final out = <String>[];
    for (final id in ['70']) {
      final f = File(
          'D:\\workplace\\code\\GuitarBar\\build\\windows\\x64\\runner\\Release\\data\\scores\\$id\\source.gp3');
      if (!f.existsSync()) continue;
      final ir = parseGp34Bytes(Uint8List.fromList(f.readAsBytesSync()));
      out.add('=== scores/$id: "${ir.title}" ===');
      final track = ir.tracks.first;
      // 同弦上一音索引（跨 rest 检测用）
      var tiePairs = 0;
      var suspiciousCrossRest = 0;
      var suspiciousCrossMeasure = 0;
      final lastNoteOf = <int, NoteIr>{};
      final lastMeasureOf = <int, int>{};
      final restSeen = <int>{};
      for (final m in track.measures) {
        // rest 拍检测：音覆盖不到的小节内拍段……简化：小节无音记 rest
        for (final n in m.notes) {
          if (n.tieEnd) {
            tiePairs++;
            final prev = lastNoteOf[n.string];
            final prevM = lastMeasureOf[n.string];
            if (prev != null) {
              final prevEnd = prev.beat + prev.duration;
              // 同小节内：源音结束拍 < 本音起始拍（中间有空隙=休止）
              if (prevM == m.index && prevEnd < n.beat - 1e-9) {
                suspiciousCrossRest++;
                if (suspiciousCrossRest <= 6) {
                  out.add('  [跨隙tie] m${m.index + 1} s${n.string} '
                      'f${prev.fret}->f${n.fret} '
                      '源止${prevEnd.toStringAsFixed(2)} 目起${n.beat.toStringAsFixed(2)}');
                }
              }
              if (prevM != null && prevM != m.index) {
                suspiciousCrossMeasure++;
              }
            }
          }
          // rest 跟踪：同弦在 rest 后再来 tie……rest 无音，用小节内
          // 拍隙近似（上面 prevEnd < beat 即已覆盖）。
          lastNoteOf[n.string] = n;
          lastMeasureOf[n.string] = m.index;
          restSeen.remove(n.string);
        }
      }
      out.add('tieStart=${track.measures.expand((m) => m.notes).where((n) => n.tieStart).length} '
          'tieEnd=$tiePairs 跨隙=$suspiciousCrossRest 跨小节=$suspiciousCrossMeasure '
          '总音=${track.measures.fold<int>(0, (s, m) => s + m.notes.length)}');
      final brushCount = track.measures
          .expand((m) => m.notes)
          .where((n) => n.brush != null)
          .length;
      final graceCount = track.measures
          .expand((m) => m.notes)
          .where((n) => n.grace)
          .length;
      out.add('brush=$brushCount grace=$graceCount '
          'hopoStart=${track.measures.expand((m) => m.notes).where((n) => n.hopoStart).length} '
          'hopoEnd=${track.measures.expand((m) => m.notes).where((n) => n.hopoEnd).length} '
          '拍号样本=${track.measures.take(3).map((m) => m.timeSignature ?? ir.timeSignature).join("/")} '
          '小节拍距样本=m1末音止${track.measures.first.notes.isEmpty ? "-" : (track.measures.first.notes.last.beat + track.measures.first.notes.last.duration).toStringAsFixed(2)}');
      // 头 6 小节逐音 dump（看 tie 分布形态）
      for (final m in track.measures.take(6)) {
        final parts = m.notes
            .map((n) =>
                's${n.string}f${n.fret}@${n.beat.toStringAsFixed(2)}'
                '+${n.duration.toStringAsFixed(2)}'
                '${n.tieStart ? "TS" : ""}${n.tieEnd ? "TE" : ""}'
                '${n.hopoStart ? "H" : ""}${n.hopoEnd ? "h" : ""}')
            .join(' | ');
        out.add('  m${m.index + 1}: $parts');
      }
    }
    File(r'D:\workplace\code\GuitarBar\tasks\tie_diag_69.txt')
        .writeAsStringSync(out.join('\n'));
  });
}
