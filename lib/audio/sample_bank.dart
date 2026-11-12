import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:flutter_soloud/flutter_soloud.dart' show AudioSource;

import '../core/music/note.dart';
import '../core/score/score_ir.dart';
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

  /// 泛音采样弦号 → 各品位泛音的发声半音数。
  /// 非标准调弦时按发声 MIDI 找最近泛音采样（跨弦借采），减少移调量
  /// （2026-10-31 走查：重移调 >2 半音的泛音听感"太实"不像泛音）。
  static const _harmonicPitch = {5: 24, 7: 19, 12: 12};

  /// 按弦+品匹配泛音采样（原始逻辑，标准调弦精确命中）。
  static ({String file, double speed})? _harmonicByString(
      int string, int fret, int soundingMidi) {
    final base = _stringBaseMidi[string];
    if (base == null) return null;
    final pitch = _harmonicPitch[fret];
    if (pitch == null) return null;
    return (
      file: _harmonicFile(string, fret, base),
      speed: _speed(soundingMidi, base + pitch),
    );
  }

  /// 按发声 MIDI 跨弦找最近泛音采样（非标准调弦主路径）。
  /// 遍历 6 弦 × 3 泛音位 = 18 个采样发声点，取距离最小的。
  static ({String file, double speed})? _harmonicByPitch(
      int soundingMidi) {
    ({String file, double speed})? best;
    var bestDist = 999;
    for (var s = 1; s <= 6; s++) {
      final base = _stringBaseMidi[s]!;
      for (final entry in _harmonicPitch.entries) {
        final sampleMidi = base + entry.value;
        final dist = (soundingMidi - sampleMidi).abs();
        if (dist < bestDist) {
          bestDist = dist;
          best = (
            file: _harmonicFile(s, entry.key, base),
            speed: _speed(soundingMidi, sampleMidi),
          );
        }
      }
    }
    return best;
  }

  /// 采样解析：文件名 + 重移调速度。弦号越界返回 null。
  ///
  /// [fret] 是谱面品位（泛音按泛音位记谱），[soundingMidi] 是记谱发声半音
  /// （调弦+夹+品，渲染器同款公式——**不含泛音偏移**）。
  /// [harmonicOffset] 泛音发声偏移（半音，解析层算好；2026-11-07 重构）：
  /// 非 null 时**强制走真泛音采样**（跨弦借采，speed = 泛音目标/采样发声），
  /// 不再受 fret ∈ {5,7,12} 白名单限制——人工泛音（如 Fret19/HFret12）与
  /// 4 品触点此前全落到拨弦采样，音色与弹奏无差（用户实测反馈根因）。
  /// 泛音音高由 speed 全权覆盖，调用方不再叠加 pitchFixed（双重移调）。
  /// [downstroke] 下拨采样（2026-11-01 技法音效：GP8 库有 Up/Down 双层，
  /// 拨弦交替轮换更贴真实演奏；null/不传 = 沿用 Up 层）。
  static ({String file, double speed})? resolve({
    required int string,
    required int fret,
    required int soundingMidi,
    String? technique,
    bool? downstroke,
    double? harmonicOffset,
  }) {
    final base = _stringBaseMidi[string];
    if (base == null) return null;
    if (harmonicOffset != null) {
      // 泛音：目标发声 = 记谱 + 偏移，跨弦找最近真泛音采样（9 个采样点
      // 覆盖 24/19/12 × 3 弦，最近距离 ≤~3 半音）。
      return _harmonicByPitch(soundingMidi + harmonicOffset.round());
    }
    if (technique == 'H' && _harmonicPitch.containsKey(fret)) {
      // 泛音采样策略（2026-10-31 走查修正）：弦+品精确命中且移调轻
      //（±2 半音）→ 直接用本弦采样；跨弦找最近泛音采样。
      final byString = _harmonicByString(string, fret, soundingMidi);
      if (byString != null && (byString.speed - 1.0).abs() < 0.2) {
        return byString;
      }
      final byPitch = _harmonicByPitch(soundingMidi);
      if (byPitch != null) return byPitch;
    }
    var best = _pluckOffsets[0];
    for (final o in _pluckOffsets) {
      if ((soundingMidi - (base + o)).abs() <
          (soundingMidi - (base + best)).abs()) {
        best = o; // 距离并列取更低采样（半音下移听感优于上移）
      }
    }
    return (
      file: _pluckFile(string, base + best, downstroke: downstroke),
      speed: _speed(soundingMidi, base + best),
    );
  }

  static double _speed(int targetMidi, int sampleMidi) =>
      math.pow(2, (targetMidi - sampleMidi) / 12).toDouble();

  /// 目标音的重移调 speed（滑音终点换算用，与 resolve 内部同公式）。
  static double speedOf({required int string, required int soundingMidi}) {
    final base = _stringBaseMidi[string];
    if (base == null) return 1;
    var best = _pluckOffsets[0];
    for (final o in _pluckOffsets) {
      if ((soundingMidi - (base + o)).abs() <
          (soundingMidi - (base + best)).abs()) {
        best = o;
      }
    }
    return _speed(soundingMidi, base + best);
  }

  /// 文件名与 .gp7bank 解出物一一对应：拨弦品的 MIDI 三位补零，
  /// 泛音文件名里泛音位两位、空弦 MIDI 原样。拨层 Up/Down（力层固定 01）。
  static String _pluckFile(int string, int sampleMidi,
          {bool? downstroke}) =>
      'Mrg12-Pck-Sus-${downstroke == true ? 'Down' : 'Up'}-01-'
      '${_stringId[string]}${_stringBaseMidi[string]}'
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

  /// 释放全部缓存音源（2026-10-31 走查"关闭慢"修复）：并行 fire-and-forget，
  /// 不逐个 await——顺序 await ~50 个原生释放曾把主 isolate 冻结数秒。
  Future<void> dispose() async {
    final sources = List.of(_cache.values);
    _cache.clear();
    for (final s in sources) {
      // 释放失败静默（原 try/catch 语义）：关闭路径不该因单音源报错炸出。
      unawaited(_sound.disposeSource(s).catchError((_) {}));
    }
  }

  /// 预载某曲触到的全部采样（2026-11-08 gp8 对照：gp8 打开文件即预渲染
  /// 音频，点播放立即出声——我们点播放才现载采样，首播延迟 1-3s）。
  /// 打开曲谱详情后后台调用，点播放时缓存全命中、零等待。
  Future<void> preloadFor(ScoreIr ir) async {
    if (ir.tuning.length != 6) return;
    final tunings = [for (final s in ir.tuning) Note.parse(s)];
    final files = <String>{};
    for (final m in ir.tracks.first.measures) {
      for (final n in m.notes) {
        if (n.tieEnd) continue;
        final capoShift = ir.capoApplied ? 0 : ir.capo;
        final soundingMidi =
            tunings[6 - n.string].midi + capoShift + n.fret;
        final r = resolve(
            string: n.string,
            fret: n.fret,
            soundingMidi: soundingMidi,
            technique: n.technique,
            harmonicOffset: n.harmonicOffset);
        if (r != null) files.add(r.file);
      }
    }
    for (final f in files) {
      await load(f);
    }
  }
}
