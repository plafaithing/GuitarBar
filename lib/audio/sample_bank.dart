import 'dart:math' as math;

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:flutter_soloud/flutter_soloud.dart' show AudioSource;

import 'sound_engine.dart';

/// GP8 12-Steel 采样库（assets/sounds/steel/ 的 114 个 ogg 真录钢弦采样）：
/// 按（弦号, 品位, 技法）→ 采样文件 + 重移调速度 → AudioSource 缓存。
///
/// 采样在标准调弦下录制：每弦 4 个拨弦采样品（空弦 + 0/4/8/12 半音），
/// 外加 5/7/12 品自然泛音。非采样品位取最近采样，播放时用 soloud 的
/// 相对速度（scale）重移调：speed = 2^((目标半音 - 采样半音)/12)。
///
/// 音高约定与离线渲染器一致（score_renderer）：发声 = 调弦 + 变调夹 + 夹后品，
/// 调用方算好发声 MIDI 传入，本类不做调弦换算。
class SteelSampleBank {
  SteelSampleBank(this._sound, {Future<ByteData> Function(String)? assetLoader})
      : _assetLoader = assetLoader ?? rootBundle.load;

  final SoundEngine _sound;
  final Future<ByteData> Function(String) _assetLoader;
  final Map<String, AudioSource> _cache = {};

  /// 弦号（1=最细高音弦）→ 采样录制基准的空弦 MIDI（标准调弦）。
  static const _stringBaseMidi = {1: 64, 2: 59, 3: 55, 4: 50, 5: 45, 6: 40};
  static const _stringId = {1: '1E', 2: '2B', 3: '3G', 4: '4D', 5: '5A', 6: '6E'};

  /// 拨弦采样的录制品位（空弦 + 半音数）。v1 固定 Up-01（上拨 mf）层。
  static const _pluckOffsets = [0, 4, 8, 12];

  /// 自然泛音品位 → 采样发声高空弦的半音数（5 品两个八度、
  /// 7 品八度+纯五度、12 品八度）。
  static const _harmonicPitch = {5: 24, 7: 19, 12: 12};

  /// 采样解析：文件名 + 重移调速度。弦号越界返回 null。
  ///
  /// [fret] 是谱面品位（泛音按泛音位记谱），[soundingMidi] 是最终发声半音
  /// （调弦+夹+品，渲染器同款公式）。泛音采样只覆盖 5/7/12 品：命中则用
  /// 泛音录音（12 品恰为八度，速度恰 1.0）；其余泛音位按普通拨弦发声，
  /// 音高正确优先。
  static ({String file, double speed})? resolve({
    required int string,
    required int fret,
    required int soundingMidi,
    String? technique,
  }) {
    final base = _stringBaseMidi[string];
    if (base == null) return null;
    if (technique == 'H') {
      final pitch = _harmonicPitch[fret];
      if (pitch != null) {
        return (
          file: _harmonicFile(string, fret, base),
          speed: _speed(soundingMidi, base + pitch),
        );
      }
    }
    var best = _pluckOffsets[0];
    for (final o in _pluckOffsets) {
      if ((soundingMidi - (base + o)).abs() <
          (soundingMidi - (base + best)).abs()) {
        best = o; // 距离并列取更低采样（半音下移听感优于上移）
      }
    }
    return (
      file: _pluckFile(string, base + best),
      speed: _speed(soundingMidi, base + best),
    );
  }

  static double _speed(int targetMidi, int sampleMidi) =>
      math.pow(2, (targetMidi - sampleMidi) / 12).toDouble();

  /// 文件名与 .gp7bank 解出物一一对应：拨弦品的 MIDI 三位补零，
  /// 泛音文件名里泛音位两位、空弦 MIDI 原样。
  static String _pluckFile(int string, int sampleMidi) =>
      'Mrg12-Pck-Sus-Up-01-${_stringId[string]}${_stringBaseMidi[string]}'
      '-${sampleMidi.toString().padLeft(3, '0')}-none-none.ogg';

  static String _harmonicFile(int string, int fret, int base) =>
      'Mrg12-Hrm-Nat-${fret.toString().padLeft(2, '0')}-none-'
      '${_stringId[string]}$base-none-none-none.ogg';

  /// 取音源（缓存优先；未载则读 assets ogg 经 loadMem 解码）。
  /// 失败（资源缺失/引擎不可用）返回 null → 调用方整曲降级 KS 合成。
  Future<AudioSource?> load(String file) async {
    final hit = _cache[file];
    if (hit != null) return hit;
    try {
      final data = await _assetLoader('assets/sounds/steel/$file');
      final src = await _sound.loadOgg(file, data.buffer.asUint8List());
      _cache[file] = src;
      return src;
    } catch (_) {
      return null;
    }
  }

  /// 释放全部缓存音源。需先停播放（无活动句柄）；页 dispose 时调用。
  Future<void> dispose() async {
    final sources = List.of(_cache.values);
    _cache.clear();
    for (final s in sources) {
      try {
        await _sound.disposeSource(s);
      } catch (_) {}
    }
  }
}
