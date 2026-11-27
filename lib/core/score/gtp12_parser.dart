import 'dart:math' as math;
import 'dart:typed_data';

import 'package:enough_convert/gbk_base.dart';

import '../music/note.dart';
import 'score_ir.dart';

/// GP1/GP2（.gtp 老格式）→ ScoreIr。
///
/// 规格依据：TuxGuitar（生产验证十余年的开源实现）
/// common/TuxGuitar-gtp 的 GP1InputStream.java / GP2InputStream.java 直译；
/// 制谱基准 实现定位佐证：GPIO.dll 的 gp::io::GP5ScoreLoader::readOldGtp
///（0x180074420，10.9KB 单函数内联全部 GP1/2 解析）。
///
/// 与 GP3/4（gp34_parser）的代际差异：
/// - 无独立 measure header 段：拍号/反复嵌在每个小节体里。
/// - 每小节固定 8 轨 × 12B 拍数表（2×U8 + beats U8 + 9B skip）。
/// - 字符串双长度字节（_sBsob：U8(len-1) + U8(len) + 内容）——GP3 是
///   int-byte-size 单长度。
/// - tie 是**拍级全拍连音**（beat flags1 0x40）：复制上一拍全部音，
///   非逐音 tie 标记（GP3 是 note type 2）。
/// - 效果是 1 字节枚举（beat：1/2 vibrato、3 bend、4 fade、8/9 泛音；
///   note：1/2 hammer、3/4 slide、5/6 bend）——GP3 起改位掩码。
/// - 弦位 bit：bit i → 弦 = stringCount - i（i=5 为弦 1 最细；GP3 是
///   bit = 1 << (7 - string)，弦 1 → bit6）。
/// - 轨选择：8 轨文件多哑轨（beats 恒 0），取第一个有音且调弦合法的轨。
ScoreIr parseGtp12Bytes(Uint8List bytes) => _Gtp12Reader(bytes).parse();

const GbkCodec _gbk = GbkCodec(allowInvalid: true);

class _NoteRef {
  _NoteRef(this.list, this.index);
  final List<NoteIr> list;
  final int index;
}

class _TrackInfo {
  _TrackInfo(this.stringCount);
  final int stringCount;
  List<int> tunings = const [];
  String name = '';
  final List<NoteIr> notes = []; // 全曲平铺（跨小节）
  final List<int> barStarts = []; // 每小节在 notes 里的起始索引
  final Map<int, _NoteRef> refs = {}; // 本轨弦 → 最近音（tie/hammer 回溯）
  final List<NoteIr> lastBeats = []; // 上一拍各音（全拍 tie 复制源）
}

class _Gtp12Reader {
  _Gtp12Reader(this._data);

  final Uint8List _data;
  int _pos = 0;
  bool _isV2 = false;
  int _code = 0; // 版本 code（parse 开头赋值）

  Never _eof() => throw FormatException('.gtp 文件截断或格式错误（offset $_pos）');

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

  /// 版本串：U8 长度 + 30B 定长。
  String _s30() {
    final size = _u8();
    _ensure(30);
    final raw = _data.sublist(_pos, _pos + 30);
    _pos += 30;
    final take = size < 30 ? size : 30;
    return String.fromCharCodes(raw.sublist(0, take < 0 ? 0 : take));
  }

  /// 双长度字节串（GP1/2 特有）：U8(len-1) + U8(len) + 内容。
  String _sBsob() {
    final size = _u8() - 1;
    final len = _u8();
    _ensure(size < 0 ? 0 : size);
    final raw = Uint8List.sublistView(
        _data, _pos, _pos + (size < 0 ? 0 : size));
    _pos += size < 0 ? 0 : size;
    final take = len >= 0 && len <= raw.length ? len : size;
    return _gbk.decode(raw.sublist(0, take < 0 ? 0 : take));
  }

  /// 单长度字节串：U8(len) + 内容。
  String _sByte() {
    final len = _u8();
    _ensure(len < 0 ? 0 : len);
    final raw =
        Uint8List.sublistView(_data, _pos, _pos + (len < 0 ? 0 : len));
    _pos += len < 0 ? 0 : len;
    return _gbk.decode(raw);
  }

  bool _bool() => _u8() == 1;

  late final List<_TrackInfo> _tracks;
  late final List<int> _barNums;
  late final List<int> _barDens;
  late final List<bool> _barRepeatOpen;
  late final List<int> _barRepeatClose; // 原始 U8（重复次数语义）
  late final List<int> _barAltMasks; // 多结尾位掩码（bit i = 第 i+1 结尾）

