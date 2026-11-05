import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/score_player.dart';
import 'package:guitarbar/audio/score_renderer.dart';
import 'package:guitarbar/audio/sound_engine.dart';

/// SoundEngine 假体：统计调用并可控状态，不触 soloud。
/// implements 门面需覆写全部 13 个成员。
class FakeEngine implements SoundEngine {
  FakeEngine({this.validHandle = true});

  /// getIsValidVoiceHandle 返回值（false = 句柄失效 = 曲终）。
  bool validHandle;

  /// position 返回值（tick 轮询读取）。
  Duration positionValue = Duration.zero;

  /// engineNow 返回值（采样调度的引擎时钟）。
  Duration engineTimeValue = Duration.zero;

  /// setPause 最后一次写入值（pause/resume 接线断言用）。
  bool pausedValue = false;

  /// loadPcm 抛错开关（验证失败不留脏时长）。
  bool throwOnLoad = false;

  /// scheduleAt 最后一次入参（采样调度接线断言用）。
  Duration lastAt = Duration.zero;
  double lastScale = 1;
  Duration? lastDuration;

  int loadCount = 0,
      oggCount = 0,
      playCount = 0,
      stopCount = 0,
      disposeCount = 0,
      scheduleCount = 0;

  @override
  Future<AudioSource> loadPcm(Int16List samples) async {
    loadCount++;
    if (throwOnLoad) throw Exception('load failed');
    // AudioSource/SoundHash 构造为 @internal：测试替身必须构造，
    // 局部 ignore（仅本文件）。
    // ignore: invalid_use_of_internal_member
    return AudioSource(const SoundHash(1));
  }

  @override
  Future<AudioSource> loadOgg(String key, Uint8List bytes) async {
    oggCount++;
    if (throwOnLoad) throw Exception('load failed');
    // ignore: invalid_use_of_internal_member
    return AudioSource(const SoundHash(2));
  }

  @override
  SoundHandle play(AudioSource src, {bool loop = false}) {
    playCount++;
    return const SoundHandle(1);
  }

  @override
  SoundHandle scheduleAt(AudioSource src,
      {required Duration atTime,
      double scale = 1,
      Duration? duration,
      double volume = 1}) {
    scheduleCount++;
    lastAt = atTime;
    lastScale = scale;
    lastDuration = duration;
    return const SoundHandle(3);
  }

  @override
  Duration engineNow() => engineTimeValue;

  @override
  void setMaxActiveVoiceCount(int count) {}

  @override
  Duration position(SoundHandle h) => positionValue;

  @override
  Future<void> stop(SoundHandle h) async => stopCount++;

  @override
  Future<void> disposeSource(AudioSource src) async => disposeCount++;

  @override
  bool getIsValidVoiceHandle(SoundHandle h) => validHandle;

  @override
  void setPause(SoundHandle h, bool paused) => pausedValue = paused;

  /// seek 最后一次入参（定位接线断言用）。
  Duration lastSeek = Duration.zero;

  @override
  void seek(SoundHandle h, Duration time) => lastSeek = time;

  int pitchActivateCount = 0;
  final Map<int, double> lastPitchShift = {};

  @override
  void activatePitchShift(AudioSource src) => pitchActivateCount++;

  @override
  void setPitchShift(AudioSource src, SoundHandle h, double v) =>
      lastPitchShift[h.hashCode] = v;

  final Map<int, double> lastVoiceVolume = {};

  @override
  void setVoiceVolume(SoundHandle h, double v) =>
      lastVoiceVolume[h.hashCode] = v;

  @override
  Future<void> init() async {}

  @override
  Future<void> shutdown() async {}
}

RenderedScore _score(double seconds) => RenderedScore(
    pcm: Int16List(0), sampleRate: 44100, seconds: seconds);

