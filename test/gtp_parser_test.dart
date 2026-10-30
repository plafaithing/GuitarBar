import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/gtp_parser.dart';
import 'package:guitarbar/core/score/score_ir.dart';

// 最小 gpif（GP6 扁平 id 引用 schema）：2 小节、泛音、调弦、tempo。
const _gpifXml = '''<?xml version="1.0" encoding="UTF-8"?>
<GPIF>
  <Score><Title><![CDATA[Steel Test]]></Title></Score>
  <MasterTrack>
    <Tracks>0</Tracks>
    <Automations>
      <Automation>
        <Type>Tempo</Type>
        <Value>90 2</Value>
      </Automation>
    </Automations>
  </MasterTrack>
  <Tracks>
    <Track id="0">
      <Name><![CDATA[Steel Guitar]]></Name>
      <Properties>
        <Property name="Tuning">
          <Pitches>40 45 50 55 59 64</Pitches>
        </Property>
      </Properties>
    </Track>
  </Tracks>
  <MasterBars>
    <MasterBar>
      <Time>4/4</Time>
      <Bars>0</Bars>
    </MasterBar>
    <MasterBar>
      <Time>4/4</Time>
      <Bars>1</Bars>
    </MasterBar>
  </MasterBars>
  <Bars>
    <Bar id="0">
      <Voices>0</Voices>
    </Bar>
    <Bar id="1">
      <Voices>1</Voices>
    </Bar>
  </Bars>
  <Voices>
    <Voice id="0">
      <Beats>0 1</Beats>
    </Voice>
    <Voice id="1">
      <Beats>2</Beats>
    </Voice>
  </Voices>
  <Beats>
    <Beat id="0">
      <Rhythm ref="0" />
      <Notes>0</Notes>
    </Beat>
    <Beat id="1">
      <Rhythm ref="0" />
      <Notes>1</Notes>
    </Beat>
    <Beat id="2">
      <Rhythm ref="0" />
      <Notes>2</Notes>
    </Beat>
  </Beats>
  <Notes>
    <Note id="0">
      <Properties>
        <Property name="String"><String>5</String></Property>
        <Property name="Fret"><Fret>0</Fret></Property>
      </Properties>
    </Note>
    <Note id="1">
      <Properties>
        <Property name="String"><String>4</String></Property>
        <Property name="Fret"><Fret>2</Fret></Property>
        <Property name="HarmonicType"><HType>Natural</HType></Property>
      </Properties>
    </Note>
    <Note id="2">
      <Properties>
        <Property name="String"><String>3</String></Property>
        <Property name="Fret"><Fret>0</Fret></Property>
      </Properties>
    </Note>
  </Notes>
  <Rhythms>
    <Rhythm id="0">
      <NoteValue>Quarter</NoteValue>
    </Rhythm>
  </Rhythms>
</GPIF>''';

/// MSB first 位打包（与解析器 _GpxBitReader 对偶），fixture 构造用。
class _BitWriter {
  final List<int> _bytes = [];
  int _current = 0;
  int _bits = 0;

  void _writeBit(int bit) {
    _current = (_current << 1) | bit;
    _bits++;
    if (_bits == 8) {
      _bytes.add(_current);
      _current = 0;
      _bits = 0;
    }
  }

  void writeBits(int value, int count) {
    for (var i = count - 1; i >= 0; i--) {
      _writeBit((value >> i) & 1);
    }
  }

  void writeBitsReversed(int value, int count) {
    for (var i = 0; i < count; i++) {
      _writeBit((value >> i) & 1);
    }
  }

  void writeBytes(List<int> bytes) {
    for (final b in bytes) {
      writeBits(b, 8);
    }
  }

  Uint8List toBytes() {
    final out = List<int>.from(_bytes);
    if (_bits > 0) out.add(_current << (8 - _bits));
    return Uint8List.fromList(out);
  }
}

