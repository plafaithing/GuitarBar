// 临时探针：Prologue.gtp（实为 GP4.06）的 tieStart/tieEnd 计数与
// 满足 1.5 拍阈值的弧线数（渲染将画的弧线量）。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:guitarbar/core/score/gp34_parser.dart';

void main() {
  test('Prologue tie 计数探针', () {
    final ir = parseGp34Bytes(Uint8List.fromList(File(
            r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores\68\source.gtp')
        .readAsBytesSync()));
    var tieStart = 0;
    var tieEnd = 0;
    final notes = ir.tracks.first.measures.expand((m) => m.notes).toList();
    for (final n in notes) {
      if (n.tieStart) tieStart++;
      if (n.tieEnd) tieEnd++;
    }
    // ignore: avoid_print
    print('总音 ${notes.length} tieStart=$tieStart tieEnd=$tieEnd');
    // 渲染弧线量：复刻 _paintMarks 判据（beat 位置差 ≤1.5，跨小节加整小节）。
    var arcs = 0;
    var barBase = 0.0;
    final mains = ir.timeSignature.split('/');
    var numSig = int.parse(mains[0]);
    var denSig = int.parse(mains[1]);
    final absPos = <double>[]; // 每音绝对 beat 位置
    for (final m in ir.tracks.first.measures) {
      final sig = m.timeSignature?.split('/');
      if (sig != null) {
        numSig = int.parse(sig[0]);
        denSig = int.parse(sig[1]);
      } else {
        numSig = int.parse(mains[0]);
        denSig = int.parse(mains[1]);
      }
      for (final n in m.notes) {
        absPos.add(barBase + n.beat);
      }
      barBase += numSig * 4.0 / denSig;
    }
    for (var i = 0; i < notes.length; i++) {
      if (!notes[i].tieStart) continue;
      for (var j = i + 1; j < notes.length; j++) {
        if (notes[j].string != notes[i].string) continue;
        if (absPos[j] - absPos[i] <= 1.5 + 1e-9) arcs++;
        break;
      }
    }
    // ignore: avoid_print
    print('满足阈值的弧线数=$arcs');
    expect(tieStart, greaterThan(0));
  }, skip: !File(
          r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores\68\source.gtp')
      .existsSync()
      ? '样本缺'
      : null);
}
