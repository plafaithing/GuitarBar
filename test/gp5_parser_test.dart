import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/gp5_parser.dart';

/// 构造一个最小 GP5 字节流的辅助（v5.10 头部结构，PyGuitarPro gp5.py 布局）。
/// 真值驱动的补充：魔数/版本校验与截断防护用，完整结构走真值文件。
Uint8List _minimalGp5() {
  final b = BytesBuilder();
  // 版本串：byte-size-string(30)
  final version = 'FICHIER GUITAR PRO v5.10'.codeUnits;
  b.addByte(version.length);
  b.add(version);
  b.add(List<int>.filled(30 - version.length, 0));

  void ibs(String s) {
    final raw = s.codeUnits; // ASCII 即 GBK 兼容
    b.add([
      raw.length + 1, 0, 0, 0, // I32 = len + 1
      raw.length, // U8 内容长度
      ...raw,
    ]);
  }

  // readInfo：9 个 IntByteSizeString + notice(0)
  for (var i = 0; i < 9; i++) {
    ibs(i == 0 ? 'T' : '');
  }
  b.add([0, 0, 0, 0]); // notice count
  // lyrics：trackChoice + 5 行
  b.add([1, 0, 0, 0]);
  for (var i = 0; i < 5; i++) {
    b.add([0, 0, 0, 0]); // startingMeasure
    b.add([0, 0, 0, 0]); // int-size-string 长度 0
  }
  // RSE master effect（v5.1）：I32 + I32 + 11 字节 EQ
  b.add(List<int>.filled(4 + 4 + 11, 0));
  // page setup：7 I32 + I16 + 10 个 IntByteSizeString
  b.add(List<int>.filled(30, 0));
  for (var i = 0; i < 10; i++) {
    ibs('');
  }
  ibs(''); // tempoName
  b.add([70, 0, 0, 0]); // tempo
  b.addByte(0); // hideTempo
  b.addByte(0); // key
  b.add([0, 0, 0, 0]); // octave
  b.add(List<int>.filled(64 * 12, 0)); // MIDI channels
  b.add(List<int>.filled(38, 0)); // directions
  b.add([0, 0, 0, 0]); // master reverb
  b.add([1, 0, 0, 0]); // measureCount = 1
  b.add([1, 0, 0, 0]); // trackCount = 1

  // measure header（首小节无 previous 空字节）
  b.addByte(0x03); // flags：拍号两段都写
  b.addByte(4); // numerator
  b.addByte(4); // denominator
  b.add([2, 2, 2, 2]); // 拍号 beaming（flags&0x03 时读 4 字节）
  b.addByte(0); // 0x10 未设 → 空字节
  b.addByte(0); // triplet feel
  // track：首轨前空字节
  b.addByte(0);
  b.addByte(0); // flags1
  final name = 'Track'.codeUnits;
  b.addByte(name.length);
  b.add(name);
  b.add(List<int>.filled(40 - name.length, 0));
  b.add([6, 0, 0, 0]); // stringCount
  for (final t in [64, 59, 55, 50, 45, 40, 0]) {
    b.add([t, 0, 0, 0]);
  }
  b.add(List<int>.filled(4, 0)); // port
  b.add([1, 0, 0, 0]); // channel
  b.add([1, 0, 0, 0]); // effectChannel
  b.add([24, 0, 0, 0]); // fretCount
  b.add([0, 0, 0, 0]); // capo
  b.add(List<int>.filled(4, 0)); // color
  b.add([0, 0]); // flags2
  b.add(List<int>.filled(3 + 12 + 4 + 4 + 4, 0)); // RSE 静态段
  b.add([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]); // RSE instrument
  b.add(List<int>.filled(4, 0)); // 轨 EQ（4 字节）
  ibs(''); // RSE effect 名
  ibs(''); // RSE effect 类别
  b.addByte(0); // 全部音轨后的空字节

  // measure（1 轨 × 1 小节）：voice0 一拍四分音（string1 fret0），
  // voice1 一拍 rest 拍（0x40 + 0x02）。
  // voice0：beatCount=1
  b.add([1, 0, 0, 0]);
  // beat：flags = 0（normal、无附点无 tuplet）；时值 0（四分）
  b.addByte(0x00);
  b.addByte(0x00); // duration = 四分
  b.addByte(0x40); // stringFlags：string1
  // note：flags = 0x20（有 type + fret）
  b.addByte(0x20);
  b.addByte(0x01); // type normal
  b.addByte(0x00); // fret
  b.addByte(0x00); // flags2
  b.add([0, 0]); // 拍级 flags2 I16
  // voice1：beatCount=1（rest 拍）
  b.add([1, 0, 0, 0]);
  b.addByte(0x40); // flags：status
  b.addByte(0x02); // rest
  b.addByte(0x00); // duration 四分
  b.addByte(0x00); // stringFlags 空
  b.add([0, 0]);
  b.addByte(0); // lineBreak
  return b.toBytes();
}

