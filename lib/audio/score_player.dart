import 'dart:async';

import 'package:flutter/foundation.dart';
// AudioSource/SoundHandle 类型来自 soloud 包（sound_engine 未重导出）。
import 'package:flutter_soloud/flutter_soloud.dart';

import 'score_renderer.dart';
import 'sound_engine.dart';

/// 自动演奏播放：渲染 PCM → loadPcm → play。
/// 位置轮询仅供 UI 播放头（与节拍器同思路，不影响音频精度）。
/// 渲染耗时 ~0.3-1s（真实谱）：调用方负责忙碌反馈（Task 15 备案）。
class ScorePlayer {
  ScorePlayer(this._sound, {this.onEnded});
  final SoundEngine _sound;

  /// 曲终回调：tick 检测到 soloud 句柄失效（自然播完）时触发，
  /// 此时播放态已同步清理（playing=false、position=0）。
  final void Function()? onEnded;

  AudioSource? _src;
  SoundHandle? _handle;
  Timer? _timer;

  double durationSeconds = 0;
  final ValueNotifier<double> positionSeconds = ValueNotifier(0);
  bool get playing => _handle != null;

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
