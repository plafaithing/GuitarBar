// 一次性诊断：全曲库 sample 预载缺失扫描——每谱每音 resolve 出的采样
// 文件名对照真实 assets 清单，报告哪些谱会降级 KS、缺哪些采样。
@Tags(['heavy'])
library;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/sample_bank.dart';
import 'package:guitarbar/core/music/note.dart';
import 'package:guitarbar/core/score/score_ir.dart';

import 'overlap_probe_lib.dart' show parseScore;

void main() {
  test('全曲库采样缺失扫描', () {
    // 真实 app 的 assets 清单（build 产物）。
    final assetsDir = Directory(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\flutter_assets\assets\sounds\steel');
    final have = <String>{
      for (final f in assetsDir.listSync()) f.path.split(r'\').last
    };
    debugPrint('assets 采样数=${have.length}');
    final libDir = Directory(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores');
    final missByTitle = <String, Set<String>>{};
    var checked = 0, degraded = 0;
    for (final d in libDir.listSync()) {
      File? f;
      for (final name in ['source.gtp', 'source.gpx', 'source.gp5', 'source.gp3', 'source.gp4']) {
        final cand = File('${d.path}\\$name');
        if (cand.existsSync()) {
          f = cand;
          break;
        }
      }
      if (f == null) continue;
      final ir = parseScore(f.readAsBytesSync(), d.path.split(r'\').last);
      if (ir == null || ir.tracks.isEmpty) continue;
      checked++;
      final tunings = [
        for (final s in ir.tuning)
          Note.parse(s).midi
      ];
      final missing = <String>{};
      final capoShift = ir.capoApplied ? 0 : ir.capo;
      for (final m in ir.tracks.first.measures) {
        for (final n in m.notes) {
          if (n.tieEnd) continue;
          final tuningNote = tunings.length == 6 ? tunings[6 - n.string] : null;
          if (tuningNote == null) {
            missing.add('<弦数=${tunings.length}>');
            continue;
          }
          final soundingMidi = tuningNote + capoShift + n.fret;
          // Up/Down 双层都查（播放器交替拨弦会用到 Down 层）。
          for (final ds in [false, true]) {
            final r = SteelSampleBank.resolve(
                string: n.string,
                fret: n.fret,
                soundingMidi: soundingMidi,
                technique: n.technique,
                downstroke: ds,
                harmonicOffset: n.harmonicOffset);
            if (r == null) {
              missing.add('<resolve null s${n.string} f${n.fret} '
                  'ds=$ds>');
              continue;
            }
            if (!have.contains(r.file)) missing.add(r.file);
          }
        }
      }
      if (missing.isNotEmpty) {
        degraded++;
        missByTitle['${ir.title} (${d.path.split(r'\').last})'] = missing;
      }
    }
    debugPrint('checked=$checked degraded=$degraded');
    for (final e in missByTitle.entries) {
      debugPrint('--- ${e.key}: 缺 ${e.value.length} 种');
      for (final m in e.value.take(6)) {
        debugPrint('    $m');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
