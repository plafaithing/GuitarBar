import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/vision/tab_prompt.dart';

void main() {
  test('user prompt 调弦顺序：tuning 本身低→高（index 0=6弦），原样输出不反转', () {
    expect(
        tabUserPrompt(
            tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
            timeSignature: '4/4',
            capo: 2,
            page: 0,
            total: 1),
        contains('E2, A2, D3, G3, B3, E4'));
  });
}
