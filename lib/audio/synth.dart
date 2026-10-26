import 'dart:math' as math;
import 'dart:typed_data';

import '../core/music/note.dart';

const _clickFreqs = [1000.0, 820.0, 620.0]; // 0 重音 / 1 强拍 / 2 弱拍

Int16List click(int kind, {int sampleRate = 44100}) {
  final n = (sampleRate * 0.06).round();
  final out = Int16List(n);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    out[i] = (0.9 * math.exp(-t * 60) * math.sin(2 * math.pi * _clickFreqs[kind] * t) * 32767)
        .round();
  }
  return out;
}

/// Karplus-Strong 拨弦合成
Int16List pluck(double freq, {int sampleRate = 44100, double seconds = 1.2}) {
  final n = (sampleRate * seconds).round();
  final delayLen = math.max(2, (sampleRate / freq).round());
  final ring = Float64List(delayLen);
  final rand = math.Random(42); // 固定种子，结果可复现
  for (var i = 0; i < delayLen; i++) {
    ring[i] = rand.nextDouble() * 2 - 1;
  }
  final out = Int16List(n);
  var idx = 0;
  for (var i = 0; i < n; i++) {
    final cur = ring[idx];
    ring[idx] = (cur + ring[(idx + 1) % delayLen]) * 0.5 * 0.996;
    out[i] = (cur * 32767 * 0.8).round().clamp(-32768, 32767).toInt();
    idx = (idx + 1) % delayLen;
  }
  return out;
}

enum PlayMode { pluckAll, arpeggio, strumDown, strumUp }

/// 按指法发声：同时 / 琶音 / 下扫 / 上扫
Int16List voicingPcm(List<Note> tuning, List<int?> frets, PlayMode mode,
    {int sampleRate = 44100, double a4 = 440}) {
  final freqs = <double>[
    for (var i = 0; i < 6; i++)
      if (frets[i] != null) Note(tuning[i].midi + frets[i]!).frequency(a4)
  ];
  if (freqs.isEmpty) return Int16List(0);
  const arpStagger = 0.22, strumStagger = 0.025;
  final staggerSamples = switch (mode) {
    PlayMode.pluckAll => 0,
    PlayMode.arpeggio => (sampleRate * arpStagger).round(),
    PlayMode.strumDown => (sampleRate * strumStagger).round(),
    PlayMode.strumUp => (sampleRate * strumStagger).round(),
  };
  final total = 52920 + staggerSamples * (freqs.length - 1);
  final mix = Float64List(total);
  for (var k = 0; k < freqs.length; k++) {
    final pcm = pluck(freqs[k], sampleRate: sampleRate);
    final rev = mode == PlayMode.strumUp;
    final off = staggerSamples * (rev ? freqs.length - 1 - k : k);
    for (var i = 0; i < pcm.length; i++) {
      mix[off + i] += pcm[i] / 32768.0;
    }
  }
  return Int16List.fromList(
      [for (final v in mix) (v.clamp(-1.0, 1.0) * 32767).round()]);
}

/// 原始 16-bit 单声道 PCM → 完整 WAV 文件字节（flutter_soloud loadMem 需要）
Uint8List wrapWav(Int16List pcm, {int sampleRate = 44100, int channels = 1}) {
  final dataLen = pcm.length * 2;
  final out = Uint8List(44 + dataLen);
  final bd = out.buffer.asByteData();
  void ascii(int off, String s) {
    for (var i = 0; i < s.length; i++) {
      out[off + i] = s.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  bd.setUint32(4, 36 + dataLen, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bd.setUint32(16, 16, Endian.little); // PCM
  bd.setUint16(20, 1, Endian.little);
  bd.setUint16(22, channels, Endian.little);
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * channels * 2, Endian.little); // byte rate
  bd.setUint16(32, channels * 2, Endian.little); // block align
  bd.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  bd.setUint32(40, dataLen, Endian.little);
  out.setRange(44, out.length, pcm.buffer.asUint8List(0, dataLen));
  return out;
}
