// 一次性诊断：Prologue 逐拍听感覆盖——拨弦事件覆盖区间（含 tie 延长
// 后的 noteSeconds）拼成时间线，空白 >1 拍的段 = 听感无声段地图。
@Tags(['heavy'])
library;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/sample_bank.dart';
import 'package:guitarbar/audio/sample_player.dart';

import 'overlap_probe_lib.dart' show parseScore;
import 'score_player_test.dart' show FakeEngine;

void main() {
  test('Prologue 听感覆盖地图', () async {
    final f = File(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores\87\source.gtp');
    final ir = parseScore(f.readAsBytesSync(), 'x')!;
    final engine = FakeEngine();
    final bank = SteelSampleBank(engine,
        assetLoader: (_) async => ByteData(4));
    final player = SampleScorePlayer(engine, bank);
    final ok = await player.play(ir);
    debugPrint('play=$ok tempo=${ir.tempo} duration=${player.durationSeconds}');
    // 全曲驱动（调度全部事件入 scheduleLog——真实调度表）。
    for (var t = 0.0; t <= player.durationSeconds; t += 0.5) {
      engine.engineTimeValue = Duration(microseconds: (t * 1e6).round());
      player.onTick();
      if (!player.playing) break;
    }
    debugPrint('scheduleLog=${engine.scheduleLog.length} 条');
    // 前 20 条 (at 秒, duration 秒)——验 tie 延长/余振实际值。
    for (var i = 0; i < 20 && i < engine.scheduleLog.length; i++) {
      final (at, dur) = engine.scheduleLog[i];
      debugPrint('  [$i] at=${(at.inMicroseconds / 1e6).toStringAsFixed(2)}s '
          'dur=${((dur?.inMicroseconds ?? 0) / 1e6).toStringAsFixed(2)}s');
    }
    // 覆盖地图：atTime + duration（ms→秒）。
    final spans = [
      for (final (at, dur) in engine.scheduleLog)
        (at.inMicroseconds / 1e6,
            (dur?.inMicroseconds ?? 0) / 1e6)
    ];
    final gaps = <String>[];
    var gapStart = -1.0;
    var total = player.durationSeconds - 1.2;
    for (var t = 0.0; t < total; t += 0.25) {
      final covered = spans.any((s) => t >= s.$1 && t < s.$1 + s.$2);
      if (!covered && gapStart < 0) gapStart = t;
      if (covered && gapStart >= 0) {
        if (t - gapStart > 0.8) {
          gaps.add('空白 拍${(gapStart / 0.8).toStringAsFixed(1)}~${(t / 0.8).toStringAsFixed(1)} '
              '（展开小节${(gapStart / 2.4 + 1).toStringAsFixed(1)}~${(t / 2.4 + 1).toStringAsFixed(1)}，'
              '${(t - gapStart).toStringAsFixed(1)}s）');
        }
        gapStart = -1;
      }
    }
    for (final g in gaps) {
      debugPrint(g);
    }
    debugPrint('共 ${gaps.length} 段空白（真实调度表口径）');
    return;
    // 手动推进全曲驱动调度（FakeEngine 时钟步进）→ 用 scheduleAt 记录？
    // FakeEngine 只存最后入参——改为复算：直接驱动 onTick 到曲末，用
    // player.positionSeconds 序列反推覆盖不可行……
    // 换直接口径：驱动全曲 + 每拍记录“该拍 0.2s 内是否有拨弦时刻落在
    // 手算块已删（改用真实调度表 scheduleLog——见上方 spans）。
  }, timeout: const Timeout(Duration(minutes: 3)));
}
