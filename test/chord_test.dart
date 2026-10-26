import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/music/builtin_tunings.dart';
import 'package:guitarbar/core/music/chord_parser.dart';
import 'package:guitarbar/core/music/fingering.dart';
import 'package:guitarbar/core/music/tuning.dart';

TuningPreset get std =>
    builtinTunings.firstWhere((t) => t.name == 'Standard');

void main() {
  test('解析和弦名', () {
    expect(parseChord('C').intervals, [0, 4, 7]);
    expect(parseChord('Am7').rootPc, 9);
    expect(parseChord('Am7').intervals, [0, 3, 7, 10]);
    expect(parseChord('F#m7b5').rootPc, 6);
    expect(parseChord('F#m7b5').intervals, [0, 3, 6, 10]);
    expect(parseChord('Dsus4').rootPc, 2);
    expect(parseChord('Bb').rootPc, 10);
    expect(parseChord('Cadd9').intervals, [0, 4, 7, 14]);
    expect(() => parseChord('X13'), throwsArgumentError);
  });

  test('C 大三和弦含 x32010', () {
    final gen = FingeringGenerator(std.strings);
    final c = parseChord('C');
    final v = gen.generate(rootPc: c.rootPc, toneClasses: chordToneClasses(c));
    expect(
        v.map((x) => x.frets.map((f) => f?.toString() ?? '').join(',')),
        contains(',3,2,0,1,0'));
    expect(v.length, lessThanOrEqualTo(6));
    for (var i = 1; i < v.length; i++) {
      expect(v[i].score, greaterThanOrEqualTo(v[i - 1].score));
    }
  });

  test('Am 含 x02210，Am7 含 x02010，E 含 022100', () {
    final gen = FingeringGenerator(std.strings);
    final am = parseChord('Am');
    expect(
        gen.generate(rootPc: am.rootPc, toneClasses: chordToneClasses(am))
            .map((x) => x.frets.map((f) => f?.toString() ?? '').join(',')),
        contains(',0,2,2,1,0'));
    final am7 = parseChord('Am7');
    expect(
        gen.generate(rootPc: am7.rootPc, toneClasses: chordToneClasses(am7))
            .map((x) => x.frets.map((f) => f?.toString() ?? '').join(',')),
        contains(',0,2,0,1,0'));
    final e = parseChord('E');
    expect(
        gen.generate(rootPc: e.rootPc, toneClasses: chordToneClasses(e))
            .map((x) => x.frets.map((f) => f?.toString() ?? '').join(',')),
        contains('0,2,2,1,0,0'));
  });

  test('所有返回指法不含和弦外音且非空（F#m7b5）', () {
    final gen = FingeringGenerator(std.strings);
    final f = parseChord('F#m7b5');
    final tones = chordToneClasses(f);
    final v = gen.generate(rootPc: f.rootPc, toneClasses: tones);
    expect(v, isNotEmpty);
    for (final vo in v) {
      final sounded = {
        for (var i = 0; i < 6; i++)
          if (vo.frets[i] != null) (std.strings[i].midi + vo.frets[i]!) % 12
      };
      expect(sounded.difference(tones), isEmpty, reason: vo.frets.join(','));
    }
  });

  test('Open G 全空弦零按指指法', () {
    final openG = builtinTunings.firstWhere((t) => t.name == 'Open G');
    final gen = FingeringGenerator(openG.strings);
    final g = parseChord('G');
    final v = gen.generate(rootPc: g.rootPc, toneClasses: chordToneClasses(g));
    expect(v, isNotEmpty);
    expect(v.first.frets.map((f) => f?.toString() ?? '').join(','),
        '0,0,0,0,0,0');
    expect(v.first.score, 0);
  });
}
