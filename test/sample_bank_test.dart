import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/sample_bank.dart';

/// 采样解析纯逻辑（文件名推导 + 重移调速度），不触引擎与 assets。
/// 弦→采样基准：6E40 / 5A45 / 4D50 / 3G55 / 2B59 / 1E64（标准调弦）。
void main() {
  double speedBySemitones(int semitones) =>
      math.pow(2, semitones / 12).toDouble();

  test('空弦精确命中采样：速度 1.0', () {
    final r = SteelSampleBank.resolve(
        string: 6, fret: 0, soundingMidi: 40, technique: null);
    expect(r, isNotNull);
    expect(r!.file, 'Mrg12-Pck-Sus-Up-01-6E40-040-none-none.ogg');
    expect(r.speed, 1.0);
  });

  test('非采样品位取最近采样并下移重移调', () {
    // 3 品（sounding 43）：|43-40|=3 vs |43-44|=1 → 44 采样，下移半音。
    final r = SteelSampleBank.resolve(string: 6, fret: 3, soundingMidi: 43);
    expect(r!.file, 'Mrg12-Pck-Sus-Up-01-6E40-044-none-none.ogg');
    expect(r.speed, closeTo(speedBySemitones(-1), 1e-9));
  });

  test('距离并列取更低采样（下移优先）', () {
    // 6 品（sounding 46）：44 与 48 等距 → 取 44。
    final r = SteelSampleBank.resolve(string: 6, fret: 6, soundingMidi: 46);
    expect(r!.file, 'Mrg12-Pck-Sus-Up-01-6E40-044-none-none.ogg');
  });

  test('高音弦 12 品：直接命中 1E64-076', () {
    final r = SteelSampleBank.resolve(string: 1, fret: 12, soundingMidi: 76);
    expect(r!.file, 'Mrg12-Pck-Sus-Up-01-1E64-076-none-none.ogg');
    expect(r.speed, 1.0);
  });

  test('变调夹/异调弦：按发声半音重移调（sounding 66 → 64 采样上移 2 半音）',
      () {
    final r = SteelSampleBank.resolve(string: 1, fret: 0, soundingMidi: 66);
    expect(r!.file, 'Mrg12-Pck-Sus-Up-01-1E64-064-none-none.ogg');
    expect(r.speed, closeTo(speedBySemitones(2), 1e-9));
  });

  test('12 品自然泛音：八度采样恰精确（速度 1.0）', () {
    final r = SteelSampleBank.resolve(
        string: 6, fret: 12, soundingMidi: 52, technique: 'H');
    expect(r!.file, 'Mrg12-Hrm-Nat-12-none-6E40-none-none-none.ogg');
    expect(r.speed, 1.0);
  });

  test('7 品自然泛音：采样发声 = 空弦+19（八度+五度），重移调对齐约定音高', () {
    // 5 弦 sounding 52（渲染器约定 = 45+7）；采样实发 45+19 = 64 → 下移 12 半音。
    final r = SteelSampleBank.resolve(
        string: 5, fret: 7, soundingMidi: 52, technique: 'H');
    expect(r!.file, 'Mrg12-Hrm-Nat-07-none-5A45-none-none-none.ogg');
    expect(r.speed, closeTo(0.5, 1e-9));
  });

  test('5 品自然泛音：采样发声 = 空弦+24（两个八度）', () {
    final r = SteelSampleBank.resolve(
        string: 6, fret: 5, soundingMidi: 45, technique: 'H');
    expect(r!.file, 'Mrg12-Hrm-Nat-05-none-6E40-none-none-none.ogg');
    expect(r.speed, closeTo(speedBySemitones(-19), 1e-9));
  });

  test('非 5/7/12 泛音位：按普通拨弦发声（音高正确优先）', () {
    final r = SteelSampleBank.resolve(
        string: 6, fret: 9, soundingMidi: 49, technique: 'H');
    expect(r!.file, 'Mrg12-Pck-Sus-Up-01-6E40-048-none-none.ogg');
    expect(r.speed, closeTo(speedBySemitones(1), 1e-9));
  });

  test('弦号越界返回 null', () {
    expect(SteelSampleBank.resolve(string: 0, fret: 0, soundingMidi: 40), isNull);
    expect(SteelSampleBank.resolve(string: 7, fret: 0, soundingMidi: 40), isNull);
  });
}
