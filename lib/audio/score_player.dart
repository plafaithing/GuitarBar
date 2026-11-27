import 'dart:async';

import 'package:flutter/foundation.dart';
// AudioSource/SoundHandle 类型来自 soloud 包（sound_engine 未重导出）。
import 'package:flutter_soloud/flutter_soloud.dart';

import 'score_renderer.dart';
import 'sound_engine.dart';

/// 两条播放路径（离线 PCM / 实时采样）的公共面：页面 UI 只看这组成员。
/// 实现方：ScorePlayer（整曲 PCM）与 SampleScorePlayer（逐音采样调度）。
abstract interface class ScorePlayback {
  bool get playing;
  bool get paused;
  double get durationSeconds;
  ValueNotifier<double> get positionSeconds;
  void pause();
  void resume();
  Future<void> stop();

  /// 定位到 [s] 秒（2026-11-01 走查：进度条拖动 + 点音起播）：
  /// 播放中即时跳转（现场声部切清重排），未播放则记住起点、start 后生效。
  Future<void> seekToSecond(double s);

  /// 速度倍率（2026-11-01 跟练三件套：0.25-3.0，1.0 = 原速）。
  double get rate;
  set rate(double r);

  /// AB 循环区间（秒；任一为 null = 不循环）。pos ≥ b 时重锚回 a。
  double? get loopA;
  double? get loopB;
  set loopA(double? v);
  set loopB(double? v);

  /// 渐进提速（2026-11-23 跟练）：AB 循环每 3 遍 rate +5% 直到 1.0
  /// 自动停。**仅 sample 路径生效**——KS 变速走声部级/重渲染（渐进
  /// 的中途换挡无法无缝），字段仅供 UI 状态一致；KS 下置位无行为。
  bool get progressiveOn;
  set progressiveOn(bool v);

  /// 渐进自动提速回调（每档触发；UI 显示「提速至 x.xx」用）。KS 不触发。
  void Function(double newRate)? onAutoRate;

  /// 反复展开（2026-11-02 制谱基准 复刻）：展开时间轴拍位 → 线性谱面拍位
  ///（播放头定位）。无反复结构的谱返回 null（调用方走原式换算）。
  double? linearBeatAt(double playBeat);

  /// 线性小节+拍位 → 展开时间轴上的起播秒（点音起播用：精确定位到点击
  /// 音符——小节首次遍次起点 + 小节内拍偏移；2026-11-03 走查修正，原
  /// 小节粒度版本在停止后点音总是回小节开头）。无展开结构返回 null。
  double? startSecondsForBeat(int measureIndex, double beat);

  /// 播放轴秒 → 展开拍位（[startSecondsForBeat] 的逆映射）。**页面层的
  /// 播放头 / 插针 / AB 标记统一走这里，不许自己 `秒 ÷ 拍长`**：音频
  /// 时间轴并不恒等于"拍位 × 拍长"——采样路径有延长记号顺延，页面层
  /// 自行线性换算会每过一个延长号就超前一拍左右，越往后累积越多
  /// （2026-11-27 用户实测"指针比发音快一到两个音"根因）。
  double playBeatAt(double seconds);
}

/// 自动演奏播放：渲染 PCM → loadPcm → play。
/// 位置轮询仅供 UI 播放头（与节拍器同思路，不影响音频精度）。
/// 渲染耗时 ~0.3-1s（真实谱）：调用方负责忙碌反馈（Task 15 备案）。
class ScorePlayer implements ScorePlayback {
  ScorePlayer(this._sound, {this.onEnded});
  final SoundEngine _sound;

  /// 曲终回调：tick 检测到 soloud 句柄失效（自然播完）时触发，
  /// 此时播放态已同步清理（playing=false、position=0）。
  final void Function()? onEnded;

  AudioSource? _src;
  SoundHandle? _handle;
  Timer? _timer;

  /// 位置刷新 ticker（2026-11-24 播放头卡顿自检）：主 tick 50ms 承担
  /// 曲终检测/AB/渐进——跟随针以 20fps 跳动=用户感知"卡顿错觉"。
  /// 16ms 独立轻刷（仅 positionSeconds，无调度），播放头 60fps 平滑。
  Timer? _posTimer;

  /// 未播放时的 seek 记忆：start 后立即定位到该处（点音起播用）。
  double? _pendingSeek;

