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

  test('反复 + 结尾走向：第二遍跳过整个结尾 1 管辖区直达结尾 2', () {
    // |A [B(1) C :‖ [D(2) E —— 结尾 1 管辖区 = B 至反复线 C（含），
    // 第二遍跳过 B、C 直达 D（2026-11-02 用户实测 GP8 行为修正）。
    final ms = [
      m(0, start: true),
      m(1, endings: [1]),
      m(2, end: true),
      m(3, endings: [2]),
      m(4),
    ];
    expect(expandMeasures(ms), [0, 1, 2, 0, 3, 4]);
  });

  test('真实文件（存在时）：月下之恋 62 线性 → 68 播放段（结尾 1 管辖 27-43）', () {
    final f = expandFile();
    if (f == null) {
      markTestSkipped('真实 gpx 不存在');
      return;
    }
    final ir = parseGpxBytes(f.readAsBytesSync());
    final ms = ir.tracks.single.measures;
    expect(ms, hasLength(62));
    final order = expandMeasures(ms);
    // 语义（2026-11-02 用户实测 GP8 修正）：第二遍 21-26（6 段）后跳过
    // 结尾 1 管辖区 27-43（17 段，含反复结束线小节），直达结尾 2（m44）。
    // 总 = 第一遍 43（0-42）+ 第二遍 6（20-25）+ 19（43-61）= 68。
    expect(order, hasLength(68));
    expect(order.first, 0);
    // 第二遍从线性 MB#21（idx 20）开始：位置 43。
    expect(order[43], 20);
    // 第二遍结尾 1 处直接跳到结尾 2：order[49]（43+6）= 43（m44）。
    expect(order[49], 43);
    // 结尾 1（idx26）与 27-42 段均只播第一遍（1 次）。
    for (final idx in [26, 27, 30, 42]) {
      expect(order.where((i) => i == idx), hasLength(1), reason: 'idx $idx');
    }
    // 结尾 2（m44）只播第二遍（1 次）。
    expect(order.where((i) => i == 43), hasLength(1));
  });

  test('dsh P1 边界：起始小节自身带 endings，第二遍不重播', () {
    // |:[A(1)] B :‖ [C(2)] D —— A 是段首兼结尾 1：第二遍跳回后 pass=2
    // 不含 1 → 跳过 A 直达 C（dsh 交叉测试指出的重播缺陷回归网）。
    final ms = [
      m(0, start: true, endings: [1]),
      m(1),
      m(2, end: true),
      m(3, endings: [2]),
      m(4),
    ];
    expect(expandMeasures(ms), [0, 1, 2, 3, 4]);
  });
}
