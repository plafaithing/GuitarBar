import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/music/note.dart';

void main() {
  test('解析科学记谱', () {
    expect(Note.parse('E2').midi, 40);
    expect(Note.parse('Eb2').midi, 39);
    expect(Note.parse('C#4').midi, 61);
    expect(Note.parse('B1').midi, 35);
    expect(Note.parse('A1').midi, 33);
    expect(Note.parse('c4').midi, 60);
    expect(Note.parse('C-1').midi, 0);
    expect(() => Note.parse('H2'), throwsArgumentError);
  });

  test('名称往返', () {
    expect(Note.parse('E2').name, 'E2');
    expect(Note.parse('Eb2').name, 'D#2');
    expect(Note.parse('Eb2').label(flats: true), 'Eb2');
    expect(Note.parse('E2').toString(), 'E2');
  });

  test('频率（A4=440）', () {
    expect(Note.parse('A4').frequency(), closeTo(440, 0.001));
    expect(Note.parse('E2').frequency(), closeTo(82.407, 0.01));
    expect(Note.parse('E4').frequency(), closeTo(329.628, 0.01));
  });

  test('频率随 A4 校准', () {
    expect(Note.parse('A4').frequency(435), closeTo(435, 0.001));
  });

  test('centsOff', () {
    expect(centsOff(440.0, 440.0), 0);
    expect(centsOff(466.16, 440.0), closeTo(100, 0.5));
    expect(centsOff(415.3, 440.0), closeTo(-100, 2));
  });
}