  // —— 跟练：变速 + AB（KS 路径的变速在下次 start 生效——重渲染需
  // Isolate 级重算，降级路径少用不做在线重锚；AB 走 position 轮询截断）。
  double _rate = 1.0;
  @override
  double get rate => _rate;
  @override
  set rate(double r) {
    // KS 实时变速（2026-11-11 用户"变速停止从头播放"根因修复）：旧实现
    // 依赖上层 stop → renderScore(rate) → start → seek（0.3-1s 阻塞 +
    // seek 轴错位 → 听感"停了从头播"）。改为声部级 setRelativePlaySpeed
    // ——soloud 句柄实时变速（自然变调），position 由引擎按新速率推进，
    // onTick 直接读取自洽。播放/暂停/未播三态都即时生效。
    _rate = r.clamp(0.25, 3.0);
    // 手动调整到 ≥1.0：渐进停止增加（用户语义 2026-11-23；渐进自身
    // 提到 1.0 也走此 setter 同样停）。
    if (_rate >= 1.0 - 1e-9) _progOn = false;
    final h = _handle;
    if (h != null) {
      _sound.setVoiceSpeed(h, _rate);
    }
    // duration 是 PCM 固定长度（渲染时定），不随 rate 变——进度条
    // 比例自然变化（同轴：媒体秒）。
  }

  double? _loopA;
  @override
  double? get loopA => _loopA;
  @override
  set loopA(double? v) => _loopA = v;

  double? _loopB;
  @override
  double? get loopB => _loopB;
  @override
  set loopB(double? v) => _loopB = v;

  // 渐进提速（2026-11-23 补齐到 KS）：用户实测反馈"1.00x 不降、3 遍
  // 不停"——KS 降级路径此前空转。KS 的变速已是声部级实时变速（可无
  // 缝换挡），渐进补齐同款逻辑（边界计数在 onTick AB 分支）。
  bool _progOn = false;
  int _progCount = 0;
  @override
  bool get progressiveOn => _progOn;
  @override
  set progressiveOn(bool v) {
    _progOn = v;
    _progCount = 0;
    // 开启时若已是原速 → 主动降速起步 0.75（sample 路径同款语义）。
    if (v && _rate >= 1.0 - 1e-9) rate = 0.75;
  }
  @override
  void Function(double newRate)? onAutoRate;

  // 反复展开反查表（KS 路径；load 时由 renderScore 展开序填充由外部）。
  @override
  double? linearBeatAt(double playBeat) {
    final order = lastOrder, starts = lastOrderStarts;
    if (order == null || starts == null || order.isEmpty) {
      // **无反复结构的谱**（renderScore 不填展开元数据）：展开轴 = 线性
      // 轴 1:1——直接返回输入拍位（2026-11-23 用户实证：LSA 选 AB 无
      // 插针——此前 null → AB 谱面标记条件不成立）。
      return playBeat;
    }
    var k = starts.length - 1;
    while (k > 0 && starts[k] > playBeat + 1e-9) {
      k--;
    }
    // 四分拍口径（2026-11-19 Prologue 根治：per-measure 表优先——
    // X/8 拍号与变拍号此前按全局分子近似错拍；表缺省回全局口径）。
    final barBeats = lastBarBeats;
    final mIdx = order[k];
    final thisBar = (barBeats != null && mIdx >= 0 && mIdx < barBeats.length)
        ? barBeats[mIdx]
        : beatsPerBarCache;
    final inMeasure = (playBeat - starts[k]).clamp(0.0, thisBar);
    var linear = 0.0;
    for (var i = 0; i < mIdx; i++) {
      linear += (barBeats != null && i < barBeats.length)
          ? barBeats[i]
          : beatsPerBarCache;
    }
    return linear + inMeasure;
  }

  /// renderScore 展开元数据（load 时从 RenderedScore 复制）。
  List<int>? lastOrder;
  List<double>? lastOrderStarts;
  List<double>? lastBarBeats;
  double beatsPerBarCache = 4;
  double _tempo = 90;

  /// 线性小节 → 展开轴起播秒（点音起播；该小节首次出现的遍次）。
  @override
  double? startSecondsForBeat(int measureIndex, double beat) {
    final order = lastOrder, starts = lastOrderStarts;
    if (order == null || starts == null || order.isEmpty) return null;
    final k = order.indexOf(measureIndex);
    if (k < 0) return null;
    return (starts[k] + beat) * 60.0 / _tempo;
  }

  /// KS 路径的整曲 PCM 时间轴 = 拍位 × 拍长（无延长记号顺延）→ 线性。
  @override
  double playBeatAt(double seconds) => seconds * _tempo / 60.0;

  @override
  double durationSeconds = 0;
  @override
  final ValueNotifier<double> positionSeconds = ValueNotifier(0);
  @override
  bool get playing => _handle != null;

  /// 暂停中（playing 仍为 true：句柄活着，soloud 冻结在暂停点）。
  bool _paused = false;
  @override
  bool get paused => _paused;

  /// 暂停：soloud setPause(true)，50ms 轮询继续但 position 冻结在暂停点。
  /// 暂停态的句柄不会自然失效（voice 未销毁），曲终检测不受影响。
  @override
  void pause() {
    final h = _handle;
    if (h == null || _paused) return;
    _sound.setPause(h, true);
    _paused = true;
  }

