import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../music/note.dart';
import 'score_ir.dart';

/// GTP（.gpx / .gp）字节 → ScoreIr。确定性导入：所有 NoteIr.confidence 保持 null。
///
/// 容器按魔数分流（实测 D:\Guitar 真实文件并与 alphaTab GpxFileSystem 权威实现对齐）：
/// - `BCFZ`（GP6）：自定义位级 LZ 压缩——**不是 zlib/deflate**（文件里不存在任何
///   deflate 流）→ 解压得 "BCFS" 扇区镜像（4096 字节/扇区的迷你文件系统）→ score.gpif。
/// - `PK`（GP7）：标准 zip 容器 → score.gpif。
///
/// gpif XML 为扁平 id 引用文档：Tracks/MasterBars/Bars/Voices/Beats/Notes/Rhythms
/// 均为顶层列表，元素间以空格分隔的 id 文本互相引用。gp6 逐引用复用：beat/note
/// 的每个引用都是独立槽位/攻击（alphaTab 对账：月下之恋 770 引用 − 41 个
/// destination="true" 续接端 = 729 攻击）；空拍是显式空引用或 "-1" 占位。
/// 弦号约定：gpif string 0 = 最粗低音弦（6 弦）；alphaTab 的 string 1 同为
/// 最粗（其 tunings 低→高索引），与 GuitarBar IR（string 1 = 最细）相反，
/// 故 IR string = 6 - gp（2026-10-31 修正，原 gp+1 造成谱面与音高双镜像）。
/// v1 只取第一轨（多轨文件其余轨忽略），不做反复（repeat）展开。
ScoreIr parseGpxBytes(Uint8List bytes) {
  if (bytes.length < 4) throw const FormatException('文件太小');
  final magic = String.fromCharCodes(bytes.sublist(0, 4));
  final String xml;
  if (magic == 'BCFZ') {
    final files = readBcfsFiles(decompressGpxImage(bytes));
    final gpif = files['score.gpif'] ??
        [
          for (final e in files.entries)
            if (e.key.toLowerCase().endsWith('.gpif')) e.value,
        ].firstOrNull;
    if (gpif == null) throw const FormatException('GP6 容器中无 score.gpif');
    xml = utf8.decode(gpif);
  } else if (magic.startsWith('PK')) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.findFile('score.gpif') ??
        [
          for (final f in archive.files)
            if (f.isFile && f.name.toLowerCase().endsWith('.gpif')) f,
        ].firstOrNull;
    if (entry == null) throw const FormatException('GP7 容器中无 score.gpif');
    xml = utf8.decode(entry.content);
  } else {
    throw FormatException('不是 .gpx 文件（魔数 $magic）');
  }
  return parseGpif(xml);
}

/// GP6 "BCFZ" 位级 LZ 解压（alphaTab GpxFileSystem.decompress 逐条转写，真实文件实测对齐）。
/// 返回跳过前 4 字节内部头后的 "BCFS" 扇区镜像；位流耗尽即止（alphaTab 同款容错）。
Uint8List decompressGpxImage(Uint8List bytes) {
  final reader = _GpxBitReader(bytes);
  final out = <int>[];
  try {
    if (String.fromCharCodes(reader.readBytes(4)) != 'BCFZ') {
      throw const FormatException('GP6 魔数错误');
    }
    final expectedLength = _readIntLe(reader.readBytes(4));
    while (out.length < expectedLength) {
      if (reader.readBit() == 1) {
        // 回溯引用：wordSize（4 位，MSB first）+ offset/size（各 wordSize 位，LSB first）
        final wordSize = reader.readBits(4);
        final offset = reader.readBitsReversed(wordSize);
        final size = reader.readBitsReversed(wordSize);
        final source = out.length - offset;
        final toRead = offset < size ? offset : size;
        if (source >= 0 && toRead > 0) {
          out.addAll(out.sublist(source, source + toRead));
        }
      } else {
        // 字面量：2 位（LSB first）字节数 + 原始字节
        final size = reader.readBitsReversed(2);
        for (var i = 0; i < size; i++) {
          out.add(reader.readByte());
        }
      }
    }
  } on _EndOfReader {
    // 位流提前耗尽：以已解出的内容继续（真实文件尾部常差 1 字节内）
  }
  if (out.length <= 4) throw const FormatException('GP6 解压结果为空');
  return Uint8List.fromList(out.sublist(4));
}