/// GP6 容器：BCFZ + expectedLength(LE 32) + 自定义位流。
/// 默认把 payload 切成 ≤3 字节的字面量块（0 标志 + 2 位计数字段）。
Uint8List _buildBcfz(List<int> payload, {Uint8List? bitStream, int? lengthOverride}) {
  final Uint8List bits;
  if (bitStream != null) {
    bits = bitStream;
  } else {
    final w = _BitWriter();
    for (var i = 0; i < payload.length; i += 3) {
      final end = i + 3 < payload.length ? i + 3 : payload.length;
      final chunk = payload.sublist(i, end);
      w.writeBits(0, 1);
      w.writeBitsReversed(chunk.length, 2);
      w.writeBytes(chunk);
    }
    bits = w.toBytes();
  }
  final len = lengthOverride ?? payload.length;
  return Uint8List.fromList([
    ...utf8.encode('BCFZ'),
    len & 0xFF,
    (len >> 8) & 0xFF,
    (len >> 16) & 0xFF,
    (len >> 24) & 0xFF,
    ...bits,
  ]);
}

/// BCFS 扇区镜像：头 4 字节 + 扇区 1（目录项）+ 扇区 2（文件数据）。
Uint8List _buildBcfsImage(String name, List<int> content) {
  const sectorSize = 4096;
  final image = Uint8List(sectorSize * 3);
  final b = ByteData.view(image.buffer);
  image.setRange(0, 4, utf8.encode('BCFS'));
  const dir = sectorSize;
  b.setUint32(dir, 2, Endian.little);
  final nameBytes = ascii.encode(name);
  image.setRange(dir + 4, dir + 4 + nameBytes.length, nameBytes);
  b.setUint32(dir + 140, content.length, Endian.little);
  b.setUint32(dir + 148, 2, Endian.little); // 数据扇区 2
  b.setUint32(dir + 152, 0, Endian.little); // 指针表终止
  image.setRange(sectorSize * 2, sectorSize * 2 + content.length, content);
  return image;
}

Uint8List _buildGp6Container(String gpifXml) {
  // 解压结果前 4 字节是内部头（skipHeader 跳过），其后才是 BCFS 镜像。
  final payload = <int>[
    ...utf8.encode('HEAD'),
    ..._buildBcfsImage('score.gpif', utf8.encode(gpifXml)),
  ];
  return _buildBcfz(payload);
}

