import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../music/note.dart';
import 'score_ir.dart';

/// gpx 容器（GP6 "BCFZ" / GP7 zip）→ score.gpif 字节。
/// 容器按魔数分流（实测 D:\Guitar 真实文件并与 alphaTab GpxFileSystem 权威实现对齐）：
/// - `BCFZ`（GP6）：自定义位级 LZ 压缩——**不是 zlib/deflate**（文件里不存在任何
///   deflate 流）→ 解压得 "BCFS" 扇区镜像（4096 字节/扇区的迷你文件系统）→ score.gpif。
/// - `PK`（GP7）：标准 zip 容器 → score.gpif。
Uint8List _gpifBytes(Uint8List bytes) {
  if (bytes.length < 4) throw const FormatException('文件太小');
  final magic = String.fromCharCodes(bytes.sublist(0, 4));
  if (magic == 'BCFZ') {
    final files = readBcfsFiles(decompressGpxImage(bytes));
    final gpif = files['score.gpif'] ??
        [
          for (final e in files.entries)
            if (e.key.toLowerCase().endsWith('.gpif')) e.value,
        ].firstOrNull;
    if (gpif == null) throw const FormatException('GP6 容器中无 score.gpif');
    return gpif;
  }
  if (magic.startsWith('PK')) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.findFile('score.gpif') ??
        [
          for (final f in archive.files)
            if (f.isFile && f.name.toLowerCase().endsWith('.gpif')) f,
        ].firstOrNull;
    if (entry == null) throw const FormatException('GP7 容器中无 score.gpif');
    return entry.content;
  }
  throw FormatException('不是 .gpx 文件（魔数 $magic）');
}

/// GTP（.gpx / .gp）字节 → ScoreIr。确定性导入：所有 NoteIr.confidence 保持 null。
///
/// gpif XML 为扁平 id 引用文档：Tracks/MasterBars/Bars/Voices/Beats/Notes/Rhythms
/// 均为顶层列表，元素间以空格分隔的 id 文本互相引用。gp6 逐引用复用：beat/note
/// 的每个引用都是独立槽位/攻击（alphaTab 对账：月下之恋 770 引用 − 41 个
/// destination="true" 续接端 = 729 攻击）；空拍是显式空引用或 "-1" 占位。
/// 弦号约定：gpif string 0 = 最粗低音弦（6 弦）；alphaTab 的 string 1 同为
/// 最粗（其 tunings 低→高索引），与 GuitarBar IR（string 1 = 最细）相反，
/// 故 IR string = 6 - gp（2026-10-31 修正，原 gp+1 造成谱面与音高双镜像）。
/// v1 只取第一轨（多轨文件其余轨忽略），不做反复（repeat）展开。
ScoreIr parseGpxBytes(Uint8List bytes) =>
    parseGpif(utf8.decode(_gpifBytes(bytes)));

