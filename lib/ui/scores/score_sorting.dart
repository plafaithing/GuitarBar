import 'package:lpinyin/lpinyin.dart';

import '../../data/database.dart';

/// 曲谱列表排序与首字母分组（2026-11-04 用户需求，参考 iPhone 通讯录）：
/// - 按首字母正序（英文名取首字母；中文名取**拼音首字母**；其他归 `#`）
/// - 同字母组内**英文名排中文名前**（用户：优先英文名文件）
/// - 字母索引条定位到各组的第一个文件
///
/// 范围决策（dsh 复测 P3 落定）：中文判定直接用 lpinyin 的
/// [ChineseHelper.isChinese]（与本库拼音表范围天然一致，Ext A/兼容区
/// 能取到拼音的都正确归组）；取不到拼音的（生僻符号等）一律归 `#`。
/// 组内中文名按**标题 code unit 序**而非拼音序——极简实现，iPhone 同组
/// 内部也不严格拼音序；用户若要完整拼音序再升级。

/// 分组键：A-Z 或 `#`。
String letterGroupKey(String title) {
  final t = title.trim();
  if (t.isEmpty) return '#';
  final first = t[0].toUpperCase();
  final code = first.codeUnitAt(0);
  if (code >= 0x41 && code <= 0x5A) return first; // ASCII A-Z
  if (ChineseHelper.isChinese(t[0])) {
    try {
      final py = PinyinHelper.getFirstWordPinyin(t);
      if (py.isNotEmpty) {
        final c = py[0].toUpperCase();
        final cc = c.codeUnitAt(0);
        if (cc >= 0x41 && cc <= 0x5A) return c;
      }
    } catch (_) {}
  }
  return '#';
}

/// 名字是否以 ASCII 字母开头（组内英文优先的次级键）。
bool _startsWithAsciiLetter(String title) {
  final t = title.trim();
  if (t.isEmpty) return false;
  final c = t.codeUnitAt(0);
  return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
}

/// 排序比较：组键（A-Z,#）→ 组内英文优先 → 名字（大小写不敏感）→
/// id 兜底（List.sort 不稳定，同名同类型的两份曲谱重载后顺序恒定）。
int compareScoresByLetter(Score a, Score b) {
  final ka = letterGroupKey(a.title), kb = letterGroupKey(b.title);
  if (ka != kb) return ka.compareTo(kb);
  final ea = _startsWithAsciiLetter(a.title), eb = _startsWithAsciiLetter(b.title);
  if (ea != eb) return ea ? -1 : 1;
  final c = a.title.toLowerCase().compareTo(b.title.toLowerCase());
  if (c != 0) return c;
  return a.id.compareTo(b.id);
}

/// 排序后的分组列表（只含有内容的组，组内已按 compareScoresByLetter 序）。
class ScoreSection {
  const ScoreSection(this.letter, this.scores);
  final String letter;
  final List<Score> scores;
}

List<ScoreSection> groupScoresByLetter(List<Score> scores) {
  final sorted = List.of(scores)..sort(compareScoresByLetter);
  final sections = <ScoreSection>[];
  for (final s in sorted) {
    final key = letterGroupKey(s.title);
    if (sections.isEmpty || sections.last.letter != key) {
      sections.add(ScoreSection(key, [s]));
    } else {
      sections.last.scores.add(s);
    }
  }
  return sections;
}