Uint8List _buildGp7Container(String gpifXml) {
  final archive = Archive();
  archive.addFile(ArchiveFile.bytes('score.gpif', utf8.encode(gpifXml)));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// 公共断言：_gpifXml 应解析出的 IR。
/// 弦号语义：gpif string 0 = 1 弦（最高音），即 IR = gp + 1。
void _expectCommonIr(ScoreIr ir) {
  expect(ir.version, 1);
  expect(ir.title, 'Steel Test');
  expect(ir.tempo, 90);
  expect(ir.timeSignature, '4/4');
  expect(ir.tuning, ['E2', 'A2', 'D3', 'G3', 'B3', 'E4']);
  expect(ir.capo, 0);
  expect(ir.unrecognizedPages, isEmpty);
  expect(ir.tracks, hasLength(1));
  expect(ir.tracks.single.name, 'Steel Guitar');
  expect(ir.tracks.single.measures, hasLength(2));

  final m0 = ir.tracks.single.measures[0];
  expect(m0.index, 0);
  expect(m0.confidence, 0);
  expect(m0.failed, isFalse);
  expect(m0.notes, hasLength(2));
  expect(m0.notes[0].beat, 0.0);
  expect(m0.notes[0].duration, 1.0);
  expect(m0.notes[0].string, 1); // gp 5 → IR 1（高音 E 弦）
  expect(m0.notes[0].fret, 0);
  expect(m0.notes[0].technique, isNull);
  expect(m0.notes[1].beat, 1.0);
  expect(m0.notes[1].duration, 1.0);
  expect(m0.notes[1].string, 2); // gp 4 → IR 2
  expect(m0.notes[1].fret, 2);
  expect(m0.notes[1].technique, 'H'); // HarmonicType
  final m1 = ir.tracks.single.measures[1];
  expect(m1.index, 1);
  expect(m1.notes, hasLength(1));
  expect(m1.notes.single.string, 3); // gp 3 → IR 3
  expect(m1.notes.single.fret, 0);
  // GTP 导入无 AI 置信度
  expect(m0.notes[0].confidence, isNull);
  expect(m0.notes[1].confidence, isNull);
  expect(m1.notes.single.confidence, isNull);
}

void main() {
  group('parseGpif（gpif XML 层）', () {
    test('扁平 schema → IR（弦号 IR=6-gp、tempo/调弦/拍号/小节）', () {
      _expectCommonIr(parseGpif(_gpifXml));
    });

    test('capo 属性读取', () {
      final xml = _gpifXml.replaceFirst(
        '<Property name="Tuning">',
        '<Property name="CapoFret"><Fret>2</Fret></Property>'
        '<Property name="Tuning">',
      );
      expect(parseGpif(xml).capo, 2);
    });

    test('capo 品语义：gpif 绝对品 → IR 夹后品；低于夹位 clamp 0', () {
      // gpif fret 是绝对品格（alphaTab 发声不加 capo）；IR 统一夹后品：
      // 9-2=7；1-2=-1 → 按弦在夹位之前（不可弹），clamp 0 按夹后空弦。
      const xml = '''<GPIF>
        <MasterTrack><Tracks>0</Tracks></MasterTrack>
        <Tracks><Track id="0"><Name><![CDATA[T]]></Name>
          <Properties><Property name="CapoFret"><Fret>2</Fret></Property></Properties>
        </Track></Tracks>
        <MasterBars><MasterBar><Time>4/4</Time><Bars>0</Bars></MasterBar></MasterBars>
        <Bars><Bar id="0"><Voices>0</Voices></Bar></Bars>
        <Voices><Voice id="0"><Beats>0 1</Beats></Voice></Voices>
        <Beats>
          <Beat id="0"><Rhythm ref="0"/><Notes>0</Notes></Beat>
          <Beat id="1"><Rhythm ref="0"/><Notes>1</Notes></Beat>
        </Beats>
        <Notes>
          <Note id="0"><Properties><Property name="String"><String>3</String></Property><Property name="Fret"><Fret>9</Fret></Property></Properties></Note>
          <Note id="1"><Properties><Property name="String"><String>4</String></Property><Property name="Fret"><Fret>1</Fret></Property></Properties></Note>
        </Notes>
        <Rhythms><Rhythm id="0"><NoteValue>Quarter</NoteValue></Rhythm></Rhythms>
      </GPIF>''';
      final ir = parseGpif(xml);
      expect(ir.capo, 2);
      final notes = ir.tracks.single.measures.single.notes;
      expect(notes[0].fret, 7); // 绝对 9 → 夹后 7
      expect(notes[1].fret, 0); // 绝对 1 低于夹位 2 → clamp 0
    });

    test('每个引用独立出音；origin 标记且前槽同弦同品仍出音', () {
      // b0: note0 (3,0)；b1: note1 (3,0) 带 origin="true"（前槽同弦同品 → 仍出音，
      // 不得按续接吞掉）；b1 重复引用 = 独立攻击（gp6 逐引用复用）。
      const xml = '''<GPIF>
        <MasterTrack><Tracks>0</Tracks></MasterTrack>
        <Tracks><Track id="0"><Name><![CDATA[T]]></Name></Track></Tracks>
        <MasterBars><MasterBar><Time>4/4</Time><Bars>0</Bars></MasterBar></MasterBars>
        <Bars><Bar id="0"><Voices>0</Voices></Bar></Bars>
        <Voices><Voice id="0"><Beats>0 1 1</Beats></Voice></Voices>
        <Beats>
          <Beat id="0"><Rhythm ref="0"/><Notes>0</Notes></Beat>
          <Beat id="1"><Rhythm ref="0"/><Notes>1</Notes></Beat>
        </Beats>
        <Notes>
          <Note id="0"><Properties><Property name="String"><String>3</String></Property><Property name="Fret"><Fret>0</Fret></Property></Properties></Note>
          <Note id="1"><Tie origin="true" destination="false"/><Properties><Property name="String"><String>3</String></Property><Property name="Fret"><Fret>0</Fret></Property></Properties></Note>
        </Notes>
        <Rhythms><Rhythm id="0"><NoteValue>Quarter</NoteValue></Rhythm></Rhythms>
      </GPIF>''';
      final notes = parseGpif(xml).tracks.single.measures.single.notes;
      expect(notes, hasLength(3)); // 逐引用独立攻击
      expect([for (final n in notes) n.beat], [0.0, 1.0, 2.0]);
      expect(notes[1].string, 3); // gp 3 → IR 3
      expect(notes[1].fret, 0);
    });

    test('跨小节 tie destination 落 beat0 不出音，时长累加到起点', () {
      // m0 beat0: note0 origin（四分）；m1 beat0: note1 destination（四分）。
      // destination 不出音（防假击弦），其时值累加回 m0 的起点 → duration 2.0。
      const xml = '''<GPIF>
        <MasterTrack><Tracks>0</Tracks></MasterTrack>
        <Tracks><Track id="0"><Name><![CDATA[T]]></Name></Track></Tracks>
        <MasterBars>
          <MasterBar><Time>4/4</Time><Bars>0</Bars></MasterBar>
          <MasterBar><Time>4/4</Time><Bars>1</Bars></MasterBar>
        </MasterBars>
        <Bars>
          <Bar id="0"><Voices>0</Voices></Bar>
          <Bar id="1"><Voices>1</Voices></Bar>
        </Bars>
        <Voices>
          <Voice id="0"><Beats>0</Beats></Voice>
          <Voice id="1"><Beats>2</Beats></Voice>
        </Voices>
        <Beats>
          <Beat id="0"><Rhythm ref="0"/><Notes>0</Notes></Beat>
          <Beat id="2"><Rhythm ref="0"/><Notes>1</Notes></Beat>
        </Beats>
        <Notes>
          <Note id="0"><Tie origin="true" destination="false"/><Properties><Property name="String"><String>3</String></Property><Property name="Fret"><Fret>0</Fret></Property></Properties></Note>
          <Note id="1"><Tie origin="false" destination="true"/><Properties><Property name="String"><String>3</String></Property><Property name="Fret"><Fret>0</Fret></Property></Properties></Note>
        </Notes>
        <Rhythms><Rhythm id="0"><NoteValue>Quarter</NoteValue></Rhythm></Rhythms>
      </GPIF>''';
      final measures = parseGpif(xml).tracks.single.measures;
      expect(measures, hasLength(2));
      expect(measures[0].notes, hasLength(1));
      expect(measures[0].notes.single.beat, 0.0);
      expect(measures[0].notes.single.duration, 2.0); // 1.0 + 跨小节续接累加
      expect(measures[1].notes, isEmpty); // destination 不出音
    });

    test('缺 Track 抛 FormatException', () {
      expect(() => parseGpif('<GPIF/>'), throwsFormatException);
    });
  });

  group('decompressGpxImage（GP6 位级 LZ）', () {
    test('字面量块', () {
      final payload = utf8.encode('HEAD' 'AAB');
      final image = decompressGpxImage(_buildBcfz(payload));
      expect(image, utf8.encode('AAB'));
    });

    test('回溯引用（wordSize MSB first，offset/size LSB first）', () {
      // 'HEAD' 字面量 → 'A' 字面量 → 回溯引用复制 1 字节（offset=1, size=1,
      // wordSize=4）→ 'B' 字面量；skipHeader 跳过 'HEAD' 后应得 'AAB'。
      final w = _BitWriter();
      w.writeBits(0, 1);
      w.writeBitsReversed(3, 2);
      w.writeBytes(utf8.encode('HEA'));
      w.writeBits(0, 1);
      w.writeBitsReversed(1, 2);
      w.writeBytes(utf8.encode('D'));
      w.writeBits(0, 1);
      w.writeBitsReversed(1, 2);
      w.writeBytes(utf8.encode('A'));
      w.writeBits(1, 1);
      w.writeBits(4, 4); // wordSize
      w.writeBitsReversed(1, 4); // offset
      w.writeBitsReversed(1, 4); // size
      w.writeBits(0, 1);
      w.writeBitsReversed(1, 2);
      w.writeBytes(utf8.encode('B'));
      final payload = utf8.encode('HEADAAB');
      final image =
          decompressGpxImage(_buildBcfz(payload, bitStream: w.toBytes()));
      expect(image, utf8.encode('AAB'));
    });

    test('位流耗尽容错（真实文件尾部截断场景）', () {
      // expectedLength 声称 20 字节，位流只解出 6 字节即 EOF → 以已解出内容继续
      final payload = utf8.encode('HEADAB');
      final container = _buildBcfz(payload, lengthOverride: 20);
      expect(decompressGpxImage(container), utf8.encode('AB'));
    });
  });

  group('readBcfsFiles（BCFS 扇区镜像）', () {
    test('目录项抽取 + fileSize 截断', () {
      final content = utf8.encode(_gpifXml);
      final files = readBcfsFiles(_buildBcfsImage('score.gpif', content));
      expect(files.keys, ['score.gpif']);
      expect(files['score.gpif'], content);
    });
  });

  group('parseGpxBytes（容器分流）', () {
    test('GP6 容器（BCFZ）解析', () {
      _expectCommonIr(parseGpxBytes(_buildGp6Container(_gpifXml)));
    });

    test('GP7 容器（zip）解析同一 gpif', () {
      _expectCommonIr(parseGpxBytes(_buildGp7Container(_gpifXml)));
    });

    test('GP7 zip 无 gpif 条目抛 FormatException', () {
      final archive = Archive();
      archive.addFile(ArchiveFile.string('other.txt', 'x'));
      final zip = Uint8List.fromList(ZipEncoder().encode(archive));
      expect(() => parseGpxBytes(zip), throwsFormatException);
    });

    test('坏魔数抛 FormatException', () {
      expect(
          () => parseGpxBytes(Uint8List.fromList([1, 2, 3, 4])),
          throwsFormatException);
    });

    test('过小文件抛 FormatException', () {
      expect(() => parseGpxBytes(Uint8List.fromList([1])),
          throwsFormatException);
    });
  });

  group('真实文件集成（存在时）', () {
    test('D:/Guitar/月下之恋.gpx（GP6 容器）→ IR', () {
      final f = File(r'D:\Guitar\月下之恋.gpx');
      if (!f.existsSync()) {
        markTestSkipped('真实 gpx 文件不存在');
        return;
      }
      final ir = parseGpxBytes(f.readAsBytesSync());
      expect(ir.title, '月下の恋');
      expect(ir.tempo, 80);
      expect(ir.timeSignature, '4/4');
      expect(ir.tuning, ['E2', 'A2', 'D3', 'G3', 'B3', 'E4']);
      expect(ir.capo, 0);
      expect(ir.tracks.single.name, 'Steel Guitar');
      expect(ir.tracks.single.measures, hasLength(62));
      // 小节 0 基准值（Python 参照实现 + alphaTab 对账逐音核对）：
      // gp6 逐引用复用 → 声部 0 五攻击（8分×4 + 二分）+ 声部 1 全音符 = 6 音。
      final m0 = ir.tracks.single.measures[0];
      expect(m0.notes, hasLength(6));
      expect(m0.notes[0].beat, 0.0);
      expect(m0.notes[0].duration, 0.5);
      expect(m0.notes[0].string, 2); // gp 4 → IR 2（B 弦）fret 9
      expect(m0.notes[0].fret, 9);
      expect(m0.notes[1].beat, 0.5);
      expect(m0.notes[1].duration, 0.5);
      expect(m0.notes[1].string, 1); // gp 5 → IR 1（高音 E）fret 9
      expect(m0.notes[1].fret, 9);
      expect(m0.notes[2].beat, 1.0);
      expect(m0.notes[2].duration, 0.5);
      expect(m0.notes[2].string, 1); // gp 5 → IR 1（重复引用 = 独立攻击）
      expect(m0.notes[2].fret, 9);
      expect(m0.notes[3].beat, 1.5);
      expect(m0.notes[3].duration, 0.5);
      expect(m0.notes[3].string, 2); // gp 4 → IR 2 fret 9
      expect(m0.notes[3].fret, 9);
      expect(m0.notes[4].beat, 2.0);
      expect(m0.notes[4].duration, 2.0); // 二分音符
      expect(m0.notes[4].string, 1); // gp 5 → IR 1 fret 9
      expect(m0.notes[4].fret, 9);
      expect(m0.notes[5].beat, 0.0);
      expect(m0.notes[5].duration, 4.0);
      expect(m0.notes[5].string, 4); // gp 2 → IR 4（G 弦）fret 7（声部 1 全音符）
      expect(m0.notes[5].fret, 7);
      var totalNotes = 0;
      for (final m in ir.tracks.single.measures) {
        totalNotes += m.notes.length;
      }
      // 770 个引用 − 41 个 destination="true" 续接端 = 729 攻击。
      expect(totalNotes, 729);
      expect(m0.notes[0].confidence, isNull);
    });
  });
}
