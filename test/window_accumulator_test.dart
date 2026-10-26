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

  test('滑窗内容：第二窗为末尾 windowSamples', () {
    final acc = PitchWindower(windowSamples: 10, hopSamples: 5);
    acc.add(List.generate(12, (i) => i.toDouble()));
    // 12 样本后余 _sinceLast=2，第二个 add 的第 3 个样本触发出窗：
    // 窗口 = 全部已见样本的末尾 10 个。
    final w2 = acc.add([for (var i = 100; i < 105; i++) i.toDouble()]);
    expect(w2.single, [5, 6, 7, 8, 9, 10, 11, 100, 101, 102]);
  });

  test('trim 分支：超 4 倍窗口后仍正确出窗', () {
    final acc = PitchWindower(windowSamples: 10, hopSamples: 5);
    final windows = acc.add(List.generate(60, (i) => i.toDouble()));
    expect(windows, isNotEmpty);
    expect(windows.last.last, 59);
  });
}
