import 'dart:typed_data';

import 'package:enough_convert/gbk_base.dart';

import '../music/note.dart';
import 'score_ir.dart';

/// GP5（Guitar Pro 5 二进制格式）→ ScoreIr。
///
/// 逐条移植 PyGuitarPro（D:\workplace\ref\PyGuitarPro）的读取路径：
/// gp5.py readSong（GP5 头部结构）→ gp3/gp4.py 的 measure header / track /
/// measure / beat / note / effects 字节级逻辑。字段顺序严格对照源码，
/// 不做任何字节跳过（chord/lyrics/页面设置等虽然丢弃，但字节必须读齐）。
///
/// v1 范围（与 gtp_parser.dart 的 gpif 通道对齐）：
/// - 只取第一轨（其余轨读齐字节后丢弃）；capoApplied=false，confidence=null
/// - 弦号：gp5 字符串编号 1..stringCount，1 = 最高音（最细）弦
///   （gp3.py readTracks：tuning 表高→低存储，GuitarString(i+1)）——与 IR
///   "string 1 = 最细高音弦" 同制，直接恒等映射（注意不是 6-gp，那是
///   gpif 0 基弦号的换算）
/// - 调弦：7 × I32（高→低），取非 0 弦翻转成 IR 低→高
/// - 反复：header flags 0x04 = repeatStart、0x08 = repeatEnd（I8 = 总遍数，
///   PyGuitarPro RepeatGroup 以 repeatClose=raw-1>0 判闭合）、0x10 =
///   AlternateEndings 位掩码（GP5 直接存 bitmask，bit i = 第 i+1 结尾）
/// - 技法：tie（note type 2）→ tieStart/tieEnd（时值累计回链首）；
///   hammer 位 → hopoEnd + 回溯补 hopoStart（GP5 只标续接端）；
///   slide 位掩码 0x01 shift / 0x02 legato；泛音（1-5 型）→ 'H'；
///   dead note（type 3）→ 'x'；letRing/palmMute/vibrato（note+beat 两级）/
///   ghost/accent（0x40 重音、0x02 重重音）/staccato/trill/grace/
///   tremolo picking/fade in（beat 0x10）；beat stroke → brush、
///   pickStroke 位 → pickStroke；note 力度 dyn → velocity/dynamicMark
/// - 忽略（v1）：triplet feel、bend 曲线、曲中 mixTableChange（tempo 取全曲
///   首值）、Directions/Segno、slap/pop、拍号中途变更加束、lineBreak、
///   chord 图、歌词、RSE 全部参数
ScoreIr parseGp5Bytes(Uint8List bytes) => _Gp5Reader(bytes).parse();

/// GBK 解码：GP5 元数据用系统本地码页（中文环境 = GBK/936，如 "Distance"
/// 的 music 字段 CE E9 BB DB）。gbk_codec 0.4.0 的 SDK 约束 <3.0.0 无法在
/// Dart 3 解析，改用 enough_convert 的 GbkCodec（fast_gbk 分支）。
const GbkCodec _gbk = GbkCodec(allowInvalid: true);

/// 单条 note 的回溯登记（tie 续接 / hopo 起点补标用）：
/// 列表引用 + 下标 + 已解析品值（tie 链上 dest 的品 = 链首品）。
class _NoteRef {
  _NoteRef(this.list, this.index, this.value);
  final List<NoteIr> list;
  final int index;
  final int value;
}

/// 音轨头（只留 IR 需要的字段）。
class _Track {
  _Track(this.name, this.tunings, this.capo);
  final String name;
  final List<int> tunings; // MIDI，高→低（与文件存储一致），长度 = stringCount
  final int capo;
}

/// 小节头（跨音轨共享）。
class _MeasureHeader {
  _MeasureHeader(this.numerator, this.denominator);
  final int numerator;
  final int denominator;
  bool isRepeatOpen = false;
  bool isRepeatClose = false;
  int repeatCount = 0; // 0x08 的 I8 原值 = 总遍数（raw-1>0 才算闭合线）
  int repeatAlternative = 0; // 0x10 位掩码（GP5 直存）
}

