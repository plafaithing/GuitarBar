import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/music/note.dart';
import 'package:guitarbar/core/music/scale.dart';
import 'package:guitarbar/core/music/builtin_tunings.dart';

void main() {
  test('大调音程', () {
    final pcs = scalePitchClasses(0, ScaleType.major); // C 大调
    expect(pcs, [0, 2, 4, 5, 7, 9, 11]);
  });

  test('五声与布鲁斯', () {
    expect(scalePitchClasses(9, ScaleType.minorPentatonic), [9, 0, 2, 4, 7]); // Am 五声 A C D E G
    expect(scalePitchClasses(4, ScaleType.blues).length, 6);
  });

  test('指板网格：Standard C 大调', () {
    final std = builtinTunings.firstWhere((t) => t.name == 'Standard');
    final grid = fretboardGrid(std.strings, 0, ScaleType.major, frets: 12);
    expect(grid[0][8], 48); // 6 弦 8 品 = C3
    expect(grid[1][3], 48); // 5 弦 3 品 = C3
    expect(grid[0][2], null); // 6 弦 2 品 = F# 不在 C 大调（E 空弦在调内）
  });

  test('Drop D 下 6 弦空弦是 D', () {
    final dropD = builtinTunings.firstWhere((t) => t.name == 'Drop D');
    final grid = fretboardGrid(dropD.strings, 2, ScaleType.major, frets: 12); // D 大调
    expect(grid[0][0], Note.parse('D2').midi);
  });
}
