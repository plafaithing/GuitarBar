// GP1/GP2（.gtp）移植对账测试：Dart 解析 vs python 直译基线（TuxGuitar
// 规格同源）逐音比对。基线由 gb_gtp12_baseline.py 生成（tick 单位）。
// 移植期对账工具（缺基线/样本自动 skip）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:guitarbar/core/score/gtp12_parser.dart';
import 'package:guitarbar/core/score/score_ir.dart';

const _samples = [
  (
    'gtp1',
    r'C:\Users\plafa\AppData\Local\Temp\gb_gtp1_baseline.json',
    r'C:\Users\plafa\AppData\Local\Temp\gb_gtp1_sample.gtp',
  ),
  (
    'gtp2',
    r'C:\Users\plafa\AppData\Local\Temp\gb_gtp2_baseline.json',
    r'C:\Users\plafa\AppData\Local\Temp\gb_gtp2_sample.gtp',
  ),
];

/// 平铺 Dart 解析：每音（tick - 960 基准 / str / fret / durTick / 效果位）。
List<Map<String, Object?>> _flatten(ScoreIr ir) {
  final mainSig = ir.timeSignature.split('/');
  final mainNum = int.parse(mainSig[0]);
  final mainDen = int.parse(mainSig[1]);
  var numSig = mainNum;
  var denSig = mainDen;
  final notes = <Map<String, Object?>>[];
  var barTick = 0;
  for (final m in ir.tracks.first.measures) {
    final sig = m.timeSignature;
    if (sig != null) {
      final parts = sig.split('/');
      numSig = int.parse(parts[0]);
      denSig = int.parse(parts[1]);
    } else {
      numSig = mainNum;
      denSig = mainDen;
    }
    for (final n in m.notes) {
      notes.add(<String, Object?>{
        'beat': (barTick + n.beat * 960).round(),
        'str': n.string,
        'fret': n.fret,
        'dur': n.duration * 960,
        'tied': n.tieEnd ? 1 : 0,
        'hammer': n.hopoStart ? 1 : 0, // 2026-11-17 origin 语义反转
        'slide': n.slide != null ? 1 : 0,
        'vibrato': n.vibrato ? 1 : 0,
        'dead': n.technique == 'x' ? 1 : 0,
        'harmonic': n.technique == 'H' ? 1 : 0,
      });
    }
    barTick += (numSig * 4.0 / denSig * 960).round();
  }
  return notes;
}

void main() {
  for (final (label, baselinePath, samplePath) in _samples) {
    final filesMissing = !File(baselinePath).existsSync() ||
        !File(samplePath).existsSync();
    test('GTP12 对账: $label', () {
      final baseline =
          jsonDecode(File(baselinePath).readAsStringSync()) as Map<String, dynamic>;
      final ir = parseGtp12Bytes(
          Uint8List.fromList(File(samplePath).readAsBytesSync()));

      expect(ir.title, (baseline['title'] as String).trim());
      expect(ir.tempo, (baseline['tempo'] as num).toDouble());
      expect(ir.tracks.first.measures.length, baseline['measureCount']);
      expect(ir.tracks.first.name,
          (baseline['selName'] as String).trim().isEmpty ? '主旋律' : (baseline['selName'] as String).trim());
      expect(
        ir.tuning.join(','),
        [
          for (final midi in (baseline['tuning'] as List).reversed)
            if ((midi as num) > 0) _midiName(midi.toInt()),
        ].join(','),
        reason: '调弦不一致',
      );

      final pyNotes = [
        for (final n in (baseline['notes'] as List))
          <String, Object?>{
            for (final e in (n as Map<String, dynamic>).entries)
              e.key: e.value,
          }
      ];
      final dartNotes = _flatten(ir);
      expect(dartNotes.length, pyNotes.length,
          reason: '$label 音符总数不一致（基线 ${pyNotes.length} vs Dart ${dartNotes.length}）');

      final diffs = <String>[];
      for (var i = 0; i < pyNotes.length && i < dartNotes.length; i++) {
        final py = pyNotes[i];
        final da = dartNotes[i];
        bool close(num a, num b) => (a - b).abs() <= 2.0;
        final fields = <String>[
          for (final k in py.keys)
            if (k == 'beat' || k == 'dur'
                ? !close(py[k] as num, da[k] as num)
                : py[k] != da[k])
              k,
        ];
        if (fields.isNotEmpty) {
          diffs.add('#$i ${fields.join(',')}: '
              'py{${py.entries.map((e) => '${e.key}=${e.value}').join(',')}} vs '
              'dart{${da.entries.map((e) => '${e.key}=${e.value}').join(',')}}');
        }
      }
      printOnFailure('$label 差异 ${diffs.length} 条 / ${pyNotes.length} 音');
      for (var i = 0; i < diffs.length && i < 30; i++) {
        printOnFailure(diffs[i]);
      }
      expect(diffs, isEmpty, reason: '$label 逐音对账有差异');
    }, skip: filesMissing ? '基线或样本缺文件' : null);
  }
}

/// MIDI → 音名（与 music/note.dart 的 Note 同款换算，测试内联避免依赖私有）。
String _midiName(int midi) {
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  return '${names[midi % 12]}${midi ~/ 12 - 1}';
}