  ScoreIr parse() {
    final version = _s30();
    if (version.contains('GUITARE') || version.contains('GUITAR PRO v1')) {
      _isV2 = false;
      // code 取版本尾段（v1.01→1 … v1.04→4；纯 v1 基串→0）。
      final v = version.trim();
      final tail = v.length <= 5 ? v : v.substring(v.length - 5);
      _code = const {'v1.01': 1, 'v1.02': 2, 'v1.03': 3, 'v1.04': 4}[tail] ?? 0;
    } else if (version.contains('v2.20')) {
      _isV2 = true;
      _code = 0;
    } else if (version.contains('v2.21')) {
      _isV2 = true;
      _code = 1;
    } else {
      throw FormatException('不支持的 Guitar Pro 版本 "$version"（仅支持 GP1/GP2）');
    }

    final fullTracks = _isV2 || _code > 2; // 8 轨 + 全字段轨段
    final trackCount = fullTracks ? 8 : 1;

    final title = _sBsob().trim();
    _sBsob(); // author
    _sBsob(); // notice
    final tempo = _i32();
    _i32(); // tripletFeel
    if (_isV2 || _code > 2) _i32(); // key

    // 每轨弦数 + 调弦连续（TuxGuitar readSong 一体循环，不可拆两遍）。
    _tracks = <_TrackInfo>[];
    for (var t = 0; t < trackCount; t++) {
      final count = _isV2 || _code > 1 ? _i32() : 6;
      final track = _TrackInfo(count);
      track.tunings = [for (var i = 0; i < count; i++) _i32()];
      _tracks.add(track);
    }

    final measureCount = _i32();
    if (measureCount < 1) throw const FormatException('GP1/2 无小节');

    for (final t in _tracks) {
      _i32(); // program
      if (fullTracks) {
        _i32(); // frets
        t.name = _sBsob();
        _bool(); // solo
        _skip(16); // vol/bal/chorus/reverb
        _i32(); // offset
      }
    }
    if (fullTracks) _skip(10);

    _barNums = <int>[];
    _barDens = <int>[];
    _barRepeatOpen = <bool>[];
    _barRepeatClose = <int>[];
    _barAltMasks = <int>[];
    var existingAlternatives = 0; // 多结尾回溯累积（repeatOpen 重置）
    for (var m = 0; m < measureCount; m++) {
      for (final t in _tracks) {
        t.barStarts.add(t.notes.length);
      }
      final num = _u8();
      final den = _u8();
      _skip(6);
      final beats = <int>[
        for (var t = 0; t < trackCount; t++)
          () {
            _u8();
            _u8();
            final b = _u8();
            _skip(9);
            return b > 127 ? 0 : b;
          }()
      ];
      _skip(2);
      final flags = _u8();
      _barNums.add(num);
      _barDens.add(den);
      _barRepeatOpen.add(flags & 0x01 != 0);
      _barRepeatClose.add(flags & 0x02 != 0 ? _u8() : 0);
      if (flags & 0x04 != 0) {
        // repeatAlternative（多结尾）：raw = "第 n 个结尾"，展开低位全 1
        // 再扣已出现位（TuxGuitar parseRepeatAlternative，与 gp34 通道同
        // 算法）。复测必修 2：24 文件第二遍连"1. 结尾"重播，展开修复。
        final raw = _u8();
        final alt = ((1 << raw) - 1) ^ existingAlternatives;
        existingAlternatives |= alt;
        _barAltMasks.add(alt);
      } else {
        _barAltMasks.add(0);
      }

      for (var t = 0; t < trackCount; t++) {
        var beatPos = 0.0;
        for (var b = 0; b < beats[t]; b++) {
          beatPos += _readBeat(_tracks[t], beatPos);
        }
      }
      if (flags & 0x01 != 0) existingAlternatives = 0; // repeatOpen 重开
    }

    // 轨选择：第一个 有音 且 调弦含非 0 的轨（8 轨文件多哑轨）。
    var sel = 0;
    for (var t = 0; t < _tracks.length; t++) {
      if (_tracks[t].notes.isNotEmpty &&
          _tracks[t].tunings.any((v) => v != 0)) {
        sel = t;
        break;
      }
    }
    final track = _tracks[sel];

    final measures = <MeasureIr>[];
    for (var m = 0; m < measureCount; m++) {
      final from = track.barStarts[m];
      final to = m + 1 < measureCount ? track.barStarts[m + 1] : track.notes.length;
      final mainSig = _firstMainSig();
      final thisSig = '${_barNums[m]}/${_barDens[m]}';
      final globalSig = '${mainSig[0]}/${mainSig[1]}';
      // gtp 的 repClose U8 = 重复次数（TuxGuitar 直存）→ 总遍数 = raw+1。
      final rawClose = _barRepeatClose[m];
      measures.add(MeasureIr(
        index: m,
        confidence: 0,
        failed: false,
        notes: track.notes.sublist(from, to),
        repeatStart: _barRepeatOpen[m],
        repeatEnd: rawClose > 0,
        repeatCount: rawClose > 0 ? rawClose + 1 : 0,
        endings: <int>[
          for (var bit = 0; bit < 8; bit++)
            if (_barAltMasks[m] & (1 << bit) != 0) bit + 1,
        ],
        timeSignature: thisSig == globalSig ? null : thisSig,
      ));
    }

    final tuning = <String>[
      for (final midi in track.tunings.reversed)
        if (midi > 0) Note(midi).name,
    ];
    final mainSig = _firstMainSig();
    return ScoreIr(
      version: irParserVersion,
      title: title.isEmpty ? '未命名' : title,
      tempo: tempo > 0 ? tempo.toDouble() : 90,
      timeSignature: '${mainSig[0]}/${mainSig[1]}',
      tuning: tuning,
      capo: 0,
      capoApplied: false,
      tracks: [
        TrackIr(
            name: track.name.isEmpty ? '主旋律' : track.name,
            measures: measures),
      ],
    );
  }

