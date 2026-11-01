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

  /// 未播放时的 seek 记忆：start 后立即定位到该处（点音起播用）。
  double? _pendingSeek;

  // —— 跟练：变速 + AB（KS 路径的变速在下次 start 生效——重渲染需
  // Isolate 级重算，降级路径少用不做在线重锚；AB 走 position 轮询截断）。
  double _rate = 1.0;
  @override
  double get rate => _rate;
  @override
  set rate(double r) => _rate = r.clamp(0.25, 3.0);

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
  }

  /// 定位：播放中 soloud 句柄内跳位（暂停中也有效，冻结点随之移动）；
  /// 未播放记住起点，start 后生效。曲终态（无句柄）seek 后需 start。
  @override
  Future<void> seekToSecond(double s) async {
    final clamped = s.clamp(0.0, durationSeconds).toDouble();
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
    final a = _loopA, b = _loopB;
    if (a != null && b != null && b > a && pos >= b) {
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
