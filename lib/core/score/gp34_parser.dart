import 'dart:typed_data';

import 'package:enough_convert/gbk_base.dart';

import '../music/note.dart';
import 'score_ir.dart';

/// GP3 / GP4（Guitar Pro 3/4 二进制格式）→ ScoreIr。
///
/// 逐字节移植 PyGuitarPro（gp3.py / gp4.py），规格依据
/// tasks/gp34_spec.md（2026-11-13 子代理从 site-packages 源码提取）。
/// 移植口径：**GP4 = GP3 + 头部 3 处插入（clipboard/lyrics/octave）+
/// chord/beatEffects/noteEffects/mixTableChange 四个差异段**，其余共用。
///
/// 与 GP5（gp5_parser.dart）的关键防混用差异（spec §6.3）：
/// - 小节头：无 skip1/beams/tripletFeel 尾字节；repeatClose **不减 1**；
///   repeatAlternative 存"第 n 个结尾"需 `(1<<raw)-1` 换算；0x10 在
///   0x20/0x40 **之前**读（GP5 在后）。
/// - 音轨：恒 98B 截到 color（GP5 尾部 flags2/RSE 全无）。
/// - 小节：单 voice 无 lineBreak（GP5 是 2 voice + lineBreak）。
/// - 拍：无末尾 flags2 I16（GP5 有）。
/// - 音符：无 durationPercent F64 / flags2 U8（GP5 有）；GP3 效果是
///   1 字节版（slide 无数据、无 staccato/palmMute/harmonic/trill/
///   vibrato note 级）。
/// - grace：4 字节版（GP5 是 5 字节）。
///
/// v1 输出口径与 gp5_parser 一致：只取第一轨、capoApplied=false、
/// 弦号 1 = 最细高音弦（gp3 readTracks tuning 高→低 + string(1)=最高）。
ScoreIr parseGp34Bytes(Uint8List bytes) => _Gp34Reader(bytes).parse();

const GbkCodec _gbk = GbkCodec(allowInvalid: true);

class _NoteRef {
  _NoteRef(this.list, this.index, this.value);
  final List<NoteIr> list;
  final int index;
  final int value;
}

class _Track {
  _Track(this.name, this.tunings, this.capo);
  final String name;
  final List<int> tunings; // MIDI，高→低（文件存储序）
  final int capo;
}

class _MeasureHeader {
  _MeasureHeader(this.numerator, this.denominator);
  final int numerator;
  final int denominator;
  bool isRepeatOpen = false;
  bool isRepeatClose = false;
  int repeatCount = 0; // 产品语义 = 总遍数（GP3/GP4 raw 是重复次数，+1 换算）
  int repeatAlternative = 0; // 位掩码（GP3/GP4 从"第 n 个结尾"换算）
}

/// GP3/GP4 逐字节读取器（gp3.py readSong 的 Dart 直译 + GP4 差异分支）。
class _Gp34Reader {
  _Gp34Reader(this._data);

  final Uint8List _data;
  bool _isV4 = false; // parse() 从版本串判定

  /// 本拍是否合成了装饰音（readNote 置位、_readBeat 收尾回写 tieEnd
  /// 数字锚后清零——拍内音序 1→6 弦，装饰音可能先于同拍 tieE 解析）。
  bool _beatHasDeco = false;
  int _pos = 0;

  Never _eof() =>
      throw FormatException('GP3/GP4 文件截断或格式错误（offset $_pos）');

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

  int _i32() {
    _ensure(4);
    final v = _data[_pos] |
        (_data[_pos + 1] << 8) |
        (_data[_pos + 2] << 16) |
        (_data[_pos + 3] << 24);
    _pos += 4;
    return v & 0x80000000 != 0 ? v - 0x100000000 : v;
  }

  void _skip(int n) {
    _ensure(n);
    _pos += n;
  }

  String _byteSizeString(int count) {
    final size = _u8();
    _ensure(count);
    final raw = Uint8List.sublistView(_data, _pos, _pos + count);
    _pos += count;
    final take = size < raw.length ? size : raw.length;
    return _gbk.decode(raw.sublist(0, take));
  }

