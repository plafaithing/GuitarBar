import 'dart:math' as math;

class Note {
  final int midi;
  const Note(this.midi);

  static const _sharp = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  static const _flat = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];
  static const _base = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};

  int get pitchClass => midi % 12;
  int get octave => (midi ~/ 12) - 1;
  String get name => '${_sharp[pitchClass]}$octave';
  String label({bool flats = false}) =>
      '${(flats ? _flat : _sharp)[pitchClass]}$octave';

  static Note parse(String s) {
    final m = RegExp(r'^([A-Ga-g])([#b]?)(-?\d+)$').firstMatch(s.trim());
    if (m == null) throw ArgumentError('无效音名: $s');
    var pc = _base[m.group(1)!.toUpperCase()]!;
    if (m.group(2) == '#') pc += 1;
    if (m.group(2) == 'b') pc -= 1;
    return Note(pc + (int.parse(m.group(3)!) + 1) * 12);
  }

  double frequency([double a4 = 440.0]) =>
      a4 * math.pow(2, (midi - 69) / 12).toDouble();
}

int centsOff(double measured, double target) =>
    (1200 * (math.log(measured / target) / math.ln2)).round();
