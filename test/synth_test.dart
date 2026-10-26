import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/synth.dart';
import 'package:guitarbar/core/music/builtin_tunings.dart';
import 'package:guitarbar/core/music/fingering.dart';
import 'package:guitarbar/core/music/chord_parser.dart';

void main() {
  test('wrapWav 头部正确', () {
    final wav = wrapWav(Int16List.fromList([0, 100, -100]));
    expect(wav.length, 50); // 44 头 + 3 样本 * 2 字节
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
  });

  test('click 长度与衰减', () {
    final c = click(0);
    expect(c.length, 2646); // 0.06s * 44100
    expect(c[10], greaterThan(8000)); // 首个正弦峰值附近（t=0 处 sin=0）
    expect(c.last.abs(), lessThan(1000)); // 已衰减
  });

  test('pluck 长度且非静音', () {
    final p = pluck(110.0);
    expect(p.length, 52920); // 1.2s * 44100
    expect(p.take(100).any((v) => v != 0), isTrue);
  });

  test('和弦 PCM：同时发声长度 = 单音长度', () {
    final std = builtinTunings.firstWhere((t) => t.name == 'Standard');
    final c = parseChord('C');
    final v = FingeringGenerator(std.strings)
        .generate(rootPc: c.rootPc, toneClasses: chordToneClasses(c))
        .first;
    final pcm = voicingPcm(std.strings, v.frets, PlayMode.pluckAll);
    expect(pcm.length, 52920);
    expect(pcm.any((x) => x != 0), isTrue);
  });

  test('琶音长度 = 单音 + 间隔*(音数-1)', () {
    final std = builtinTunings.firstWhere((t) => t.name == 'Standard');
    final c = parseChord('C');
    final v = FingeringGenerator(std.strings)
        .generate(rootPc: c.rootPc, toneClasses: chordToneClasses(c))
        .first;
    final count = v.frets.whereType<int>().length;
    final pcm = voicingPcm(std.strings, v.frets, PlayMode.arpeggio);
    expect(pcm.length, 52920 + 9702 * (count - 1)); // 0.22s * 44100 = 9702
  });
}