/// GP5 逐字节读取器（PyGuitarPro GP5File.readSong 的 Dart 直译）。
class _Gp5Reader {
  _Gp5Reader(this._data);

  final Uint8List _data;
  int _pos = 0;
  int _minor = 1; // 版本次号：0 = v5.0，>0 = v5.1+（RSE 字段有无的开关）
  bool get _isV50 => _minor == 0;

  // —— 字节原语（io.py）——

  Never _eof() =>
      throw FormatException('GP5 文件截断或格式错误（offset $_pos）');

  void _ensure(int n) {
    if (_pos + n > _data.length) _eof();
  }

  int _u8() {
    if (_pos >= _data.length) _eof();
    return _data[_pos++];
  }

  int _i8() {
    final b = _u8();
    return b & 0x80 != 0 ? b - 0x100 : b;
  }

  int _i16() {
    _ensure(2);
    final v = _data[_pos] | (_data[_pos + 1] << 8);
    _pos += 2;
    return v & 0x8000 != 0 ? v - 0x10000 : v;
  }

  int _i32() {
    _ensure(4);
    final v = _data[_pos] |
        (_data[_pos + 1] << 8) |
        (_data[_pos + 2] << 16) |
        (_data[_pos + 3] << 24);
    _pos += 4;
    return v & 0x80000000 != 0 ? v - 0x100000000 : v;
  }

  double _f64() {
    _ensure(8);
    final v = ByteData.sublistView(_data, _pos, _pos + 8)
        .getFloat64(0, Endian.little);
    _pos += 8;
    return v;
  }

  void _skip(int n) {
    _ensure(n);
    _pos += n;
  }

  /// byte-size-string：1 字节内容长度 + count 字节缓冲（截到内容长度）。
  String _byteSizeString(int count) {
    final size = _u8();
    _ensure(count);
    final raw = Uint8List.sublistView(_data, _pos, _pos + count);
    _pos += count;
    final take = size < raw.length ? size : raw.length;
    return _gbk.decode(raw.sublist(0, take));
  }

  /// int-size-string：I32 长度 + 内容。
  String _intSizeString() {
    final count = _i32();
    _ensure(count < 0 ? 0 : count);
    final raw = Uint8List.sublistView(_data, _pos, _pos + (count < 0 ? 0 : count));
    _pos += count < 0 ? 0 : count;
    return _gbk.decode(raw);
  }

  /// int-byte-size-string：I32（= 内容长度+1）+ byte-size-string。
  String _intByteSizeString() {
    final count = _i32();
    return _byteSizeString(count < 1 ? 0 : count - 1);
  }

  // —— 顶层（gp5.py readSong）——

  late final List<_MeasureHeader> _headers;
  late final List<_Track> _tracks;

  /// tie 续接 / hopo 起点回溯登记：每声部一张 弦号 → 最近 note 表。
  late final List<Map<int, _NoteRef>> _voiceRefs;

