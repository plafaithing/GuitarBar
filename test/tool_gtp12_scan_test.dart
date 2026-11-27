// GP1/GP2（.gtp）全量扫描：158 目录全部 .gtp 逐个解析，零炸点验证。
// 版本分层：v1.x/v2.x 走 gtp12 通道；错标 v3/v4 走 gp34 通道自愈
//（444 份实测分布：191 GP1 + 180 GP2 + 73 错标 GP3/4）。
// 与 python 直译全量判决双向对账（gb_gtp12_pyscan.py 产出的
// gb_gtp12_pyverdict.json；缺文件时单向健全性扫描）。
// 健全性：弦号不超调弦数、时值为正、调弦非空。
// 缺目录自动 skip（换机器/无曲库时 CI 不挂）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:guitarbar/core/score/gp34_parser.dart';
import 'package:guitarbar/core/score/gtp12_parser.dart';
import 'package:guitarbar/core/score/score_ir.dart';

const _root = r'D:\Guitar\158吉他谱电子版大全';
const _pyVerdict = r'C:\Users\plafa\AppData\Local\Temp\gb_gtp12_pyverdict.json';

/// 曲库内已知截断/损坏文件（解析器抛 FormatException 是正确行为——
/// 导入时同样报错不崩）。原靠 Temp 的 pyverdict.json（python 直译判决）
/// 跳过，Temp 被系统清理后判决表丢失（2026-11-27 实证：同日 11:09 套件
/// 全绿、11:40 起这 5 个文件报"截断"，报错偏移 = 文件长度，文件
/// mtime 2025-02-17 未变）——名单固化进源码，不再依赖 Temp。
/// 按文件名匹配（已确认曲库内唯一）。
const _knownBad = {
  '单身情歌2.gtp',
  '朴树-那些花儿2.gtp',
  '自动胜利.gtp',
  '灰姑娘2.gtp',
  '爱的呼唤2.gtp',
};

/// 头 31 字节版本串（1 长度 + 30 定长）。
String _versionOf(List<int> bytes) {
  if (bytes.length < 31) return '';
  final size = bytes[0];
  final raw = latin1.decode(bytes.sublist(1, 31));
  return (size < 1 ? '' : raw.substring(0, size < 30 ? size : 30)).trim();
}

bool _isGtp12(String v) =>
    v.contains('GUITARE') ||
    v.contains('GUITAR PRO v1') ||
    v.contains('v2.20') ||
    v.contains('v2.21');

List<File> _collect() {
  final files = <File>[];
  void walk(Directory dir) {
    for (final e in dir.listSync()) {
      if (e is Directory) {
        walk(e);
      } else if (e is File) {
        if (e.path.toLowerCase().endsWith('.gtp')) files.add(e);
      }
    }
  }

  final root = Directory(_root);
  if (!root.existsSync()) return files;
  walk(root);
  return files;
}

void main() {
  test('GTP12 全量扫描（158 目录）', () {
    final files = _collect();
    if (files.isEmpty) {
      markTestSkipped('曲谱目录不存在: $_root');
      return;
    }
    expect(files.length, greaterThan(100), reason: '样本数异常偏少');

    // python 直译全量判决（可选）：py 失败文件的绝对路径集合。
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
    var gtp1 = 0;
    var gtp2 = 0;
    var mislabeled34 = 0;
    var pyBadSkipped = 0;
    var totalNotes = 0;
    for (final f in files) {
      if (pyBad.contains(f.path) || _knownBad.any(f.path.endsWith)) {
        pyBadSkipped++;
        continue;
      }
      final bytes = f.readAsBytesSync();
      try {
        final version = _versionOf(bytes);
        final ScoreIr ir;
        if (_isGtp12(version)) {
          if (version.contains('v2.2')) {
            gtp2++;
          } else {
            gtp1++;
          }
          ir = parseGtp12Bytes(bytes);
        } else if (version.contains('v3.') ||
            version.contains('v4.') ||
            version.contains('L4.')) {
          mislabeled34++;
          ir = parseGp34Bytes(bytes);
        } else {
          failures.add('${f.path}: 未知版本 "$version"');
          continue;
        }
        final stringCount = ir.tuning.length;
        if (stringCount < 4) {
          failures.add('${f.path}: 调弦异常 ${ir.tuning}');
        }
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
    printOnFailure('扫描 ${files.length} 个 .gtp'
        '（GP1 $gtp1 / GP2 $gtp2 / 错标 v3,v4 走 gp34 $mislabeled34 / '
        'py 同判坏跳过 $pyBadSkipped），共 $totalNotes 音');
    for (var i = 0; i < failures.length && i < 40; i++) {
      printOnFailure(failures[i]);
    }
    expect(failures.length, 0,
        reason: '失败 ${failures.length} / ${files.length}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