  String _intSizeString() {
    final count = _i32();
    _ensure(count < 0 ? 0 : count);
    final raw =
        Uint8List.sublistView(_data, _pos, _pos + (count < 0 ? 0 : count));
    _pos += count < 0 ? 0 : count;
    return _gbk.decode(raw);
  }

  String _intByteSizeString() {
    final count = _i32();
    return _byteSizeString(count < 1 ? 0 : count - 1);
  }

  late final List<_MeasureHeader> _headers;
  late final List<_Track> _tracks;
  // GP3/GP4 单 voice：一张 弦号 → 最近 note 登记表（tie/hopo 回溯用）。
  late final Map<int, _NoteRef> _refs;

  ScoreIr parse() {
    final version = _byteSizeString(30);
    // GP4 剪贴板版本串 'CLIPBOARD GUITAR PRO 4.0 [c6]' 不含 v4./L4.
    //（pyguitarpro io.py:17）——前缀也计入判定，防剪贴板 tmp 文件被误拒。
    final isClipboard = version.startsWith('CLIPBOARD');
    final isV3 = version.contains('v3.');
    final isV4 =
        isClipboard || version.contains('v4.') || version.contains('L4.');
    if (!isV3 && !isV4) {
      throw FormatException(
          '不支持的 Guitar Pro 版本 "$version"（本解析器仅支持 GP3/GP4）');
    }
    _isV4 = isV4;

    // GP4 clipboard 段（版本串 CLIPBOARD 前缀时 4×I32，普通文件无）。
    if (isClipboard) {
      _skip(16);
    }

    // readInfo（gp3.py:64）：8 个 IntByteSizeString + notice（GP5 才是 9 个）。
    final title = _intByteSizeString().trim();
    for (var i = 0; i < 7; i++) {
      _intByteSizeString(); // subtitle..instructions（words 兼 music）
    }
    final noticeCount = _i32();
    for (var i = 0; i < noticeCount; i++) {
      _intByteSizeString();
    }

    // triplet feel（v1 忽略；GP3/GP4 是 1 字节 bool，GP5 在每小节头尾部）。
    _u8();

    // GP4 readLyrics（gp4.py:82）：I32 trackChoice + 5×(I32 + IntSizeString)。
    if (isV4) {
      _i32();
      for (var i = 0; i < 5; i++) {
        _i32();
        _intSizeString();
      }
    }

    final tempo = _i32();
    _i32(); // key（v1 忽略调号）
    if (isV4) _i8(); // octave（GP4 新增保留字段）

    _skip(768); // 64 个 MIDI 通道 × 12B（GP3/GP4/GP5 三代共用段）

    final measureCount = _i32();
    final trackCount = _i32();
    if (measureCount < 0 || trackCount < 1) {
      throw const FormatException('GP3/GP4 小节/音轨数非法');
    }

    _headers = _readMeasureHeaders(measureCount);
    _tracks = _readTracks(trackCount);

    // 轨选择：跳过调弦全 0 的哑轨（158 曲库实测部分 gp3 轨 1 是
    // 转换工具产出的全 0 弦哑轨，PyGuitarPro 同样读出全 0）。
    final trackIdx = _tracks.indexWhere((t) => t.tunings.any((m) => m > 0));
    final selected = trackIdx >= 0 ? trackIdx : 0;

    _refs = <int, _NoteRef>{};
    final measures = <MeasureIr>[];
    for (var h = 0; h < _headers.length; h++) {
      final notes = <NoteIr>[];
      for (var t = 0; t < _tracks.length; t++) {
        _readMeasure(t, t == selected ? notes : null);
      }
      final hd = _headers[h];
      final endings = <int>[
        for (var bit = 0; bit < 8; bit++)
          if (hd.repeatAlternative & (1 << bit) != 0) bit + 1,
      ];
      final mainSig =
          _headers.firstWhere((h) => h.numerator >= 4, orElse: () => _headers.first);
      final globalSig = '${mainSig.numerator}/${mainSig.denominator}';
      final thisSig = '${hd.numerator}/${hd.denominator}';
      measures.add(MeasureIr(
        index: h,
        confidence: 0,
        failed: false,
        notes: notes,
        repeatStart: hd.isRepeatOpen,
        repeatEnd: hd.isRepeatClose,
        repeatCount: hd.repeatCount,
        endings: endings,
        timeSignature: thisSig == globalSig ? null : thisSig,
      ));
    }
    if (measures.isEmpty) throw const FormatException('GP3/GP4 无小节');

    final track = _tracks[selected];
    final tuning = <String>[
      for (final midi in track.tunings.reversed)
        if (midi > 0) Note(midi).name,
    ];
    final mainSig = _headers
        .firstWhere((h) => h.numerator >= 4, orElse: () => _headers.first);
    return ScoreIr(
      version: irParserVersion,
      title: title.isEmpty ? '未命名' : title,
      tempo: tempo > 0 ? tempo.toDouble() : 90,
      timeSignature: '${mainSig.numerator}/${mainSig.denominator}',
      tuning: tuning,
      capo: track.capo,
      capoApplied: false,
      tracks: [
        TrackIr(
            name: track.name.isEmpty ? '主旋律' : track.name, measures: measures),
      ],
    );
  }

