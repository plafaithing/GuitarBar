// 项目铁律「数字不重叠」常驻探针（lessons.md 规则 18/19）：
// 真实曲库（app 已导入曲谱 + Temp 样本）× 多行宽（786~1300，覆盖
// effectiveWidth 上限）逐帧捕获 paint 真实墨盒（TabViewDebug）→
// 两两判相交（双轴穿透 >1px）→ 零重叠。任何排布/标注改动后必须过。
// 曲库缺文件自动缩谱集（换机器 CI 不挂）。
//
// 渲染高度 = 谱面全高（TabLayout.sizeFor）——旧 h=2400 只覆盖前 ~12
// 行，长谱（LAS 30+ 行）下方行漏检（2026-11-16 全量扫描时补的洞）。
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

const _appDataScores =
    r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores';
const _extraSamples = [
  r'C:\Users\plafa\AppData\Local\Temp\gb_gp34_sample.gp4', // 世界最慢
  r'C:\Users\plafa\AppData\Local\Temp\gb_gtp1_sample.gtp', // GP1 样本
  r'C:\Users\plafa\AppData\Local\Temp\gb_gtp2_sample.gtp', // GP2 样本
];
/// 158 库"历史雷区"名单（lessons 规则 19 的常驻兜底——每轮修复引出
/// 过残类的谱，日常快速探针必测；全量探针另行覆盖全库）：
/// 时间.gp3（grace 谱面级滥用）/Paganini（grace 贴身）/狩猎曲（泛音
/// 三连）/第一次2（跨小节 grace）/哆啦A梦与 Prologue（app 曲库已含）。
const _heavyLibRoot = r'D:\Guitar\158吉他谱电子版大全';
const _heavyLibNames = ['时间.gp3', 'Paganini', '狩猎曲', '第一次2'];

Widget _host(ScoreIr ir, double width, double height) => MaterialApp(
      theme: GuitarBarTheme.light(),
      home: Scaffold(
        body: SizedBox(width: width, height: height, child: TabView(ir: ir)),
      ),
    );

void main() {
  setUpAll(loadScoreFonts);
  testWidgets('重叠探针：真实曲库 × 多行宽（铁律「数字不重叠」）', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // —— 谱集发现（app 已导入 + 额外样本 + 158 库雷区）——
    final files = <File>[];
    final scoresDir = Directory(_appDataScores);
    if (scoresDir.existsSync()) {
      files.addAll(collectScoreFiles(scoresDir));
    }
    for (final p in _extraSamples) {
      final f = File(p);
      if (f.existsSync()) files.add(f);
    }
    // 雷区名单（存在才加——换机器/无曲库自动缩谱集）
    if (Directory(_heavyLibRoot).existsSync()) {
      files.addAll(collectScoreFiles(Directory(_heavyLibRoot))
          .where((f) => _heavyLibNames.any(f.path.contains)));
    }
    expect(files.length, greaterThan(5), reason: '探针谱集异常偏少：$_appDataScores');

    // —— 逐谱 × 逐宽探针 ——
    final violations = <String>[];
    final inkViolations = <String>[];
    final colViolations = <String>[];
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
      final ScoreIr ir;
      try {
        final parsed =
            parseScore(bytes, f.uri.pathSegments.last);
        if (parsed == null) {
          skipped++;
          continue;
        }
        ir = parsed;
      } catch (_) {
        skipped++; // 坏文件跳过（与导入行为一致：报错不崩）
        continue;
      }
      final layout = TabLayout(ir);

      for (final w in widths) {
        // 谱面全高（长谱全部行入帧；sizeFor 按行数算高）。
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
        // 不同拍同列铁律（2026-11-18 用户定案）：本探针的 findBeatColumn
        // Violations 只**计数记档**（供诊断聚合）；铁律的**判罚闸门**在
        // 折行求解器（2026-11-27）：候选行调渲染同一个 buildRowFlow 预测
        // 终位，非豁免近似同列/倒置在折行时直接拒行——预测渲染干净才
        // 合并。残余不判罚类（度量口径，tool_diag_colcount 量化）：
        // 宽标签跨弦咬合（`<12>` 级联形态，用户验收接受）与装饰槽位
        // 倒置（渲染层设计豁免）——app 曲库均 0 或接受值。
        final beatCols = findBeatColumnViolations(TabViewDebug.lastFlow);
        // 结构性豁免（与全量探针同口径，规则 22）：折行被迫压缩的超宽
        // 行 + 白名单谱（雷区谱集含已知排布极限谱）。
        if (found.isNotEmpty &&
            (layout.hasOverfullMeasure(w) ||
                heavyWaiverScores.contains(f.uri.pathSegments.last))) {
          exempted++;
          exemptedPairs += found.length;
          printOnFailure('[豁免] ${f.uri.pathSegments.last} w=$w: '
              '${found.length} 对（结构性/白名单）');
          continue;
        }
        for (final v in found) {
          violations.add('${f.uri.pathSegments.last} w=$w: $v');
          inkViolations.add('${f.uri.pathSegments.last} w=$w: $v');
        }
        // 同列/倒置：计数记档（printOnFailure 汇总），不进判罚清单。
        colViolations.addAll(beatCols
            .map((v) => '${f.uri.pathSegments.last} w=$w $v'));
        checked++;
      }
    }

    printOnFailure('探针：判罚组合 $checked，跳过 $skipped；'
        '豁免组合 $exempted（$exemptedPairs 对，结构性不可满足）；'
        '墨重叠 ${inkViolations.length} 处 + 同列 ${colViolations.length} 处'
        ' = ${violations.length}，paint 异常 ${renderFails.length}');
    for (var i = 0; i < renderFails.length && i < 10; i++) {
      printOnFailure(renderFails[i]);
    }
    for (var i = 0; i < violations.length && i < 40; i++) {
      printOnFailure(violations[i]);
    }
    expect(renderFails, isEmpty, reason: 'paint 炸点 ${renderFails.length} 处');
    expect(violations, isEmpty,
        reason: '铁律「数字不重叠」违例 ${violations.length} 处');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
