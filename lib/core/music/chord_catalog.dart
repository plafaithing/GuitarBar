import 'chord_parser.dart';

/// 和弦分类浏览目录（设计文档 §13.1）：新手查阅路径。
/// 子类音程与 chord_parser 的 _qualities 表同源——一致性由
/// chord_catalog_test 的交叉验证钉住（拼名走 parseChord 断言相同）。
class ChordSubtype {
  const ChordSubtype(this.suffix, this.name, this.intervals);
  final String suffix; // 拼名后缀（'' 为大三）
  final String name; // 中文显示名
  final List<int> intervals; // 音程（与 _qualities 同值）
}

class ChordCategory {
  const ChordCategory(this.name, this.subtypes);
  final String name;
  final List<ChordSubtype> subtypes;
}

const _triads = ChordCategory('三和弦', [
  ChordSubtype('', '大三', [0, 4, 7]),
  ChordSubtype('m', '小三', [0, 3, 7]),
  ChordSubtype('aug', '增三', [0, 4, 8]),
  ChordSubtype('dim', '减三', [0, 3, 6]),
  ChordSubtype('5', '五度', [0, 7]),
]);

const _sevenths = ChordCategory('七和弦', [
  ChordSubtype('7', '属七', [0, 4, 7, 10]),
  ChordSubtype('m7', '小七', [0, 3, 7, 10]),
  ChordSubtype('maj7', '大七', [0, 4, 7, 11]),
  ChordSubtype('m7b5', '半减七', [0, 3, 6, 10]),
]);

const _suspended = ChordCategory('挂留和弦', [
  ChordSubtype('sus2', '挂二', [0, 2, 7]),
  ChordSubtype('sus4', '挂四', [0, 5, 7]),
]);

const _extended = ChordCategory('加音与扩展', [
  ChordSubtype('add9', '加九', [0, 4, 7, 14]),
  ChordSubtype('6', '六和弦', [0, 4, 7, 9]),
  ChordSubtype('m6', '小六', [0, 3, 7, 9]),
  ChordSubtype('9', '属九', [0, 4, 7, 10, 14]),
  ChordSubtype('m9', '小九', [0, 3, 7, 10, 14]),
]);

const chordCategories = [_triads, _sevenths, _suspended, _extended];

/// 根音表（浏览用，音名 → pitch class）。
const rootNames = <String, int>{
  'C': 0, 'C#': 1, 'D': 2, 'D#': 3, 'E': 4, 'F': 5,
  'F#': 6, 'G': 7, 'G#': 8, 'A': 9, 'A#': 10, 'B': 11,
};

/// 浏览选中 → ParsedChord（不经字符串解析；目录与解析器一致性由测试钉住）。
ParsedChord browseChord(int rootPc, String suffix) {
  for (final cat in chordCategories) {
    for (final sub in cat.subtypes) {
      if (sub.suffix == suffix) return ParsedChord(rootPc, sub.intervals);
    }
  }
  throw ArgumentError('未知和弦类型: $suffix');
}

/// 拼和弦显示名（如 'Am7'；大三空后缀只显根音）。
String chordDisplayName(int rootPc, String suffix) {
  final root =
      rootNames.entries.firstWhere((e) => e.value == rootPc).key;
  return root + suffix;
}