  // —— 小节头（gp3.py readMeasureHeader，GP3/GP4 读取路径相同）——

  List<_MeasureHeader> _readMeasureHeaders(int measureCount) {
    final headers = <_MeasureHeader>[];
    _MeasureHeader? prev;
    var existingAlternatives = 0; // repeatAlternative 回溯掩码累积
    for (var number = 1; number <= measureCount; number++) {
      final flags = _u8();
      final h = _MeasureHeader(
        (flags & 0x01) != 0 ? _i8() : prev?.numerator ?? 4,
        (flags & 0x02) != 0 ? _i8() : prev?.denominator ?? 4,
      );
      h.isRepeatOpen = flags & 0x04 != 0;
      if (flags & 0x08 != 0) {
        // GP3/GP4：I8 raw = 重复次数（gp3.py:225 直存 repeatClose，与 GP5
        // 的 -1 换算对照：GP5 raw=总遍数）。下游（score_ir 展开器）的
        // repeatCount 语义 = 总遍数 → raw+1 换算；raw > 0 即闭合。
        final raw = _i8();
        h.isRepeatClose = raw > 0;
        h.repeatCount = raw > 0 ? raw + 1 : 0;
      }
      if (flags & 0x10 != 0) {
        // GP3/GP4 readRepeatAlternative（gp3.py:239）：raw = "第 n 个结尾"
        //（1-based），先展开低 n 位全 1，再扣除此前已出现的位。
        // 回溯范围：当前 header 往前直到（不含）最近 repeatOpen。
        var mask = 0;
        if (prev != null) {
          mask = existingAlternatives;
        }
        final raw = _u8();
        h.repeatAlternative = ((1 << raw) - 1) ^ mask;
        existingAlternatives |= h.repeatAlternative;
      }
      if (flags & 0x20 != 0) {
        _intByteSizeString(); // marker 名
        _skip(4); // marker 颜色（R G B + 空字节）
      }
      if (flags & 0x40 != 0) {
        _i8(); // key signature root
        _i8(); // key signature type
      }
      // 注意：GP3/GP4 的读取顺序 0x10 在 0x20/0x40 **之前**（上方实现即此序）。
      // GP3/GP4 无 beams（0x03 时 GP5 才读 4 字节）、无 0x10 未置位的 skip(1)、
      // 无尾部 tripletFeel。
      if (h.isRepeatOpen) {
        existingAlternatives = 0; // repeatOpen 重开累积
      }
      headers.add(h);
      prev = h;
    }
    return headers;
  }

  // —— 音轨（gp3.py readTrack，GP3/GP4 相同，每轨恒 98B）——

