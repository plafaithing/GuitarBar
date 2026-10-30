import 'dart:typed_data';

import '../core/music/note.dart';
import '../core/score/score_ir.dart';
import 'synth.dart';

class RenderedScore {
  const RenderedScore(
      {required this.pcm, required this.sampleRate, required this.seconds});
  final Int16List pcm;
  final int sampleRate;
  final double seconds;
}

/// 渲染式自动演奏（设计文档 §7.1）：整曲 IR → 离线 PCM。
/// beat→sample 按 tempo 换算；音符 = KS pluck 叠加进时间线；
/// 闷音 x 短衰减；failed 小节跳过；变速 = 改 tempo 重渲染（M5）。
RenderedScore renderScore(ScoreIr ir,
    {int sampleRate = 44100, double a4 = 440}) {
  final beatSamples = 60.0 / ir.tempo * sampleRate;
  const tailSeconds = 1.2;
  final beatsPerBar = int.tryParse(ir.timeSignature.split('/')[0]) ?? 4;

  // 总长：最后音符结束 + 尾音。全曲绝对拍 = 小节号 * 每小节拍数 + 小节内
  // 拍位（与 tab_view 播放头同款约定）；failed 小节保留 index 占位，
  // 后续小节按 index 定位 → 恰好产生正确的静音小节。
  var endBeat = 0.0;
  for (final t in ir.tracks) {
    for (final m in t.measures) {
      for (final n in m.notes) {
        final e = m.index * beatsPerBar +
            n.beat +
            n.duration +
            tailSeconds * ir.tempo / 60;
        if (e > endBeat) endBeat = e;
      }
    }
  }
  final total = (endBeat * beatSamples).ceil() + 1;
  final mix = Float64List(total);
  final tunings = [for (final s in ir.tuning) Note.parse(s)];

  var renderedAny = false;
  for (final t in ir.tracks) {
    for (final m in t.measures) {
      if (m.failed) continue;
      // 同拍多音微 stagger（走查反馈：多弦合弹"有先后顺序，听感差"）：
      // 同 beat 分组（LinkedHashMap 保持 beat 首现序 = 既有 beat 排序），
      // 组内按弦号低→高（string 大者先）各错开 10ms——KS 低音弦起振慢，
      // 数学绝对同时反而听成先后错乱；10ms 错开贴近真实指弹的拨弦错手。
      final byBeat = <double, List<NoteIr>>{};
      for (final n in m.notes) {
        byBeat.putIfAbsent(n.beat, () => []).add(n);
      }
      for (final group in byBeat.values) {
        group.sort((a, b) => b.string.compareTo(a.string)); // 低音弦先
        for (var k = 0; k < group.length; k++) {
          final n = group[k];
          renderedAny = true;
          // 弦号映射：NoteIr.string 1=最细高音弦，tuning 低→高 index 0=6弦，
          // 故 string 1 → tunings[5]（E4）。
          // 品语义（2026-10-31 走查统一）：IR.fret 两通道统一为夹后品
          // （gpx 导入已 fret-capo 转换；AI 通道谱面印刷数字本就按夹后计），
          // 发声 = tuning + capo + 夹后品——capo 恰补一次：双补（gpx 旧病，
          // 音高多 capo 度）或零补（夹后曲整体低 capo 度）都不对。
          final freq = Note(tunings[6 - n.string].midi + ir.capo + n.fret)
              .frequency(a4);
          final pcm = pluck(freq,
              sampleRate: sampleRate,
              seconds: n.technique == 'x' ? 0.3 : tailSeconds);
          final off = ((m.index * beatsPerBar + n.beat) * beatSamples +
                  k * sampleRate * 0.01)
              .round();
          for (var i = 0; i < pcm.length && off + i < total; i++) {
            mix[off + i] += pcm[i] / 32768.0;
          }
        }
      }
    }
  }
  // 无可发音符（全 failed/空）：空 PCM + seconds=0，防 ~2e-5 小数绕过
  // 播放器的 durationSeconds==0 守卫。
  if (!renderedAny) {
    return RenderedScore(pcm: Int16List(0), sampleRate: sampleRate, seconds: 0);
  }
  final out = Int16List(total);
  for (var i = 0; i < total; i++) {
    out[i] = (mix[i].clamp(-1.0, 1.0) * 32767).round();
  }
  return RenderedScore(
      pcm: out, sampleRate: sampleRate, seconds: total / sampleRate);
}