void main() {
  group('parseGp5Bytes（GP5 二进制）', () {
    test('最小构造流：魔数/头部/单音', () {
      final ir = parseGp5Bytes(_minimalGp5());
      expect(ir.version, 1);
      expect(ir.title, 'T');
      expect(ir.tempo, 70);
      expect(ir.timeSignature, '4/4');
      expect(ir.tuning, ['E2', 'A2', 'D3', 'G3', 'B3', 'E4']);
      expect(ir.capo, 0);
      expect(ir.capoApplied, isFalse);
      expect(ir.tracks, hasLength(1));
      expect(ir.tracks.single.measures, hasLength(1));
      final notes = ir.tracks.single.measures.single.notes;
      expect(notes, hasLength(1));
      expect(notes.single.string, 1);
      expect(notes.single.fret, 0);
      expect(notes.single.beat, 0.0);
      expect(notes.single.duration, 1.0);
      expect(notes.single.confidence, isNull);
    });

    test('魔数不符抛 FormatException（GP4 版本串）', () {
      final raw = _minimalGp5();
      final bad = Uint8List.fromList(raw);
      const v4 = 'FICHIER GUITAR PRO v4.06';
      bad[0] = v4.length;
      bad.setRange(1, 1 + v4.length, v4.codeUnits);
      expect(() => parseGp5Bytes(bad), throwsFormatException);
    });

    test('过小文件抛 FormatException', () {
      expect(() => parseGp5Bytes(Uint8List.fromList([1, 2])),
          throwsFormatException);
    });
  });

  group('真实文件集成（存在时）', () {
    test(r'D:\Guitar\Distance .gp5 → IR（PyGuitarPro 基线对账）', () {
      final f = File(r'D:\Guitar\Distance .gp5');
      if (!f.existsSync()) {
        markTestSkipped('真实 gp5 文件不存在');
        return;
      }
      final ir = parseGp5Bytes(f.readAsBytesSync());
      expect(ir.version, 1);
      expect(ir.title, 'Distance');
      expect(ir.tempo, 70);
      expect(ir.timeSignature, '4/4');
      expect(ir.capo, 3);
      expect(ir.capoApplied, isFalse);
      expect(ir.tuning, ['E2', 'A2', 'D3', 'G3', 'B3', 'E4']);
      expect(ir.tracks, hasLength(1));
      expect(ir.tracks.single.name, '音轨 1');
      expect(ir.tracks.single.measures, hasLength(61));
      // 小节 0（PyGuitarPro 基线：两个二分音拍 × 两弦）
      final m0 = ir.tracks.single.measures[0];
      expect(m0.notes, hasLength(4));
      expect(m0.notes[0].string, 1);
      expect(m0.notes[0].fret, 12);
      expect(m0.notes[0].beat, 0.0);
      expect(m0.notes[0].duration, 2.0);
      expect(m0.notes[1].beat, 2.0);
      expect(m0.notes[1].duration, 2.0);
      expect(m0.notes[2].string, 5);
      expect(m0.notes[2].fret, 0);
      expect(m0.notes[3].string, 6);
      expect(m0.notes[3].fret, 4);
      // 全曲：809 个音符（含 76 个 tie 续接端，均入列表）
      var total = 0;
      var tieEnds = 0;
      var tieStarts = 0;
      for (final m in ir.tracks.single.measures) {
        total += m.notes.length;
        tieEnds += m.notes.where((n) => n.tieEnd).length;
        tieStarts += m.notes.where((n) => n.tieStart).length;
      }
      expect(total, 809);
      expect(tieEnds, 76);
      // 76 个续接端中 2 个无链首（m31 声部1 弦6、m33 声部2 弦1——该声部
      // 该弦此前从未出音，PyGuitarPro getTiedNoteValue 返回 -1 → 品值夹 0），
      // 无链首不补 tieStart。
      expect(tieStarts, 74);
      // 反复结构（PyGuitarPro 基线）：header20 open / header33 结尾1 /
      // header38 闭合（raw=2 → 弹两遍）/ header39 结尾2
      final measures = ir.tracks.single.measures;
      expect(measures[19].repeatStart, isTrue);
      expect(measures[32].endings, [1]);
      expect(measures[37].repeatEnd, isTrue);
      expect(measures[37].repeatCount, 2);
      expect(measures[38].endings, [2]);
      // tie 链首时长应大于单音时值（至少有一条链完成累计）
      final merged = measures
          .expand((m) => m.notes)
          .where((n) => n.tieStart && n.duration > 2.0);
      expect(merged, isNotEmpty);
      for (final m in measures) {
        for (final n in m.notes) {
          expect(n.confidence, isNull);
        }
      }
    });

    test(r'D:\Guitar\Flower.gp5 → IR（GBK 标题/1-4 拍号）', () {
      final f = File(r'D:\Guitar\Flower.gp5');
      if (!f.existsSync()) {
        markTestSkipped('真实 gp5 文件不存在');
        return;
      }
      final ir = parseGp5Bytes(f.readAsBytesSync());
      expect(ir.title, 'flower 岸部真明');
      expect(ir.tempo, 120);
      expect(ir.timeSignature, '1/4'); // 首小节 1/4 弱起
      expect(ir.capo, 0);
      expect(ir.tuning, ['E2', 'A2', 'D3', 'G3', 'B3', 'E4']);
      expect(ir.tracks.single.name, '音轨 1');
      expect(ir.tracks.single.measures, hasLength(43));
      // 首小节（PyGuitarPro 基线）：3 弦 0 品 → 2 品，各半拍
      final m0 = ir.tracks.single.measures[0];
      expect(m0.notes, hasLength(2));
      expect(m0.notes[0].string, 3);
      expect(m0.notes[0].fret, 0);
      expect(m0.notes[0].beat, 0.0);
      expect(m0.notes[0].duration, 0.5);
      expect(m0.notes[1].string, 3);
      expect(m0.notes[1].fret, 2);
      expect(m0.notes[1].beat, 0.5);
      // 全曲 439 音、无 tie
      var total = 0;
      for (final m in ir.tracks.single.measures) {
        total += m.notes.length;
      }
      expect(total, 439);
      // 反复结构：header10 open / header28 结尾1 / header39 闭合 / header40 结尾2
      final measures = ir.tracks.single.measures;
      expect(measures[9].repeatStart, isTrue);
      expect(measures[27].endings, [1]);
      expect(measures[38].repeatEnd, isTrue);
      expect(measures[38].repeatCount, 2);
      expect(measures[39].endings, [2]);
    });
  });
}
