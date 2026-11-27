// 一次性诊断：全曲库 GP 谱逐个跑 sample play（FakeEngine + stub 采样
// 都成功——只暴露 _collectEvents/调弦/空事件层的失败），输出降级原因。
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
  test('全库 sample play 链诊断', () async {
    final engine = FakeEngine();
    final bank = SteelSampleBank(engine, assetLoader: (_) async => ByteData(4));
    final player = SampleScorePlayer(engine, bank);
    final libDir = Directory(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores');
    var ok = 0, fail = 0;
    for (final d in libDir.listSync()) {
      File? f;
      for (final name in ['source.gtp', 'source.gpx', 'source.gp5', 'source.gp3']) {
        final cand = File('${d.path}\\$name');
        if (cand.existsSync()) {
          f = cand;
          break;
        }
      }
      if (f == null) continue;
      final ir = parseScore(f.readAsBytesSync(), d.path.split(r'\').last);
      if (ir == null) continue;
      final okPlay = await player.play(ir);
      await player.stop();
      if (okPlay) {
        ok++;
      } else {
        fail++;
        debugPrint('[FAIL] ${ir.title} (${d.path.split(r'\').last}) '
            'tuning=${ir.tuning} tempo=${ir.tempo}');
      }
    }
    debugPrint('ok=$ok fail=$fail');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