/// BCFS 扇区镜像 → 文件名 → 内容（alphaTab GpxFileSystem._readUncompressedBlock
/// 逐条转写）。目录项在每扇区头部：type(LE 32)=2、名称（零终止，127 字节上限）、
/// fileSize(LE 32，offset+140)、扇区指针表（offset+148 起，0 结尾）。
/// 扇区循环里目录游标被重定向到最后数据扇区是原实现行为，真实文件实测必须保留。
Map<String, Uint8List> readBcfsFiles(Uint8List image) {
  const sectorSize = 4096;
  final files = <String, Uint8List>{};
  var offset = sectorSize;
  while (offset + 3 < image.length) {
    if (_readIntLeAt(image, offset) == 2) {
      final name = _readCString(image, offset + 4, 127);
      final fileSize = _readIntLeAt(image, offset + 140);
      // 指针表基址在循环前定死（offset 会被下方数据扇区重定向）。
      final dataPointerOffset = offset + 148;
      final data = <int>[];
      var sectorCount = 0;
      while (true) {
        final ptrOffset = dataPointerOffset + 4 * sectorCount;
        if (ptrOffset + 4 > image.length) break; // 指针表越界防护
        final sector = _readIntLeAt(image, ptrOffset);
        sectorCount++;
        if (sector == 0) break;
        final start = sector * sectorSize;
        offset = start;
        if (start + sectorSize > image.length) break; // 数据扇区越界防护
        data.addAll(image.sublist(start, start + sectorSize));
      }
      files[name] = data.length > fileSize
          ? Uint8List.fromList(data.sublist(0, fileSize))
          : Uint8List.fromList(data);
    }
    offset += sectorSize;
  }
  return files;
}

/// gpif XML（GP6/GP7 共用的扁平 id 引用 schema）→ ScoreIr。
ScoreIr parseGpif(String xml) {
  XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on XmlException catch (e) {
    throw FormatException('gpif XML 解析失败: $e');
  }

  final tempo = _readTempo(doc);
  final title = _childText(_section(doc, 'Score'), 'Title')?.trim() ?? '';

  final track = _section(doc, 'Tracks')?.findElements('Track').firstOrNull;
  if (track == null) throw const FormatException('gpif 缺少 Track');
  final trackName = _childText(track, 'Name')?.trim() ?? '';

  var tuning = const <String>[];
  var capo = 0;
  final properties = _child(track, 'Properties');
  if (properties != null) {
    for (final prop in properties.findElements('Property')) {
      switch (prop.getAttribute('name')) {
        case 'Tuning':
          final pitches = _childText(prop, 'Pitches')?.trim() ?? '';
          tuning = [
            for (final s in pitches.split(_ws))
              if (int.tryParse(s) case final midi?) Note(midi).name,
          ];
          break;
        case 'CapoFret':
          capo = int.tryParse(_childText(prop, 'Fret')?.trim() ?? '') ?? 0;
          break;
      }
    }
  }

  // 拍号：第一个 MasterBar 的 Time（"4/4"）
  var timeSignature = '4/4';
  final firstTime = _childText(
      _child(_section(doc, 'MasterBars'), 'MasterBar'), 'Time')?.trim();
  if (firstTime != null && firstTime.isNotEmpty) timeSignature = firstTime;

  final barsById = _indexById(_section(doc, 'Bars'));
  final voicesById = _indexById(_section(doc, 'Voices'));
  final beatsById = _indexById(_section(doc, 'Beats'));
  final notesById = _indexById(_section(doc, 'Notes'));
  final rhythmsById = _indexById(_section(doc, 'Rhythms'));

  final masterBars = _section(doc, 'MasterBars');
  if (masterBars == null) throw const FormatException('gpif 缺少 MasterBars');

  final measures = <MeasureIr>[];
  // tie 起点登记：(弦,品) → 最近一次出音位置（列表引用 + 下标），
  // 续接端的时值跨小节累加回起点。
  final tieOrigins = <(int, int), (List<NoteIr>, int)>{};
  var measureIndex = 0;
  for (final masterBar in masterBars.findElements('MasterBar')) {
    // masterbar 的 Bars 引用按轨序排列；v1 单轨取第一个有效 id（"-1" 为空轨占位）。
    final barId = _refs(_childText(masterBar, 'Bars')).firstOrNull;
    final bar = barId == null ? null : barsById[barId];
    if (bar == null) {
      throw FormatException(
          'gpif 引用了不存在的 bar（小节 $measureIndex, id $barId）');
    }
    final notes = <NoteIr>[];
    for (final voiceId in _refs(_childText(bar, 'Voices'))) {
      final voice = voicesById[voiceId];
      if (voice == null) {
        throw FormatException('gpif 引用了不存在的 voice id $voiceId');
      }
      // 多声部各自从 0 拍起计时（第二声部与主声部同时开始）。
      _readVoice(voice, beatsById, rhythmsById, notesById, tieOrigins, notes);
    }
    measures.add(
        MeasureIr(index: measureIndex++, confidence: 0, failed: false, notes: notes));
  }
  if (measures.isEmpty) throw const FormatException('gpif 无小节');

  return ScoreIr(
    version: 1,
    title: title.isEmpty ? '未命名' : title,
    tempo: tempo,
    timeSignature: timeSignature,
    tuning: tuning,
    capo: capo,
    tracks: [
      TrackIr(name: trackName.isEmpty ? '主旋律' : trackName, measures: measures),
    ],
  );
}

