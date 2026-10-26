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
    expect(f!, closeTo(82.41, 0.5));
  });
  test('检测 E4 ≈ 329.63 Hz', () {
    final f = detectPitch(sine(329.63, sr, 4096), sr);
    expect(f!, closeTo(329.63, 1.0));
  });
  test('检测谐波丰富信号 A2 ≈ 110 Hz（基频+2f+3f+4f）', () {
    final sig = [
      for (var i = 0; i < 4096; i++)
        1.0 * math.sin(2 * math.pi * 110 * i / sr) +
            0.5 * math.sin(2 * math.pi * 220 * i / sr) +
            0.25 * math.sin(2 * math.pi * 330 * i / sr) +
            0.125 * math.sin(2 * math.pi * 440 * i / sr),
    ];
    expect(detectPitch(sig, sr)!, closeTo(110.0, 0.5));
  });
  test('检测低幅度信号（拨弦衰减尾段 amp 0.05）', () {
    expect(detectPitch(sine(110, sr, 4096, amp: 0.05), sr)!, closeTo(110.0, 0.5));
  });
  test('静音返回 null', () {
    expect(detectPitch(List.filled(4096, 0.0), sr), isNull);
  });
}
