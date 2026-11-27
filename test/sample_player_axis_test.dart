// 采样播放器时间轴（2026-11-27）：延长记号顺延下，秒 ↔ 拍的换算必须
// 与事件调度同一条轴。用户实测"指针比发音快一到两个音，越到后面越
// 明显"的根因 = 播放头按 `秒 ÷ 拍长` 线性折算，没扣延长记号顺延，
// 每过一个延长号超前约一拍。
//
// 延长记号语义（制谱基准 同款）：延长位上的音**准时响并被拉长**，其后的音
// 顺延。（2026-11-27 前：延长位上的音本身也被顺延——停顿落在被标记音
// 之前，月下之恋 m60 末音 / m62 终止和弦"响之前先卡一下"。）
//
// 不变量（指针与发音一致）：**每个音发声的那一刻，playBeatAt(发声秒)
// == 该音的展开拍位**；停顿期间指针停在延长音上。停止态（prepare 后、
// 未 play）起播秒换算同样准确（点音插针）。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:guitarbar/audio/sample_bank.dart';
import 'package:guitarbar/audio/sample_player.dart';
import 'package:guitarbar/core/score/score_ir.dart';

import 'score_player_test.dart' show FakeEngine;

NoteIr _n(double beat, int fret) =>
    NoteIr(beat: beat, duration: 1, string: 1, fret: fret, technique: null);

/// 3 小节 4/4 @60bpm（1 拍 = 1s）；m2 第 3 拍（展开拍 6）有延长记号，
/// 顺延 1 拍：展开拍 6 之后的音发声时间 +1s。
/// 展开拍 → 发声秒：0→0, 1→1, 4→4, 5→5, 6→6, 7→8, 8→9。
ScoreIr _ir() => ScoreIr(
      version: 1,
      title: 'T',
      tempo: 60,
      timeSignature: '4/4',
      tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
      capo: 0,
      tracks: [
        TrackIr(name: 'T', measures: [
          MeasureIr(
              index: 0,
              confidence: 1,
              failed: false,
              notes: [_n(0, 1), _n(1, 2)]),
          MeasureIr(
              index: 1,
              confidence: 1,
              failed: false,
              notes: [_n(0, 3), _n(1, 4), _n(2, 5), _n(3, 6)],
              fermatas: const [FermataIr(beat: 2, length: 1)]),
          MeasureIr(
              index: 2, confidence: 1, failed: false, notes: [_n(0, 7)]),
        ]),
      ],
    );

const _soundAt = [0.0, 1.0, 4.0, 5.0, 6.0, 8.0, 9.0];
const _beatOf = [0.0, 1.0, 4.0, 5.0, 6.0, 7.0, 8.0];

(SampleScorePlayer, FakeEngine) _make() {
  final engine = FakeEngine();
  final bank = SteelSampleBank(engine, assetLoader: (_) async => ByteData(4));
  return (SampleScorePlayer(engine, bank), engine);
}

