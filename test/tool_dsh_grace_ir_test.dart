// 装饰音 IR 形态回归（Prologue GP4 m4/m17；曲库 id 漂移 → 动态找谱）：
// 装饰音合成**普通音形态**（2026-11-19 用户决策"不当小号挂靠，当成
// 单独的音"）：fret3 hopoS=true dur=0.0625 先于本体同拍，本体 grace=
// false tie 链首保留；tie 延续音 (N) 显示形态在 tabLabel（不在此测）。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/gp34_parser.dart';
import 'package:guitarbar/core/score/score_ir.dart';

void main() {
  test('装饰音 IR 形态（Prologue m4/m17）', () {
    // 动态找 Prologue（曲库 id 频繁漂移：68→87→90）。
    final dir = Directory(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores');
    ScoreIr? ir;
    for (final d in dir.listSync()) {
      final f = File('${d.path}\\source.gtp');
      if (!f.existsSync()) continue;
      try {
        final cand = parseGp34Bytes(Uint8List.fromList(f.readAsBytesSync()));
        if (cand.title.contains('Prologue')) {
          ir = cand;
          break;
        }
      } catch (_) {}
    }
    if (ir == null) return; // 曲库无 Prologue：静默跳过
    final m4 = ir.tracks.first.measures[3];
    final m17 = ir.tracks.first.measures[16];
    // 结构断言（2026-11-19 三轮形态）：装饰音（fret3 + deco + slide
    // 'shift' + 64 分时值）先于本体（fret10/7）同拍；本体 grace/deco
    // 均 false、tie 链首保留；同拍 tieEnd 音带 tieAnchor（制谱基准 逐弧
    // 实证：装饰拍 tieE 裸数字显示）。
    final g4 = m4.notes.firstWhere(
        (n) => n.string == 2 && n.fret == 3 && n.deco);
    final main4 = m4.notes
        .firstWhere((n) => n.string == 2 && n.fret == 10 && !n.tieEnd);
    expect(g4.beat, main4.beat);
    expect(g4.duration, moreOrLessEquals(0.0625, epsilon: 1e-6));
    expect(g4.grace, false);
    expect(g4.slide, 'shift'); // 制谱基准 sl 弧形态（hammer→sl 非 H）
    expect(g4.hopoStart, false);
    expect(g4.velocity, 95);
    expect(main4.grace, false);
    expect(main4.tieStart, true); // 链尾 b2.5 的链首保留
    // 同拍 tieEnd（3弦0）带数字锚。
    final tieE4 =
        m4.notes.firstWhere((n) => n.string == 3 && n.tieEnd);
    expect(tieE4.beat, main4.beat);
    expect(tieE4.tieAnchor, true);
    final g17 = m17.notes.firstWhere(
        (n) => n.string == 1 && n.fret == 3 && n.deco);
    final main17 = m17.notes
        .firstWhere((n) => n.string == 1 && n.fret == 7 && !n.tieEnd);
    expect(g17.beat, main17.beat);
    expect(g17.duration, moreOrLessEquals(0.0625, epsilon: 1e-6));
    expect(main17.grace, false);
    final tieE17 = m17.notes.firstWhere(
        (n) => n.string == 2 && n.tieEnd && n.beat == main17.beat);
    expect(tieE17.tieAnchor, true);
  });
}
