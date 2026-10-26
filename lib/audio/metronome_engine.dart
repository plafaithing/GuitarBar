import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'sound_engine.dart';
import 'synth.dart';

class MetronomeConfig {
  final double bpm;
  final int beatsPerBar;
  final int subdivision; // 每拍细分：1 四分 / 2 八分 / 3 三连 / 4 十六分
  const MetronomeConfig(
      {required this.bpm, required this.beatsPerBar, required this.subdivision});
  double get beatSeconds => 60.0 / bpm;
  double get tickSeconds => beatSeconds / subdivision;
}

class TickEvent {
  final int sample;
  final int kind; // 0 重音 / 1 强拍 / 2 弱拍
  const TickEvent(this.sample, this.kind);
}

int tickKind(int tickIndex, MetronomeConfig cfg) {
  final beatInBar = (tickIndex ~/ cfg.subdivision) % cfg.beatsPerBar;
  final sub = tickIndex % cfg.subdivision;
  if (sub != 0) return 2;
  return beatInBar == 0 ? 0 : 1;
}

List<TickEvent> scheduleTicks(
    {required MetronomeConfig cfg,
    required int startSample,
    required int tickCount,
    required int sampleRate}) {
  return [
    for (var i = 0; i < tickCount; i++)
      TickEvent(
          startSample + (i * cfg.tickSeconds * sampleRate).round(),
          tickKind(i, cfg))
  ];
}

double bpmFromTaps(List<DateTime> taps) {
  if (taps.length < 2) return 0;
  final gaps = <double>[];
  for (var i = 1; i < taps.length; i++) {
    final g = taps[i].difference(taps[i - 1]).inMilliseconds / 1000.0;
    if (g <= 2.0) gaps.add(g);
  }
  if (gaps.isEmpty) return 0;
  gaps.sort();
  return 60.0 / gaps[gaps.length ~/ 2];
}

/// 引擎：把整段节拍音轨按采样精确铺好后循环播放（音轨本身无漂移），
/// UI 拍点用 getPosition 轮询（仅供指示灯显示，不影响音频精度）。
class MetronomeEngine {
  MetronomeEngine(this._sound);
  final SoundEngine _sound;

  MetronomeConfig cfg =
      const MetronomeConfig(bpm: 100, beatsPerBar: 4, subdivision: 1);
  bool running = false;
  final ValueNotifier<int> currentTick = ValueNotifier(-1);

  AudioSource? _track;
  SoundHandle? _handle;
  Timer? _uiTimer;
  bool _busy = false;

  Future<void> start() async {
    if (_busy) return;
    _busy = true;
    try {
      const sr = 44100;
      final barSamples = (cfg.beatSeconds * cfg.beatsPerBar * sr).round();
      final bars = (sr * 60) ~/ barSamples; // 约 60 秒，取整小节数保证无缝循环
      final totalSamples = bars * barSamples;
      final tickSamples = cfg.tickSeconds * sr;
      final ticks = scheduleTicks(
          cfg: cfg,
          startSample: 0,
          tickCount: bars * cfg.beatsPerBar * cfg.subdivision,
          sampleRate: sr);
      final pcm = Int16List(totalSamples);
      for (final t in ticks) {
        final c = click(t.kind, sampleRate: sr);
        for (var i = 0; i < c.length; i++) {
          final idx = t.sample + i;
          if (idx >= totalSamples) break;
          pcm[idx] = (pcm[idx] + c[i]).clamp(-32768, 32767).toInt();
        }
      }
      _track = await _sound.loadPcm(pcm);
      _handle = _sound.play(_track!, loop: true);
      currentTick.value = -1;
      running = true;
      _uiTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
        if (!running || _handle == null) return;
        final pos = _sound.position(_handle!);
        currentTick.value =
            (pos.inMicroseconds / 1e6 * sr / tickSamples).floor();
      });
    } finally {
      _busy = false;
    }
  }

  Future<void> stop() async {
    _uiTimer?.cancel();
    _uiTimer = null;
    running = false;
    currentTick.value = -1;
    if (_handle != null) await _sound.stop(_handle!);
    _handle = null;
    if (_track != null) _sound.disposeSource(_track!);
    _track = null;
  }
}