  List<_Track> _readTracks(int trackCount) {
    final tracks = <_Track>[];
    for (var number = 1; number <= trackCount; number++) {
      _u8(); // flags1（drums/12弦/banjo）
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
      final capo = _i32();
      _skip(4); // color
      // GP3/GP4 无 flags2/RSE/循环后 skip（GP5 专属）。
      tracks.add(_Track(name, tunings, capo));
    }
    return tracks;
  }

  // —— 小节内容（gp3.py readMeasure → readVoice → readBeat）——

  void _readMeasure(int trackIdx, List<NoteIr>? out) {
    // GP3/GP4：单 voice、无 lineBreak（GP5 是 2 voice + lineBreak）。
    var beatPos = 0.0;
    final beatCount = _i32();
    for (var b = 0; b < beatCount; b++) {
      beatPos += _readBeat(trackIdx, beatPos, out);
    }
  }

  double _readBeat(int trackIdx, double beatPos, List<NoteIr>? out) {
    final flags = _u8();
    var status = 1; // normal
    if (flags & 0x40 != 0) status = _u8(); // 0 = empty, 1 = normal, 2 = rest

    final durByte = _i8();
    final noteValue = durByte >= -2 && durByte <= 6 ? 1 << (durByte + 2) : 4;
    var beats = 4.0 / noteValue;
    if (flags & 0x01 != 0) beats *= 1.5; // dotted
    if (flags & 0x20 != 0) {
      final tuplet = _i32();
      final ratio = _tupletRatio(tuplet);
      if (ratio != null) beats *= ratio;
    }

    // beat 级效果与 beat 级泛音（GP3 泛音在 beat 层，应用到 beat 内所有音）。
    var wideVibrato = false;
    var gp3NoteVibrato = false; // GP3 beat flags1&0x01：note 级 vibrato
    var beatHarmonic = false; // GP3 beat flags1&0x04/0x08
    String? brush;
    String? pickStroke;
    var fadeIn = false;
    if (flags & 0x02 != 0) _readChord();
    if (flags & 0x04 != 0) _intByteSizeString(); // text
    if (flags & 0x08 != 0) {
      if (!_isV4) {
        // GP3（gp3.py:658）：1 字节 flags。
        final f1 = _u8();
        gp3NoteVibrato = f1 & 0x01 != 0;
        wideVibrato = f1 & 0x02 != 0;
        beatHarmonic = f1 & 0x04 != 0 || f1 & 0x08 != 0; // natural/artificial
        fadeIn = f1 & 0x10 != 0;
        if (f1 & 0x20 != 0) {
          // GP3 f1&0x20 = tremolo bar / slap（pyguitarpro gp3.py:687-693
          // 同款：U8 子类型 + [none → tremoloBar I32 | tap/slap/pop →
          // I32]，两分支均 5 字节——2026-11-17 一度误改 1 字节致 68
          // 文件截断，已回滚）。
          final sub = _u8();
          if (sub == 0) {
            _i32(); // tremolo bar：GP3 仅 I32 value
          } else {
            _i32(); // tap/slap/pop 占位
          }
        }
        if (f1 & 0x40 != 0) {
          // GP3 stroke：字节 1 = 上扫速度、字节 2 = 下扫速度（py gp3.py
          // 的 docstring "stroke up and stroke down" 与 制谱基准 实测一致——
          // py 代码按 down 先读是它自己的 bug，TuxGuitar 照抄同错；
          // gp5 的 readBeatStroke+swapDirection 网络效果即 byte1→up，
          // 三代格式存储同序）。用户 制谱基准 对照实证（哆啦A梦.gp3）。
          final a = _i8();
          final b = _i8();
          brush = a > 0 ? 'up' : (b > 0 ? 'down' : null);
        }
      } else {
        // GP4（gp4.py:203）：2 字节 flags（GP5 沿用同款）。
        final f1 = _i8();
        final f2 = _i8();
        wideVibrato = f1 & 0x02 != 0;
        fadeIn = f1 & 0x10 != 0;
        if (f1 & 0x20 != 0) _i8(); // slapEffect（GP4 无 tremolo 转换分支）
        if (f2 & 0x04 != 0) _readBend(); // tremolo bar = 完整 bend
        if (f1 & 0x40 != 0) {
          // GP4 stroke 方向（2026-11-18 用户 制谱基准 对照实证 Promise.gp4
          // 全部反）：GP4 字节 1 = **下扫**、字节 2 = 上扫——与 GP3
          // 的"字节 1 = 上扫"（哆啦A梦 制谱基准 实证）**相反**，两代格式
          // 语义不同须分开（py GP4 沿用 gp3 基类读法 byte1=down 变量
          // 且无 swap → py 的 down = 文件 byte1 > 0 = 制谱基准 的 down ✓
          // py 与 制谱基准 一致，旧实现 byte1→up 反向）。
          final a = _i8();
          final b = _i8();
          brush = a > 0 ? 'down' : (b > 0 ? 'up' : null);
        }
        if (f2 & 0x02 != 0) {
          final d = _i8(); // pickStroke direction：1 = up, 2 = down
          pickStroke = d == 1 ? 'up' : (d == 2 ? 'down' : null);
        }
      }
    }
    if (flags & 0x10 != 0) _readMixTableChange();

    // 音符（gp3.py readNotes：弦号 1..stringCount，bit = 1 << (7 - string)）。
    final stringFlags = _u8();
    final tunings = _tracks[trackIdx].tunings;
    for (var si = 0; si < tunings.length; si++) {
      final stringNumber = si + 1;
      if (stringFlags & (1 << (7 - stringNumber)) != 0) {
        _readNote(
          stringNumber,
          beatPos: beatPos,
          beats: beats,
          status: status,
          out: out,
          wideVibrato: wideVibrato || gp3NoteVibrato,
          beatHarmonic: beatHarmonic,
          fadeIn: fadeIn,
          brush: brush,
          pickStroke: pickStroke,
        );
      }
    }

    // 同拍 tieEnd 数字锚回写（制谱基准 逐弧实证 121 例唯一例外：tieE 所在
    // 拍含装饰音 → 该 tieE 裸数字显示——m4 3弦0/m17 2弦3；其余小节内
    // tieE 隐藏）。**拍内音序 1→6 弦**（py/图双重实证）——装饰音挂在
    // 高音弦音上时，同拍 tieE 音（更低弦）尚未解析 → 合成时向前回写
    // 扑空；beat 收尾统一回写（_beatHasDeco 由 readNote 置位）。
    if (_beatHasDeco && out != null) {
      for (var i = out.length - 1; i >= 0; i--) {
        final p = out[i];
        if ((p.beat - beatPos).abs() > 1e-9) break;
        if (p.tieEnd && !p.tieAnchor) {
          out[i] = p.copyWith(tieAnchor: true);
        }
      }
    }
    _beatHasDeco = false;

    // GP3/GP4 无拍尾 flags2 I16（GP5 专属）。
    // empty beat（status=0）不占时值（gp3.py:468
    // `return duration.time if not beat.status == empty else 0`）；
    // rest 拍（status=2）照常推进。
    return status == 0 ? 0.0 : beats;
  }

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

