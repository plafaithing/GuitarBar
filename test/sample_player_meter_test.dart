// 6/8 拍号四分拍口径回归（2026-11-19 Prologue"指针到了不响"根治）：
// X/8 拍号此前按**分子**计拍——6/8 小节被当 6 拍 4.8s，而音符 beat 是
// 四分拍口径（八分=0.5）只占 3 拍 → 每小节末 2.4s 空白、总时长 2x、
// 播放头爬出小节盒后 snap 回下一小节起点（用户实证）。修后：
// 小节 = 3 四分拍 × 0.8s = 2.4s，m2 首事件 2.4s（非 4.8s），无空白。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/sample_bank.dart';
import 'package:guitarbar/audio/sample_player.dart';
import 'package:guitarbar/audio/score_renderer.dart';
import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';

import 'score_player_test.dart' show FakeEngine;

ScoreIr ir68() => ScoreIr(
      version: 1, title: 'T', tempo: 75, timeSignature: '6/8',
      tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], capo: 0,
      tracks: [
        TrackIr(name: 'T', measures: [
          for (var m = 0; m < 2; m++)
            MeasureIr(
              index: m,
              confidence: 0.9,
              failed: false,
              notes: [
                for (var k = 0; k < 6; k++)
                  NoteIr(beat: k * 0.5, duration: 0.5, string: 1,
                      fret: 0, technique: null),
              ],
            ),
        ]),
      ],
    );

