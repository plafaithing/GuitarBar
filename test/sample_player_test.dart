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
    // 四枚同弦空弦 → 交替拨弦 Up/Down 两文件各载一次（2026-11-01 技法音效）。
    expect(engine.oggCount, 2);
    // 前瞻窗口 2.0s（2026-11-24：0.5s 窗口被 GC/内存压力拖过即断流——
    // 事件全驻内存，提前钉到引擎时钟零成本）：beat 0/1/2（t=0/1/2s）
    // 起播即入队，beat 3（t=3s）在窗外。
    expect(engine.scheduleLog, [
      (Duration.zero, Duration.zero),
      (const Duration(seconds: 1), Duration.zero),
      (const Duration(seconds: 2), Duration.zero),
    ]);
    expect(engine.lastScale, 1.0); // 空弦精确命中
    // 普通音不按时值截停：duration=zero 完整自然衰减（2026-11-25 用户
    // 对照 制谱基准 实证——同弦连拨叠振不断音；仅 staccato/grace 等保留短值）。
    expect(engine.lastDuration, Duration.zero);
    expect(player.durationSeconds, 5.2); // 4 拍 + 1.2 尾音

    // 时间推进到 1.2s：beat 3（time 3.0）进入前瞻窗口入队。
    engine.engineTimeValue = const Duration(milliseconds: 1200);
    player.onTick();
    expect(engine.scheduleCount, 4);
    expect(engine.lastAt, const Duration(seconds: 3));
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
    expect(engine.scheduleCount, 3); // beat 0/1/2（前瞻窗口 2s）
    player.pause();
    expect(player.paused, isTrue);
    expect(player.playing, isTrue); // 暂停≠停止
    expect(engine.stopCount, 3); // 窗口内 3 个声部被切（句柄有效 → stop）
    // 暂停中 tick 是空操作。
    engine.engineTimeValue = const Duration(seconds: 3);
    player.onTick();
    expect(engine.scheduleCount, 3);
    expect(player.positionSeconds.value, 0); // 冻结在暂停点

    player.resume();
    expect(player.paused, isFalse);
    player.onTick(); // t0 = 引擎现在(3s) - 暂停点(0) → beat 0/1/2 重排（被切过）
    expect(engine.scheduleCount, 6);
    // 从暂停点起推进 1.2s（引擎时钟 4.2s，绝对时钟不回拨）：beat 3 入队。
    engine.engineTimeValue = const Duration(milliseconds: 4200);
    player.onTick();
    expect(engine.scheduleCount, 7);
    // 引擎时刻 = 新零点(3s) + 事件轴时间(3s)——绝对时钟不回拨。
    expect(engine.lastAt, const Duration(seconds: 6));
    expect(player.positionSeconds.value, 1.2);
    await player.stop();
  });

  test('stop：playing 归假、position 归零、句柄收割；可重播（缓存命中）', () async {
    final (player, engine, _) = make();
    await player.play(fourNotes());
    await player.stop();
    expect(player.playing, isFalse);
    expect(player.positionSeconds.value, 0);
    expect(engine.stopCount, 3); // 窗口内 3 个句柄被收割
    // 重播：预载命中缓存（oggCount 不增——首遍已载 Up/Down 两文件），
    // 调度重新开始（beat 0/1/2 再入队）。
    final ok = await player.play(fourNotes());
    expect(ok, isTrue);
    expect(engine.oggCount, 2);
    expect(engine.scheduleCount, 6);
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

  test('变速轴一致（2026-11-11）：scale × rate + 位置连续 + 不误判曲终', () async {
    final (player, engine, _) = make();
    await player.play(fourNotes());
    expect(engine.lastScale, 1.0);
    // 播放到 1.2s（beat 1 已调度）后切 2x：
    engine.engineTimeValue = const Duration(milliseconds: 1200);
    player.onTick();
    expect(player.positionSeconds.value, 1.2);
    player.setRate(2.0);
    expect(player.rate, 2.0);
    // 谱面秒 V 连续（变速瞬间播放位置不跳）：仍 1.2；duration 同步
    // 缩短为 raw(4.2)/2 + 1.2 = 3.3 → 曲终判定两轴一致不再误停（⑤）。
    expect(player.positionSeconds.value, closeTo(1.2, 1e-9));
    expect(player.durationSeconds, closeTo(4.0 / 2 + 1.2, 1e-9));
    expect(player.playing, isTrue); // 未被误判停止（⑤ 根因回归）
    // 时间再推进 1s（引擎 2.2s）：V = (2.2-(-1.2))/2 = 1.7。
    engine.engineTimeValue = const Duration(milliseconds: 2200);
    player.onTick();
    expect(player.positionSeconds.value, closeTo(1.7, 0.01));
    // 事件轴推进 0.5 谱面秒 → beat 2（time 2.0）入队，scale=2x。
    expect(engine.scheduleCount, greaterThanOrEqualTo(3));
    expect(engine.lastScale, closeTo(2.0, 1e-9));
    await player.stop();
  });
}