  // —— 音符（gp3.py readNote，GP3/GP4 相同；效果段分层）——

  void _readNote(
    int stringNumber, {
    required double beatPos,
    required double beats,
    required int status,
    required List<NoteIr>? out,
    required bool wideVibrato,
    required bool beatHarmonic,
    required bool fadeIn,
    required String? brush,
    required String? pickStroke,
  }) {
    final flags = _u8();
    final ghost = flags & 0x04 != 0;
    final accent = flags & 0x40 != 0;
    // 注意：0x02（heavy accentuated）GP3/GP4 读取路径忽略（GP5 才读）。
    var noteType = 0;
    if (flags & 0x20 != 0) noteType = _u8(); // 1 = normal, 2 = tie, 3 = dead
    if (flags & 0x01 != 0) {
      _i8(); // time-independent duration
      _i8(); // tuplet（原始值）
    }
    var dyn = 0;
    if (flags & 0x10 != 0) dyn = _i8(); // 力度档 1..8
    var fret = 0;
    if (flags & 0x20 != 0) {
      fret = _i8();
      if (noteType == 2) fret = _tiedValue(stringNumber);
      // clamp 0..99（gp3.py:918 的 min(max(value,0),99)）。
      if (fret < 0) fret = 0;
      if (fret > 99) fret = 99;
    }
    if (flags & 0x80 != 0) {
      _i8(); // leftHandFinger
      _i8(); // rightHandFinger
    }

    // note effects（GP3 1 字节 / GP4 2 字节）。
    var hammer = false;
    var letRing = false;
    var staccato = false;
    var palmMute = false;
    var noteVibrato = false;
    var tremoloPicking = false;
    var harmonic = false;
    var trill = false;
    // grace 装饰数据（2026-11-19 Prologue m4/m17 修复：此前 4 字节全丢
    // → 装饰音从谱面/播放消失、本体被误当装饰——见本体 add 处合成）。
    ({int fret, int velocity, int transition, double duration})? graceData;
    String? slide;
    if (flags & 0x08 != 0) {
      if (!_isV4) {
        // GP3（gp3.py:948）：1 字节 flags。
        final f1 = _u8();
        hammer = f1 & 0x02 != 0;
        letRing = f1 & 0x08 != 0;
        if (f1 & 0x01 != 0) _readBend();
        if (f1 & 0x04 != 0) slide = 'shift'; // GP3 slide 无数据恒 shift
        if (f1 & 0x10 != 0) graceData = _readGrace();
      } else {
        // GP4（gp4.py:304）：2 字节 flags（GP5 沿用同款）。
        final f1 = _i8();
        final f2 = _i8();
        hammer = f1 & 0x02 != 0;
        letRing = f1 & 0x08 != 0;
        staccato = f2 & 0x01 != 0;
        palmMute = f2 & 0x02 != 0;
        tremoloPicking = f2 & 0x04 != 0;
        trill = f2 & 0x20 != 0;
        noteVibrato = f2 & 0x40 != 0;
        if (f1 & 0x01 != 0) _readBend();
        if (f1 & 0x10 != 0) graceData = _readGrace();
        if (f2 & 0x04 != 0) _i8(); // tremolo picking 速度档
        if (f2 & 0x08 != 0) slide = _readSlidesGp4();
        if (f2 & 0x10 != 0) {
          harmonic = true;
          _readHarmonic();
        }
        if (f2 & 0x20 != 0) {
          _i8(); // trill fret
          _i8(); // trill period
        }
      }
    }

    // 非选中轨：字节读齐即可，不入 IR、不登记 tie 回溯表
    //（_refs 全局共享，哑轨数据不得污染选中轨的 tie/hopo 回溯）。
    if (out == null) return;

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
    } else if (harmonic || beatHarmonic) {
      technique = 'H'; // 泛音（GP3 beat 级 / GP4 note 级）
    }