  ScoreIr parse() {
    final version = _byteSizeString(30);
    final m = RegExp(r'5\.(\d)').firstMatch(version);
    if (m == null) {
      throw FormatException(
          '不支持的 Guitar Pro 版本 "$version"（v1 仅支持 GP5）');
    }
    _minor = int.parse(m.group(1)!);

    if (version.startsWith('CLIPBOARD')) {
      _skip(28); // GP4 clipboard 4×I32 + GP5 startBeat/stopBeat/subBarCopy 3×I32
    }

    // readInfo：9 个 IntByteSizeString + notice（title 去首尾空白，与
    // gtp_parser 的 Title 处理一致——真值文件标题常带尾随空格）
    final title = _intByteSizeString().trim();
    for (var i = 0; i < 8; i++) {
      _intByteSizeString(); // subtitle, artist, album, words, music,
      // copyright, tab, instructions
    }
    final noticeCount = _i32();
    for (var i = 0; i < noticeCount; i++) {
      _intByteSizeString();
    }

    // readLyrics（gp4）：trackChoice + 5 行（startMeasure + int-size-string）
    _i32();
    for (var i = 0; i < 5; i++) {
      _i32();
      _intSizeString();
    }

    // RSE master effect（v5.1+）：volume I32 + reserved I32 + 11 段 EQ
    if (!_isV50) {
      _i32();
      _i32();
      _skip(11);
    }

    // page setup：页尺寸 2 I32 + 边距 4 I32 + 比例 1 I32 + 页眉脚 I16
    // + 10 个 IntByteSizeString（实测 Distance：173 起 210/297/10/10/15/10/
    // 100/0x01FF，字符串 203 起 "%TITLE%"）
    _skip(30);
    for (var i = 0; i < 10; i++) {
      _intByteSizeString();
    }

    _intByteSizeString(); // tempoName
    final tempo = _i32();
    if (!_isV50) _u8(); // hideTempo
    _i8(); // key
    _i32(); // octave

    _skip(768); // 64 个 MIDI 通道 ×（I32 + 6 I8 + 2 空字节）
    _skip(38); // directions：19 个 I16
    _i32(); // master reverb

    final measureCount = _i32();
    final trackCount = _i32();
    if (measureCount < 0 || trackCount < 1) {
      throw const FormatException('GP5 小节/音轨数非法');
    }

    _headers = _readMeasureHeaders(measureCount);
    _tracks = _readTracks(trackCount);

    _voiceRefs = [for (var v = 0; v < 2; v++) <int, _NoteRef>{}];
    final measures = <MeasureIr>[];
    for (var h = 0; h < _headers.length; h++) {
      // 小节按 头 × 轨 序读（gp3.py readMeasures）；第一轨进 IR。
      final notes = <NoteIr>[];
      for (var t = 0; t < _tracks.length; t++) {
        _readMeasure(t, notes);
      }
      final hd = _headers[h];
      final endings = <int>[
        for (var bit = 0; bit < 8; bit++)
          if (hd.repeatAlternative & (1 << bit) != 0) bit + 1,
      ];
      measures.add(MeasureIr(
        index: h,
        confidence: 0,
        failed: false,
        notes: notes,
        repeatStart: hd.isRepeatOpen,
        repeatEnd: hd.isRepeatClose,
        repeatCount: hd.repeatCount,
        endings: endings,
      ));
    }
    if (measures.isEmpty) throw const FormatException('GP5 无小节');

    final track = _tracks.first;
    final tuning = <String>[
      for (final midi in track.tunings.reversed)
        if (midi > 0) Note(midi).name,
    ];

    return ScoreIr(
      version: 1,
      title: title.isEmpty ? '未命名' : title,
      tempo: tempo > 0 ? tempo.toDouble() : 90,
      timeSignature:
          '${_headers.first.numerator}/${_headers.first.denominator}',
      tuning: tuning,
      capo: track.capo,
      capoApplied: false, // fret = 绝对品，发声时由渲染器 +capo
      tracks: [
        TrackIr(
            name: track.name.isEmpty ? '主旋律' : track.name, measures: measures),
      ],
    );
  }

  // —— 小节头（gp5.py readMeasureHeader）——

  List<_MeasureHeader> _readMeasureHeaders(int measureCount) {
    final headers = <_MeasureHeader>[];
    _MeasureHeader? prev;
    for (var number = 1; number <= measureCount; number++) {
      if (prev != null) _skip(1); // 固定空字节
      final flags = _u8();
      final h = _MeasureHeader(
        (flags & 0x01) != 0 ? _i8() : prev?.numerator ?? 4,
        (flags & 0x02) != 0 ? _i8() : prev?.denominator ?? 4,
      );
      h.isRepeatOpen = flags & 0x04 != 0;
      if (flags & 0x08 != 0) {
        final raw = _i8();
        // PyGuitarPro：repeatClose = raw - 1，RepeatGroup 以 >0 判闭合 →
        // raw = 总遍数（2 = 弹两遍）。
        h.isRepeatClose = raw > 1;
        h.repeatCount = raw > 0 ? raw : 0;
      }
      if (flags & 0x20 != 0) {
        _intByteSizeString(); // marker 名
        _skip(4); // marker 颜色（RGB + 空字节）
      }
      if (flags & 0x40 != 0) {
        _i8(); // key signature root
        _i8(); // key signature type
      }
      if (flags & 0x10 != 0) {
        h.repeatAlternative = _u8(); // GP5 直存位掩码（GP3 才做数值换算）
      }
      if (flags & 0x03 != 0) {
        _skip(4); // 拍号 beaming
      }
      if (flags & 0x10 == 0) {
        _skip(1); // 固定空字节
      }
      _u8(); // triplet feel（v1 忽略）
      headers.add(h);
      prev = h;
    }
    return headers;
  }

