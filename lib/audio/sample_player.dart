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

  /// 未播放时的 seek 记忆：play 后从该处起播（点音起播用）。
  double? _pendingSeek;

  // —— 跟练三件套（2026-11-01 走查定案：变速 + AB 循环；多音轨指弹用不上）——

  /// 速度倍率（1.0 = 原速）。事件时间轴（_pending.time）始终是**原速秒**，
  /// 调度/位置读数按 rate 换算：engine 时刻 = t0 + time/rate，
  /// 位置 = (now-t0)。变速即重锚时间轴（保持当前位置无缝续走）。
  double _rate = 1.0;
  @override
  double get rate => _rate;
  @override
  set rate(double r) => setRate(r);

  /// AB 循环区间（变速后秒，null = 未设）。pos ≥ b 时重锚回 a。
  @override
  double? loopA;
  @override
  double? loopB;

  // 反复展开（2026-11-02 GP8 复刻）：播放序元素起始拍 + 对应线性小节，
  // 播放头反查谱面位置用。
  final List<double> playbackOrderStarts = [];
  final List<int> playbackOrderMeasures = [];
  int _beatsPerBar = 4;
  double _beatSeconds = 0;

  /// 展开时间轴拍位 → 线性谱面拍位（播放头定位）。无展开结构时 null
  ///（调用方走原式）。
  @override
  double? linearBeatAt(double playBeat) {
    if (playbackOrderMeasures.isEmpty) return null;
    var k = playbackOrderStarts.length - 1;
    while (k > 0 && playbackOrderStarts[k] > playBeat + 1e-9) {
      k--;
    }
    final inMeasure = (playBeat - playbackOrderStarts[k])
        .clamp(0.0, _beatsPerBar.toDouble());
    return playbackOrderMeasures[k] * _beatsPerBar + inMeasure;
  }

  /// 线性小节 → 展开轴起播秒（点音起播；该小节首次出现的遍次）。
  @override
  double? startSecondsForMeasure(int measureIndex) {
    if (playbackOrderMeasures.isEmpty || _beatSeconds == 0) return null;
    final k = playbackOrderMeasures.indexOf(measureIndex);
    if (k < 0) return null;
    return playbackOrderStarts[k] * _beatSeconds;
  }

  /// 活动滑音 ramp（handle → PitchShift 逐 tick 推进）。
  final List<_SlideRamp> _slides = [];

  /// 滑音 ramp 推进（50ms 步进，pitchShift 保时长只变音高）。
  void _advanceSlides() {
    if (_slides.isEmpty) return;
    _slides.removeWhere((s) {
      // 句柄已失效（播完/被切）：直接清除。
      if (!_sound.getIsValidVoiceHandle(s.handle)) return true;
      s.step++;
      final t = s.step / s.steps;
      final v = s.from + (s.to - s.from) * t;
      _sound.setPitchShift(s.src, s.handle, v);
      return s.step >= s.steps; // ramp 完成后保持终值到 voice 自然结束
    });
  }

  /// 变速：播放/暂停中重锚时间轴保持当前位置；未播放直接生效。
  void setRate(double r) {
    final pos = _playing ? _positionSeconds() : (_pendingSeek ?? 0);
    _rate = r.clamp(0.25, 3.0);
    if (_playing) {
      _reanchor(pos, keepPause: _paused);
    } else {
      _pendingSeek = pos;
    }
  }

  /// 时间轴重锚：当前位置 [pos]（变速后秒）不变，零点/指针重排。
  /// [keepPause] 暂停中只重排暂停点（恢复时按新零点续走）。
  void _reanchor(double pos, {required bool keepPause}) {
    _killVoices(); // 现场 + 预调度声部全切（重排后重调度）
    if (keepPause) {
      _pausedAt = pos;
    } else {
      _t0 = _sound.engineNow() -
          Duration(microseconds: (pos * 1e6).round());
    }
    final rawPos = pos * _rate; // 事件轴（原速秒）
    while (_pointer > 0 && _pending[_pointer - 1].time >= rawPos - 1e-9) {
      _pointer--;
    }
    while (_pointer < _pending.length &&
        _pending[_pointer].time < rawPos - 1e-9) {
      _pointer++;
    }
    if (!keepPause) {
      positionSeconds.value = pos;
      onTick(); // 立即调度 pos 起的音（不等 50ms tick）
    }
  }

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
      // PitchShift 滤镜激活（source 级一次性，滑音 ramp 用；未设句柄
      // shift 默认 1.0 = 不移调，非滑音 voice 无感）。
      _sound.activatePitchShift(src);
    }

    _sound.setMaxActiveVoiceCount(64);
    // 未播放时的 seek 记忆（点音起播）：时间轴零点前移到起点，
    // 指针跳过起点前的事件。
    final seek = _pendingSeek;
    _pendingSeek = null;
    if (seek != null) {
      _t0 = _sound.engineNow() -
          Duration(microseconds: (seek * 1e6).round());
      // 事件轴原速秒 = 变速后秒 × rate。
      final rawSeek = seek * _rate;
      while (_pointer < _pending.length &&
          _pending[_pointer].time < rawSeek - 1e-9) {
        _pointer++;
      }
    } else {
      _t0 = _sound.engineNow();
    }
    _playing = true;
    _paused = false;
    _pausedAt = 0;
    onTick(); // 立即调度开头的音，不等首个 tick（50ms 延迟可闻）
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => onTick());
    return true;
  }

  /// IR → 事件 + 时长。失败（调弦解析/空事件）返回 false。
  /// 播放按 **反复展开序列**（expandMeasures，2026-11-02 GP8 复刻）：
  /// 曲内反复跳回、结尾按遍数走向；时间轴 = 展开序累计拍位。
  bool _collectEvents(ScoreIr ir) {
    _pending.clear();
    if (ir.tuning.length != 6) return false; // 钢弦采样库按 6 弦录制
    final tunings = [for (final s in ir.tuning) Note.parse(s)];
    final beatsPerBar = int.tryParse(ir.timeSignature.split('/')[0]) ?? 4;
    _beatsPerBar = beatsPerBar;
    final beatSeconds = 60.0 / ir.tempo;
    _beatSeconds = beatSeconds;
    final measures = ir.tracks.first.measures;
    final order = expandMeasures(measures);
    // 展开序各元素起始拍（播放头反查用）。
    playbackOrderStarts
      ..clear()
      ..addAll([for (var k = 0; k < order.length; k++) k * beatsPerBar.toDouble()]);
    playbackOrderMeasures
      ..clear()
      ..addAll(order);
    var endBeat = 0.0;
    // 交替拨弦（2026-11-01 技法音效）：同弦出音轮换 Up/Down 层。
    final strokeFlip = <int, bool>{};
    for (var k = 0; k < order.length; k++) {
      final m = measures[order[k]];
      final baseBeat = k * beatsPerBar.toDouble();
      for (final n in m.notes) {
          if (n.tieEnd) continue; // tie 续接端不出音（时长已累计回链首）
          // 弦号映射与渲染器同款：string 1（最细）→ tunings[5]；
          // 发声 MIDI 按通道语义（渲染器同款 capoApplied 公式）：
          // gpx=绝对品（+capo）、AI=夹后品（已含不补）。
          final capoShift = ir.capoApplied ? 0 : ir.capo;
          final soundingMidi =
              tunings[6 - n.string].midi + capoShift + n.fret;
          final down = !(strokeFlip[n.string] ?? false);
          strokeFlip[n.string] = down;
          final r = SteelSampleBank.resolve(
              string: n.string,
              fret: n.fret,
              soundingMidi: soundingMidi,
              technique: n.technique,
              downstroke: down);
          if (r == null) continue; // 弦号越界的坏数据：跳过该音
          // 展开序拍位（反复第二遍的同一小节播在后续时间轴上）。
          final absBeat = baseBeat + n.beat;
          // 采样时长 = 音符时值 + 极短余振（0.08s，2026-10-31 二轮收窄：
          // 0.15s 在 82bpm 快速指弹中仍叠出"抢拍"感）。
          final noteSeconds = n.duration * beatSeconds + 0.08;
          // 力度（2026-11-01 技法音效，GP8 无独立采样靠力度近似——其
          // 内部同为采样+处理）：击勾端弱击 0.75、闷音暗弱 0.7。
          final volume = (n.hopoEnd || n.hopoStart)
              ? 0.75
              : (n.technique == 'x' ? 0.7 : 1.0);
          _pending.add(_PendingEvent(
              time: absBeat * beatSeconds,
              file: r.file,
              speed: r.speed,
              muted: n.technique == 'x',
              noteSeconds: noteSeconds,
              volume: volume,
              slide: n.slide != null,
              string: n.string,
              absBeat: absBeat));
          final e = absBeat + n.duration;
          if (e > endBeat) endBeat = e;
        }
      // failed 小节：不出音但拍位照占（展开轴连续，静音小节）。
    }
    if (_pending.isEmpty) return false;
    _pending.sort((a, b) => a.time.compareTo(b.time));
    _attachSlideTargets();
    // 时长含尾音（与渲染器同款 1.2s）：末音采样自然衰减不受限，
    // 越线余振由下一轮 play/stop 收割（见 stop）。变速后秒（rate 换算）。
    durationSeconds = endBeat * beatSeconds / _rate + 1.2;
    return true;
  }

  /// 滑音接线（2026-11-01 技法音效）：slide 起音事件补终点速度——
  /// **播放序**（排序后的 _pending）中同弦下一个出音事件的 speed。
  /// 起音按起点音高起播（scale = 起点 speed），起播后 PitchShift 逐
  /// tick 从 1.0 ramp 到 终/起 比率，音高连续滑向终点（pitchShift 保
  /// 时长）。展开序下第二遍的滑音同样自然接线。
  void _attachSlideTargets() {
    for (var i = 0; i < _pending.length; i++) {
      final e = _pending[i];
      if (!e.slide) continue;
      for (var j = i + 1; j < _pending.length; j++) {
        if (_pending[j].string == e.string) {
          e.slideEndSpeed = _pending[j].speed;
          break;
        }
      }
    }
  }

  /// 50ms tick 一步。公开为可直测（Timer 周期在测试里难控）。
  @visibleForTesting
  void onTick() {
    if (!_playing || _paused) return;
    _advanceSlides();
    final pos = _positionSeconds();
    // AB 循环（2026-11-01 跟练）：越 B 点重锚回 A（A/B 均设才生效）。
    final a = loopA, b = loopB;
    if (a != null && b != null && b > a && pos >= b) {
      _reanchor(a, keepPause: false);
      return;
    }
    // 前瞻调度：窗口内事件全部钉到引擎时钟（事件轴原速秒 → engine 时刻
    // = t0 + time/rate）。
    final rawHorizon = (pos + _horizonSeconds) * _rate;
    while (_pointer < _pending.length && _pending[_pointer].time <= rawHorizon) {
      final e = _pending[_pointer];
      _pointer++;
      final src = e.src;
      if (src == null) continue; // 理论不可达：play 已确保全部预载
      try {
        final h = _sound.scheduleAt(
          src,
          atTime: _t0 +
              Duration(microseconds: (e.time / _rate * 1e6).round()),
          scale: e.speed,
          duration: e.muted
              ? Duration(milliseconds: (_mutedSeconds * 1000).round())
              : Duration(
                  microseconds: (e.noteSeconds / _rate * 1e6).round()),
          volume: e.volume,
        );
        _voices.add(h);
        // 滑音起音：注册 PitchShift ramp（终点速度接线过才 ramp）。
        if (e.slide && e.slideEndSpeed != null) {
          final steps =
              ((e.noteSeconds / _rate).clamp(0.08, 0.45) * 1000 / 50)
                  .round()
                  .clamp(2, 9);
          _slides.add(_SlideRamp(
              src: src,
              handle: h,
              from: 1.0,
              to: e.slideEndSpeed! / e.speed,
              step: 0,
              steps: steps));
        }
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

  /// 定位（2026-11-01 走查：进度条拖动 + 点音起播）。三种态：
  /// - 播放中：切现场声部，时间轴零点重锚到 [s]，指针重排到 s 后首事件
  /// - 暂停中：同播放中重排（暂停点更新为 s，恢复即从 s 续）
  /// - 未播放：记住起点，play 后从该处起播
  @override
  Future<void> seekToSecond(double s) async {
    final clamped = s.clamp(0.0, durationSeconds).toDouble();
    if (!_playing) {
      _pendingSeek = clamped;
      return;
    }
    _reanchor(clamped, keepPause: _paused);
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
    // 指针回卷：暂停时窗口内已排事件被切，恢复需从暂停点起重排
    //（事件轴原速秒 = 变速后秒 × rate）。
    final rawPos = _pausedAt * _rate;
    while (_pointer > 0 && _pending[_pointer - 1].time >= rawPos - 1e-9) {
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
    _pendingSeek = null; // 停止=回开头，清未生效的 seek 记忆
    positionSeconds.value = 0;
    _killVoices();
  }

  /// 停掉全部活动句柄（预调度中 + 余振）。已自然失效的句柄跳过。
  void _killVoices() {
    _slides.clear(); // 滑音 ramp 随声部全切
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
      required this.noteSeconds,
      this.volume = 1,
      this.slide = false,
      required this.string,
      required this.absBeat});
  final double time;
  final String file;
  final double speed;
  final bool muted;
  final double noteSeconds; // 采样时长限制（音符时值+0.15s 余振）
  final double volume; // 力度（击勾弱击/闷音暗弱）
  final bool slide; // 滑音起音（起播后 PitchShift ramp 向终点）
  double? slideEndSpeed; // 滑音终点的重移调 speed（_attachSlideTargets 回填）
  final int string;
  final double absBeat;
  AudioSource? src;
}

/// 滑音 ramp：handle 的 PitchShift 从 from 到 to 分 steps 步推进。
class _SlideRamp {
  _SlideRamp(
      {required this.src,
      required this.handle,
      required this.from,
      required this.to,
      required this.step,
      required this.steps});
  final AudioSource src;
  final SoundHandle handle;
  final double from;
  final double to;
  int step;
  final int steps;
}