  /// 恢复：从暂停点继续播。
  @override
  void resume() {
    final h = _handle;
    if (h == null || !_paused) return;
    _sound.setPause(h, false);
    _paused = false;
  }

  Future<void> load(RenderedScore r) async {
    await stop();
    _src = await _sound.loadPcm(r.pcm);
    // 加载成功才定长：loadPcm 失败时不留脏时长。
    durationSeconds = r.seconds;
    // 反复展开元数据（播放头反查；renderScore 无结构谱为 null）。
    lastOrder = r.order;
    lastOrderStarts = r.orderStarts;
    lastBarBeats = r.barBeatsQuarter;
    beatsPerBarCache = r.beatsPerBar;
    _tempo = r.tempo;
  }

  Future<void> start() async {
    final src = _src;
    if (src == null || _handle != null) return;
    _handle = _sound.play(src);
    // 未播放时的 seek 记忆（点音起播）：起播后立即定位。
    final seek = _pendingSeek;
    if (seek != null) {
      _pendingSeek = null;
      await seekToSecond(seek);
    }
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => onTick());
    _posTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final h = _handle;
      if (h == null || !_sound.getIsValidVoiceHandle(h)) return;
      final pos = _sound.position(h).inMicroseconds / 1e6;
      positionSeconds.value = pos.clamp(0.0, durationSeconds).toDouble();
    });
  }

  /// 定位：播放中 soloud 句柄内跳位（暂停中也有效，冻结点随之移动）；
  /// 未播放记住起点，start 后生效。曲终态（无句柄）seek 后需 start。
  @override
  Future<void> seekToSecond(double s) async {
    // 未播放（插针）：KS 未 load 时 durationSeconds=0，clamp 吞成 0
    // ——同 sample_player 修（2026-11-25 "插针后播放从头"根因）。
    final clamped = (playing || paused) && durationSeconds > 0
        ? s.clamp(0.0, durationSeconds).toDouble()
        : s.toDouble();
    final h = _handle;
    if (h == null) {
      _pendingSeek = clamped;
      return;
    }
    _sound.seek(h, Duration(microseconds: (clamped * 1e6).round()));
    positionSeconds.value = clamped;
  }

  /// 50ms 轮询一步。公开为可直测（Timer 周期在测试里难控，
  /// 抽方法直测而非引入 fake_async）。
  @visibleForTesting
  void onTick() {
    final h = _handle;
    if (h == null) return;
    // 曲终检测：soloud 句柄失效即自然播完（不用 pos 启发式）。
    if (!_sound.getIsValidVoiceHandle(h)) {
      // 同步清理先行（timer 回调里不走 await 链），释放 fire-and-forget。
      final d = _detachPlayback();
      if (d != null) unawaited(_release(d.$1, d.$2));
      onEnded?.call();
      return;
    }
    final pos = _sound.position(h).inMicroseconds / 1e6;
    positionSeconds.value = pos.clamp(0.0, durationSeconds).toDouble();
    // AB 循环（2026-11-01 跟练）：越 B 点跳回 A（A/B 均设才生效）。
    // 渐进提速边界计数（2026-11-23 补齐到 KS）：每 3 遍 rate +5% 到
    // 1.0 自动停——KS 的 rate setter 是声部级实时变速（无缝换挡）。
    final a = _loopA, b = _loopB;
    if (a != null && b != null && b > a && pos >= b) {
      if (_progOn && _rate < 1.0 - 1e-9) {
        _progCount++;
        if (_progCount >= 3) {
          _progCount = 0;
          // 走 rate setter（声部级 setRelativePlaySpeed 实时变速生效）。
          rate = (_rate + 0.05).clamp(0.25, 1.0).toDouble();
          onAutoRate?.call(_rate);
          if (_rate >= 1.0 - 1e-9) _progOn = false; // 达原速自动停
        }
      } else {
        _progCount = 0;
      }
      unawaited(seekToSecond(a));
    }
  }

  @override
  Future<void> stop() async {
    final d = _detachPlayback();
    if (d != null) await _release(d.$1, d.$2);
  }

  /// 同步清理播放态，返回待释放的 (句柄, 音源)；未播放返回 null。
  /// 先取句柄再置空（Task 15 审查备案：置序颠倒会让 stop 永不执行）。
  (SoundHandle, AudioSource)? _detachPlayback() {
    _timer?.cancel();
    _timer = null;
    _posTimer?.cancel();
    _posTimer = null;
    final h = _handle;
    _handle = null;
    _paused = false; // 停止/曲终即清暂停态，否则下次 start 后 UI 误显示恢复键
    _pendingSeek = null; // 停止/曲终清未生效的 seek 记忆（停止=回开头）
    positionSeconds.value = 0;
    final s = _src;
    _src = null;
    if (h == null || s == null) return null;
    return (h, s);
  }

  Future<void> _release(SoundHandle h, AudioSource s) async {
    await _sound.stop(h);
    await _sound.disposeSource(s);
  }
}