void main() {
  test('measureQuarterBeats：N/D → N×4/D 四分拍', () {
    expect(measureQuarterBeats('6/8', fallback: 4), 3.0);
    expect(measureQuarterBeats('12/8', fallback: 4), 6.0);
    expect(measureQuarterBeats('2/2', fallback: 4), 4.0);
    expect(measureQuarterBeats('4/4', fallback: 4), 4.0);
    expect(measureQuarterBeats('3/4', fallback: 4), 3.0);
    expect(measureQuarterBeats('1/4', fallback: 4), 1.0);
    expect(measureQuarterBeats(null, fallback: 3.0), 3.0); // 继承全曲
    expect(measureQuarterBeats('x/y', fallback: 2.0), 2.0); // 坏拍号容错
  });

  test('TabLayout 线性轴四分拍：linearStarts/measureAtBeat（视觉宽不变）', () {
    final l = TabLayout(ir68());
    // 线性轴：每小节 3 四分拍。
    expect(l.linearStarts, [0.0, 3.0]);
    expect(l.measureAtBeat(2.99), 0);
    expect(l.measureAtBeat(3.0), 1);
    // 视觉盒宽保持分子口径（渲染零变化）：6/8 → 6 × pxPerBeat。
    expect(l.measureWidthOf(0), 6 * TabLayout.pxPerBeat);
    expect(l.beatsOfBar(0), 6);
  });

  test('sample 播放：6/8 小节 2.4s，m2 首事件 2.4s，无小节末空白', () async {
    final engine = FakeEngine();
    final bank = SteelSampleBank(engine, assetLoader: (_) async => ByteData(4));
    final player = SampleScorePlayer(engine, bank);
    final ok = await player.play(ir68());
    expect(ok, isTrue);
    // 全曲驱动（0.5s 步进推引擎时钟 → 前瞻窗口全部调度入 log）。
    for (var t = 0.0; t <= player.durationSeconds; t += 0.5) {
      engine.engineTimeValue = Duration(microseconds: (t * 1e6).round());
      player.onTick();
      if (!player.playing) break;
    }
    // 12 事件（每小节 6 八分）。
    expect(engine.scheduleLog.length, 12);
    final times = [
      for (final (at, _) in engine.scheduleLog) at.inMicroseconds / 1e6
    ];
    final want = [
      for (var k = 0; k < 12; k++) k * 0.4,
    ];
    for (var i = 0; i < 12; i++) {
      expect(times[i], closeTo(want[i], 1e-6),
          reason: '事件[$i] 应在 ${want[i]}s（旧口径 m2 从 4.8s 起）');
    }
    // 相邻事件最大间隔 = 0.4s（旧口径 m1→m2 之间 2.8s 空白）。
    for (var i = 1; i < times.length; i++) {
      expect(times[i] - times[i - 1], lessThan(0.400001));
    }
    // 总时长 = 6 四分拍 × 0.8 + 1.2 尾音（旧口径 2x = 10.8）。
    expect(player.durationSeconds, closeTo(6.0, 1e-6));
    // 播放头线性轴：3.0 拍 = m2 起点（旧口径返回 6.0）。
    expect(player.linearBeatAt(3.0), closeTo(3.0, 1e-9));
    expect(player.linearBeatAt(2.5), closeTo(2.5, 1e-9));
    await player.stop();
  });

  test('KS 渲染：6/8 总长 6.0s（旧口径 10.8s），per-measure 四分拍表',
      () async {
    final r = renderScore(ir68());
    expect(r.barBeatsQuarter, [3.0, 3.0]);
    expect(r.beatsPerBar, 3.0);
    // endBeat = m2 末音尾 3.0+3.0 = 6 拍 + 1.2s 尾音×75/60=1.5 拍 →
    // 7.5 拍 × 0.8s（+1 采样 ceil，容差放宽）。
    expect(r.seconds, closeTo(7.5 * 0.8, 0.001));
  });

  test('尾休止小节：播放头休止段钳在末音位不爬出小节盒（dsh P1-1）', () {
    // 4/4 单小节两短音（beat 0/0.5 各 dur 0.5）→ contentBeats = 1.0
    // < 4：11-18 平铺布局下 inMeasure 轴走满 4 拍，休止段（1.0~4.0）
    // 此前爬出小节盒侵入下一小节再 snap 回。
    final ir = ScoreIr(
      version: 1, title: 'T', tempo: 90, timeSignature: '4/4',
      tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], capo: 0,
      tracks: [
        TrackIr(name: 'T', measures: [
          MeasureIr(
            index: 0,
            confidence: 0.9,
            failed: false,
            notes: [
              NoteIr(beat: 0, duration: 0.5, string: 1, fret: 0,
                  technique: null),
              NoteIr(beat: 0.5, duration: 0.5, string: 1, fret: 3,
                  technique: null),
            ],
          ),
        ]),
      ],
    );
    final l = TabLayout(ir);
    expect(l.contentBeatsOf(0), 1.0);
    final wide = l.measureWidth + TabLayout.leftPad * 2;
    final xEnd = l.noteX(0, l.contentBeatsOf(0), wide);
    // 休止段任意拍位（1.0~4.0）都钳在末音位。
    expect(l.noteX(0, 2.0, wide), xEnd);
    expect(l.noteX(0, 4.0, wide), xEnd);
    // 且不越右竖线净空界。
    expect(xEnd - TabLayout.leftPad,
        lessThanOrEqualTo(l.measureWidth - TabLayout.notePad));
  });

  test('staccato 短时值不被余振补齐（dsh P1-2）', () async {
    // 单小节单 staccato 四分音，同弦后续无事件 → natural = 1.2 > 0.48，
    // fixedDur 挡住补齐（此前被拉到 1.2s，"时值减半留空拍感"失效）。
    final ir = ScoreIr(
      version: 1, title: 'T', tempo: 75, timeSignature: '4/4',
      tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], capo: 0,
      tracks: [
        TrackIr(name: 'T', measures: [
          MeasureIr(
            index: 0,
            confidence: 0.9,
            failed: false,
            notes: [
              NoteIr(beat: 0, duration: 1.0, string: 1, fret: 0,
                  technique: null, staccato: true),
            ],
          ),
        ]),
      ],
    );
    final engine = FakeEngine();
    final bank = SteelSampleBank(engine, assetLoader: (_) async => ByteData(4));
    final player = SampleScorePlayer(engine, bank);
    expect(await player.play(ir), isTrue);
    for (var t = 0.0; t <= player.durationSeconds; t += 0.5) {
      engine.engineTimeValue = Duration(microseconds: (t * 1e6).round());
      player.onTick();
      if (!player.playing) break;
    }
    expect(engine.scheduleLog.length, 1);
    final dur = (engine.scheduleLog.first.$2!.inMicroseconds / 1e6);
    // 既有语义：(0.8 + 0.08) × 0.5 = 0.44（staccato 连余振整体乘半）
    // ——关键断言是**不被余振补齐拉到 1.2**（fixedDur 生效）。
    expect(dur, closeTo((1.0 * 0.8 + 0.08) * 0.5, 1e-6));
    expect(dur, lessThan(1.0));
    await player.stop();
  });

  test('装饰音播放：同拍 deco+本体 sort 稳定（dsh 三轮 P1——seq tie-break）',
      () async {
    // 3 小节每小节 b0 一对：deco(f3, 0.0625 拍, slide shift)+本体(f10,
    // 0.5 拍)同弦同拍——time 精确相等，sort 不稳定时翻转 → deco 的
    // nextSame 跳到下一小节 deco（2.4s）→ 被余振补齐 1.2s（长鸣）。
    // seq tie-break 后 deco 恒先于本体 → nextSame=本体（time 相等）
    // → natural=0 → deco dur 保持 0.13s。
    final ir = ScoreIr(
      version: 1, title: 'T', tempo: 75, timeSignature: '4/4',
      tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], capo: 0,
      tracks: [
        TrackIr(name: 'T', measures: [
          for (var m = 0; m < 3; m++)
            MeasureIr(
              index: m,
              confidence: 0.9,
              failed: false,
              notes: [
                NoteIr(beat: 0, duration: 0.0625, string: 1, fret: 3,
                    technique: null, deco: true, slide: 'shift',
                    velocity: 95),
                NoteIr(beat: 0, duration: 0.5, string: 1, fret: 10,
                    technique: null),
              ],
            ),
        ]),
      ],
    );
    final engine = FakeEngine();
    final bank = SteelSampleBank(engine, assetLoader: (_) async => ByteData(4));
    final player = SampleScorePlayer(engine, bank);
    expect(await player.play(ir), isTrue);
    for (var t = 0.0; t <= player.durationSeconds; t += 0.5) {
      engine.engineTimeValue = Duration(microseconds: (t * 1e6).round());
      player.onTick();
      if (!player.playing) break;
    }
    expect(engine.scheduleLog.length, 6);
    final durs = [
      for (final (_, d) in engine.scheduleLog) d!.inMicroseconds / 1e6
    ];
    // deco 事件 = 0.0625×0.8+0.08 = 0.13s；本体同弦距 2.4s → 补到 1.2s。
    var decoCount = 0;
    for (final d in durs) {
      if (d > 0.10 && d < 0.16) decoCount++;
    }
    expect(decoCount, 3, reason: '3 个装饰音须保持 0.13s（sort 翻转会变 1.2s）');
    await player.stop();
  });
}