void main() {
  group('延长记号顺延下的秒 ↔ 拍换算', () {
    test('停止态（prepare 后未播放）：起播秒与逆换算已含顺延', () {
      final (player, _) = _make();
      player.prepare(_ir());
      // 延长位及之前：线性（延长位上的音准时响）。
      expect(player.startSecondsForBeat(0, 1), closeTo(1, 1e-9));
      expect(player.startSecondsForBeat(1, 1), closeTo(5, 1e-9));
      expect(player.startSecondsForBeat(1, 2), closeTo(6, 1e-9),
          reason: '延长记号所标记的音准时发声');
      // 延长位之后：+1s（与事件调度同轴）。
      expect(player.startSecondsForBeat(1, 3), closeTo(8, 1e-9));
      expect(player.startSecondsForBeat(2, 0), closeTo(9, 1e-9));
      // 逆换算。
      expect(player.playBeatAt(5), closeTo(5, 1e-9));
      expect(player.playBeatAt(6), closeTo(6, 1e-9));
      expect(player.playBeatAt(6.5), closeTo(6, 1e-9),
          reason: '停顿中：延长音（展开拍 6）还在响，指针停在它上面');
      expect(player.playBeatAt(7), closeTo(6, 1e-9));
      expect(player.playBeatAt(7.5), closeTo(6.5, 1e-9));
      expect(player.playBeatAt(9.5), closeTo(8.5, 1e-9));
    });

    test('播放态：每个音发声瞬间，指针换算回来的拍位 == 该音拍位', () async {
      final (player, engine) = _make();
      expect(await player.play(_ir()), isTrue);
      // 前瞻窗口 2s：t=0/1 的事件已入队。推进引擎时钟让其余事件入队。
      for (final t in [2.0, 5.0, 8.5, 9.5]) {
        engine.engineTimeValue = Duration(microseconds: (t * 1e6).round());
        player.onTick();
      }
      expect(engine.scheduleLog.length, _soundAt.length,
          reason: '7 个音全部入队');
      for (var i = 0; i < _soundAt.length; i++) {
        final at = engine.scheduleLog[i].$1;
        expect(at.inMicroseconds / 1e6, closeTo(_soundAt[i], 1e-6),
            reason: '第 $i 个音的发声秒（延长位上的音准时、其后顺延）');
        expect(player.playBeatAt(_soundAt[i]), closeTo(_beatOf[i], 1e-9),
            reason: '第 $i 个音发声瞬间指针须正好在该音的拍位');
      }
      // 总时长含顺延：末音展开拍 8（时长 1 拍 → 9）+ 顺延 1 拍 + 1.2s 尾音。
      expect(player.durationSeconds, closeTo(9 + 1 + 1.2, 1e-9));
      await player.stop();
    });

    test('无延长记号：换算保持线性（回归防护）', () {
      final ir = _ir();
      final plain = ScoreIr(
          version: ir.version,
          title: ir.title,
          tempo: ir.tempo,
          timeSignature: ir.timeSignature,
          tuning: ir.tuning,
          capo: ir.capo,
          tracks: [
            TrackIr(
                name: 'T',
                measures: [
                  for (final m in ir.tracks.first.measures)
                    MeasureIr(
                        index: m.index,
                        confidence: 1,
                        failed: false,
                        notes: m.notes)
                ])
          ]);
      final (player, _) = _make();
      player.prepare(plain);
      expect(player.startSecondsForBeat(2, 0), closeTo(8, 1e-9));
      for (final t in [0.0, 3.3, 6.5, 8.0]) {
        expect(player.playBeatAt(t), closeTo(t, 1e-9));
      }
    });

    test('停止态插针链：起播秒的逆换算 == 点击拍位（显示与起播同源）', () {
      // 页面层停止态规则：轴播放器 = 采样播放器（timelineReady）。
      // 点击"延长位之后的音"（m3 首音，展开拍 8）：起播秒含顺延，
      // playBeatAt 逆换算必须回到展开拍 8——若页面误用 KS 的线性轴，
      // 线性秒 8s 在采样轴上 = 展开拍 7（偏早 1 拍 = 插针错位根因）。
      final (player, _) = _make();
      player.prepare(_ir());
      expect(player.timelineReady, isTrue);
      final start = player.startSecondsForBeat(2, 0);
      expect(start, isNotNull);
      expect(start!, closeTo(9, 1e-9));
      expect(player.playBeatAt(start), closeTo(8, 1e-9));
      // KS 线性轴对照（ScorePlayer.playBeatAt = 秒 × tempo/60）：同一线性
      // 秒在采样轴上偏早——证明两轴不等价、页面必须单源。
      expect(8.0 * 60.0 / 60.0, closeTo(8, 1e-9));
      expect(player.playBeatAt(8.0), closeTo(7, 1e-9),
          reason: '线性秒 8s 在采样轴上 = 展开拍 7（顺延回扣）');
    });
  });
}
