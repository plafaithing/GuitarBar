import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/data/database.dart';
import 'package:guitarbar/ui/scores/score_sorting.dart';

Score _s(int id, String title) => Score(
    id: id,
    title: title,
    sourceType: 'gtp',
    sourcePath: '',
    createdAt: DateTime(2026, 11, 4),
    updatedAt: DateTime(2026, 11, 4));

void main() {
  test('letterGroupKey：英文名取首字母、中文取拼音首字母、其他归 #', () {
    expect(letterGroupKey('Like a star'), 'L');
    expect(letterGroupKey('月下之恋'), 'Y'); // yue
    expect(letterGroupKey('a star'), 'A');
    expect(letterGroupKey('2022 练习曲'), '#'); // 数字开头
    expect(letterGroupKey('【自制】xxx'), '#'); // 符号开头
  });

  test('排序：首字母正序、同组英文优先于中文、组内名字典序', () {
    final list = [
      _s(1, '月下之恋'), // Y 组（中文）
      _s(2, 'like a star'), // L 组
      _s(3, '雨的印记'), // Y 组（中文，rain → Y？不——"雨"=yu → Y）
      _s(4, 'A Star'), // A 组
      _s(5, '2022 练习曲'), // # 组
      _s(6, 'Flower'), // F 组
    ];
    final sorted = List.of(list)..sort(compareScoresByLetter);
    expect(sorted.map((s) => s.title).toList(), [
      '2022 练习曲', // # 在 A 前（'#' < 'A'）
      'A Star',
      'Flower',
      'like a star',
      // Y 组：英文（无）……两个都中文，按名字典序
      // 'rain' vs 'yue'？不对——都是中文，走名字典序（title 小写）。
      // '月下之恋' vs '雨的印记'：code unit 0x6708(月) < 0x96E8(雨)。
      '月下之恋',
      '雨的印记',
    ]);
  });

  test('排序：同字母组内英文名排中文名前（用户：优先英文名）', () {
    // "爱"= ai → A 组；与英文名 A 开头同组。
    final list = [_s(1, '爱的供养'), _s(2, 'Amazing Grace')];
    final sorted = List.of(list)..sort(compareScoresByLetter);
    expect(sorted.map((s) => s.title).toList(),
        ['Amazing Grace', '爱的供养']); // 组内英文在前
  });

  test('groupScoresByLetter：分组结构正确（组序/组内序/只含有内容的组）', () {
    final sections = groupScoresByLetter([
      _s(1, '月下之恋'),
      _s(2, 'Flower'),
      _s(3, 'like a star'),
      _s(4, 'Flower Dance'),
    ]);
    expect(sections.map((s) => s.letter).toList(), ['F', 'L', 'Y']);
    expect(sections[0].scores.map((s) => s.title).toList(),
        ['Flower', 'Flower Dance']);
    expect(sections[0].scores.length, 2);
    expect(sections[1].scores.single.title, 'like a star');
    expect(sections[2].scores.single.title, '月下之恋');
  });
}
