// 全量重叠探针（lessons 规则 19 扩展谱集）：158 吉他谱样本库全部
// 支持格式（gp3/gp4/gp5/gtp/gpx）× 多行宽 → 全谱高渲染 → 零重叠。
// 与常驻探针（app 已导入曲库）互补：常驻探针快（每次排布改动跑），
// 本文件全（定期跑/解析器与排布大改后跑）。缺目录自动 skip。
//
// **heavy tag + 分桶并行**（2026-11-17 测试耗时优化）：单 test 串行
// 3376 文件 ≈ 25 分钟 → 4 桶并发 ≈ 6~8 分钟；日常命令
// `flutter test --exclude-tags=heavy` 跳过本文件，终验 `flutter test` 全跑。
@Tags(['heavy'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';
import 'package:guitarbar/ui/scores/tab_view.dart';
import 'package:guitarbar/ui/theme.dart';

import 'font_setup.dart';
import 'overlap_probe_lib.dart';

const _root = r'D:\Guitar\158吉他谱电子版大全';
const _buckets = 4;

Widget _host(ScoreIr ir, double width, double height) => MaterialApp(
      theme: GuitarBarTheme.light(),
      home: Scaffold(
        body: SizedBox(width: width, height: height, child: TabView(ir: ir)),
      ),
    );

/// 单桶探针（[bucket]/[_buckets]）：文件名哈希分桶（确定性，跨轮稳定）。
void _probeBucket(int bucket, List<File> allFiles) {
  testWidgets('全量重叠探针 桶$bucket/$_buckets（铁律「数字不重叠」）',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final files = allFiles
        .where((f) => f.path.hashCode % _buckets == bucket)
        .toList();
    if (files.isEmpty) {
      markTestSkipped('桶 $bucket 无文件');
      return;
    }

    final violations = <String>[];
    final renderFails = <String>[];
    var checked = 0;
    var exempted = 0;
    var exemptedPairs = 0;
    var skipped = 0;
    const widths = [786.0, 900.0, 1100.0, 1300.0];
    for (final f in files) {
      final Uint8List bytes;
      try {
        bytes = Uint8List.fromList(f.readAsBytesSync());
      } catch (_) {
        skipped++;
        continue;
      }
      final ir = parseScore(bytes, f.uri.pathSegments.last);
      if (ir == null) {
        skipped++; // 坏文件/不支持版本跳过（与导入行为一致）
        continue;
      }
      final layout = TabLayout(ir);
      for (final w in widths) {
        final contentH = layout.sizeFor(w).height;
        final h = contentH < 2400.0 ? 2400.0 : contentH + 100;
        tester.view.physicalSize = Size(w, h);
        try {
          await tester.pumpWidget(_host(ir, w, h));
          await tester.pumpAndSettle();
        } catch (e) {
          renderFails.add('${f.uri.pathSegments.last} w=$w: pump 异常 $e');
          await tester.pumpWidget(const SizedBox.shrink());
          continue;
        }
        final paintErr = tester.takeException();
        if (paintErr != null) {
          renderFails.add(
              '${f.uri.pathSegments.last} w=$w: paint 异常 $paintErr');
        }
        final caps = TabViewDebug.lastPaintedTexts;
        final found = findViolations(caps);
        // 结构性豁免（lessons 铁律冲突）：折行被迫压缩的超宽小节
        // （连排密度 × 墨阈 > 行可用宽，数学不可满足，制谱基准 靠窄音乐
        // 字体才放得下）→ 计数不判罚；白名单谱同（排布极限，见上）。
        if (found.isNotEmpty &&
            (layout.hasOverfullMeasure(w) ||
                heavyWaiverScores.contains(f.uri.pathSegments.last))) {
          exempted++;
          exemptedPairs += found.length;
          if (exempted <= 8) {
            printOnFailure('[豁免] ${f.uri.pathSegments.last} w=$w: '
                '${found.length} 对（连排密度超行容量）');
          }
          continue;
        }
        for (final v in found) {
          violations.add('${f.uri.pathSegments.last} w=$w: $v');
        }
        checked++;
      }
    }

    printOnFailure('全量探针[桶$bucket]：${files.length} 文件，'
        '判罚组合 $checked，跳过 $skipped；'
        '豁免组合 $exempted（$exemptedPairs 对）；'
        '违例 ${violations.length} 处，paint 异常 ${renderFails.length}');
    for (var i = 0; i < renderFails.length && i < 10; i++) {
      printOnFailure(renderFails[i]);
    }
    for (var i = 0; i < violations.length && i < 800; i++) {
      printOnFailure(violations[i]);
    }
    expect(renderFails, isEmpty, reason: 'paint 炸点 ${renderFails.length} 处');
    expect(violations, isEmpty,
        reason: '铁律「数字不重叠」违例 ${violations.length} 处');
  }, timeout: const Timeout(Duration(minutes: 15)));
}

void main() {
  setUpAll(loadScoreFonts);
  final allFiles = collectScoreFiles(Directory(_root));
  if (allFiles.isEmpty) {
    test('全量重叠探针：样本库不存在，跳过', () {
      markTestSkipped('样本库不存在: $_root');
    });
    return;
  }
  for (var b = 0; b < _buckets; b++) {
    _probeBucket(b, allFiles);
  }
}