final RegExp _ws = RegExp(r'\s+');

XmlElement? _child(XmlNode? parent, String name) =>
    parent?.findElements(name).firstOrNull;

/// gpif 顶层节（根元素 GPIF 的直接子元素）。
XmlElement? _section(XmlDocument doc, String name) =>
    doc.rootElement.findElements(name).firstOrNull;

String? _childText(XmlNode? parent, String name) =>
    parent?.findElements(name).firstOrNull?.innerText;

/// 空格分隔的 id 引用文本 → id 列表（"-1" 为 GP 的空占位）。
List<String> _refs(String? text) => (text ?? '')
    .trim()
    .split(_ws)
    .where((s) => s.isNotEmpty && s != '-1')
    .toList();

Map<String, XmlElement> _indexById(XmlElement? section) {
  final out = <String, XmlElement>{};
  if (section != null) {
    for (final e in section.childElements) {
      final id = e.getAttribute('id');
      if (id != null) out[id] = e;
    }
  }
  return out;
}

/// tempo：MasterTrack → Automations → Automation[Type=Tempo] → Value（"80 2"，
/// 首 token 为 BPM，次为拍单位分母——v1 只取 BPM）。缺省 90（与 ScoreIr.fromJson 一致）。
double _readTempo(XmlDocument doc) {
  final automations = _child(_section(doc, 'MasterTrack'), 'Automations');
  if (automations != null) {
    for (final auto in automations.findElements('Automation')) {
      if ((_childText(auto, 'Type')?.trim() ?? '') != 'Tempo') continue;
      final value = (_childText(auto, 'Value')?.trim() ?? '').split(_ws).first;
      final bpm = double.tryParse(value);
      if (bpm != null && bpm > 0) return bpm;
    }
  }
  return 90;
}

/// 单声部 → 追加音符到 out。gp6 的 beat/note 引用逐次独立复用：每个引用都是
/// 一次攻击，槽位时位照常推进；空拍是显式空引用（或 "-1" 占位），不是静音。
/// 仅 `<Tie destination="true">` 续接端不出音，其时值累加到 tie 起点
/// （alphaTab untilTieEnd 语义），起点按 (弦,品) 由 [tieOrigins] 定位。
void _readVoice(
  XmlElement voice,
  Map<String, XmlElement> beatsById,
  Map<String, XmlElement> rhythmsById,
  Map<String, XmlElement> notesById,
  Map<(int, int), (List<NoteIr>, int)> tieOrigins,
  List<NoteIr> out,
) {
  var beatPos = 0.0;
  for (final beatId in _refs(_childText(voice, 'Beats'))) {
    final beat = beatsById[beatId];
    if (beat == null) {
      throw FormatException('gpif 引用了不存在的 beat id $beatId');
    }
    final rhythmId = beat.findElements('Rhythm').firstOrNull?.getAttribute('ref');
    final duration = _rhythmBeats(rhythmId == null ? null : rhythmsById[rhythmId]);
    for (final noteId in _refs(_childText(beat, 'Notes'))) {
      final noteEl = notesById[noteId];
      if (noteEl == null) {
        throw FormatException('gpif 引用了不存在的 note id $noteId');
      }
      final (gpString, fret) = _noteProps(noteEl);
      if (gpString == null || fret == null) continue; // 无弦/品信息无法定位（v1 丢弃）
      if (_isTieDestination(noteEl)) {
        final origin = tieOrigins[(gpString, fret)];
        if (origin != null) {
          final (list, idx) = origin;
          list[idx] = list[idx].copyWith(duration: list[idx].duration + duration);
        }
        continue; // tie 续接端：不出音
      }
      out.add(NoteIr(
        beat: beatPos,
        duration: duration,
        // 弦号语义换算（2026-10-31 走查实证修正）：gpif 的 string 0 =
        // 最粗低音弦（6 弦），alphaTab string 1 = tunings[0] = 最粗——而
        // GuitarBar IR string 1 = 最细高音弦，两体系"1"相反，故 IR = 6 - gp。
        // 原公式 gp+1 造成谱面上下镜像 + 播放弦音高 E2↔E4 反转。
        string: 6 - gpString,
        fret: fret,
        technique: _technique(noteEl),
      ));
      tieOrigins[(gpString, fret)] = (out, out.length - 1);
    }
    beatPos += duration;
  }
}

