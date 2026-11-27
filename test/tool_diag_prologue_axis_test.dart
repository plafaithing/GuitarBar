// 一次性诊断：Prologue 指针声音错位离线复现——FakeEngine 手动推进
// 时间驱动 onTick（内含临时 AXIS dump：pos/beat/linear/pending_next），
// 声音轴 pending_next vs 指针轴 linear 差值 = 错位量。
@Tags(['heavy'])
library;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/sample_bank.dart';
import 'package:guitarbar/audio/sample_player.dart';
import 'overlap_probe_lib.dart' show parseScore;

import 'score_player_test.dart' show FakeEngine;

void main() {
  test('Prologue 轴对照', () async {
    final f = File(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores\87\source.gtp');
    final ir = parseScore(f.readAsBytesSync(), 'x')!;
    final engine = FakeEngine();
    final bank =
        SteelSampleBank(engine, assetLoader: (_) async => ByteData(4));
    final player = SampleScorePlayer(engine, bank);
    final ok = await player.play(ir);
    debugPrint('play=$ok tempo=${ir.tempo} '
        'measures=${ir.tracks.first.measures.length} '
        'fermatas=${ir.tracks.first.measures.fold<int>(0, (a, m) => a + m.fermatas.length)} '
        'duration=${player.durationSeconds.toStringAsFixed(1)}s');
    final beatSec = 60.0 / ir.tempo;
    // 直测反查（beat=168 处实测 linear=12 的矛盾定位）+ 表 dump。
    debugPrint('直测 linearBeatAt(168)=${player.linearBeatAt(168)}');
    debugPrint('表长=${player.playbackOrderMeasures.length} '
        'starts40-46=${List.generate(7, (i) => player.playbackOrderStarts[40 + i].toStringAsFixed(0)).join(',')} '
        'measures40-46=${List.generate(7, (i) => player.playbackOrderMeasures[40 + i]).join(',')}');
    var ended = false;
    for (var i = 0; i <= 220 && !ended; i++) {
      final t = i * beatSec;
      engine.engineTimeValue = Duration(microseconds: (t * 1e6).round());
      player.onTick();
      if (!player.playing) ended = true;
    }
    debugPrint('推毕 ended=$ended');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
