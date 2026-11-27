// GP3/GP4 移植对账测试：Dart 解析结果 vs PyGuitarPro 基线逐音比对。
// 基线由 C:\Users\plafa\AppData\Local\Temp\gb_gp34_baseline.py 生成。
// 本文件是移植期对账工具，格式稳定后转正式金测试。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:guitarbar/core/score/gp34_parser.dart';
import 'package:guitarbar/core/score/score_ir.dart';

const _samples = [
  (
    'gp3',
    r'C:\Users\plafa\AppData\Local\Temp\gb_gp3_baseline.json',
    r'D:\Guitar\158吉他谱电子版大全\gtp格式-吉他谱全集\gtp格式 歌手目录\伤心1999-加旋律.gp3',
  ),
  (
    'gp4',
    r'C:\Users\plafa\AppData\Local\Temp\gb_gp4_baseline.json',
    // 原路径含零宽字符目录名，对账用 Temp 副本（内容相同）。
    r'C:\Users\plafa\AppData\Local\Temp\gb_gp34_sample.gp4',
  ),
];

/// 平铺 Dart 解析结果：每音（绝对 tick，str，fret，时值 tick，效果位）。
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
      // null = 回到全局拍号（不是保持上一小节！）。
      numSig = mainNum;
      denSig = mainDen;
    }
    for (final n in m.notes) {
      notes.add(<String, Object?>{
        'beat': (barTick + n.beat * 960).round(),
        'str': n.string,
        'fret': n.fret,
        'durTick': n.duration * 960,
        'tied': n.tieEnd ? 1 : 0,
        'hammer': n.hopoStart ? 1 : 0, // 2026-11-17 origin 语义反转：标志
        // 位仍在文件标志音上（py 侧同位），弧向由渲染层处理
        'slide': n.slide != null ? 1 : 0,
        'vibrato': n.vibrato ? 1 : 0,
        'ghost': n.ghost ? 1 : 0,
        'staccato': n.staccato ? 1 : 0,
        'palmMute': n.palmMute ? 1 : 0,
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
    test('GP34 对账: $label', () {
      final baselineFile = File(baselinePath);
      final sampleFile = File(samplePath);

      final baseline =
          jsonDecode(baselineFile.readAsStringSync()) as Map<String, dynamic>;
      final ir = parseGp34Bytes(
          Uint8List.fromList(sampleFile.readAsBytesSync()));

      // 基线 timeSig 形如 "4/Duration(value=4, isDotted=False, ...)"
      //（拍号本身不参与对账：py 音的 beat 是绝对 tick 直取）。
      final pyTrack = (baseline['tracks'] as List).first as Map<String, dynamic>;
      final pyNotes = <Map<String, Object?>>[];
      for (final m in (pyTrack['measures'] as List)) {
        for (final n in ((m as Map<String, dynamic>)['notes'] as List)) {
          final nd = n as Map<String, dynamic>;
          pyNotes.add(<String, Object?>{
            'beat': nd['beat'],
            'str': nd['str'],
            'fret': nd['fret'],
            'durTick': 4.0 / (nd['dur'] as int).toDouble() *
                (nd['dotted'] == 1 ? 1.5 : 1.0) *
                (nd['tupletRatio'] as num).toDouble() *
                960,
            'tied': nd['tied'],
            'hammer': nd['hammer'],
            'slide': nd['slide'],
            'vibrato': nd['vibrato'],
            'ghost': nd['ghost'],
            'staccato': nd['staccato'],
            'palmMute': nd['palmMute'],
            'harmonic': nd['harmonic'],
          });
        }
      }

      // py 侧对齐产品的 tie 合并口径：tied=1 的音时值并入**直接前一同弦音**
      //（链式——中间 tied 音也吸收后音，与 gp34_parser 的 _refs 逐音登记一致）。
      for (var i = 1; i < pyNotes.length; i++) {
        if (pyNotes[i]['tied'] == 1) {
          var j = i - 1;
          while (j >= 0 && pyNotes[j]['str'] != pyNotes[i]['str']) {
            j--;
          }
          if (j >= 0) {
            pyNotes[j]['durTick'] =
                (pyNotes[j]['durTick'] as num) + (pyNotes[i]['durTick'] as num);
          }
        }
      }
      // PyGuitarPro 绝对 tick 从 quarterTime(960) 起步（gp3.py:384
      // `start = gp.Duration.quarterTime`），产品拍数从 0 起——对齐基准。
      for (final n in pyNotes) {
        n['beat'] = (n['beat'] as num) - 960;
      }

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
            if (k == 'beat' || k == 'durTick'
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
