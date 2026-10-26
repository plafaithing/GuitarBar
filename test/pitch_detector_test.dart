import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/pitch_detector.dart';

List<double> sine(double freq, int sampleRate, int n, {double amp = 0.8}) =>
    [for (var i = 0; i < n; i++) amp * math.sin(2 * math.pi * freq * i / sampleRate)];

void main() {
  const sr = 44100;
  test('检测低音 E2 ≈ 82.41 Hz', () {
    final f = detectPitch(sine(82.41, sr, 4096), sr);
    expect(f, isNotNull);
    expect(f!, closeTo(82.41, 1.0));
  });
  test('检测 E4 ≈ 329.63 Hz', () {
    final f = detectPitch(sine(329.63, sr, 4096), sr);
    expect(f!, closeTo(329.63, 1.0));
  });
  test('静音返回 null', () {
    expect(detectPitch(List.filled(4096, 0.0), sr), isNull);
  });
}
