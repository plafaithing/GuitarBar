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
  ScorePlayer(this._sound);
  final SoundEngine _sound;

  AudioSource? _src;
  SoundHandle? _handle;
  Timer? _timer;

  double durationSeconds = 0;
  final ValueNotifier<double> positionSeconds = ValueNotifier(0);
  bool get playing => _handle != null;
  bool get loaded => _src != null;

  Future<void> load(RenderedScore r) async {
    await stop();
    durationSeconds = r.seconds;
    _src = await _sound.loadPcm(r.pcm);
  }

  Future<void> start() async {
    final src = _src;
    if (src == null || _handle != null) return;
    _handle = _sound.play(src);
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final h = _handle;
      if (h == null) return;
      final pos = _sound.position(h).inMicroseconds / 1e6;
      positionSeconds.value = pos.clamp(0.0, durationSeconds).toDouble();
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    // 先取句柄再置空（Task 15 审查备案：置序颠倒会让 stop 永不执行）。
    final h = _handle;
    _handle = null;
    positionSeconds.value = 0;
    final s = _src;
    _src = null;
    if (h != null) await _sound.stop(h);
    if (s != null) await _sound.disposeSource(s);
  }
}
