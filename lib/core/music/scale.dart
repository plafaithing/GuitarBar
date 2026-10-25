import 'note.dart';

enum ScaleType {
  major('大调', [0, 2, 4, 5, 7, 9, 11]),
  naturalMinor('自然小调', [0, 2, 3, 5, 7, 8, 10]),
  majorPentatonic('大调五声', [0, 2, 4, 7, 9]),
  minorPentatonic('小调五声', [0, 3, 5, 7, 10]),
  blues('布鲁斯', [0, 3, 5, 6, 7, 10]);

  final String label;
  final List<int> intervals;
  const ScaleType(this.label, this.intervals);
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

/// 唱名下标（大调体系内按根音起算），不在音阶内返回 -1
int solfegeIndex(int rootPc, int pitchClass) {
  final idx = scalePitchClasses(rootPc, ScaleType.major)
      .toList()
      .indexOf(pitchClass);
  return idx;
}