/// gpif 的 tie 用显式属性标两端：origin="true"（起点，出音）、
/// destination="true"（续接端，不出音）。alphaTab 只认 destination === 'true'。
bool _isTieDestination(XmlElement note) =>
    note.findElements('Tie').firstOrNull?.getAttribute('destination')?.toLowerCase() ==
    'true';

/// note 的 String/Fret 属性（GP6 schema：`<Property name="String"><String>N</String>`）。
(int?, int?) _noteProps(XmlElement note) {
  int? gpString;
  int? fret;
  final properties = _child(note, 'Properties');
  if (properties != null) {
    for (final prop in properties.findElements('Property')) {
      switch (prop.getAttribute('name')) {
        case 'String':
          gpString = int.tryParse(_childText(prop, 'String')?.trim() ?? '');
          break;
        case 'Fret':
          fret = int.tryParse(_childText(prop, 'Fret')?.trim() ?? '');
          break;
      }
    }
  }
  return (gpString, fret);
}

/// Rhythm 元素 → 时值（拍）。NoteValue + 附点（×1.5^n）+ 连音（×den/num）。
double _rhythmBeats(XmlElement? rhythm) {
  if (rhythm == null) return 1; // 缺节奏元素按四分音处理
  const values = {
    'Whole': 4.0,
    'Half': 2.0,
    'Quarter': 1.0,
    'Eighth': 0.5,
    '16th': 0.25,
    '32nd': 0.125,
    '64th': 0.0625,
    '128th': 0.03125,
    '256th': 0.015625,
  };
  var beats = values[_childText(rhythm, 'NoteValue')?.trim()] ?? 1;
  final dotCount =
      int.tryParse(_child(rhythm, 'AugmentationDot')?.getAttribute('count') ?? '') ?? 0;
  for (var i = 0; i < dotCount; i++) {
    beats *= 1.5;
  }
  final tuplet = _child(rhythm, 'PrimaryTuplet');
  if (tuplet != null) {
    final num = int.tryParse(tuplet.getAttribute('num') ?? '');
    final den = int.tryParse(tuplet.getAttribute('den') ?? '');
    if (num != null && den != null && num > 0 && den > 0) {
      beats *= den / num;
    }
  }
  return beats;
}

/// v1 技法映射：HarmonicType（非 NoHarmonic）→ H、Muted（Enable）→ x、
/// Slide（Property 的 Flags 非空）→ s。
String? _technique(XmlElement note) {
  final properties = _child(note, 'Properties');
  if (properties != null) {
    for (final prop in properties.findElements('Property')) {
      switch (prop.getAttribute('name')) {
        case 'HarmonicType':
          final t = (_childText(prop, 'HType')?.trim() ?? '').toLowerCase();
          if (t.isNotEmpty && t != 'noharmonic') return 'H';
          break;
        case 'Muted':
          if (prop.findElements('Enable').isNotEmpty) return 'x';
          break;
        case 'Slide':
          if ((_childText(prop, 'Flags')?.trim() ?? '').isNotEmpty) return 's';
          break;
      }
    }
  }
  return null;
}

int _readIntLe(Uint8List b) => b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24);

int _readIntLeAt(Uint8List data, int offset) => _readIntLe(
    Uint8List.sublistView(data, offset, offset + 4));

String _readCString(Uint8List data, int offset, int maxLen) {
  final codes = <int>[];
  for (var i = 0; i < maxLen && offset + i < data.length; i++) {
    final c = data[offset + i];
    if (c == 0) break;
    codes.add(c);
  }
  return String.fromCharCodes(codes);
}

class _EndOfReader implements Exception {
  const _EndOfReader();
}

/// GP6 位流读取器，字节内 MSB first（alphaTab BitReader 转写）。
class _GpxBitReader {
  _GpxBitReader(this._source);

  final Uint8List _source;
  int _bytePos = 0;
  int _currentByte = 0;
  int _bitPos = 8;

  int readBit() {
    if (_bitPos >= 8) {
      if (_bytePos >= _source.length) throw const _EndOfReader();
      _currentByte = _source[_bytePos++];
      _bitPos = 0;
    }
    final value = (_currentByte >> (8 - _bitPos - 1)) & 1;
    _bitPos++;
    return value;
  }

  /// 高位在前。
  int readBits(int count) {
    var bits = 0;
    for (var i = count - 1; i >= 0; i--) {
      bits |= readBit() << i;
    }
    return bits;
  }

  /// 低位在前（GP6 的 offset/size/字面量计数字段）。
  int readBitsReversed(int count) {
    var bits = 0;
    for (var i = 0; i < count; i++) {
      bits |= readBit() << i;
    }
    return bits;
  }

  int readByte() => readBits(8);

  Uint8List readBytes(int count) {
    final out = Uint8List(count);
    for (var i = 0; i < count; i++) {
      out[i] = readByte();
    }
    return out;
  }
}
