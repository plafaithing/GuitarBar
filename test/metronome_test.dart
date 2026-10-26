import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/metronome_engine.dart';

void main() {
  const sr = 44100;
  test('120bpm 4/4 二细分：tick 间隔与重音', () {
    final cfg = const MetronomeConfig(bpm: 120, beatsPerBar: 4, subdivision: 2);
    final ticks = scheduleTicks(cfg: cfg, startSample: 0, tickCount: 9, sampleRate: sr);
    expect(ticks[0].kind, 0); // 小节头重音
    expect(ticks[0].sample, 0);
    expect(ticks[1].kind, 2); // 弱拍（细分）
    expect(ticks[1].sample, 11025); // 0.25s
    expect(ticks[2].kind, 1); // 强拍（非小节头正拍）
    expect(ticks[2].sample, 22050);
    expect(ticks[8].kind, 0); // 下一个小节头
  });

  test('6/8 单细分：第 6 拍回到重音', () {
    final cfg = const MetronomeConfig(bpm: 120, beatsPerBar: 6, subdivision: 1);
    final ticks = scheduleTicks(cfg: cfg, startSample: 0, tickCount: 7, sampleRate: sr);
    expect(ticks[6].kind, 0);
  });

  test('bpmFromTaps', () {
    final base = DateTime(2026, 10, 25);
    final taps = [base, base.add(const Duration(milliseconds: 500)),
        base.add(const Duration(seconds: 1)),
        base.add(const Duration(milliseconds: 1500))];
    expect(bpmFromTaps(taps), closeTo(120, 0.1));
    expect(bpmFromTaps(taps.sublist(0, 1)), 0);
  });

  test('tap 间隔超 2 秒被忽略', () {
    final base = DateTime(2026, 10, 25);
    final taps = [base, base.add(const Duration(milliseconds: 500)),
        base.add(const Duration(seconds: 5)),
        base.add(const Duration(seconds: 5, milliseconds: 500))];
    expect(bpmFromTaps(taps), closeTo(120, 0.1)); // 只用最后两个
  });
}