    final isTie = noteType == 2;
    final prev = _refs[stringNumber];
    if (isTie && prev != null) {
      prev.list[prev.index] = prev.list[prev.index]
          .copyWith(duration: prev.list[prev.index].duration + beats, tieStart: true);
    }
    // GP3/GP4 hammer 标志 = **原音语义**（2026-11-17 哆啦A梦 制谱基准 对照
    // 实证：制谱基准 m1 弧为 10→9/7→9/10→9/7→9，弧起点恰为带标志音——
    // TuxGuitar/py 的 destination 语义（标志音=弧终点）与 制谱基准 相反，
    // 旧实现弧整体前移一音、出现 7→7 同品弧）。hopoEnd 不设（弧由
    // 渲染层 hopoStart→同弦下一音画出；制谱基准 老格式读取器 v1-4 同路径，
    // gtp12 通道同改）。
    // if (hammer && prev != null) { ...hopoStart 移到标志音... }

    // grace 装饰音合成（2026-11-19 Prologue m4/m17 用户实证 + py 对照：
    // GP3/4 的 grace 是**本体音上的装饰数据**（装饰 fret + transition，
    // m4 = 3→10 击弦装饰、m17 = 3→7）——此前 4 字节全丢 → 装饰音从
    // 谱面/播放消失、本体被误画成小号装饰音（用户"滑音漏掉/丢音/拍位
    // 错乱"）。**用户决策（2026-11-19 深夜）：装饰音不当小号挂靠形态
    // （"不要小号3紧贴了，直接当成单独的音"）——合成普通音 NoteIr**
    // （正常数字、同拍组独立 dup 排布；时值本身 64 分级=播放自然一闪
    // 50ms，无需 grace 标志）；transition 仍映射连接属性（hammer→
    // hopoStart 击弦弧、slide→shift 滑线）。本体 grace=false 正常音。
    if (graceData != null) {
      final g = graceData; // 流分析提升非空（无 !）
      const tHammer = 3, tSlide = 1;
      out.add(NoteIr(
        beat: beatPos,
        duration: g.duration, // _readGrace 已换算四分拍（64 分 → 0.0625）
        string: stringNumber,
        fret: g.fret < 0 ? 0 : g.fret,
        technique: g.fret < 0 ? 'x' : null,
        // 尾部淡出（2026-11-25 LSA 用户实测 `<12>^2` 泛音装饰与主音
        // "混在一起"）：deco 音音量渐弱收尾——硬切尾与主音起音叠出
        // 混浊，fade out 柔化交接。
        fadding: 'out',
        // 制谱基准 实图形态（2026-11-19 逐弧精读）：装饰音 = 小号数字+↗+
        // TAB 上方 "sl" 弧——连接属性用 slide:'shift'（渲染 sl 弧；
        // hammer 也显示 sl 非 H）。播放：slide ramp 滑向本体音高。
        deco: true,
        slide: (g.transition == tHammer || g.transition == tSlide)
            ? 'shift'
            : null,
        velocity: g.velocity > 0 ? g.velocity : null,
      ));
      _beatHasDeco = true; // beat 收尾统一回写同拍 tieEnd 数字锚
    }