  // —— 音轨（gp5.py readTrack / readRSEInstrument）——

  List<_Track> _readTracks(int trackCount) {
    final tracks = <_Track>[];
    for (var number = 1; number <= trackCount; number++) {
      if (number == 1 || _isV50) _skip(1); // 固定空字节
      _u8(); // flags1（drums/12弦/banjo/可见/solo/mute/RSE/调弦显示）
      final name = _byteSizeString(40);
      final stringCount = _i32();
      final tunings = <int>[];
      for (var i = 0; i < 7; i++) {
        final tuning = _i32();
        if (stringCount > i) tunings.add(tuning); // 高→低
      }
      _i32(); // port
      _i32(); // channel
      _i32(); // effectChannel
      _i32(); // fretCount
      final capo = _i32(); // offset = capo 品位（0 = 无）
      _skip(4); // color
      _i16(); // flags2（显示设置）
      _skip(3); // autoAccentuation / bank / humanize
      _skip(4); // clefTranspose
      _skip(4); // clefTransposeSecondary
      _skip(4); // unknown（通常 -1 或 100）
      _skip(12); // unknown
      _i32(); // RSE instrument
      _i32(); // RSE unknown
      _i32(); // RSE soundBank
      if (_isV50) {
        _i16();
        _skip(1);
      } else {
        _i32(); // RSE effectNumber
      }
      if (!_isV50) {
        _skip(4); // 3 段轨 EQ（4 I8）
        _intByteSizeString(); // RSE effect 名
        _intByteSizeString(); // RSE effect 类别
      }
      tracks.add(_Track(name, tunings, capo));
    }
    _skip(_isV50 ? 2 : 1); // 全部音轨后的固定空字节
    return tracks;
  }

  // —— 小节内容（gp5.py readMeasure → gp3.py readVoice/readBeat）——

  void _readMeasure(int trackIdx, List<NoteIr> out) {
    for (var voice = 0; voice < 2; voice++) {
      var beatPos = 0.0;
      final beatCount = _i32();
      for (var b = 0; b < beatCount; b++) {
        beatPos += _readBeat(trackIdx, voice, beatPos, out);
      }
    }
    // lineBreak（gp5.py 用 readU8(default=0)——实测真值文件可能省略最后一个
    // 字节，EOF 时按 0 = 不换行处理）
    if (_pos < _data.length) _pos++;
  }