void main() {
  test('load→start→tick 推进 position，超长 clamp 到时长', () async {
    final engine = FakeEngine();
    final player = ScorePlayer(engine);
    await player.load(_score(12.5));
    expect(player.durationSeconds, 12.5);
    expect(engine.loadCount, 1);
    await player.start();
    expect(player.playing, isTrue);
    expect(engine.playCount, 1);
    engine.positionValue = const Duration(seconds: 5);
    player.onTick();
    expect(player.positionSeconds.value, 5.0);
    engine.positionValue = const Duration(seconds: 30);
    player.onTick();
    expect(player.positionSeconds.value, 12.5);
    await player.stop(); // 取消 Timer（测试收尾无 pending timer）
  });

  test('stop：playing 归假、position 归零、句柄被释放；可重新 load 再播（置序回归）',
      () async {
    final engine = FakeEngine();
    final player = ScorePlayer(engine);
    await player.load(_score(10));
    await player.start();
    await player.stop();
    expect(player.playing, isFalse);
    expect(player.positionSeconds.value, 0);
    expect(engine.stopCount, 1);
    expect(engine.disposeCount, 1);
    // stop 后再 load→start 成功 = 置序正确（句柄/音源真的被清了）。
    await player.load(_score(8));
    await player.start();
    expect(player.playing, isTrue);
    expect(engine.playCount, 2);
    await player.stop();
    expect(engine.stopCount, 2);
  });

  test('曲终：tick 检测句柄失效 → 自动停止并触发 onEnded', () async {
    final engine = FakeEngine(validHandle: false);
    var ended = 0;
    final player = ScorePlayer(engine, onEnded: () => ended++);
    await player.load(_score(10));
    await player.start();
    player.onTick();
    expect(ended, 1);
    expect(player.playing, isFalse);
    expect(player.positionSeconds.value, 0);
    expect(engine.stopCount, 1);
    // 曲终释放是 fire-and-forget（timer 回调不走 await 链）：
    // disposeSource 在下一个 microtask，排空事件循环后再断言。
    await pumpEventQueue();
    expect(engine.disposeCount, 1);
  });

  test('loadPcm 失败：durationSeconds 不被污染', () async {
    final engine = FakeEngine()..throwOnLoad = true;
    final player = ScorePlayer(engine);
    await expectLater(player.load(_score(10)), throwsA(anything));
    expect(player.durationSeconds, 0);
    expect(player.playing, isFalse);
  });

  test('未播放时 stop/tick 是空操作', () async {
    final engine = FakeEngine();
    final player = ScorePlayer(engine);
    await player.stop();
    player.onTick();
    expect(engine.stopCount, 0);
    expect(player.playing, isFalse);
  });

  test('pause/resume：setPause 接线 + 状态翻转；轮询继续但 position 冻结',
      () async {
    final engine = FakeEngine();
    final player = ScorePlayer(engine);
    await player.load(_score(10));
    await player.start();
    engine.positionValue = const Duration(seconds: 4);
    player.onTick();
    player.pause();
    expect(player.paused, isTrue);
    expect(player.playing, isTrue); // 暂停≠停止：句柄仍活着
    expect(engine.pausedValue, isTrue);
    // 暂停中 soloud position 冻结：fake 固定返回 4s，tick 继续读同值。
    player.onTick();
    expect(player.positionSeconds.value, 4.0);
    player.resume();
    expect(player.paused, isFalse);
    expect(engine.pausedValue, isFalse);
    expect(player.playing, isTrue);
    await player.stop();
  });

  test('pause/resume 空操作守卫：未播放/重复调用不触引擎', () async {
    final engine = FakeEngine();
    final player = ScorePlayer(engine);
    player.pause(); // 未播放：早退
    expect(engine.pausedValue, isFalse);
    expect(player.paused, isFalse);
    player.resume(); // 未暂停：早退
    expect(engine.pausedValue, isFalse);
    await player.load(_score(10));
    await player.start();
    player.pause();
    player.pause(); // 已暂停：早退（引擎只见一次 true）
    expect(engine.pausedValue, isTrue);
    player.resume();
    player.resume(); // 未暂停：早退（引擎只见一次 false）
    expect(engine.pausedValue, isFalse);
    await player.stop();
  });

  test('stop 清暂停态：pause → stop → 重新 load/start 后 paused 为假',
      () async {
    final engine = FakeEngine();
    final player = ScorePlayer(engine);
    await player.load(_score(10));
    await player.start();
    player.pause();
    expect(player.paused, isTrue);
    await player.stop();
    expect(player.paused, isFalse);
    expect(player.playing, isFalse);
    await player.load(_score(10));
    await player.start();
    expect(player.playing, isTrue);
    expect(player.paused, isFalse); // 旧暂停态不得泄漏到新一轮播放
    await player.stop();
  });
}
