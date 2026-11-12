import 'dart:async';
import 'dart:math' as math;

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
  // 各小节实际拍数（2026-11-10 pickup 修复；下标=线性小节号）。
  List<int> _beatsOfMeasures = const [];
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
    final mIdx = playbackOrderMeasures[k];
    // 小节级拍数（pickup 修复：返回线性拍按各小节实际宽度累计）。
    final barBeats =
        _beatsOfMeasures.length > mIdx && mIdx >= 0
            ? _beatsOfMeasures[mIdx]
            : _beatsPerBar;
    final inMeasure =
        (playBeat - playbackOrderStarts[k]).clamp(0.0, barBeats.toDouble());
    // 线性谱面拍位 = 线性小节序 × 基准拍数 + 小节内偏移（近似映射，
    // 供 TabView 播放头；1/4 pickup 小节按 1 拍计）。
    var linearBars = 0;
    for (var i = 0; i < mIdx; i++) {
      linearBars += _beatsOfMeasures.length > i
          ? _beatsOfMeasures[i]
          : _beatsPerBar;
    }
    return linearBars.toDouble() + inMeasure;
  }

  /// 线性小节+拍位 → 展开轴起播秒（点音起播；精确到点击音符——2026-11-03
  /// 走查修正：小节首次遍次起点 + 小节内拍偏移，原小节粒度版本停止后
  /// 点音总是回小节开头）。
  @override
  double? startSecondsForBeat(int measureIndex, double beat) {
    if (playbackOrderMeasures.isEmpty || _beatSeconds == 0) return null;
    final k = playbackOrderMeasures.indexOf(measureIndex);
    if (k < 0) return null;
    return (playbackOrderStarts[k] + beat) * _beatSeconds;
  }

  /// 活动滑音 ramp（handle → PitchShift 逐 tick 推进）。
  final List<_SlideRamp> _slides = [];
  final List<_VolumeRamp> _volumeRamps = [];

  /// 滑音 ramp 推进（50ms 步进，pitchShift 保时长只变音高）。
  void _advanceSlides() {
    if (_slides.isEmpty) return;
    _slides.removeWhere((s) {
      // 句柄已失效（播完/被切）：直接清除。
      if (!_sound.getIsValidVoiceHandle(s.handle)) return true;
      s.step++;
      if (s.pingpong) {
        // 揉弦往复（三角波循环）：from→to→from 循环推进，音结束才清。
        final cycle = s.steps * 2;
        final t = (s.step % cycle) / s.steps; // 0..2
        final v = t <= 1 ? t : 2 - t; // 三角 0..1..0
        _sound.setPitchShift(
            s.src, s.handle, s.from + (s.to - s.from) * v);
        return false;
      }
      final t = s.step / s.steps;
      final v = s.from + (s.to - s.from) * t;
      _sound.setPitchShift(s.src, s.handle, v);
      return s.step >= s.steps; // ramp 完成后保持终值到 voice 自然结束
    });
  }

  /// 音量 ramp 推进（FadeIn/FadeOut；50ms 步进，到位即移除）。
  void _advanceVolumeRamps() {
    if (_volumeRamps.isEmpty) return;
    _volumeRamps.removeWhere((r) {
      r.step++;
      final t = (r.step / r.steps).clamp(0.0, 1.0);
      _sound.setVoiceVolume(r.handle, r.from + (r.to - r.from) * t);
      return r.step >= r.steps;
    });
  }

  /// 变速：播放/暂停中重锚时间轴保持当前位置；未播放直接生效。
  /// 变速（2026-11-10 实时变速重构）：时间轴重锚 + **声部速率同步**
  /// ——scale 传 e.speed×_rate（采样变速自然变调，gp8 同行为；注释中
  /// "天然保调"的旧复核结论是错的：scale 恒 1 时采样原速播，调度时刻
  /// 压缩只造成提前结束，速率从未变化）。KS 降级路径由上层重渲染接续。
  void setRate(double r) {
    // 先算再设：pos 是变速后秒（_positionSeconds ÷ 旧 rate）；换挡后零点
    // 以旧轴 pos 重锚（_t0 = now - pos×新rate），听感连续（2026-11-11
    // 根因修复的轴一致化）。
    final pos = _playing ? _positionSeconds() : (_pendingSeek ?? 0);
    _rate = r.clamp(0.25, 3.0);
    if (_playing) {
      _reanchor(pos, keepPause: _paused);
    } else {
      _pendingSeek = pos;
    }
    // duration 轴同步（2026-11-11）：pos 是变速后秒（连续轴），时长
    // 以新 rate 换算——变速中/后 onTick 的曲终判定两轴一致。
    durationSeconds = _rawDurationSeconds / _rate + 1.2;
  }

  /// 时间轴重锚：当前位置 [pos]（变速后秒）不变，零点/指针重排。
  /// [keepPause] 暂停中只重排暂停点（恢复时按新零点续走）。
  void _reanchor(double pos, {required bool keepPause}) {
    _killVoices(); // 现场 + 预调度声部全切（重排后重调度）
    if (keepPause) {
      _pausedAt = pos;
      // 暂停态 seek 播放头即时跟随（2026-11-04 用户实测实锤：点音定位
      // 后 positionSeconds 留在旧暂停点——用户暂停时机常在小节边界附近，
      // 看上去就是"跳到前一小节最后位置"；恢复播放前的 UI 全错）。
      positionSeconds.value = pos;
    } else {
      // 轴一致（2026-11-11）：pos 变速后秒，_t0 = now - pos×rate。
      _t0 = _sound.engineNow() -
          Duration(microseconds: (pos * _rate * 1e6).round());
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
      // 重锚后读回（2026-11-11）：onTick 内部曲终判定/AB 检查都
      // 用 _positionSeconds()，确保 notifier 与轴一致（变速后
      // _t0 已按新 rate 重设，读回即 pos）。
      positionSeconds.value = _positionSeconds();
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
      // 轴一致（2026-11-11）：_positionSeconds = 引擎流逝/rate——
      // _t0 = now - seek×rate 使其读回 seek（变速后秒）。
      _t0 = _sound.engineNow() -
          Duration(microseconds: (seek * _rate * 1e6).round());
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
    final globalBeats =
        int.tryParse(ir.timeSignature.split('/')[0]) ?? 4;
    _beatsPerBar = globalBeats;
    // 各小节实际拍数（2026-11-10 Flower 1/4 pickup 修复：小节级拍号
    // 参与，展开时间轴累计不再按全局 4/4 错位）。
    final beatsOf = [
      for (final m in ir.tracks.first.measures)
        m.timeSignature == null
            ? globalBeats
            : (int.tryParse(m.timeSignature!.split('/')[0]) ?? globalBeats),
    ];
    _beatsOfMeasures = beatsOf;
    final beatSeconds = 60.0 / ir.tempo;
    _beatSeconds = beatSeconds;
    final measures = ir.tracks.first.measures;
    final order = expandMeasures(measures);
    // 展开序各元素起始拍（播放头反查用）：逐元素按其**小节实际拍数**
    // 累计（pickup 1/4 小节只占 1 拍）。
    final starts = <double>[];
    var acc = 0.0;
    for (var k = 0; k < order.length; k++) {
      starts.add(acc);
      acc += beatsOf[order[k]].toDouble();
    }
    playbackOrderStarts
      ..clear()
      ..addAll(starts);
    playbackOrderMeasures
      ..clear()
      ..addAll(order);
    var endBeat = 0.0;
    // 交替拨弦（2026-11-01 技法音效）：同弦出音轮换 Up/Down 层。
    final strokeFlip = <int, bool>{};
    for (var k = 0; k < order.length; k++) {
      final m = measures[order[k]];
      final baseBeat = starts[k]; // 小节级拍数累计（pickup 修复）
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
              downstroke: down,
              // 泛音偏移交给采样库（强制真泛音采样 + speed 移调，
              // 2026-11-07：原 pitchFixed 移调叠加拨弦采样，音色与弹奏
              // 无差——用户实测反馈根因）。
              harmonicOffset: n.harmonicOffset);
          if (r == null) continue; // 弦号越界的坏数据：跳过该音
          // 展开序拍位（反复第二遍的同一小节播在后续时间轴上）。
          final absBeat = baseBeat + n.beat;
          // 采样时长 = 音符时值 + 极短余振（0.08s，2026-10-31 二轮收窄：
          // 0.15s 在 82bpm 快速指弹中仍叠出"抢拍"感）。
          var noteSeconds = n.duration * beatSeconds + 0.08;
          // 力度（2026-11-01 技法音效，GP8 无独立采样靠力度近似——其
          // 内部同为采样+处理）：击勾端弱击 0.75、闷音暗弱 0.7。
          var volume = (n.hopoEnd || n.hopoStart)
              ? 0.75
              : (n.technique == 'x' ? 0.7 : 1.0);
          // 符号播放映射（2026-11-04 gp8 对照补完）：
          // - Ghost 幽灵音 = 极弱（GP8 ~0.3-0.5 力度带）
          // - Accent 重音 = 强调（在 Dynamic/Velocity 基础上再抬）
          if (n.ghost) volume *= 0.4;
          if (n.accent) volume *= 1.15;
          // 时值截短（gp8 同款发声行为）：
          // - Staccato 断音 = 时值减半（留空拍感）
          // - Grace 装饰音 = 极短一闪（~30-40ms 量级）
          if (n.staccato) noteSeconds *= 0.5;
          if (n.grace) noteSeconds *= 0.12;
          // Dynamic 力度映射（2026-11-02 gp8 播放复刻）：力度记号影响
          // 发声音量（GP8 同款——ff 到 pp 的 MIDI 力度带）。
          volume *= _dynamicVolume(n.dynamicMark);
          // Note Velocity（MIDI 0-127）：线性映射夹 0.35-1.0。
          if (n.velocity != null) {
            volume *= ((n.velocity! / 127.0) * 0.65 + 0.35)
                .clamp(0.35, 1.0);
          }
          // 震音拨（2026-11-02 gp8 播放复刻）：该音符时值内按 32 分
          //（0.125 拍）快速重复发声（首音满时值，其余短音衰减）。
          if (n.tremolo && n.duration > 0.15) {
            const step = 0.125;
            var t = n.beat;
            var k = 0;
            while (t < n.beat + n.duration - 1e-9) {
              final seg = k == 0 ? step : step; // 等长 32 分颗粒
              _pending.add(_PendingEvent(
                  time: (baseBeat + t) * beatSeconds,
                  file: r.file,
                  speed: r.speed,
                  muted: n.technique == 'x',
                  noteSeconds: seg * beatSeconds + 0.08,
                  volume: volume * (k == 0 ? 1.0 : 0.8),
                  slide: false,
                  string: n.string,
                  absBeat: baseBeat + t));
              t += seg;
              k++;
            }
            final e2 = baseBeat + n.beat + n.duration;
            if (e2 > endBeat) endBeat = e2;
            continue;
          }
          // 颤音 Trill（2026-11-04 gp8 对照补完）：32 分与上方大二度
          //（2 半音，GP8 默认交替音程）快速交替——奇数粒固定移调
          //（PitchShift 恒定，非 ramp）。曲库样本无 Trill 数据（探针
          // 实锤），交替音程/速度按 GP8 默认，待真实谱校准。
          if (n.trill && n.duration > 0.15) {
            const step = 0.125;
            var t = n.beat;
            var k = 0;
            while (t < n.beat + n.duration - 1e-9) {
              final e = _PendingEvent(
                  time: (baseBeat + t) * beatSeconds,
                  file: r.file,
                  speed: r.speed,
                  muted: n.technique == 'x',
                  noteSeconds: step * beatSeconds + 0.08,
                  volume: volume * (k.isEven ? 1.0 : 0.85),
                  slide: false,
                  string: n.string,
                  absBeat: baseBeat + t);
              if (k.isOdd) e.pitchFixed = 2.0; // 交替粒 +2 半音
              _pending.add(e);
              t += step;
              k++;
            }
            final e3 = baseBeat + n.beat + n.duration;
            if (e3 > endBeat) endBeat = e3;
            continue;
          }
          _pending.add(_PendingEvent(
              time: absBeat * beatSeconds,
              file: r.file,
              speed: r.speed,
              muted: n.technique == 'x',
              noteSeconds: noteSeconds,
              volume: volume,
              slide: n.slide != null,
              string: n.string,
              absBeat: absBeat,
              arpeggio: n.arpeggio,
              brush: n.brush,
              vibrato: n.vibrato,
              fade: n.fadding));
          // 弯音/摇把（2026-11-04 gp8 补完）：bend 曲线首尾优先，
          // 否则拍级摇把 origin→destination。首尾相等（全 0 占位）不挂。
          // 泛音不走 pitchFixed（2026-11-07：音高由泛音采样的 speed 全权
          // 移调——resolve(harmonicOffset) 已覆盖，叠加会双重移调）。
          {
            final pFrom = n.bend != null && n.bend!.isNotEmpty
                ? n.bend!.first.value
                : (n.whammy != null ? n.whammy![0] : null);
            final pTo = n.bend != null && n.bend!.isNotEmpty
                ? n.bend!.last.value
                : (n.whammy != null ? n.whammy![1] : null);
            if (pFrom != null &&
                pTo != null &&
                (pFrom - pTo).abs() > 1e-6) {
              _pending.last.pitchFrom = pFrom;
              _pending.last.pitchTo = pTo;
            }
          }
          final e = absBeat + n.duration;
          if (e > endBeat) endBeat = e;
        }
      // failed 小节：不出音但拍位照占（展开轴连续，静音小节）。
    }
    if (_pending.isEmpty) return false;
    // 延长记号顺延（2026-11-07 gp8 对照补完，月下之恋 8 处真值）：
    // 含 Fermata 的小节，拍位 ≥ offset 的事件（含后续小节——absBeat
    // 单调）time 顺延 length 拍；多记号逐个累计。排序前改 time。
    var fermataExtra = 0.0;
    for (var k = 0; k < order.length; k++) {
      final m = measures[order[k]];
      if (m.fermatas.isEmpty) continue;
      final base = starts[k]; // 小节级拍数累计（pickup 修复）
      for (final fm in m.fermatas) {
        final extra = fm.length * beatSeconds;
        final from = base + fm.beat;
        for (final e in _pending) {
          if (e.absBeat >= from - 1e-9) e.time += extra;
        }
        fermataExtra += extra;
      }
    }
    _pending.sort((a, b) => a.time.compareTo(b.time));
    _staggerArpeggios();
    _attachSlideTargets();
    // 时长含尾音（与渲染器同款 1.2s）：末音采样自然衰减不受限，
    // 越线余振由下一轮 play/stop 收割（见 stop）。变速后秒（rate 换算）；
    // 延长记号的总顺延秒同步计入（rate 换算同式）。
    // 原速轴总时长（2026-11-11 抽出：setRate 时直接换算变速后秒）。
    _rawDurationSeconds = endBeat * beatSeconds + fermataExtra;
    durationSeconds = _rawDurationSeconds / _rate + 1.2;
    return true;
  }

  /// 原速轴总时长（不含 1.2 尾音）：duration = _raw/rate + 1.2。
  double _rawDurationSeconds = 0;

  /// Dynamic 力度记号 → 发声音量系数（GP8 MIDI 力度带惯例）。无记号
  /// 维持原音量 1.0（GP 默认力度=f）；显示层已画行底力度字，此处是发声
  /// 映射。
  static double _dynamicVolume(String? mark) {
    switch (mark) {
      case 'pp':
        return 0.45;
      case 'p':
        return 0.55;
      case 'mp':
        return 0.68;
      case 'mf':
        return 0.85;
      case 'f':
        return 0.92;
      case 'ff':
        return 1.0;
      default:
        return 1.0;
    }
  }

  /// 琶音依次发声（2026-11-02 三期待办，gp8 行为复刻）：琶音不是全部
  /// 同响，而是按方向依次弹出对应琴弦——Up（↑）从低音弦（6）扫向高音
  /// 弦（1），Down 反之。每弦错开 30ms（事件轴原速秒；gp8 听感 20-40ms
  /// 量级）。Beat 级标注挂该拍全部音 → 同 absBeat 的琶音事件为一群。
  void _staggerArpeggios() {
    const step = 0.03;
    const brushStep = 0.015; // 扫弦比琶音更快依次（GP8 听感惯例）
    var i = 0;
    while (i < _pending.length) {
      final e = _pending[i];
      if (e.arpeggio == null && e.brush == null) {
        i++;
        continue;
      }
      // 方向语义（GP8）：琶音 up = 低音弦（6）先响；扫弦 down（向下扫）
      // = 6 弦先响——brush 与 arpeggio 的方向词相反、弦序一致。
      final isDownward =
          e.arpeggio != null ? e.arpeggio == 'up' : e.brush == 'down';
      final stepBeat = e.arpeggio != null ? step : brushStep;
      var j = i;
      while (j < _pending.length &&
          _pending[j].absBeat == e.absBeat &&
          (_pending[j].arpeggio != null || _pending[j].brush != null)) {
        j++;
      }
      final group = _pending.sublist(i, j)
        ..sort((a, b) => isDownward
            ? b.string.compareTo(a.string) // 6 弦先响 → string 降序
            : a.string.compareTo(b.string)); // 1 弦先响
      for (var k = 0; k < group.length; k++) {
        group[k].time += k * stepBeat;
      }
      i = j;
    }
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
    _advanceVolumeRamps();
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
          // 声部播放速率 = 移调值 × 变速率（2026-11-10 实时变速修复：
          // scale 是 soloud 的播放速率——此前只传移调恒 1.0，变速无效
          // 根因。duration 同步按变速率缩短）。
          scale: e.speed * _rate,
          duration: e.muted
              ? Duration(milliseconds: (_mutedSeconds * 1000).round())
              : Duration(
                  microseconds: (e.noteSeconds / _rate * 1e6).round()),
          volume: e.volume,
        );
        _voices.add(h);
        // 颤音 Trill 交替粒：固定移调（恒定 PitchShift，非 ramp）。
        // Trill 交替粒固定移调（basePitch）；其余声部恒 1.0 不移调。
        final basePitch = e.pitchFixed != null
            ? math.pow(2.0, e.pitchFixed! / 12).toDouble()
            : 1.0;
        if (basePitch != 1.0) {
          _sound.setPitchShift(src, h, basePitch);
        }
        // 揉弦：音高 ±0.4 半音三角波往复（~200ms 周期，GP8 木弦幅度
        // 小幅惯例），持续整个音。
        if (e.vibrato) {
          _slides.add(_SlideRamp(
              src: src,
              handle: h,
              from: math.pow(2.0, -0.4 / 12).toDouble(),
              to: math.pow(2.0, 0.4 / 12).toDouble(),
              step: 0,
              steps: 4,
              pingpong: true));
        }
        // 淡入/淡出：音量 ramp 铺满音符时值（in 0.3→v；out v→0.2）。
        if (e.fade != null) {
          _volumeRamps.add(_VolumeRamp(
              handle: h,
              from: e.fade == 'in' ? 0.3 : e.volume,
              to: e.fade == 'in' ? e.volume : 0.2,
              step: 0,
              steps: (e.noteSeconds / _rate * 1000 / 50)
                  .round()
                  .clamp(2, 20)));
        }
        // 滑音起音：注册 PitchShift ramp（终点速度接线过才 ramp）。
        if (e.pitchFrom != null && e.pitchTo != null) {
          // 弯音/摇把（2026-11-04 gp8 补完）：曲线铺满音符时值，
          // 50ms 步进线性推进（多点曲线 v1 以首尾两点近似——真实谱
          // 校准待遇）。半音 → PitchShift 频率比 2^(s/12)。
          final dur = (e.noteSeconds / _rate).clamp(0.1, 2.0);
          final steps = (dur * 1000 / 50).round().clamp(2, 20);
          _slides.add(_SlideRamp(
              src: src,
              handle: h,
              from: math.pow(2.0, e.pitchFrom! / 12).toDouble(),
              to: math.pow(2.0, e.pitchTo! / 12).toDouble(),
              step: 0,
              steps: steps));
        } else if (e.slide && e.slideEndSpeed != null) {
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
    // 时间轴零点搬到现在-暂停点×速率（_positionSeconds 返回
    // 引擎流逝/rate = 变速后秒；_t0 设 now - pausedAt×rate 使其读回
    // pausedAt——2026-11-11 轴一致化）。
    _t0 = _sound.engineNow() -
        Duration(microseconds: (_pausedAt * _rate * 1e6).round());
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
    _slides.clear(); // 滑音/揉弦 ramp 随声部全切
    _volumeRamps.clear(); // 淡入出 ramp 同切
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
    if (raw < 0) return 0;
    // 位置轴（谱面秒 V）：引擎流逝 ÷ 当前 rate——与 duration 同轴
    //（2026-11-11 轴定案：V 连续——变速瞬间数值不变、比例变，因为
    // duration 同步 = raw/rate；此前混轴导致变速后 pos > duration 误判
    // 曲终→播放停止，⑤ 的根因）。
    return raw / _rate;
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
      required this.absBeat,
      this.arpeggio,
      this.brush,
      this.vibrato = false,
      this.fade});
  double time; // 可变：琶音依次发声的错开偏移（事件轴原速秒）
  final String file;
  final double speed;
  final bool muted;
  final double noteSeconds; // 采样时长限制（音符时值+0.15s 余振）
  final double volume; // 力度（击勾弱击/闷音暗音色的力度层用）
  final bool slide; // 滑音起音（起播后 PitchShift ramp 向终点）
  double? slideEndSpeed; // 滑音终点的重移调 speed（_attachSlideTargets 回填）
  final int string;
  final double absBeat;
  final String? arpeggio; // 琶音方向（'up'|'down'，依次发声用）
  final String? brush; // 扫弦方向（'up'|'down'，各弦快速依次发声）
  final bool vibrato; // 揉弦（音高往复循环 ramp）
  final String? fade; // 'in'|'out'（音量渐变 ramp）
  // 弯音/摇把（2026-11-04 gp8 补完）：起止半音（null = 无）。
  // bend（音级曲线首尾）优先于 whammy（拍级 origin→destination）。
  double? pitchFrom;
  double? pitchTo;
  // 颤音 Trill 交替粒的固定移调（半音；恒定 PitchShift 非 ramp）。
  double? pitchFixed;
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
      required this.steps,
      this.pingpong = false});
  final AudioSource src;
  final SoundHandle handle;
  final double from;
  final double to;
  int step;
  final int steps;
  // true = 揉弦往复循环（from→to→from 三角波，音结束才清）。
  final bool pingpong;
}

/// 音量 ramp（FadeIn/FadeOut）：handle 音量 from→to 分 steps 步推进。
class _VolumeRamp {
  _VolumeRamp(
      {required this.handle,
      required this.from,
      required this.to,
      required this.step,
      required this.steps});
  final SoundHandle handle;
  final double from;
  final double to;
  int step;
  final int steps;
}