  List<int> _firstMainSig() {
    for (var i = 0; i < _barNums.length; i++) {
      if (_barNums[i] >= 4) return [_barNums[i], _barDens[i]];
    }
    return [
      _barNums.isNotEmpty ? _barNums[0] : 4,
      _barDens.isNotEmpty ? _barDens[0] : 4
    ];
  }

  double _readBeat(_TrackInfo track, double beatPos) {
    _i32(); // 拍头占位（TuxGuitar 同款忽略）
    final durByte = _i8();
    // 2^(b+2)：b 可为负（breve 等），math.pow 防 Dart 移位负数崩
    //（1 << -1 = ArgumentError；TuxGuitar Math.pow 同式，复测建议 4）。
    var dur = 4.0 / math.pow(2, durByte + 2).toDouble();
    final flags1 = _u8();
    var flags2 = 0;
    if (_isV2) {
      flags2 = _u8();
      if (flags2 & 0x02 != 0) _readMixChange();
      if (flags2 & 0x01 != 0) {
        _u8(); // strokeType
        _u8(); // strokeDuration
      }
    }
    if (flags1 & 0x10 != 0) dur *= 1.5; // dotted
    if (flags1 & 0x20 != 0) {
      _skip(1); // triplet（3:2）
      dur *= 2 / 3;
    }

    String? beatEffect;
    if (flags1 & 0x04 != 0) {
      final eff = _u8();
      if (eff == 1 || eff == 2) {
        beatEffect = 'vibrato';
      } else if (eff == 3) {
        _skip(8); // bend
      } else if (eff == 4) {
        beatEffect = 'fade';
      } else if (eff == 5) {
        beatEffect = 'tap'; // TuxGuitar tapping（GP1InputStream.java:304）
      } else if (eff == 8 || eff == 9) {
        beatEffect = 'harmonic';
      }
    }
    if (flags1 & 0x02 != 0) _readChord();
    if (flags1 & 0x01 != 0) _sByte(); // text

    if (flags1 & 0x40 != 0) {
      // 全拍 tie（flags1 0x40）：复制紧邻上一拍全部音为 tieEnd 哑音、源音
      // 吸收时值（TuxGuitar getBeat(lastReadedStart) 语义）。上一拍是休止/
      // 空拍时其 voice 无音——lastBeats 已清空 → 复制 0 音（静音拍）。
      for (final src in track.lastBeats) {
        final ref = track.refs[src.string];
        if (ref != null) {
          ref.list[ref.index] = ref.list[ref.index]
              .copyWith(duration: ref.list[ref.index].duration + dur, tieStart: true);
        }
        final fret = ref?.list[ref.index].fret ?? src.fret;
        final note = NoteIr(
          beat: beatPos,
          duration: dur,
          string: src.string,
          fret: fret,
          tieEnd: true,
          vibrato: src.vibrato,
          technique: src.technique,
          tap: src.tap,
        );
        track.notes.add(note);
        _registerRef(track, src.string);
      }
    } else if (flags1 & 0x08 == 0) {
      // 常规拍读音符；0x08 = 空拍（无音、无弦表）。
      final stringsFlags = _u8();
      final effectsFlags = _u8();
      final graceFlags = _isV2 ? _u8() : 0;
      final newBeats = <NoteIr>[];
      for (var i = 5; i >= 0; i--) {
        if (stringsFlags & (1 << i) != 0) {
          final fret = _u8();
          var dyn = 0;
          if (_isV2) dyn = _u8(); // dynamic（GP2 力度档，复测建议 3）
          var hammer = false;
          String? slide;
          var vibrato = beatEffect == 'vibrato';
          if (effectsFlags & (1 << i) != 0) {
            final e = _u8();
            if (e == 1 || e == 2) {
              hammer = true;
            } else if (e == 3 || e == 4) {
              slide = 'shift';
            } else if (e == 5 || e == 6) {
              _skip(8); // bend
            }
          }
          final dead = fret < 0 || fret >= 100;
          final string = track.stringCount - i;
          // GP1/2 hammer 标志 = **原音语义**（2026-11-17 哆啦A梦 gp3
          // 对照实证：制谱基准 老格式读取器 v1-4 同路径，弧从带标志音出发
          // 到同弦下一音——TuxGuitar/py 的 destination 语义与 制谱基准 相
          // 反；详见 gp34_parser 同注释）。
          // if (hammer && ref != null) { ...hopoStart 移到标志音... }
          // GP2 力度 → velocity/dynamicMark（与 gp34 通道同换算 16d-1）。
          int? velocity;
          String? dynamicMark;
          if (_isV2 && dyn > 0) {
            velocity = dyn * 16 - 1;
            if (dyn <= 8) {
              dynamicMark = const [
                'ppp', 'pp', 'p', 'mp', 'mf', 'f', 'ff', 'fff',
              ][dyn - 1];
            }
          }
          final note = NoteIr(
            beat: beatPos,
            duration: dur,
            string: string,
            fret: dead ? 0 : fret,
            technique: dead ? 'x' : (beatEffect == 'harmonic' ? 'H' : null),
            hopoStart: hammer,
            vibrato: vibrato,
            slide: slide,
            fadding: beatEffect == 'fade' ? 'in' : null,
            tap: beatEffect == 'tap',
            velocity: velocity,
            dynamicMark: dynamicMark,
          );
          track.notes.add(note);
          _registerRef(track, string);
          newBeats.add(note);
        }
        if (_isV2 && graceFlags & (1 << i) != 0) {
          _skip(3); // grace note
        }
      }
      track.lastBeats
        ..clear()
        ..addAll(newBeats);
    } else {
      // 0x08 休止拍：TuxGuitar 把休止拍加进小节但 voice 无音符——其后
      // 的全拍 tie 查到空 voice = 复制 0 音（静音拍）。lastBeats 必须
      // 清空，否则休止前的旧音被幻影延音（复测必修 1：曲库 8 文件
      // 22 处，GP1InputStream.java:249 对空 voice 迭代为空）。
      track.lastBeats.clear();
    }
    return dur;
  }

  void _readMixChange() {
    final flags = _u8();
    if (flags & 0x20 != 0) {
      _i32(); // tempo
      _u8();
    }
    for (final bit in [0x10, 0x08, 0x04, 0x02]) {
      if (flags & bit != 0) {
        _u8();
        _u8();
      }
    }
    if (flags & 0x01 != 0) _u8();
  }

  void _readChord() {
    // v1 低版本（code<=3）只有 1 个双长度串；v1.04 与 v2 全字段。
    if (!_isV2 && _code <= 3) {
      _sBsob();
      return;
    }
    _sByte(); // name
    _skip(1);
    if (_i32() < 12) _skip(32);
    final firstFret = _i32();
    if (firstFret != 0) {
      for (var i = 0; i < 6; i++) {
        _i32();
      }
    }
  }

  /// 登记弦 → 最近音引用（tie/hammer 回溯用）。
  void _registerRef(_TrackInfo track, int string) {
    track.refs[string] = _NoteRef(track.notes, track.notes.length - 1);
  }
}
