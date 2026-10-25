import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/music/builtin_tunings.dart';
import 'package:guitarbar/core/music/tuning.dart';

void main() {
  test('内置 20 组，分组 5/4/7/4', () {
    expect(builtinTunings.length, 20);
    int count(TuningGroup g) => builtinTunings.where((t) => t.group == g).length;
    expect(count(TuningGroup.standardDown), 5);
    expect(count(TuningGroup.drop), 4);
    expect(count(TuningGroup.open), 7);
    expect(count(TuningGroup.special), 4);
  });

  test('Standard = E2 A2 D3 G3 B3 E4', () {
    final std = builtinTunings.firstWhere((t) => t.name == 'Standard');
    expect(std.strings.map((n) => n.name).toList(),
        ['E2', 'A2', 'D3', 'G3', 'B3', 'E4']);
    expect(std.isBuiltIn, isTrue);
  });

  test('Drop D 六弦为 D2，其余同 Standard', () {
    final d = builtinTunings.firstWhere((t) => t.name == 'Drop D');
    expect(d.strings[0].name, 'D2');
    expect(d.strings[1].name, 'A2');
  });

  test('名称无重复、每弦数 6', () {
    expect(builtinTunings.map((t) => t.name).toSet().length, 20);
    for (final t in builtinTunings) {
      expect(t.strings.length, 6, reason: t.name);
    }
  });
}
