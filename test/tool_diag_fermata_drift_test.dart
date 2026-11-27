// 延长记号漂移量化（2026-11-27）：app 曲库每首谱的延长记号数量、
// 旧换算（秒 ÷ 拍长，不扣顺延）到曲末会累积超前多少拍/秒，以及修复后
// 的不变量——展开序上每个会发声的音：playBeatAt(其发声秒) == 其展开拍位。
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/sample_bank.dart';
import 'package:guitarbar/audio/sample_player.dart';
import 'package:guitarbar/core/score/score_ir.dart';

import 'overlap_probe_lib.dart';
import 'score_player_test.dart' show FakeEngine;

const _root =
    'D:/workplace/code/GuitarBar/build/windows/x64/runner/Release/data';

void main() {
  test('fermata drift', () {
    final list = (jsonDecode(File('tasks/_db_scores.json').readAsStringSync())
            as List)
        .cast<Map>();
    var totalChecked = 0;
    final bad = <String>[];
    for (final e in list) {
      final id = e['id'] as int;
      final title = e['title'] as String;
      final f = Directory('$_root/scores/$id').listSync().firstWhere(
          (x) => const ['.gpx', '.gp5', '.gp3', '.gp4', '.gtp']
              .any(x.path.endsWith));
      final ir = parseScore(File(f.path).readAsBytesSync(), 'source.gpx');
      if (ir == null) continue;
      final engine = FakeEngine();
      final player = SampleScorePlayer(
          engine, SteelSampleBank(engine, assetLoader: (_) async => ByteData(4)));
      player.prepare(ir);
      final measures = ir.tracks.first.measures;
      // 展开序上的延长记号（含反复的第二遍）与总顺延。
      var fermatas = 0;
      var extraBeats = 0.0;
      for (final mi in player.playbackOrderMeasures) {
        for (final fm in measures[mi].fermatas) {
          fermatas++;
          extraBeats += fm.length;
        }
      }
      final bs = 60.0 / ir.tempo;
      // 不变量：每个会发声的音（首次遍次），其起播秒逆换算回自己的展开拍。
      var checked = 0;
      for (var k = 0; k < player.playbackOrderMeasures.length; k++) {
        final mi = player.playbackOrderMeasures[k];
        if (k != player.playbackOrderMeasures.indexOf(mi)) continue; // 仅首次遍次
        for (final n in measures[mi].notes) {
          if (n.tieEnd) continue;
          final t = player.startSecondsForBeat(mi, n.beat);
          if (t == null) continue;
          final want = player.playbackOrderStarts[k] + n.beat;
          final got = player.playBeatAt(t);
          checked++;
          if ((got - want).abs() > 1e-6) {
            bad.add('$title m${mi + 1} b${n.beat}: 期望拍 $want 实得 $got');
          }
        }
      }
      totalChecked += checked;
      for (var k = 0; k < player.playbackOrderMeasures.length; k++) {
        final mi = player.playbackOrderMeasures[k];
        for (final fm in measures[mi].fermatas) {
          // ignore: avoid_print
          print('    $title 延长记号：m${mi + 1} 第 ${fm.beat + 1} 拍，'
              '顺延 ${fm.length} 拍；该拍上的音：'
              '${measures[mi].notes.where((n) => (n.beat - fm.beat).abs() < 1e-6).map((n) => "s${n.string}f${n.fret}").join(",")} '
              '/ 小节末拍 ${measures[mi].notes.map((n) => n.beat).fold<double>(0, math.max)}');
        }
      }
      // ignore: avoid_print
      print('${title.padRight(22)} 延长记号 $fermatas 处 / 曲末旧换算超前 '
          '${extraBeats.toStringAsFixed(1)} 拍 = '
          '${(extraBeats * bs).toStringAsFixed(2)} 秒；不变量核对 $checked 音');
    }
    // ignore: avoid_print
    print('不变量违例 ${bad.length} 处 / 共核对 $totalChecked 音');
    for (final b in bad.take(10)) {
      // ignore: avoid_print
      print('  BAD $b');
    }
  });
}
