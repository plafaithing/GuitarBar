import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/sample_bank.dart';
import 'package:guitarbar/audio/sample_player.dart';
import 'package:guitarbar/audio/score_player.dart' show ScorePlayback;
import 'package:guitarbar/core/score/score_ir.dart';

import 'score_player_test.dart' show FakeEngine;

/// 实时采样播放器：FakeEngine + 假 assetLoader（不触 soloud/assets），
/// onTick 直测（Timer 周期在测试里难控，先例见 score_player_test）。
void main() {
  NoteIr n(double beat, int string, int fret, {String? technique}) =>
      NoteIr(
          beat: beat,
          duration: 1,
          string: string,
          fret: fret,
          technique: technique);

  ScoreIr buildIr(List<NoteIr> notes, {bool failedMeasure = false}) => ScoreIr(
        version: 1,
        title: 't',
        tempo: 60, // 1 拍 = 1s，心算友好
        timeSignature: '4/4',
        tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
        capo: 0,
        tracks: [
          TrackIr(name: '主旋律', measures: [
            MeasureIr(
                index: 0,
                confidence: failedMeasure ? 0 : 1,
                failed: failedMeasure,
                notes: notes),
          ]),
        ],
      );

  /// 四分音符四枚（beat 0/1/2/3，全 6 弦空弦），时长 = 4 拍 + 1.2s 尾音。
  ScoreIr fourNotes() => buildIr([n(0, 6, 0), n(1, 6, 0), n(2, 6, 0), n(3, 6, 0)]);

  (SampleScorePlayer, FakeEngine, SteelSampleBank) make(
      {Future<ByteData> Function(String)? loader, void Function()? onEnded}) {
    final engine = FakeEngine();
    final bank = SteelSampleBank(engine,
        assetLoader: loader ?? ((_) async => ByteData(4)));
    final player = SampleScorePlayer(engine, bank, onEnded: onEnded);
    return (player, engine, bank);
  }

  test('play：预载 + 前瞻调度（窗口内事件钉到引擎时钟，scale 接线）', () async {
    final (player, engine, _) = make();
    final ok = await player.play(fourNotes());
    expect(ok, isTrue);
    expect(player.playing, isTrue);
    expect(engine.oggCount, 1); // 四枚同弦空弦 → 唯一采样只载一次
    // 窗口 0.5s：仅 beat 0 入队。
    expect(engine.scheduleCount, 1);
    expect(engine.lastAt, Duration.zero);
    expect(engine.lastScale, 1.0); // 空弦精确命中
    // 非闷音也带时长限制（音符时值 1.0 拍 @60bpm + 0.08s 余振 = 1.08s）。
    expect(engine.lastDuration, const Duration(milliseconds: 1080));
    expect(player.durationSeconds, 5.2); // 4 拍 + 1.2 尾音

    // 时间推进到 1.2s：beat 1（time 1.0）入队；beat 2/3 仍在窗外。
    engine.engineTimeValue = const Duration(milliseconds: 1200);
    player.onTick();
    expect(engine.scheduleCount, 2);
    expect(player.positionSeconds.value, 1.2);
    await player.stop();
  });

  test('ScorePlayback 公共面：SampleScorePlayer 与 ScorePlayer 同构', () {
    final (player, _, _) = make();
    expect(player, isA<ScorePlayback>());
  });

  test('曲终：时间轴越过时长 → onEnded + playing 归假 + position 归零', () async {
    var ended = 0;
    final (player, engine, _) = make(onEnded: () => ended++);
    await player.play(fourNotes());
    engine.engineTimeValue = const Duration(seconds: 6); // > 5.2
    player.onTick();
    expect(ended, 1);
    expect(player.playing, isFalse);
    expect(player.positionSeconds.value, 0);
    // 曲终不切余振：句柄留给下一轮 play/stop 收割。
    expect(engine.stopCount, 0);
  });

  test('预载失败（资源缺失）：play 返回 false，零调度', () async {
    final (player, engine, _) = make(loader: (path) async {
      if (path.contains('6E40')) throw Exception('missing');
      return ByteData(4);
    });
    final ok = await player.play(fourNotes());
    expect(ok, isFalse);
    expect(player.playing, isFalse);
    expect(engine.scheduleCount, 0);
  });

  test('无可发音符（全 failed 小节）：play 返回 false → 调用方降级 KS', () async {
    final (player, engine, _) = make();
    final ok = await player.play(buildIr(const [], failedMeasure: true));
    expect(ok, isFalse);
    expect(engine.scheduleCount, 0);
  });

  test('坏调弦（非 6 弦）：play 返回 false', () async {
    final (player, _, _) = make();
    final ir = ScoreIr(
        version: 1,
        title: 't',
        tempo: 60,
        timeSignature: '4/4',
        tuning: const ['E2', 'A2', 'D3', 'G3'],
        capo: 0,
        tracks: [
          TrackIr(name: 'b', measures: [
            MeasureIr(
                index: 0, confidence: 1, failed: false, notes: [n(0, 4, 0)]),
          ]),
        ]);
    expect(await player.play(ir), isFalse);
  });

  test('闷音 x：scheduleAt 带 0.3s 截短（与 KS 路径同款）', () async {
    final (player, engine, _) = make();
    await player.play(buildIr([n(0, 6, 0, technique: 'x')]));
    expect(engine.lastDuration, const Duration(milliseconds: 300));
    await player.stop();
  });

  test('pause/resume：切声部 + 时间轴零点搬移 + 指针回卷重排被切音', () async {
    final (player, engine, _) = make();
    await player.play(fourNotes());
    expect(engine.scheduleCount, 1); // beat 0
    player.pause();
    expect(player.paused, isTrue);
    expect(player.playing, isTrue); // 暂停≠停止
    expect(engine.stopCount, 1); // 现场声部被切（句柄有效 → stop）
    // 暂停中 tick 是空操作。
    engine.engineTimeValue = const Duration(seconds: 3);
    player.onTick();
    expect(engine.scheduleCount, 1);
    expect(player.positionSeconds.value, 0); // 冻结在暂停点

    player.resume();
    expect(player.paused, isFalse);
    player.onTick(); // t0 = 引擎现在(3s) - 暂停点(0) → beat 0 重排（被切过）
    expect(engine.scheduleCount, 2);
    // 从暂停点起推进 1.2s（引擎时钟 4.2s，绝对时钟不回拨）：beat 1 入队。
    engine.engineTimeValue = const Duration(milliseconds: 4200);
    player.onTick();
    expect(engine.scheduleCount, 3);
    expect(player.positionSeconds.value, 1.2);
    await player.stop();
  });

  test('stop：playing 归假、position 归零、句柄收割；可重播（缓存命中）', () async {
    final (player, engine, _) = make();
    await player.play(fourNotes());
    await player.stop();
    expect(player.playing, isFalse);
    expect(player.positionSeconds.value, 0);
    expect(engine.stopCount, 1); // beat 0 句柄被收割
    // 重播：预载命中缓存（oggCount 不增），调度重新开始。
    final ok = await player.play(fourNotes());
    expect(ok, isTrue);
    expect(engine.oggCount, 1);
    expect(engine.scheduleCount, 2);
    await player.stop();
  });

  test('预载期间被 stop：放弃起播（代际守卫）', () async {
    final engine = FakeEngine();
    final gate = Completer<void>();
    final bank = SteelSampleBank(engine,
        assetLoader: (_) => gate.future.then((_) => ByteData(4)));
    final player = SampleScorePlayer(engine, bank);
    final playFuture = player.play(fourNotes());
    // 让 play 走到预载挂起点（gen 已捕获、等 gate 放行）。
    await pumpEventQueue();
    await player.stop(); // 预载挂起中停止 → 代际递增
    gate.complete();
    expect(await playFuture, isFalse);
    expect(player.playing, isFalse);
    expect(engine.scheduleCount, 0);
  });
}