    out.add(NoteIr(
      beat: beatPos,
      duration: beats,
      string: stringNumber,
      fret: fret,
      technique: technique,
      tieEnd: isTie,
      hopoStart: hammer,
      letRing: letRing,
      palmMute: palmMute,
      vibrato: noteVibrato || wideVibrato,
      ghost: ghost,
      slide: slide,
      brush: brush,
      pickStroke: pickStroke,
      trill: trill,
      accent: accent,
      staccato: staccato,
      dynamicMark: dynamicMark,
      fadding: fadeIn ? 'in' : null,
      tremolo: tremoloPicking,
      velocity: velocity,
    ));
    if (status != 0) {
      _refs[stringNumber] = _NoteRef(out, out.length - 1, fret);
    }
  }

  int _tiedValue(int stringNumber) => _refs[stringNumber]?.value ?? 0;

  // —— 效果子块 ——

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

  /// GP3/GP4 grace（4 字节，py gp3.readGrace 序）：fret I8 + velocity
  /// U8（unpackVelocity = 16v-1）+ **duration 编码值** U8 + transition
  /// I8（2026-11-19 Prologue m4 实证：原实现按 py 字段序误读 trans/dur
  /// 互换——装饰音 3→10 击弦被误映射成 shift 滑音）。duration 编码：
  /// 1=32 分 2=24 分 3=16 分，py 同款换算 Duration = 1<<(7-code)，
  /// IR 四分拍 = 4/value。transition：0 none / 1 slide / 2 bend /
  /// 3 hammer。
  ({int fret, int velocity, int transition, double duration}) _readGrace() {
    final fret = _i8();
    final velocity = (_u8() * 16 - 1).clamp(1, 127);
    final durationCode = _u8();
    final transition = _i8();
    return (
      fret: fret,
      velocity: velocity,
      transition: transition,
      duration: 4 / (1 << (7 - durationCode)),
    );
  }

  /// GP4 slides（gp4.py:396）：I8 单值枚举（SlideType）。1 = shift,
  /// 2 = legato，3/4 = outDown/outUp，-1/-2 = intoFromBelow/Above。
  /// v1 统一映射滑音标记（shift），出/入滑与 shift 渲染近似。
  String? _readSlidesGp4() {
    final v = _i8();
    if (v == 2) return 'legato';
    if (v >= 1 && v <= 4 || v >= -2 && v <= -1) return 'shift';
    return null;
  }

  /// GP4 泛音（gp4.py:404）：I8 类型 1=natural 3=tapped 4=pinch 5=semi
  /// 15/17/22=artificial。v1 统一映射 'H'（类型字节读齐即可）。
  void _readHarmonic() {
    _i8();
  }

  /// 和弦图（gp3.py readChord 入口共用；new 格式 GP3/GP4 各一套）。
  void _readChord() {
    final newFormat = _u8() != 0;
    if (!newFormat) {
      // readOldChord（GP3/GP4 共用）。
      _intByteSizeString();
      final firstFret = _i32();
      if (firstFret != 0) {
        for (var i = 0; i < 6; i++) {
          _i32();
        }
      }
      return;
    }
    if (!_isV4) {
      // GP3 readNewChord（gp3.py:571，I32 字段版，合计 124B）。
      _u8(); // sharp
      _skip(3);
      _i32(); // root
      _i32(); // type
      _i32(); // extension
      _i32(); // bass
      _i32(); // tonality
      _u8(); // add
      _byteSizeString(22); // name
      _i32(); // fifth
      _i32(); // ninth
      _i32(); // eleventh
      _i32(); // firstFret
      for (var i = 0; i < 6; i++) {
        _i32(); // frets（GP3 是 6 弦）
      }
      _i32(); // barresCount
      for (var i = 0; i < 2; i++) {
        _i32(); // barreFrets
      }
      for (var i = 0; i < 2; i++) {
        _i32(); // barreStarts
      }
      for (var i = 0; i < 2; i++) {
        _i32(); // barreEnds
      }
      for (var i = 0; i < 7; i++) {
        _u8(); // omissions
      }
      _skip(1);
      // GP3 无 fingerings/show（GP4 新增）。
    } else {
      // GP4 readNewChord（gp4.py:111，U8 字段版，合计 106B）。
      _u8(); // sharp
      _skip(3);
      _u8(); // root
      _u8(); // type
      _u8(); // extension
      _i32(); // bass
      _i32(); // tonality
      _u8(); // add
      _byteSizeString(22); // name
      _u8(); // fifth
      _u8(); // ninth
      _u8(); // eleventh
      _i32(); // firstFret
      for (var i = 0; i < 7; i++) {
        _i32(); // frets（GP4 是 7 弦）
      }
      _u8(); // barresCount
      _skip(15); // barre frets/starts/ends 各 5 字节（U8）
      for (var i = 0; i < 7; i++) {
        _u8(); // omissions
      }
      _skip(1);
      for (var i = 0; i < 7; i++) {
        _i8(); // fingerings（GP4 新增）
      }
      _u8(); // show（GP4 新增）
    }
  }

  /// 曲中参数变化（GP3:764 / GP4:263）。v1 丢弃，字节读齐。
  void _readMixTableChange() {
    _i8(); // instrument
    final volume = _i8();
    final balance = _i8();
    final chorus = _i8();
    final reverb = _i8();
    final phaser = _i8();
    final tremolo = _i8();
    final tempo = _i32();
    // durations：volume→balance→chorus→reverb→phaser→tremolo→tempo 顺序。
    if (volume >= 0) _i8();
    if (balance >= 0) _i8();
    if (chorus >= 0) _i8();
    if (reverb >= 0) _i8();
    if (phaser >= 0) _i8();
    if (tremolo >= 0) _i8();
    if (tempo >= 0) _i8();
    // instrument 无 duration。
    if (_isV4) _i8(); // GP4 追加 flags（allTracks 位族）
  }
}
