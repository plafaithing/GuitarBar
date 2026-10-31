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
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => onTick());
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
