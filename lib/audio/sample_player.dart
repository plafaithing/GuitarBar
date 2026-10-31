import 'dart:async';

import 'package:flutter/foundation.dart';
// AudioSource/SoundHandle 类型来自 soloud 包（sound_engine 未重导出）。
import 'package:flutter_soloud/flutter_soloud.dart';

import '../core/music/note.dart';
import '../core/score/score_ir.dart';
import 'sample_bank.dart';
import 'score_player.dart' show ScorePlayback;
import 'sound_engine.dart';

/// 实时采样播放（GP8 真录钢弦音色）：不走离线渲染，事件按绝对拍排好，
/// 前瞻 ticker 分批经 scheduleAt 钉到 soloud 引擎时钟——采样精确、
/// 重移调 scale 出生原子生效，ticker 抖动不影响时值（只决定入队时机）。
///
/// 公开面与 ScorePlayer 同构（ScorePlayback）：页面采样优先，
/// play 返回 false（采样缺失/无可发音符）时降级离线 KS 渲染。
///
/// 暂停语义与 PCM 路径的差异（备案）：PCM 路径 soloud 冻结在暂停点精确
/// 续播；采样路径引擎时钟不停，暂停 = 切掉现场声部 + 冻结时间轴，
/// 恢复时从暂停点继续调度后续音符（被切声部不续响）。
class SampleScorePlayer implements ScorePlayback {
  SampleScorePlayer(this._sound, this._bank, {this.onEnded});
  final SoundEngine _sound;
  final SteelSampleBank _bank;

  /// 曲终回调：tick 检测时间轴越过时长时触发（同 ScorePlayer）。
  final void Function()? onEnded;

  /// 本轮事件（绝对时刻升序）。src 预载回填后调度零 await。
  final List<_PendingEvent> _pending = [];

  /// 已入队未收割的句柄（预调度中 + 余振中）。
  final List<SoundHandle> _voices = [];

  Timer? _timer;
  Duration _t0 = Duration.zero; // 时间轴零点（引擎时钟）
  int _pointer = 0;
  int _gen = 0; // 代际：预载 await 期间被 stop 时放弃起播
  bool _playing = false;
  bool _paused = false;
  double _pausedAt = 0;

  @override
  double durationSeconds = 0;
  @override
  final ValueNotifier<double> positionSeconds = ValueNotifier(0);

  @override
  bool get playing => _playing;
  @override
  bool get paused => _paused;

  /// 前瞻调度窗口：每次 tick 把窗口内的事件全部钉到引擎时钟。
  static const _horizonSeconds = 0.5;

  /// 闷音 x：与 KS 路径同款 0.3s 截短（scheduleAt 到点自动停）。
  static const _mutedSeconds = 0.3;

