// GP3/GP4 全量扫描：158 目录全部 .gp3/.gp4 逐个解析，零炸点验证。
// 魔数分层（与 score_repository._gpBinaryFlavor 同口径）：
// v3/v4 → parseGp34Bytes；错标 v5 → parseGp5Bytes 自愈；
// v1/v2 老格式跳过。与 PyGuitarPro 全量判决双向对账（Temp 的
// gb_gp34_pyverdict.json，由 gb_gp34_pyscan.py 生成；缺文件时只做
// 单向健全性扫描）：py 失败的文件 dart 失败合法；py 成功的 dart
// 必须成功。健全性：弦号不超调弦数、时值为正。
// 缺目录自动 skip（换机器/无曲库时 CI 不挂）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:guitarbar/core/score/gp34_parser.dart';
import 'package:guitarbar/core/score/gp5_parser.dart';
import 'package:guitarbar/core/score/score_ir.dart';

const _root = r'D:\Guitar\158吉他谱电子版大全';
const _pyVerdict = r'C:\Users\plafa\AppData\Local\Temp\gb_gp34_pyverdict.json';

String? _flavor(List<int> bytes) {
  if (bytes.length < 31) return null;
  final head4 = latin1.decode(bytes.sublist(0, 4));
  if (head4 == 'BCFZ' || head4.startsWith('PK')) return 'gpx';
  final size = bytes[0];
  final raw = latin1.decode(bytes.sublist(1, 31));
  final version =
      (size < 1 ? '' : raw.substring(0, size < 30 ? size : 30)).trim();
  if (version.contains('v3.') ||
      version.contains('v4.') ||
      version.contains('L4.')) {
    return 'gp34';
  }
  if (version.contains('v5.')) return 'gp5';
  return null;
}

List<File> _collect() {
  final files = <File>[];
  void walk(Directory dir) {
    for (final e in dir.listSync()) {
      if (e is Directory) {
        walk(e);
      } else if (e is File) {
        final ext = e.path.toLowerCase();
        if (ext.endsWith('.gp3') || ext.endsWith('.gp4')) files.add(e);
      }
    }
  }

  final root = Directory(_root);
  if (!root.existsSync()) return files;
  walk(root);
  return files;
}

void main() {
  test('GP34 全量扫描（158 目录）', () {
    final files = _collect();
    if (files.isEmpty) {
      markTestSkipped('曲谱目录不存在: $_root');
      return;
    }
    expect(files.length, greaterThan(100), reason: '样本数异常偏少');

    // PyGuitarPro 全量判决（可选）：py 失败文件的绝对路径集合。
    final pyBad = <String>{};
    final verdictFile = File(_pyVerdict);
    if (verdictFile.existsSync()) {
      final verdict =
          jsonDecode(verdictFile.readAsStringSync()) as Map<String, dynamic>;
      for (final line in (verdict['bad'] as List)) {
        pyBad.add((line as String).split(' | ').first);
      }
    }

    final failures = <String>[];
    var gp3 = 0;
    var gp4 = 0;
    var gp5Mislabeled = 0;
    var legacy = 0;
    var pyBadSkipped = 0;
    var totalNotes = 0;
    for (final f in files) {
      final isGp3 = f.path.toLowerCase().endsWith('.gp3');
      isGp3 ? gp3++ : gp4++;
      // PyGuitarPro 也失败的坏文件：跳过（参考实现同样炸 = 文件问题）。
      if (pyBad.contains(f.path)) {
        pyBadSkipped++;
        continue;
      }
      final bytes = f.readAsBytesSync();
      try {
        final flavor = _flavor(bytes);
        if (flavor == null) {
          // GP1/2 老格式或坏文件（PyGuitarPro 也不支持 GP1/2）。
          legacy++;
          continue;
        }
        final ScoreIr ir;
        if (flavor == 'gp5') {
          gp5Mislabeled++;
          ir = parseGp5Bytes(bytes);
        } else {
          ir = parseGp34Bytes(bytes);
        }
        final stringCount = ir.tuning.length;
        for (final track in ir.tracks) {
          for (final m in track.measures) {
            for (final n in m.notes) {
              totalNotes++;
              if (n.string < 1 || n.string > stringCount) {
                failures.add('${f.path} m${m.index + 1}: 弦号 ${n.string}'
                    ' 超出调弦数 $stringCount');
              }
              if (n.duration <= 0) {
                failures.add(
                    '${f.path} m${m.index + 1}: 时值非正 ${n.duration}');
              }
            }
          }
        }
      } catch (e) {
        failures.add('${f.path}: $e');
      }
    }
    printOnFailure('扫描 ${files.length} 个文件'
        '（gp3 $gp3 / gp4 $gp4，其中错标 v5 $gp5Mislabeled、'
        'GP1/2 老格式 $legacy、py 同判坏 $pyBadSkipped），共 $totalNotes 音');
    for (var i = 0; i < failures.length && i < 40; i++) {
      printOnFailure(failures[i]);
    }
    expect(failures.length, 0,
        reason: '失败 ${failures.length} / ${files.length}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