/// 解压 gpx 容器取 score.gpif XML 文本（13.4 源文件查看用）。
/// 坏容器/非 gpx 返回 null（查看页提示），不抛异常。
String? extractGpifXml(Uint8List bytes) {
  try {
    return utf8.decode(_gpifBytes(bytes));
  } catch (_) {
    return null;
  }
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
  // 2026-10-31 走查发现：部分 gpx 的 capo 存在 Beat 的
  // <FreeText>capo:N</FreeText>（GP8 曲中标注，注意大小写）而非
  // Track Properties。属性级优先（精确）；FreeText 级兜底（首个非零值）。
  if (capo == 0) {
    for (final ft in doc.findAllElements('FreeText')) {
      final m =
          RegExp(r'capo[:\s]*(\d+)', caseSensitive: false)
              .firstMatch(ft.innerText);
      if (m != null) {
        final v = int.tryParse(m.group(1)!) ?? 0;
        if (v > 0) {
          capo = v;
          break;
        }
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
    // 反复记号（2026-11-02 走查：GP8 显示反复双竖线，v1 缺失）——
    // MasterBar 的 Repeat 子元素 start/end 属性（实测月下の恋 MB#21
    // start=true、MB#43 end=true）。
    final repeatEl = masterBar.findElements('Repeat').firstOrNull;
    final repeatStart = repeatEl?.getAttribute('start')?.toLowerCase() == 'true';
    final repeatEnd = repeatEl?.getAttribute('end')?.toLowerCase() == 'true';
    final repeatCount =
        repeatEl == null ? 0 : (int.tryParse(repeatEl.getAttribute('count') ?? '') ?? 0);
    // 结尾跳房子（GP8 "1."/"2." 括号）：AlternateEndings（注意是
    // Alternate 不是 Alternative）。GP6 schema 变体实测（月下之恋）：
    // **innerText 直接是编号**（"1" / "2"，可能逗号分隔多值），无 Ending
    // 子元素；GP7 兼容 Ending number 属性形态一并支持。
    final endings = <int>[];
    final ae = masterBar.findElements('AlternateEndings').firstOrNull;
    if (ae != null) {
      final raw = ae.innerText.trim();
      for (final part in raw.split(',')) {
        final v = int.tryParse(part.trim());
        if (v != null) endings.add(v);
      }
      for (final e in ae.findElements('Ending')) {
        final v = int.tryParse((e.getAttribute('number') ?? '').trim());
        if (v != null) endings.add(v);
      }
    }
    final notes = <NoteIr>[];
    for (final voiceId in _refs(_childText(bar, 'Voices'))) {
      final voice = voicesById[voiceId];
      if (voice == null) {
        throw FormatException('gpif 引用了不存在的 voice id $voiceId');
      }
      // 多声部各自从 0 拍起计时（第二声部与主声部同时开始）。
      _readVoice(
          voice, beatsById, rhythmsById, notesById, tieOrigins, capo, notes);
    }
    measures.add(MeasureIr(
        index: measureIndex++,
        confidence: 0,
        failed: false,
        notes: notes,
        repeatStart: repeatStart,
        repeatEnd: repeatEnd,
        repeatCount: repeatCount,
        endings: endings));
  }
  if (measures.isEmpty) throw const FormatException('gpif 无小节');

  return ScoreIr(
    version: 1,
    title: title.isEmpty ? '未命名' : title,
    tempo: tempo,
    timeSignature: timeSignature,
    tuning: tuning,
    capo: capo,
    capoApplied: false, // gpif fret = 绝对品（GP8 同款），发声时加 capo
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
/// [capo]：gpif fret 是绝对品格（从枕位起算，alphaTab 发声不加 capo），
/// 输出统一为夹后品（fret - capo，与 AI 通道谱面印刷数字同语义，
/// 发声由 renderScore 统一 +capo 恰补一次）；tie 配对仍用 gpif 原始品。
void _readVoice(
  XmlElement voice,
  Map<String, XmlElement> beatsById,
  Map<String, XmlElement> rhythmsById,
  Map<String, XmlElement> notesById,
  Map<(int, int), (List<NoteIr>, int)> tieOrigins,
  int capo,
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
    // Beat 级标注（2026-10-31 走查补齐；Like A Star 实测结构）：
    // <Arpeggio>Down</Arpeggio>（Beat 子元素）、Brush/PickStroke
    // （Beat Properties，<Direction>Up|Down</Direction>）。挂该拍全部音。
    final arpeggioEl = beat.findElements('Arpeggio').firstOrNull;
    final arpeggio =
        arpeggioEl == null ? null : _upDown(arpeggioEl.innerText);
    String? brush;
    String? pickStroke;
    final beatProps = _child(beat, 'Properties');
    if (beatProps != null) {
      for (final prop in beatProps.findElements('Property')) {
        switch (prop.getAttribute('name')) {
          case 'Brush':
            brush = _upDown(_childText(prop, 'Direction') ?? '');
            break;
          case 'PickStroke':
            pickStroke = _upDown(_childText(prop, 'Direction') ?? '');
            break;
        }
      }
    }
    for (final noteId in _refs(_childText(beat, 'Notes'))) {
      final noteEl = notesById[noteId];
      if (noteEl == null) {
        throw FormatException('gpif 引用了不存在的 note id $noteId');
      }
      final (gpString, fret) = _noteProps(noteEl);
      if (gpString == null || fret == null) continue; // 无弦/品信息无法定位（v1 丢弃）
      final isTieDest = _isTieDestination(noteEl);
      // 标注解析（2026-10-31 GP8 逆向补齐）：gpif 属性/子元素 → NoteIr 标记。
      final marks = _noteMarks(noteEl);
      if (isTieDest) {
        final origin = tieOrigins[(gpString, fret)];
        if (origin != null) {
          final (list, idx) = origin;
          // 发声时长仍累计回链首（tieEnd 不发声，仅作弧线端点入列表）。
          list[idx] = list[idx].copyWith(duration: list[idx].duration + duration);
        }
        out.add(NoteIr(
          beat: beatPos,
          duration: duration,
          string: 6 - gpString,
          fret: fret,
          technique: marks.technique,
          tieEnd: true,
          letRing: marks.letRing,
          palmMute: marks.palmMute,
          vibrato: marks.vibrato,
          tap: marks.tap,
          ghost: marks.ghost,
          slide: marks.slide,
          arpeggio: arpeggio,
          brush: brush,
          pickStroke: pickStroke,
        ));
        // 链式 tie（dest 再连下一 dest）时 dest 也登记为 origin（实测无此形态，兜底）。
        tieOrigins[(gpString, fret)] = (out, out.length - 1);
        continue;
      }
      final tieOriginAttr = noteEl.findElements('Tie').firstOrNull
              ?.getAttribute('origin')?.toLowerCase() ==
          'true';
      out.add(NoteIr(
        beat: beatPos,
        duration: duration,
        // 弦号语义换算（2026-10-31 走查实证修正）：gpif 的 string 0 =
        // 最粗低音弦（6 弦），alphaTab string 1 = tunings[0] = 最粗——而
        // GuitarBar IR string 1 = 最细高音弦，两体系"1"相反，故 IR = 6 - gp。
        // 原公式 gp+1 造成谱面上下镜像 + 播放弦音高 E2↔E4 反转。
        string: 6 - gpString,
        // fret 保持 gpif 绝对品（2026-10-31 二次修正）：GP8 显示/发声都用
        // 绝对品（不加 capo），gpx 通道不做 -capo 转换——此前减法把全曲
        // 品位错移 capo 度（Like A Star 12 品全变 10）。两条通道语义：
        // gpx = 绝对品（发声 = tuning + fret），AI = 夹后品（发声 =
        // tuning + capo + fret）——renderScore 按 ir.capoApplied 区分。
        fret: fret,
        technique: marks.technique,
        tieStart: tieOriginAttr,
        hopoStart: marks.hopoStart,
        hopoEnd: marks.hopoEnd,
        legatoStart: marks.legatoStart,
        legatoEnd: marks.legatoEnd,
        letRing: marks.letRing,
        palmMute: marks.palmMute,
        vibrato: marks.vibrato,
        tap: marks.tap,
        ghost: marks.ghost,
        slide: marks.slide,
        arpeggio: arpeggio,
        brush: brush,
        pickStroke: pickStroke,
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

/// 标注集合（gpif Note → NoteIr 标记字段），2026-10-31 GP8 GPCore.dll
/// strings 侦察 + 真实文件实测定名：
/// - Properties 属性：HopoOrigin/HopoDestination（击勾弦）、LegatoOrigin/
///   LegatoDestination（连滑音）、PalmMuted（闷音）、Tapped/LeftHandTapped
///   （点弦）、Muted（闷击 x）、HarmonicType（泛音）、Slide Flags（滑音分型）
/// - Note 子元素（非 Property）：LetRing（延音）、Vibrato（揉弦）、
///   AntiAccent（幽灵音，重音的反义）
/// - Slide Flags 位定义（alphaTab GpifReader 转写）：低 4 位 = 出滑，
///   0x01 定滑 shift / 0x02 连滑 legato（高 4 位入滑，v1 只画出滑）
class _NoteMarks {
  String? technique;
  bool hopoStart = false;
  bool hopoEnd = false;
  bool legatoStart = false;
  bool legatoEnd = false;
  bool letRing = false;
  bool palmMute = false;
  bool vibrato = false;
  bool tap = false;
  bool ghost = false;
  String? slide;
}

bool _propEnabled(XmlElement note, String name) => note
    .findAllElements('Property')
    .any((p) => p.getAttribute('name') == name && p.findElements('Enable').isNotEmpty);

/// gpif 方向值（"Up"/"Down"）→ 小写规范形；空/未知返回 null。
String? _upDown(String raw) {
  final t = raw.trim().toLowerCase();
  if (t == 'up') return 'up';
  if (t == 'down') return 'down';
  return null;
}

_NoteMarks _noteMarks(XmlElement note) {
  final m = _NoteMarks();
  m.hopoStart = _propEnabled(note, 'HopoOrigin');
  m.hopoEnd = _propEnabled(note, 'HopoDestination');
  m.legatoStart = _propEnabled(note, 'LegatoOrigin');
  m.legatoEnd = _propEnabled(note, 'LegatoDestination');
  m.palmMute = _propEnabled(note, 'PalmMuted');
  m.tap = _propEnabled(note, 'Tapped') || _propEnabled(note, 'LeftHandTapped');
  // Note 子元素形态（探针实测：LetRing/Vibrato/AntiAccent 直接挂在 Note 下）。
  m.letRing = note.findElements('LetRing').isNotEmpty;
  m.vibrato = note.findElements('Vibrato').isNotEmpty;
  m.ghost = note.findElements('AntiAccent').isNotEmpty;
  final properties = _child(note, 'Properties');
  if (properties != null) {
    for (final prop in properties.findElements('Property')) {
      switch (prop.getAttribute('name')) {
        case 'HarmonicType':
          final t = (_childText(prop, 'HType')?.trim() ?? '').toLowerCase();
          if (t.isNotEmpty && t != 'noharmonic') m.technique = 'H';
          break;
        case 'Muted':
          if (prop.findElements('Enable').isNotEmpty) m.technique = 'x';
          break;
        case 'Slide':
          final flags =
              int.tryParse(_childText(prop, 'Flags')?.trim() ?? '') ?? 0;
          if (flags & 0x02 != 0) {
            m.slide = 'legato';
          } else if (flags & 0x01 != 0) {
            m.slide = 'shift';
          }
          break;
      }
    }
  }
  // 兼容旧技法字母：连滑/击勾由专用弧线表达（渲染按品数判 H/P），
  // gpx 通道不再写 h/p/s 字母；AI 通道的 technique 字段不受影响。
  return m;
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