  /// 解析 IR → 预载本曲触到的采样 → 开始调度。返回 false 表示采样路径
  /// 不可用（资源缺失/引擎不可用/无可发音符），调用方降级 KS。
  /// 预载耗时 ~0.1-0.5s（首次，之后缓存命中）：调用方负责忙碌反馈。
  Future<bool> play(ScoreIr ir) async {
    if (_playing) return true;
    await stop();
    final gen = _gen;
    try {
      if (!_collectEvents(ir)) return false;
    } catch (_) {
      return false; // 调弦解析失败等坏 IR：整曲降级 KS
    }
    for (final e in _pending) {
      final src = await _bank.load(e.file);
      if (gen != _gen) return false; // 预载期间被 stop：放弃起播
      if (src == null) return false; // 采样缺失是系统性问题：整曲降级
      e.src = src;
    }

    _sound.setMaxActiveVoiceCount(64);
    _t0 = _sound.engineNow();
    _pointer = 0;
    _playing = true;
    _paused = false;
    _pausedAt = 0;
    onTick(); // 立即调度开头的音，不等首个 tick（50ms 延迟可闻）
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => onTick());
    return true;
  }

  /// IR → 事件 + 时长。失败（调弦解析/空事件）返回 false。
  bool _collectEvents(ScoreIr ir) {
    _pending.clear();
    if (ir.tuning.length != 6) return false; // 钢弦采样库按 6 弦录制
    final tunings = [for (final s in ir.tuning) Note.parse(s)];
    final beatsPerBar = int.tryParse(ir.timeSignature.split('/')[0]) ?? 4;
    final beatSeconds = 60.0 / ir.tempo;
    var endBeat = 0.0;
    for (final t in ir.tracks) {
      for (final m in t.measures) {
        if (m.failed) continue;
        for (final n in m.notes) {
          if (n.tieEnd) continue; // tie 续接端不出音（时长已累计回链首）
          // 弦号映射与渲染器同款：string 1（最细）→ tunings[5]；
          // 发声 MIDI 按通道语义（渲染器同款 capoApplied 公式）：
          // gpx=绝对品（+capo）、AI=夹后品（已含不补）。
          final capoShift = ir.capoApplied ? 0 : ir.capo;
          final soundingMidi =
              tunings[6 - n.string].midi + capoShift + n.fret;
          final r = SteelSampleBank.resolve(
              string: n.string,
              fret: n.fret,
              soundingMidi: soundingMidi,
              technique: n.technique);
          if (r == null) continue; // 弦号越界的坏数据：跳过该音
          final absBeat = m.index * beatsPerBar + n.beat;
          // 采样时长 = 音符时值 + 极短余振（0.08s，2026-10-31 二轮收窄：
          // 0.15s 在 82bpm 快速指弹中仍叠出"抢拍"感）。
          final noteSeconds = n.duration * beatSeconds + 0.08;
          _pending.add(_PendingEvent(
              time: absBeat * beatSeconds,
              file: r.file,
              speed: r.speed,
              muted: n.technique == 'x',
              noteSeconds: noteSeconds));
          final e = absBeat + n.duration;
          if (e > endBeat) endBeat = e;
        }
      }
    }
    if (_pending.isEmpty) return false;
    // 时长含尾音（与渲染器同款 1.2s）：末音采样自然衰减不受限，
    // 越线余振由下一轮 play/stop 收割（见 stop）。
    durationSeconds = endBeat * beatSeconds + 1.2;
    _pending.sort((a, b) => a.time.compareTo(b.time));
    return true;
  }

  /// 50ms tick 一步。公开为可直测（Timer 周期在测试里难控）。
  @visibleForTesting
  void onTick() {
    if (!_playing || _paused) return;
    final pos = _positionSeconds();
    // 前瞻调度：窗口内事件全部钉到引擎时钟（t0 + 绝对时刻）。
    final horizon = pos + _horizonSeconds;
    while (_pointer < _pending.length && _pending[_pointer].time <= horizon) {
      final e = _pending[_pointer];
      _pointer++;
      final src = e.src;
      if (src == null) continue; // 理论不可达：play 已确保全部预载
      try {
        _voices.add(_sound.scheduleAt(
          src,
          atTime: _t0 + Duration(microseconds: (e.time * 1e6).round()),
          scale: e.speed,
          duration: e.muted
              ? Duration(milliseconds: (_mutedSeconds * 1000).round())
              : Duration(
                  microseconds: (e.noteSeconds * 1e6).round()),
        ));
      } catch (_) {
        // 单音调度失败不致命：跳过该音。
      }
    }
    positionSeconds.value = pos > durationSeconds ? durationSeconds : pos;
    if (pos >= durationSeconds) {
      // 曲终：状态清理；余振不切（自然衰减），下一轮 play/stop 统一收割。
      _playing = false;
      _paused = false;
      _timer?.cancel();
      _timer = null;
      positionSeconds.value = 0;
      onEnded?.call();
    }
  }

  @override
  void pause() {
    if (!_playing || _paused) return;
    _pausedAt = positionSeconds.value;
    _killVoices();
    _timer?.cancel();
    _timer = null;
    _paused = true;
  }

  @override
  void resume() {
    if (!_playing || !_paused) return;
    // 时间轴零点搬到现在-暂停点：调度与位置读数无缝续走。
    _t0 =
        _sound.engineNow() - Duration(microseconds: (_pausedAt * 1e6).round());
    // 指针回卷：暂停时窗口内已排事件被切，恢复需从暂停点起重排。
    while (_pointer > 0 && _pending[_pointer - 1].time >= _pausedAt - 1e-9) {
      _pointer--;
    }
    _paused = false;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => onTick());
  }

  @override
  Future<void> stop() async {
    _gen++;
    _timer?.cancel();
    _timer = null;
    _playing = false;
    _paused = false;
    _pending.clear();
    _pointer = 0;
    positionSeconds.value = 0;
    _killVoices();
  }

  /// 停掉全部活动句柄（预调度中 + 余振）。已自然失效的句柄跳过。
  void _killVoices() {
    final voices = List.of(_voices);
    _voices.clear();
    for (final h in voices) {
      if (_sound.getIsValidVoiceHandle(h)) {
        unawaited(_sound.stop(h)); // native 立即生效，Future 仅回执
      }
    }
  }

  double _positionSeconds() {
    final raw = (_sound.engineNow().inMicroseconds - _t0.inMicroseconds) / 1e6;
    return raw < 0 ? 0 : raw;
  }
}

/// 解析期事件：src 在预载后回填；调度期按 time 升序走指针。
class _PendingEvent {
  _PendingEvent(
      {required this.time,
      required this.file,
      required this.speed,
      required this.muted,
      required this.noteSeconds});
  final double time;
  final String file;
  final double speed;
  final bool muted;
  final double noteSeconds; // 采样时长限制（音符时值+0.15s 余振）
  AudioSource? src;
}
