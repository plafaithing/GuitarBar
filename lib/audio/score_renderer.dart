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

  // 总长：最后音符结束 + 尾音。
  var endBeat = 0.0;
  for (final t in ir.tracks) {
    for (final m in t.measures) {
      for (final n in m.notes) {
        final e = n.beat + n.duration + tailSeconds * ir.tempo / 60;
        if (e > endBeat) endBeat = e;
      }
    }
  }
  final total = (endBeat * beatSamples).ceil() + 1;
  final mix = Float64List(total);
  final tunings = [for (final s in ir.tuning) Note.parse(s)];

  for (final t in ir.tracks) {
    for (final m in t.measures) {
      if (m.failed) continue;
      for (final n in m.notes) {
        // 弦号映射：NoteIr.string 1=最细高音弦，tuning 低→高 index 0=6弦，
        // 故 string 1 → tunings[5]（E4）。
        final freq = Note(tunings[6 - n.string].midi + n.fret).frequency(a4);
        final pcm = pluck(freq,
            sampleRate: sampleRate,
            seconds: n.technique == 'x' ? 0.3 : tailSeconds);
        final off = (n.beat * beatSamples).round();
        for (var i = 0; i < pcm.length && off + i < total; i++) {
          mix[off + i] += pcm[i] / 32768.0;
        }
      }
    }
  }
  return RenderedScore(
      pcm: Int16List.fromList(
          [for (final v in mix) (v.clamp(-1.0, 1.0) * 32767).round()]),
      sampleRate: sampleRate,
      seconds: total / sampleRate);
}
