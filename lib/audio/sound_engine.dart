import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

import 'synth.dart';

/// flutter_soloud 门面：全应用唯一音频入口。接口保持稳定，
/// 将来若要换回其他音频栈，只需重写本类。
class SoundEngine {
  SoundEngine._();
  static final SoundEngine I = SoundEngine._();

  Future<void>? _initFuture;
  int _counter = 0;

  /// Future 备忘录：并发调用共享同一次初始化，失败后允许重试
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    try {
      await SoLoud.instance.init(sampleRate: 44100, channels: Channels.mono);
    } catch (_) {
      _initFuture = null; // 允许重试
      rethrow;
    }
  }

  /// 原始 16-bit 单声道 PCM → 加载为可播放音源
  Future<AudioSource> loadPcm(Int16List samples) async {
    await init();
    return SoLoud.instance.loadMem(
        'gen-${_counter++}', wrapWav(samples),
        mode: LoadMode.memory);
  }

  SoundHandle play(AudioSource src, {bool loop = false}) =>
      SoLoud.instance.play(src, looping: loop);

  Duration position(SoundHandle h) => SoLoud.instance.getPosition(h);

  Future<void> stop(SoundHandle h) => SoLoud.instance.stop(h);

  Future<void> disposeSource(AudioSource src) =>
      SoLoud.instance.disposeSource(src);
}
