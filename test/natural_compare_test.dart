import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_repository.dart';

void main() {
  test('naturalCompare：数字段按数值比较', () {
    final names = ['谱例-10.jpg', '谱例-2.jpg', '谱例-1.jpg'];
    final sorted = [...names]..sort(ScoreRepository.naturalCompare);
    expect(sorted, ['谱例-1.jpg', '谱例-2.jpg', '谱例-10.jpg']);
  });

  test('naturalCompare：纯文本回退字典序、大小写不敏感', () {
    expect(ScoreRepository.naturalCompare('abc.jpg', 'ABD.jpg'), lessThan(0));
    expect(ScoreRepository.naturalCompare('a.jpg', 'a.jpg'), 0);
  });

  test('naturalCompare：超长数字段按数值比较不溢出', () {
    expect(
        ScoreRepository.naturalCompare('a-12345678901234567890.jpg', 'a-1.jpg'),
        greaterThan(0));
  });

  test('naturalCompare：前导零视同相等、短前缀在前', () {
    expect(ScoreRepository.naturalCompare('007', '7'), 0);
    expect(ScoreRepository.naturalCompare('abc', 'abcd'), lessThan(0));
  });
}
