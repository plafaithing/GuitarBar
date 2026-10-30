import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/score_renderer.dart';
import 'package:guitarbar/core/score/score_ir.dart';

ScoreIr irWith(List<NoteIr> notes, {double tempo = 60, int capo = 0}) =>
    ScoreIr(
      version: 1, title: 'T', tempo: tempo, timeSignature: '4/4',
      tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], capo: capo,
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

  test('多小节：第 2 小节音符落在 4s 处（绝对拍 = index*拍数 + beat）', () {
    final ir = ScoreIr(
        version: 1, title: 'T', tempo: 60, timeSignature: '4/4',
        tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], capo: 0,
        tracks: [
          TrackIr(name: '主旋律', measures: [
            const MeasureIr(index: 0, confidence: 1, failed: false, notes: []),
            const MeasureIr(index: 1, confidence: 1, failed: false, notes: [
              NoteIr(beat: 0, duration: 1, string: 6, fret: 0,
                  technique: null, confidence: null),
            ]),
          ]),
        ]);
    final r = renderScore(ir);
    // tempo 60 → 第 2 小节（index=1）起点 = 4 拍 = 4s = 176400 样本
    for (var i = 0; i < 4 * sr - 1; i++) {
      expect(r.pcm[i], 0, reason: '第 2 小节（4s 起）前应静音');
    }
    // 4-4.2s 窗口有能量（pluck 3ms 淡入后起振）。
    expect(
        r.pcm.sublist(4 * sr, 4 * sr + 8820).any((v) => v.abs() > 1000),
        isTrue);
    // 总长 = 4（小节偏移）+ 1（duration）+ 1.2（尾音）= 6.2s
    expect(r.seconds, closeTo(6.2, 0.1));
  });

  test('capo 语义统一（IR.fret=夹后品）：同音 + capo 恰补一次', () {
    // 2026-10-31 走查：IR.fret 两通道统一为夹后品（gpx 导入 fret-capo 转换；
    // AI 通道谱面印刷数字本就按夹后计），发声 = tuning + capo + 夹后品。
    // 两条断言合起来唯一锁定该公式：
    // - 同音断言杀双补（若再加一次 capo：capo2/fret0 → tuning+4 ≠ tuning+2）；
    // - 异音断言杀零补（若不加 capo：capo2/fret0 与 capo0/fret0 同为空弦音）。
    final a = renderScore(irWith([
      const NoteIr(beat: 0, duration: 1, string: 1, fret: 0,
          technique: null, confidence: null),
    ], capo: 2));
    final b = renderScore(irWith([
      const NoteIr(beat: 0, duration: 1, string: 1, fret: 2,
          technique: null, confidence: null),
    ]));
    // 夹后语义：capo 2 夹后空弦 ≡ 无夹按 2 品（同 midi → 同频同波形）。
    expect(a.pcm, b.pcm);
    expect(a.pcm.any((v) => v != 0), isTrue);
    final c = renderScore(irWith([
      const NoteIr(beat: 0, duration: 1, string: 1, fret: 0,
          technique: null, confidence: null),
    ]));
    // capo 参与发声：夹 2 品后的空弦音 ≠ 真空弦音。
    expect(a.pcm, isNot(c.pcm));
  });

  test('failed 小节跳过渲染（违约夹具：failed 且带 notes）', () {
    final irFailed = ScoreIr(
        version: 1, title: 'T', tempo: 60, timeSignature: '4/4',
        tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], capo: 0,
        tracks: [
          TrackIr(name: '主旋律', measures: [
            const MeasureIr(index: 0, confidence: 0, failed: true, notes: [
              NoteIr(beat: 0, duration: 1, string: 6, fret: 0,
                  technique: null, confidence: null),
            ]),
          ]),
        ]);
    final r = renderScore(irFailed);
    expect(r.pcm.every((v) => v == 0), isTrue);
    // 无可发音符 → seconds 恰为 0，防 2e-5 级小数绕过播放器 duration 守卫。
    expect(r.seconds, 0);
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
    // 真防满格：不允许任何样本顶到 ±32767。
    expect(r.pcm.any((v) => v.abs() >= 32767), isFalse);
  });

  test('同拍双音微 stagger：低音弦先响，第二音错开 ~441 样本（10ms）', () {
    // 输入故意高音弦在前：断言排序（string 大者先）而非输入序。
    final both = renderScore(irWith([
      const NoteIr(beat: 0, duration: 1, string: 1, fret: 0,
          technique: null, confidence: null),
      const NoteIr(beat: 0, duration: 1, string: 6, fret: 0,
          technique: null, confidence: null),
    ]));
    final lo = renderScore(irWith([
      const NoteIr(beat: 0, duration: 1, string: 6, fret: 0,
          technique: null, confidence: null),
    ]));
    final hi = renderScore(irWith([
      const NoteIr(beat: 0, duration: 1, string: 1, fret: 0,
          technique: null, confidence: null),
    ]));
    final stagger = (sr * 0.01).round(); // 10ms = 441 样本
    // 前缀段（0-441）：只有低音弦（k=0 原位），高音弦（k=1）尚未进入。
    // 无 stagger 时高音 3ms 淡入后（~132 样本）即有能量，此处会失败。
    for (var i = 132; i < stagger; i++) {
      expect(both.pcm[i], closeTo(lo.pcm[i], 1), reason: '前缀段 i=$i');
    }
    // stagger 之后：合奏 = 低音原样 + 高音右移 441 样本（不削波前提下
    // 逐样本线性可加；±1 容差覆盖各渲染 int16 取整差）。
    for (var i = stagger; i < lo.pcm.length; i++) {
      expect(both.pcm[i], closeTo(lo.pcm[i] + hi.pcm[i - stagger], 1),
          reason: '叠加段 i=$i');
    }
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
