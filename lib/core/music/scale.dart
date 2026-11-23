import 'note.dart';

enum ScaleType {
  major('大调', [0, 2, 4, 5, 7, 9, 11],
      feel: '明亮、安定', usage: '旋律、创作，以及几乎所有场景'),
  naturalMinor('自然小调', [0, 2, 3, 5, 7, 8, 10],
      feel: '暗沉、严肃', usage: '抒情曲、摇滚和小调流行'),
  majorPentatonic('大调五声', [0, 2, 4, 7, 9],
      feel: '开阔、友好', usage: '乡村、流行和经典摇滚独奏'),
  minorPentatonic('小调五声', [0, 3, 5, 7, 10],
      feel: '粗砺、像人声', usage: '第一段独奏、布鲁斯和摇滚主奏'),
  blues('布鲁斯', [0, 3, 5, 6, 7, 10],
      feel: '布鲁斯味、紧张', usage: '布鲁斯、摇滚和乡村的乐句');

  final String label;
  final List<int> intervals;
  // 听感/用途（openguitarchords 同款文案，指板页信息卡用）。
  final String feel;
  final String usage;
  const ScaleType(this.label, this.intervals, {required this.feel, required this.usage});
}

/// 音级名（半音数 → 级数标记，参考站同款：1 2 ♭3 4 5 ♭5 ♭7）。
const _degreeNames = ['1', '♭2', '2', '♭3', '3', '4', '♭5', '5', '♭6', '6', '♭7', '7'];

String degreesOf(ScaleType type) =>
    type.intervals.map((i) => _degreeNames[i]).join(' ');

/// 音程模式（相邻半音差：1→H、2→W、3→m3；末音回绕到主音）。
String intervalPattern(ScaleType type) {
  final out = <String>[];
  for (var i = 0; i < type.intervals.length; i++) {
    final next = i + 1 < type.intervals.length
        ? type.intervals[i + 1]
        : type.intervals[0] + 12;
    final w = next - type.intervals[i];
    out.add(w == 1 ? 'H' : w == 2 ? 'W' : w == 3 ? 'm3' : w == 4 ? 'M3' : '$w');
  }
  return out.join('-');
}

List<int> scalePitchClasses(int rootPc, ScaleType type) =>
    type.intervals.map((i) => (rootPc + i) % 12).toList();

/// grid[弦索引][品] = 该品 midi（在音阶内）或 null
List<List<int?>> fretboardGrid(
    List<Note> tuning, int rootPc, ScaleType type,
    {int frets = 12}) {
  final pcs = scalePitchClasses(rootPc, type).toSet();
  return [
    for (final s in tuning)
      [
        for (var f = 0; f <= frets; f++)
          pcs.contains((s.midi + f) % 12) ? s.midi + f : null
      ]
  ];
}

const solfege = ['Do', 'Re', 'Mi', 'Fa', 'Sol', 'La', 'Si'];

/// 唱名下标：按**平行大调音阶级数**取下标（C 大调内 Do..Si）。
/// 注意：小调/五声/布鲁斯的特征音（不在对应平行大调内的音，如布鲁斯降五音）
/// 返回 -1，调用方需自行降级显示；属已知设计取舍，Task 15 接线时决定是否升级为
/// 关系大调（La 基）唱名。
int solfegeIndex(int rootPc, int pitchClass) {
  final idx = scalePitchClasses(rootPc, ScaleType.major)
      .toList()
      .indexOf(pitchClass);
  return idx;
}
