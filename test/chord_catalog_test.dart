import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/music/chord_catalog.dart';
import 'package:guitarbar/core/music/chord_parser.dart';

void main() {
  // 注：2026-11-01 扩充对齐 zhibojiaoshi 216 和弦 = 18 类型 × 12 根音
  //（新增 dim7/mMaj7），目录与解析器 _qualities 同源故为 18。
  test('四大分类覆盖全部 18 种子类、无重复', () {
    final all = <String>{};
    for (final cat in chordCategories) {
      for (final sub in cat.subtypes) {
        expect(all.contains(sub.suffix), isFalse,
            reason: '${sub.suffix} 重复出现在 ${cat.name}');
        all.add(sub.suffix);
      }
    }
    expect(all.length, 18);
    expect(chordCategories.length, 4);
    expect(chordCategories.map((c) => c.name),
        ['三和弦', '七和弦', '挂留和弦', '加音与扩展']);
  });

  test('全目录枚举 = 216 和弦（18 类型 × 12 根音，对齐参考站）', () {
    var total = 0;
    for (final cat in chordCategories) {
      total += cat.subtypes.length * rootNames.length;
    }
    expect(total, 216);
  });

  test('目录与解析器一致：每个 (根音, 后缀) 拼名走 parseChord 结果相同', () {
    for (final root in rootNames.keys) {
      for (final cat in chordCategories) {
        for (final sub in cat.subtypes) {
          final p = parseChord(root + sub.suffix);
          expect(p.rootPc, rootNames[root],
              reason: '$root${sub.suffix} 根音');
          expect(p.intervals, sub.intervals,
              reason: '$root${sub.suffix} 音程');
        }
      }
    }
  });

  test('浏览选中直接构造 ParsedChord', () {
    final c = browseChord(9, 'm7'); // Am7
    expect(c.rootPc, 9);
    expect(c.intervals, [0, 3, 7, 10]);
  });

  test('browseChord 未知后缀抛 ArgumentError', () {
    expect(() => browseChord(0, 'zz'), throwsArgumentError);
  });

  test('根音表 12 个覆盖八度（0..11 唯一）', () {
    expect(rootNames.length, 12);
    expect(rootNames.values.toSet().length, 12);
    expect(rootNames['C'], 0);
    expect(rootNames['A'], 9);
  });
}
