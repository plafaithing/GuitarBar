// dsh 第二轮复核探针（跑完即删）：Prologue del\87\source.gtp 实测
// A 项装饰音 grace 标志 / E 项"装饰音+同弦 tieEnd"场景存在性 / B 项 tie 显示面规模。
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/gp34_parser.dart';

void main() {
  test('dsh round2 probe: Prologue', () {
    final bytes = File(
            r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores\del\87\source.gtp')
        .readAsBytesSync();
    final ir = parseGp34Bytes(bytes);
    final buf = StringBuffer();
    var graceCount = 0;
    var tieEndCount = 0;
    // E 项模式：同拍同弦"短值音 + tieEnd 音"相邻（装饰音普通化后的形态）
    var decoTiePairs = 0;
    final pairDesc = <String>[];
    for (var mi = 0; mi < ir.tracks.first.measures.length; mi++) {
      final m = ir.tracks.first.measures[mi];
      for (final n in m.notes) {
        if (n.grace) graceCount++;
        if (n.tieEnd) tieEndCount++;
      }
      // 同弦同拍对扫描
      for (var i = 0; i < m.notes.length; i++) {
        for (var j = i + 1; j < m.notes.length; j++) {
          final a = m.notes[i];
          final b = m.notes[j];
          if (a.string == b.string &&
              (a.beat - b.beat).abs() < 1e-9 &&
              b.tieEnd) {
            decoTiePairs++;
            pairDesc.add(
                'm${mi + 1} beat${a.beat} s${a.string}: f${a.fret}(d${a.duration}) -> f${b.fret}(d${b.duration},tieEnd)');
          }
        }
      }
      if (mi == 3 || mi == 16) {
        buf.writeln('--- m${mi + 1} ---');
        for (final n in m.notes) {
          buf.writeln(
              'beat${n.beat} s${n.string} f${n.fret} d${n.duration} '
              'tieE${n.tieEnd} tieS${n.tieStart} g${n.grace} '
              'hS${n.hopoStart} hE${n.hopoEnd} slide${n.slide} x${n.technique == 'x'}');
        }
      }
    }
    // 同弦相邻音序扫描（跨拍变体：短值音后同弦直接 tieEnd，无 intervening 发声音）
    var adjDecoTie = 0;
    final adjDesc = <String>[];
    for (var mi = 0; mi < ir.tracks.first.measures.length; mi++) {
      final m = ir.tracks.first.measures[mi];
      // 按 (beat,string) 排序模拟播放遍历序
      final ns = [...m.notes]..sort((a, b) {
          final c = a.beat.compareTo(b.beat);
          if (c != 0) return c;
          return a.string.compareTo(b.string);
        });
      var lastSounding = <int, int>{}; // string -> idx of last sounding note
      for (var k = 0; k < ns.length; k++) {
        final n = ns[k];
        if (n.tieEnd) {
          final li = lastSounding[n.string];
          if (li != null) {
            final p = ns[li];
            if (p.duration <= 0.0626) {
              adjDecoTie++;
              adjDesc.add(
                  'm${mi + 1} s${n.string}: f${p.fret}(d${p.duration}@${p.beat}) -> tieEnd f${n.fret}(d${n.duration}@${n.beat})');
            }
          }
          continue;
        }
        lastSounding[n.string] = k;
      }
    }
    buf.writeln('grace=true notes: $graceCount');
    buf.writeln('tieEnd notes: $tieEndCount');
    buf.writeln('same-beat same-string deco->tieEnd pairs: $decoTiePairs');
    for (final d in pairDesc.take(20)) {
      buf.writeln('  PAIR $d');
    }
    buf.writeln('adjacent short->tieEnd (same string, no intervening): $adjDecoTie');
    for (final d in adjDesc.take(20)) {
      buf.writeln('  ADJ $d');
    }
    // ignore: avoid_print
    print(buf.toString());
    expect(graceCount, 0, reason: '装饰音普通化后全曲不应有 grace=true（gp34 路径）');
  }, skip: '一次性探针已完结（头注释"跑完即删"）；引用的曲库 id 87 已删，'
      '需用时改路径（IR 回归见 tool_dsh_grace_ir_test）');
}
