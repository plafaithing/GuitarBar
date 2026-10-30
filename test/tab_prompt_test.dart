import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/vision/tab_prompt.dart';

void main() {
  test('user prompt 调弦顺序：tuning 本身低→高（index 0=6弦），原样输出不反转', () {
    expect(
        tabUserPrompt(
            tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
            timeSignature: '4/4',
            page: 0,
            total: 1),
        contains('E2, A2, D3, G3, B3, E4'));
  });

  test('user prompt 调弦行为兜底语义：谱面标注优先，不诱导回显叠加', () {
    // 2026-10-31 走查（调弦识别）：手选标准调弦只作兜底，模型应从谱面
    // 标注读 tuning 字段（指弹谱常为特殊调弦）。
    final p = tabUserPrompt(
        tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
        timeSignature: '4/4',
        page: 0,
        total: 1);
    expect(p, contains('调弦兜底'));
    expect(p, contains('谱面标注了调弦则以谱面为准'));
  });

  test('user prompt capo 行：只让模型从谱面标注识别，不携带任何手填值', () {
    // 2026-10-31 走查（capo 语义统一）：用户值进 prompt 会诱导模型回显叠加。
    final p = tabUserPrompt(
        tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
        timeSignature: '4/4',
        page: 0,
        total: 1);
    expect(p, contains('从谱面标注识别并在 JSON capo 字段报告'));
    expect(p, contains('无标注填 0'));
    expect(p, isNot(contains('第 2 品'))); // 旧手填值文案不得回流
  });
}
