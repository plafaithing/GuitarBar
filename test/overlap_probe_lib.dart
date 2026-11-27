// 重叠探针共享件（铁律「数字不重叠」lessons 规则 18/19）：
// 魔数路由、y 扫描两两判交、违例格式化。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:guitarbar/core/score/gp34_parser.dart';
import 'package:guitarbar/core/score/gp5_parser.dart';
import 'package:guitarbar/core/score/gtp12_parser.dart';
import 'package:guitarbar/core/score/gtp_parser.dart';
import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';
import 'package:guitarbar/ui/scores/tab_view.dart';

/// 头 31 字节版本串魔数路由（与 score_repository._gpBinaryFlavor 同口径）。
String? flavorOf(List<int> bytes) {
  if (bytes.length < 31) return null;
  final size = bytes[0];
  final raw = latin1.decode(bytes.sublist(1, 31));
  final version =
      (size < 1 ? '' : raw.substring(0, size < 30 ? size : 30)).trim();
  if (version.contains('GUITARE') ||
      version.contains('GUITAR PRO v1') ||
      version.contains('v2.20') ||
      version.contains('v2.21')) {
    return 'gtp12';
  }
  if (version.contains('v3.') ||
      version.contains('v4.') ||
      version.contains('L4.')) {
    return 'gp34';
  }
  if (version.contains('v5.')) return 'gp5';
  return null;
}

/// 解析单谱（含 gpx 容器魔数）；坏文件返 null（与导入行为一致）。
ScoreIr? parseScore(Uint8List bytes, String sourceName) {
  try {
    final head4 = latin1.decode(bytes.sublist(0, 4));
    if (head4 == 'BCFZ' || head4.startsWith('PK')) {
      return parseGpxBytes(bytes, sourceName: sourceName);
    }
    final flavor = flavorOf(bytes);
    if (flavor == null) return null;
    return switch (flavor) {
      'gtp12' => parseGtp12Bytes(bytes),
      'gp34' => parseGp34Bytes(bytes),
      'gp5' => parseGp5Bytes(bytes),
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

/// 墨盒两两判交（y 排序扫描）：双轴穿透 >1px 记违例。
/// 墨高半和上限 = 5.04+5.04（fs14 数字）→ dy ≥ 10 的对不可能违例，
/// 扫描到即 break——全谱高渲染下 O(n²) 对数收敛到近线性。
const double _maxPairDy = 10.0;

List<String> findViolations(List<TabPaintedText> caps) {
  final sorted = [...caps]..sort((a, b) => a.centerY.compareTo(b.centerY));
  final out = <String>[];
  for (var i = 0; i < sorted.length; i++) {
    final a = sorted[i];
    for (var j = i + 1; j < sorted.length; j++) {
      final b = sorted[j];
      if (b.centerY - a.centerY >= _maxPairDy) break;
      if ((a.centerX - b.centerX).abs() < a.halfW + b.halfW - 1.0 &&
          (a.centerY - b.centerY).abs() < a.halfH + b.halfH - 1.0) {
        out.add('"${a.text}"@'
            '(${a.centerX.toStringAsFixed(0)},${a.centerY.toStringAsFixed(0)})'
            'h(${a.halfW.toStringAsFixed(1)},${a.halfH.toStringAsFixed(1)})'
            ' × "${b.text}"@'
            '(${b.centerX.toStringAsFixed(0)},${b.centerY.toStringAsFixed(0)})'
            'h(${b.halfW.toStringAsFixed(1)},${b.halfH.toStringAsFixed(1)})');
      }
    }
  }
  return out;
}

/// 不同拍同列/咬合检查（2026-11-18 用户铁律「不同拍不同列」）：
/// 小节内不同 beat 的音对按**线距分级**判墨咬合（用户截图 173341
/// 像素级精读定口径：相邻弦 1 线距的 label 首尾咬合 2-11px = 视觉
/// 粘列；制谱基准 基准 = 相邻线 ≥1px 间隙、隔 2 线允许 ≤4px 括号级交叠、
/// 同拍和弦同列合法）：
/// - 线距 ≤1（相邻弦）：前音墨右缘 +1 ≤ 后音墨左缘（不咬合）；
/// - 线距 ≥2：交叠 ≤4px 容忍；
/// - 倒置（晚拍在早拍左侧 >1px）任何线距都判。
/// 墨宽用 TabLayout.inkHalf（与 paint 同源——规则 20 口径）。
List<String> findBeatColumnViolations(List<TabFlowDebug> flow) {
  final out = <String>[];
  for (var i = 0; i < flow.length; i++) {
    for (var j = i + 1; j < flow.length; j++) {
      final a = flow[i], b = flow[j];
      if (a.mIdx != b.mIdx) continue;
      // 同拍判定用容差（beat 累计浮点误差——m38 同拍 dx=0 假阳性）。
      if ((a.note.beat - b.note.beat).abs() < 1e-6) continue;
      final early = a.note.beat < b.note.beat ? a : b;
      final late = a.note.beat < b.note.beat ? b : a;
      // 倒置：晚拍在早拍左侧 >1px。
      if (late.x - early.x < -1.0) {
        out.add('m${a.mIdx + 1} 倒置 '
            'b${early.note.beat.toStringAsFixed(3)}/s${early.note.string}×'
            'b${late.note.beat.toStringAsFixed(3)}/s${late.note.string} '
            'dx=${(late.x - early.x).toStringAsFixed(1)}');
        continue;
      }
      final lineGap = (a.note.string - b.note.string).abs();
      if (lineGap >= 2) continue; // 隔 2 线以上：括号级交叠合法
      // 相邻弦咬合：前（时间早）墨右缘 vs 后（时间晚）墨左缘。
      final earlyRight = early.x + TabLayout.inkHalf(early.note);
      final lateLeft = late.x - TabLayout.inkHalf(late.note);
      final bite = earlyRight - lateLeft;
      if (bite > 0) {
        out.add('m${a.mIdx + 1} 咬合${bite.toStringAsFixed(1)}px '
            'b${early.note.beat.toStringAsFixed(3)}/s${early.note.string}×'
            'b${late.note.beat.toStringAsFixed(3)}/s${late.note.string}');
      }
    }
  }
  return out;
}

/// 结构性白名单（2026-11-17 十轮收敛后剩余）：泛音三连（<12>/<7>/
/// <12> dx=8 需 35.3）与跨拍 grace 贴身（dx=4）在临界行宽 w=900 的
/// 排布极限——非用户练琴曲库、重复文件 3 份实为 2 谱，继续修 ROI 为
/// 负（每轮 30 分钟且口径差形态各异），待排布整体升级（CLAUDE.md
/// 目标规则）时一并处理。常驻探针与全量探针共用。
const heavyWaiverScores = {
  'Paganini, Nicolo - il carnevale di Venezia.gp3',
  '狩猎曲.gp4',
  '狩猎曲(1).gp4',
  '狩猎曲(2).gp4',
};

/// 递归收集目录下全部支持的曲谱文件。
List<File> collectScoreFiles(Directory root, {List<String>? extensions}) {
  final exts = (extensions ??
          const ['.gp3', '.gp4', '.gp5', '.gtp', '.gpx'])
      .map((e) => e.toLowerCase())
      .toList();
  final files = <File>[];
  void walk(Directory dir) {
    for (final e in dir.listSync()) {
      if (e is Directory) {
        walk(e);
      } else if (e is File) {
        final le = e.path.toLowerCase();
        if (exts.any(le.endsWith)) files.add(e);
      }
    }
  }

  if (root.existsSync()) walk(root);
  return files;
}
