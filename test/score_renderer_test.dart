import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/score_renderer.dart';
import 'package:guitarbar/core/score/score_ir.dart';

ScoreIr irWith(List<NoteIr> notes, {double tempo = 60}) => ScoreIr(
      version: 1, title: 'T', tempo: tempo, timeSignature: '4/4',
      tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], capo: 0,
      tracks: [
        TrackIr(name: '主旋律', measures: [
          MeasureIr(index: 0, confidence: 1, failed: false, notes: notes),
        ]),
      ],
    );

const sr = 44100;

void main() {
  test('单音：beat 前无声、起始处有能量、总长含尾音', () {
    final r = renderScore(irWith([
      const NoteIr(beat: 1.0, duration: 1.0, string: 6, fret: 0,
          technique: null, confidence: null),
    ]));
    // tempo 60 → 1 拍 = 1s = 44100 样本
    for (var i = 0; i < 44000; i++) {
      expect(r.pcm[i], 0, reason: 'beat=1 前应静音');
    }
    // 拨弦有 3ms 淡入（首样本为 0），检查起始窗内出现能量。
    expect(r.pcm.sublist(44100, 44600).any((v) => v.abs() > 1000), isTrue);
    // 总长 ≥ 音符结束(2s) + 尾音(1.2s) = 3.2s
    expect(r.seconds, closeTo(3.2, 0.01));
  });

  test('failed 小节跳过渲染', () {
    final irFailed = ScoreIr(
        version: 1, title: 'T', tempo: 60, timeSignature: '4/4',
        tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], capo: 0,
        tracks: [
          TrackIr(name: '主旋律', measures: [
            const MeasureIr(index: 0, confidence: 0, failed: true, notes: []),
          ]),
        ]);
    final r = renderScore(irFailed);
    expect(r.pcm.every((v) => v == 0), isTrue);
  });

  test('闷音 x 衰减快：0.3s 尾部能量远小于正常拨弦', () {
    final normal = renderScore(irWith([
      const NoteIr(beat: 0, duration: 1, string: 6, fret: 0,
          technique: null, confidence: null),
    ]));
    final muted = renderScore(irWith([
      const NoteIr(beat: 0, duration: 1, string: 6, fret: 0,
          technique: 'x', confidence: null),
    ]));
    final tail = (sr * 0.25).round(); // 闷音 pluck 0.3s，取 0.25s 后比较
    num sumN = 0, sumM = 0;
    for (var i = tail; i < tail + 1000; i++) {
      sumN += normal.pcm[i].abs();
      sumM += muted.pcm[i].abs();
    }
    expect(sumM * 3, lessThan(sumN));
  });

  test('混音：双音叠加非零且不削波（有限值即可）', () {
    final r = renderScore(irWith([
      const NoteIr(beat: 0, duration: 1, string: 6, fret: 0,
          technique: null, confidence: null),
      const NoteIr(beat: 0, duration: 1, string: 5, fret: 0,
          technique: null, confidence: null),
    ]));
    expect(r.pcm.any((v) => v != 0), isTrue);
    expect(r.pcm.any((v) => v < -32768 || v > 32767), isFalse);
  });

  test('弦号映射：string 1（最细）比 string 6（最粗）频率高两个八度', () {
    // KS 拨弦起振含宽带噪声，过零率不随基频变化（实测 E4/E2 各窗口 zc 比均
    // ≈1），故用归一化自相关锁基频周期：E4≈329.6Hz → 周期≈134 样本，
    // E2≈82.4Hz → 周期≈535（恰为 E4 的 4 次谐波位置，实测自相关 -0.17）。
    // string 1 应发 E4（自相关@134≈0.99），string 6 应发 E2（@134≈-0.17）；
    // 若 tunings[6 - n.string] 映射被镜像颠倒，两断言同时翻转失败。
    double normAuto(Int16List pcm, int lag) {
      const win = 52920; // 1.2s 尾音全长
      var s = 0.0, e0 = 0.0, e1 = 0.0;
      for (var i = 0; i + lag < win; i++) {
        final a = pcm[i].toDouble(), b = pcm[i + lag].toDouble();
        s += a * b;
        e0 += a * a;
        e1 += b * b;
      }
      return s / math.sqrt(e0 * e1 + 1e-9);
    }

    final hi = renderScore(irWith([
      const NoteIr(beat: 0, duration: 1, string: 1, fret: 0,
          technique: null, confidence: null),
    ]));
    final lo = renderScore(irWith([
      const NoteIr(beat: 0, duration: 1, string: 6, fret: 0,
          technique: null, confidence: null),
    ]));
    expect(normAuto(hi.pcm, 134), greaterThan(0.5),
        reason: 'string 1 应为 E4（基频周期≈134 样本）');
    expect(normAuto(lo.pcm, 134), lessThan(0.5),
        reason: 'string 6 应为 E2（基频周期≈535 样本）');
  });
}
