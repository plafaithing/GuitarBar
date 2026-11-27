// 一次性诊断：Prologue 全曲逐小节声音覆盖——每小节新拨弦事件数 +
// tie 延长覆盖 + 空白拍段（听感无声 >0.5 拍的段清单，定位用户指认
// 的"指针到了不响"小节）。
@Tags(['heavy'])
library;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/sample_bank.dart';
import 'package:guitarbar/audio/sample_player.dart';
import 'package:guitarbar/core/score/score_ir.dart';

import 'overlap_probe_lib.dart' show parseScore;
import 'score_player_test.dart' show FakeEngine;

void main() {
  test('Prologue 声音覆盖', () async {
    final f = File(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores\87\source.gtp');
    final ir = parseScore(f.readAsBytesSync(), 'x')!;
    final engine = FakeEngine();
    final bank = SteelSampleBank(engine,
        assetLoader: (_) async => ByteData(4));
    // FakeEngine + 空采样：play 会 false（预载失败）——不走 play，
    // 直接读内部表（playbackOrderMeasures）+ 手算覆盖。
    final player = SampleScorePlayer(engine, bank);
    // 先触发 _collectEvents（play 里）——空采样会降级 false……改用
    // 反射不可行；改为公开接口：play 失败也填了 playbackOrder*？
    // 验证：_collectEvents 在 play 里预载前调用（230 行）——表已填。
    await player.play(ir);
    final ms = ir.tracks.first.measures;
    final order = player.playbackOrderMeasures;
    final starts = player.playbackOrderStarts;
    final beatSec = 60.0 / ir.tempo;
    debugPrint('表长=${order.length} tempo=${ir.tempo}');
    // 逐展开小节：音符事件（tieEnd 不算新拨弦，时长入延长）。
    final out = <String>[];
    for (var k = 0; k < order.length; k++) {
      final mIdx = order[k];
      final m = ms[mIdx];
      final base = starts[k];
      var plucks = 0, tieExtends = 0;
      final spans = <double>[]; // 新拨弦的 (absBeat, noteSeconds)
      for (final n in m.notes) {
        if (n.tieEnd) {
          tieExtends++;
          continue;
        }
        plucks++;
        spans.add(base + n.beat);
        spans.add(n.duration * beatSec);
      }
      // 空白检测：小节内（6 拍）无拨弦且无延长 → 纯空白；部分空白
      // 需链首 noteSeconds——本诊断只标注拨弦数与延长数。
      if (plucks == 0 || tieExtends > 0) {
        out.add('展开k=$k 线性m${mIdx + 1} 拨弦=$plucks tie延续=$tieExtends '
            '起拍=${base.toStringAsFixed(1)}');
      }
    }
    // 全曲 tie 延长后的实际 voice 覆盖算不了（noteSeconds 在私有结构），
    // 用拨弦+tie 计数先分型。
    for (final s in out) {
      debugPrint(s);
    }
    debugPrint('共 ${out.length} 个低拨弦/含tie小节');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