  /// 读一拍，返回推进的时值（拍；空拍 = 0）。
  double _readBeat(int trackIdx, int voice, double beatPos, List<NoteIr> out) {
    final flags = _u8();
    var status = 1; // normal
    if (flags & 0x40 != 0) status = _u8(); // 0 = empty, 1 = normal, 2 = rest

    // 时值：I8 档位 → 1 << (i+2) 音符值（4 = 四分）；附点 ×1.5；连音 ×times/enters
    final durByte = _i8();
    final noteValue = durByte >= -2 && durByte <= 6 ? 1 << (durByte + 2) : 4;
    var beats = 4.0 / noteValue;
    if (flags & 0x01 != 0) beats *= 1.5; // dotted
    if (flags & 0x20 != 0) {
      final tuplet = _i32();
      final ratio = _tupletRatio(tuplet);
      if (ratio != null) beats *= ratio;
    }

    // 拍级效果（gp4.py readBeatEffects，GP5 沿用两字节 flags 版本）
    var wideVibrato = false;
    String? brush;
    String? pickStroke;
    var fadeIn = false;
    if (flags & 0x02 != 0) _readChord();
    if (flags & 0x04 != 0) _intByteSizeString(); // text
    if (flags & 0x08 != 0) {
      final f1 = _i8();
      final f2 = _i8();
      wideVibrato = f1 & 0x02 != 0;
      fadeIn = f1 & 0x10 != 0;
      if (f1 & 0x20 != 0) _i8(); // slapEffect（tap/slap/pop）
      if (f2 & 0x04 != 0) _readBend(); // tremolo bar
      if (f1 & 0x40 != 0) {
        // GP5 存储相对 GP3 对调：字节 1 = 上扫、字节 2 = 下扫
        //（gp5 readBeatStroke = gp3 读取后 swapDirection）
        final a = _i8();
        final b = _i8();
        brush = a > 0 ? 'up' : (b > 0 ? 'down' : null);
      }
      if (f2 & 0x02 != 0) {
        final d = _i8(); // BeatStrokeDirection：1 = up, 2 = down
        pickStroke = d == 1 ? 'up' : (d == 2 ? 'down' : null);
      }
    }
    if (flags & 0x10 != 0) _readMixTableChange();

    // 音符（gp3.py readNotes：弦号 1..stringCount 顺序，bit 7-string）
    final stringFlags = _u8();
    final tunings = _tracks[trackIdx].tunings;
    for (var si = 0; si < tunings.length; si++) {
      final stringNumber = si + 1;
      if (stringFlags & (1 << (7 - stringNumber)) != 0) {
        _readNote(
          trackIdx,
          voice,
          stringNumber,
          beatPos: beatPos,
          beats: beats,
          status: status,
          out: out,
          wideVibrato: wideVibrato,
          fadeIn: fadeIn,
          brush: brush,
          pickStroke: pickStroke,
        );
      }
    }

    // GP5 拍级第二段 flags（I16）+ 可选 break secondary beams
    final flags2 = _i16();
    if (flags2 & 0x0800 != 0) _u8();

    return status == 0 ? 0.0 : beats;
  }

  /// 连音档位 → times/enters（gp3.py readDuration 的映射表）。
  double? _tupletRatio(int tuplet) {
    const ratios = {
      3: 2 / 3,
      5: 4 / 5,
      6: 4 / 6,
      7: 4 / 7,
      9: 8 / 9,
      10: 8 / 10,
      11: 8 / 11,
      12: 8 / 12,
      13: 8 / 13,
    };
    return ratios[tuplet];
  }

  // —— 音符（gp5.py readNote → gp4.py readNoteEffects）——

