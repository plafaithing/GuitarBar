import 'chord_parser.dart';
import 'note.dart';

Set<int> chordToneClasses(ParsedChord c) =>
    c.intervals.map((i) => (c.rootPc + i) % 12).toSet();

/// frets[0] = 6 弦（低音），null = 不弹
class ChordVoicing {
  final List<int?> frets;
  final int score; // 越小越易
  const ChordVoicing(this.frets, this.score);
}

class FingeringGenerator {
  final List<Note> tuning; // 低 → 高
  FingeringGenerator(this.tuning)
      : assert(tuning.length == 6, '当前生成器仅支持 6 弦');

  /// 在所有 4 品宽窗口搜索，返回按易到难排序的前 top 个
  List<ChordVoicing> generate(
      {required int rootPc, required Set<int> toneClasses,
      int maxFret = 15, int top = 6}) {
    final found = <String, ChordVoicing>{};
    for (var w = 0; w + 3 <= maxFret; w++) {
      _search(w, rootPc, toneClasses, found);
    }
    final list = found.values.toList()
      ..sort((a, b) => a.score.compareTo(b.score));
    return list.take(top).toList();
  }

  void _search(int w, int rootPc, Set<int> tones, Map<String, ChordVoicing> out) {
    final options = <int?>[null, 0, w, w + 1, w + 2, w + 3];

    void dfs(int idx, List<int?> acc) {
      if (idx == 6) {
        final sounded = <int>{};
        for (var i = 0; i < 6; i++) {
          final f = acc[i];
          if (f != null) sounded.add((tuning[i].midi + f) % 12);
        }
        if (!sounded.containsAll(tones)) return;
        if (!sounded.every(tones.contains)) return;
        final fretted = acc.whereType<int>().where((f) => f > 0).toList();
        if (fretted.toSet().length > 4) return; // 横按同品算 1 指（零按指天然通过）
        var span = 0;
        if (fretted.isNotEmpty) {
          final hi = fretted.reduce((a, b) => a > b ? a : b);
          final lo = fretted.reduce((a, b) => a < b ? a : b);
          span = hi - lo;
        }
        if (span > 3) return;
        final key = acc.join(',');
        if (out.containsKey(key)) return;
        var score = w + 2 * acc.where((f) => f == null).length + span;
        // 根音必须在低音位（最低发音弦），否则视为转位 +4；
        // 这保证 x32010 类教科书指法优先于低音为三/五音的全开放按法。
        // 零按指（开放扫弦）豁免：开放调弦的全空弦即其本命和弦，无低音形态选择
        final bassIdx = acc.indexWhere((f) => f != null);
        final rootInBass = fretted.isEmpty ||
            (tuning[bassIdx].midi + acc[bassIdx]!) % 12 == rootPc;
        if (!rootInBass) score += 4;
        out[key] = ChordVoicing(List.of(acc), score);
        return;
      }
      for (final f in options) {
        acc.add(f);
        dfs(idx + 1, acc);
        acc.removeLast();
      }
    }

    dfs(0, <int?>[]);
  }
}
