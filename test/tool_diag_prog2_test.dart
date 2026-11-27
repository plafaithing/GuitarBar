// 一次性诊断：1.0 速开启渐进 → setter 应自动降 0.75（用户实测没降）。
@Tags(['heavy'])
library;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/sample_bank.dart';
import 'package:guitarbar/audio/sample_player.dart';
import 'package:guitarbar/core/score/score_ir.dart';

import 'score_player_test.dart' show FakeEngine;

void main() {
  test('1.0 开渐进 → 自动降 0.75', () async {
    final ir = ScoreIr(
      version: 1, title: 'T', tempo: 75, timeSignature: '6/8',
      tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], capo: 0,
      tracks: [
        TrackIr(name: 'T', measures: [
          MeasureIr(
            index: 0,
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
    final engine = FakeEngine();
    final bank = SteelSampleBank(engine, assetLoader: (_) async => ByteData(4));
    final player = SampleScorePlayer(engine, bank);
    expect(await player.play(ir), isTrue);
    // 用户序列：播放中（1.0）→ 点开关。
    debugPrint('before: rate=${player.rate} playing=${player.playing}');
    player.progressiveOn = true;
    debugPrint('after setter: rate=${player.rate} progOn=${player.progressiveOn}');
    // 边界一轮确认渐进爬升从 0.75 起。
    player.loopA = 0;
    player.loopB = 1.6; // 0.75 速下 V 轴小节长=0.75*2.4=1.8?——用 1.6 触发近界
    for (var step = 0; step < 20 && player.playing; step++) {
      engine.engineTimeValue =
          Duration(microseconds: (step * 0.3 * 1e6).round());
      player.onTick();
    }
    debugPrint('after loops: rate=${player.rate} progOn=${player.progressiveOn}');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