  void _readNote(
    int trackIdx,
    int voice,
    int stringNumber, {
    required double beatPos,
    required double beats,
    required int status,
    required List<NoteIr> out,
    required bool wideVibrato,
    required bool fadeIn,
    required String? brush,
    required String? pickStroke,
  }) {
    final flags = _u8();
    final heavyAccent = flags & 0x02 != 0;
    final ghost = flags & 0x04 != 0;
    final accent = flags & 0x40 != 0;
    var noteType = 0; // rest（未读 type 字节时的缺省，实际谱面恒走 0x20 分支）
    if (flags & 0x20 != 0) noteType = _u8(); // 1 = normal, 2 = tie, 3 = dead
    var dyn = 0;
    if (flags & 0x10 != 0) dyn = _i8(); // 力度档 1..8
    var fret = 0;
    if (flags & 0x20 != 0) {
      fret = _i8();
      if (noteType == 2) fret = _tiedValue(trackIdx, voice, stringNumber);
      if (fret < 0 || fret >= 100) fret = 0; // gp5 的取值夹取
    }
    if (flags & 0x80 != 0) {
      _i8(); // leftHandFinger
      _i8(); // rightHandFinger
    }
    if (flags & 0x01 != 0) _f64(); // durationPercent
    _u8(); // flags2（swapAccidentals）

    // note effects（gp4.py readNoteEffects：两字节 flags）
    var hammer = false;
    var letRing = false;
    var staccato = false;
    var palmMute = false;
    var noteVibrato = false;
    var tremoloPicking = false;
    var harmonic = false;
    var trill = false;
    var grace = false;
    String? slide;
    if (flags & 0x08 != 0) {
      final f1 = _i8();
      final f2 = _i8();
      hammer = f1 & 0x02 != 0;
      letRing = f1 & 0x08 != 0;
      grace = f1 & 0x10 != 0;
      staccato = f2 & 0x01 != 0;
      palmMute = f2 & 0x02 != 0;
      tremoloPicking = f2 & 0x04 != 0;
      trill = f2 & 0x20 != 0;
      noteVibrato = f2 & 0x40 != 0;
      if (f1 & 0x01 != 0) _readBend();
      if (f1 & 0x10 != 0) _readGrace();
      if (f2 & 0x04 != 0) _i8(); // tremolo picking 速度档
      if (f2 & 0x08 != 0) slide = _readSlides();
      if (f2 & 0x10 != 0) {
        harmonic = true;
        _readHarmonic();
      }
      if (f2 & 0x20 != 0) {
        _i8(); // trill fret
        _i8(); // trill period
      }
    }

    // 非第一轨：字节读齐即可，不入 IR。
    final refs = trackIdx == 0 ? _voiceRefs[voice] : null;
    if (refs == null) return;

    // 力度 → MIDI velocity + 力度记号（unpackVelocity = 15 + 16*dyn - 16）。
    int? velocity;
    String? dynamicMark;
    if (flags & 0x10 != 0) {
      velocity = dyn * 16 - 1;
      if (dyn >= 1 && dyn <= 8) {
        dynamicMark = const ['ppp', 'pp', 'p', 'mp', 'mf', 'f', 'ff', 'fff']
            [dyn - 1];
      }
    }

    String? technique;
    if (noteType == 3) {
      technique = 'x'; // dead note
    } else if (harmonic) {
      technique = 'H'; // 泛音（natural/artificial/tapped/pinch/semi）
    }

    final isTie = noteType == 2;
    final prev = refs[stringNumber];
    if (isTie && prev != null) {
      // 续接端不出音，时值累计回链首（与 gtp_parser _readVoice 同语义）。
      // 经 prev.list 定位（tie 常跨小节，登记的是当时所在列表）。
      prev.list[prev.index] = prev.list[prev.index]
          .copyWith(duration: prev.list[prev.index].duration + beats, tieStart: true);
    }
    if (hammer && prev != null) {
      // GP5 只标击勾续接端；起点回溯补标（渲染按两端的品数走向画 H/P）。
      prev.list[prev.index] = prev.list[prev.index].copyWith(hopoStart: true);
    }

    out.add(NoteIr(
      beat: beatPos,
      duration: beats,
      string: stringNumber, // gp5 弦号 1 = 最细 = IR 1，恒等映射
      fret: fret,
      technique: technique,
      tieEnd: isTie,
      hopoEnd: hammer,
      letRing: letRing,
      palmMute: palmMute,
      vibrato: noteVibrato || wideVibrato,
      ghost: ghost,
      slide: slide,
      brush: brush,
      pickStroke: pickStroke,
      trill: trill,
      accent: accent || heavyAccent,
      staccato: staccato,
      grace: grace,
      dynamicMark: dynamicMark,
      fadding: fadeIn ? 'in' : null,
      tremolo: tremoloPicking,
      velocity: velocity,
    ));
    // 空拍上的残缺音不入登记（getTiedNoteValue 只搜非空拍）。
    if (status != 0) {
      refs[stringNumber] = _NoteRef(out, out.length - 1, fret);
    }
  }

  /// tie 续接端的品值：同弦最近一次出音（gp3.py getTiedNoteValue 的
  /// 登记表等价实现——登记表按读取顺序更新，回溯即"同声部同弦最近音"）。
  int _tiedValue(int trackIdx, int voice, int stringNumber) {
    if (trackIdx != 0) return 0;
    return _voiceRefs[voice][stringNumber]?.value ?? 0;
  }

  // —— 效果子块 ——

