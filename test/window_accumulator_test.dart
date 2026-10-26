import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/mic_pitch_stream.dart';

void main() {
  test('累计到 hop 出窗，窗口大小正确', () {
    final acc = PitchWindower(windowSamples: 10, hopSamples: 5);
    final windows = acc.add(List.generate(12, (i) => i.toDouble()));
    expect(windows.length, 1);
    expect(windows.single.length, 10);
    expect(windows.single.first, 0); // 最早样本在窗口头
    expect(acc.add(List.generate(5, (i) => (100 + i).toDouble())).length, 1);
  });

  test('样本不足不出窗', () {
    final acc = PitchWindower(windowSamples: 10, hopSamples: 5);
    expect(acc.add(List.generate(4, (i) => i.toDouble())), isEmpty);
  });

  test('windowRms 门限语义', () {
    expect(windowRms(List.filled(4096, 0.0)), 0);
    expect(windowRms(List.filled(4096, 0.8)), closeTo(0.8, 1e-12));
    expect(windowRms(List.filled(4096, 0.004)), closeTo(0.004, 1e-9));
  });
}
