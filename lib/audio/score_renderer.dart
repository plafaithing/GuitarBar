import 'dart:typed_data';

import '../core/music/note.dart';
import '../core/score/score_ir.dart';
import 'synth.dart';

class RenderedScore {
  const RenderedScore(
      {required this.pcm,
      required this.sampleRate,
      required this.seconds,
      this.order,
      this.orderStarts,
      this.beatsPerBar = 4,
      this.tempo = 90});
  final Int16List pcm;
  final int sampleRate;
  final double seconds;

  // 反复展开元数据（2026-11-02 GP8 复刻；无结构谱为 null）——播放头
  // 展开时间轴 → 线性谱面拍位反查用。
  final List<int>? order;
  final List<double>? orderStarts;
  final int beatsPerBar;
  final double tempo; // 点音起播秒换算用
}

/// 渲染式自动演奏（设计文档 §7.1）：整曲 IR → 离线 PCM。
/// beat→sample 按 tempo 换算；音符 = KS pluck 叠加进时间线；
/// 闷音 x 短衰减；failed 小节跳过。
/// [rate] 速度倍率（2026-11-01 跟练：1.0 = 原速；>1 加速）——tempo×rate
/// 保音调变速（KS 路径，采样路径走调度时间轴缩放）。
RenderedScore renderScore(ScoreIr ir,
    {int sampleRate = 44100, double a4 = 440, double rate = 1.0}) {
  if (ir.tracks.isEmpty) {
    return RenderedScore(pcm: Int16List(0), sampleRate: sampleRate, seconds: 0);
  }
  final beatSamples = 60.0 / (ir.tempo * rate) * sampleRate;
  const tailSeconds = 1.2;
  final beatsPerBar = int.tryParse(ir.timeSignature.split('/')[0]) ?? 4;

  // 反复展开（2026-11-02 GP8 复刻）：播放按展开序，时间轴 = 展开位
  // 累计拍位；failed 小节拍位照占（静音小节）。
  final t0 = ir.tracks.first;
  final order = expandMeasures(t0.measures);
  final orderStarts = [
    for (var k = 0; k < order.length; k++) k * beatsPerBar.toDouble()
  ];
  // 有结构 = 展开改变了序列长度（反复真的生效）；播放头元数据仅此需要。
  final structured = order.length != t0.measures.length;

  // 总长：最后音符结束 + 尾音（展开轴）。
  var endBeat = 0.0;
  for (var k = 0; k < order.length; k++) {
    final m = t0.measures[order[k]];
    for (final n in m.notes) {
      final e = k * beatsPerBar +
          n.beat +
          n.duration +
          tailSeconds * ir.tempo / 60;
      if (e > endBeat) endBeat = e;
    }
  }
  final total = (endBeat * beatSamples).ceil() + 1;
  final mix = Float64List(total);
  final tunings = [for (final s in ir.tuning) Note.parse(s)];

  var renderedAny = false;
  for (var k = 0; k < order.length; k++) {
    final m = t0.measures[order[k]];
    if (m.failed) continue;
    // 同拍多音微 stagger（走查反馈：多弦合弹"有先后顺序，听感差"）：
    // 同 beat 分组（LinkedHashMap 保持 beat 首现序 = 既有 beat 排序），
    // 组内按弦号低→高（string 大者先）各错开 10ms——KS 低音弦起振慢，
    // 数学绝对同时反而听成先后错乱；10ms 错开贴近真实指弹的拨弦错手。
    final byBeat = <double, List<NoteIr>>{};
    for (final n in m.notes) {
      if (n.tieEnd) continue; // tie 续接端不出音（时长已累计回链首）
      byBeat.putIfAbsent(n.beat, () => []).add(n);
    }
    for (final group in byBeat.values) {
      group.sort((a, b) => b.string.compareTo(a.string)); // 低音弦先
      for (var k2 = 0; k2 < group.length; k2++) {
        final n = group[k2];
        renderedAny = true;
        // 弦号映射：NoteIr.string 1=最细高音弦，tuning 低→高 index 0=6弦，
        // 故 string 1 → tunings[5]（E4）。
        // 品语义（2026-10-31 二次修正，capoApplied 标记）：两通道 fret
        // 语义不同——gpx=绝对品（capoApplied=false，发声加 capo）、
        // AI=夹后品（capoApplied=true，capo 已含不再加）。
        final capoShift = ir.capoApplied ? 0 : ir.capo;
        final freq = Note(
                tunings[6 - n.string].midi + capoShift + n.fret)
            .frequency(a4);
        final pcm = pluck(freq,
            sampleRate: sampleRate,
            seconds: n.technique == 'x' ? 0.3 : tailSeconds);
        final off = ((k * beatsPerBar + n.beat) * beatSamples +
                k2 * sampleRate * 0.01)
            .round();
        for (var i = 0; i < pcm.length && off + i < total; i++) {
          mix[off + i] += pcm[i] / 32768.0;
        }
      }
    }
  }
  // 无可发音符（全 failed/空）：空 PCM + seconds=0，防 ~2e-5 小数绕过
  // 播放器的 durationSeconds==0 守卫。
  if (!renderedAny) {
    return RenderedScore(pcm: Int16List(0), sampleRate: sampleRate, seconds: 0);
  }
  // 无反复结构：order 元数据不填（播放头走原式换算）。
  final out = Int16List(total);
  for (var i = 0; i < total; i++) {
    out[i] = (mix[i].clamp(-1.0, 1.0) * 32767).round();
  }
  return RenderedScore(
      pcm: out,
      sampleRate: sampleRate,
      seconds: total / sampleRate,
      order: structured ? order : null,
      orderStarts: structured ? orderStarts : null,
      beatsPerBar: beatsPerBar,
      tempo: ir.tempo);
}
