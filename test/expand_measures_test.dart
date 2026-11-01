// 播放反复展开（expandMeasures，2026-11-02 GP8 播放结构复刻）专项测试。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/gtp_parser.dart';
import 'package:guitarbar/core/score/score_ir.dart';

/// 真实反复结构样本（D:\Guitar 的月下之恋；无文件返回 null）。
File? expandFile() {
  final f = File(r'D:\Guitar\月下之恋.gpx');
  return f.existsSync() ? f : null;
}

MeasureIr m(int index,
        {bool start = false,
        bool end = false,
        int count = 0,
        List<int> endings = const []}) =>
    MeasureIr(
        index: index,
        confidence: 1,
        failed: false,
        notes: const [],
        repeatStart: start,
        repeatEnd: end,
        repeatCount: count,
        endings: endings);

void main() {
  test('无反复结构：恒等序列', () {
    final ms = [m(0), m(1), m(2)];
    expect(expandMeasures(ms), [0, 1, 2]);
  });

  test('简单反复：|A B :‖ 缺省 2 遍', () {
    final ms = [m(0, start: true), m(1), m(2, end: true), m(3)];
    expect(expandMeasures(ms), [0, 1, 2, 0, 1, 2, 3]);
  });

  test('count=3：三遍', () {
    final ms = [m(0, start: true), m(1, end: true, count: 3), m(2)];
    expect(expandMeasures(ms), [0, 1, 0, 1, 0, 1, 2]);
  });

  test('反复 + 结尾走向：第一遍走结尾 1、第二遍跳过走结尾 2', () {
    // |A [B(1) C :‖ [D(2) E —— B 仅第一遍、D 仅第二遍。
    final ms = [
      m(0, start: true),
      m(1, endings: [1]),
      m(2, end: true),
      m(3, endings: [2]),
      m(4),
    ];
    expect(expandMeasures(ms), [0, 1, 2, 0, 2, 3, 4]);
  });

  test('真实文件（存在时）：月下之恋 62 小节 → 反复展开 84 小节', () {
    final f = expandFile();
    if (f == null) {
      markTestSkipped('真实 gpx 不存在');
      return;
    }
    final ir = parseGpxBytes(f.readAsBytesSync());
    final ms = ir.tracks.single.measures;
    expect(ms, hasLength(62));
    final order = expandMeasures(ms);
    // 展开 = 62 + 22（MB#21-42 段重复一遍，第一遍未播结尾 2 的 m44）= 84。
    expect(order, hasLength(84));
    expect(order.first, 0);
    // 第二遍从线性 MB#21（idx 20）开始：位置 43 = 0..19 + 20..42 共 43 个。
    expect(order[43], 20);
    // 结尾 1（m27, idx 26）只播第一遍、结尾 2（m44, idx 43）只播第二遍。
    expect(order.where((i) => i == 26), hasLength(1));
    expect(order.where((i) => i == 43), hasLength(1));
    // 结尾 2 在结尾 1 之后才出现。
    expect(order.indexOf(43), greaterThan(order.indexOf(26)));
  });
}
