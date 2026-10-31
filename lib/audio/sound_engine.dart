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

  /// 关机清理（门面第 7 个成员，冻结接口的追加）：拆除 soloud 引擎——
  /// 引擎拆除即停止全部活动句柄与音源（未持句柄登记簿，一步到位）。
  /// 重复调用安全（未初始化时 deinit 抛错，此处吞掉）。
  /// deinit 为同步 void 调用（非 Future）。
  Future<void> shutdown() async {
    try {
      SoLoud.instance.deinit();
    } catch (_) {}
  }

  /// 曲终检测：句柄是否仍挂在活动声音上（自然播完即失效）。
  /// 冻结接口的追加（门面第 8 个成员，先例见 shutdown）：ScorePlayer 的
  /// 50ms tick 用它区分"播放中/曲终"，替代位置启发式。
  bool getIsValidVoiceHandle(SoundHandle h) =>
      SoLoud.instance.getIsValidVoiceHandle(h);

  /// 暂停/恢复句柄（第 9 个成员，照冻结接口追加先例）。soloud 语义：
  /// true=暂停（position 冻结在暂停点，句柄仍有效）、false=从暂停点继续。
  /// flutter_soloud 5.2.1 签名：void setPause(SoundHandle, bool)。
  void setPause(SoundHandle h, bool paused) =>
      SoLoud.instance.setPause(h, paused);

  /// ogg 等压缩音频字节 → 可播放音源（第 10 个成员，GP8 采样库用）。
  /// loadMem 原生解码 ogg 容器（非 RAW PCM）；mode=memory 全量驻留防寻址卡顿。
  Future<AudioSource> loadOgg(String key, Uint8List bytes) async {
    await init();
    return SoLoud.instance.loadMem(key, bytes, mode: LoadMode.memory);
  }

  /// 引擎时钟（第 11 个成员）：playScheduled 的绝对时基。设备停摆时冻结，
  /// 预调度声音的偏移量在设备恢复后保持不变。
  Duration engineNow() => SoLoud.instance.getEngineTime();

  /// 绝对引擎时刻起播（第 12 个成员）：采样精确的节奏性调度；scale =
  /// 相对播放速度（重移调 2^(半音差/12)），出生时原子生效无音高滑变；
  /// duration 非空时到点自动停（闷音短音用）。atTime 已过则尽快起播。
  SoundHandle scheduleAt(
    AudioSource src, {
    required Duration atTime,
    double scale = 1,
    Duration? duration,
  }) =>
      SoLoud.instance.playScheduled(src, atTime,
          scale: scale, duration: duration ?? Duration.zero);

  /// 活跃声部上限（第 13 个成员，默认 16）：逐音采样 + 自然衰减会并发
  /// 叠加多条余振，16 不够（KS 路径是单条 PCM 流无此约束）。
  void setMaxActiveVoiceCount(int count) =>
      SoLoud.instance.setMaxActiveVoiceCount(count);
}