  /// bend / tremolo bar（gp3.py readBend）：type I8 + value I32 + 点数 I32
  /// + 每点（I32 位置 + I32 值 + 1 字节 vibrato）。曲线本身 v1 不入 IR。
  void _readBend() {
    _i8();
    _i32();
    final points = _i32();
    for (var i = 0; i < points; i++) {
      _i32();
      _i32();
      _u8();
    }
  }

  /// grace note（gp5.py readGrace）：fret + 力度 + transition + duration
  /// + flags，各 1 字节。
  void _readGrace() {
    _u8();
    _u8();
    _u8();
    _u8();
    _u8();
  }

  /// slide（gp5.py readSlides）：位掩码 0x01 shift / 0x02 legato /
  /// 0x04 出下 / 0x08 出上 / 0x10 入下 / 0x20 入上。出/入滑 v1 不映射
  /// （IR 的 slide 语义是连接两音的滑线）。
  String? _readSlides() {
    final bits = _u8();
    if (bits & 0x02 != 0) return 'legato';
    if (bits & 0x01 != 0) return 'shift';
    return null;
  }

  /// 泛音（gp5.py readHarmonic）：1 natural / 2 artificial（+3 字节）/
  /// 3 tapped（+1 字节）/ 4 pinch / 5 semi。类型 v1 统一映射 'H'。
  void _readHarmonic() {
    final type = _i8();
    if (type == 2) {
      _u8(); // semitone
      _i8(); // accidental
      _u8(); // octave
    } else if (type == 3) {
      _u8(); // fret
    }
  }

  /// 和弦图（gp3.py readChord → gp4.py readNewChord）。v1 丢弃，字节读齐。
  void _readChord() {
    final newFormat = _u8() != 0;
    if (!newFormat) {
      _intByteSizeString(); // 名
      final firstFret = _i32();
      if (firstFret != 0) {
        for (var i = 0; i < 6; i++) {
          _i32(); // 各弦品
        }
      }
      return;
    }
    _u8(); // sharp
    _skip(3);
    _u8(); // root
    _u8(); // type
    _u8(); // extension
    _i32(); // bass
    _i32(); // tonality
    _u8(); // add
    _byteSizeString(22); // 名
    _u8(); // fifth
    _u8(); // ninth
    _u8(); // eleventh
    _i32(); // firstFret
    for (var i = 0; i < 7; i++) {
      _i32(); // 各弦品
    }
    _u8(); // barres 数
    _skip(15); // barre frets/starts/ends 各 5 字节（U8）
    for (var i = 0; i < 7; i++) {
      _u8(); // omissions
    }
    _skip(1);
    for (var i = 0; i < 7; i++) {
      _i8(); // fingerings
    }
    _u8(); // show
  }

  /// 曲中参数变化（gp5.py readMixTableChange 全链）。v1 丢弃，字节读齐：
  /// 值（含内嵌 RSE 乐器）→ 时长 → flags → wah → RSE effect 字符串。
  void _readMixTableChange() {
    _i8(); // instrument
    _i32(); // RSE instrument
    _i32(); // RSE unknown
    _i32(); // RSE soundBank
    if (_isV50) {
      _i16();
      _skip(1);
    } else {
      _i32(); // RSE effectNumber
    }
    if (_isV50) _skip(1);
    var changed = 0;
    for (var i = 0; i < 6; i++) {
      if (_i8() >= 0) changed |= 1 << i; // volume/balance/chorus/reverb/phaser/tremolo
    }
    _intByteSizeString(); // tempoName
    final tempo = _i32();
    for (var i = 0; i < 6; i++) {
      if (changed & (1 << i) != 0) _i8(); // 各项时长
    }
    if (tempo >= 0) {
      _i8(); // tempo 时长
      if (!_isV50) _u8(); // hideTempo
    }
    _i8(); // flags（allTracks 位 + useRSE + wah 显示）
    _i8(); // wah
    if (!_isV50) {
      _intByteSizeString(); // RSE effect 名
      _intByteSizeString(); // RSE effect 类别
    }
  }
}
