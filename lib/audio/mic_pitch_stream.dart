import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

import 'pitch_detector.dart';

/// 滑窗累积器：每新增 hopSamples 个样本，吐出一个末尾 windowSamples 大小的窗口
class PitchWindower {
  PitchWindower({required this.windowSamples, required this.hopSamples})
      : assert(hopSamples > 0 && windowSamples >= hopSamples);
  final int windowSamples;
  final int hopSamples;

  final List<double> _buf = [];
  int _sinceLast = 0;

  List<List<double>> add(Iterable<double> samples) {
    final out = <List<double>>[];
    for (final s in samples) {
      _buf.add(s);
      _sinceLast++;
      if (_sinceLast >= hopSamples) {
        _sinceLast = 0;
        if (_buf.length >= windowSamples) {
          out.add(List.of(_buf.sublist(_buf.length - windowSamples)));
        }
      }
    }
    if (_buf.length > windowSamples * 4) {
      _buf.removeRange(0, _buf.length - windowSamples);
    }
    return out;
  }
}

/// 窗口 RMS（有效值），供静音门限使用
double windowRms(List<double> w) {
  if (w.isEmpty) return 0;
  var sum = 0.0;
  for (final v in w) {
    sum += v * v;
  }
  return math.sqrt(sum / w.length);
}

/// 低于此 RMS 的窗口视为静音，产出 null（挡住 50Hz 工频嗡声等 idle 噪底）
const rmsGate = 0.005;

/// 订阅麦克风（record 包，16-bit 单声道 PCM），产出最新音高（Hz 或 null）
class MicPitchStream {
  final AudioRecorder _rec = AudioRecorder();
  final PitchWindower _windower =
      PitchWindower(windowSamples: 4096, hopSamples: 2048);
  StreamSubscription<Uint8List>? _rawSub;
  StreamController<double?>? _out;

  Future<Stream<double?>> start({int sampleRate = 44100}) async {
    if (!await _rec.hasPermission()) {
      throw StateError('麦克风权限被拒绝');
    }
    final raw = await _rec.startStream(RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1));
    _out = StreamController<double?>();
    _rawSub = raw.listen((chunk) {
      final i16 = Int16List.view(chunk.buffer, 0, chunk.lengthInBytes ~/ 2);
      final doubles = [for (final v in i16) v / 32768.0];
      for (final w in _windower.add(doubles)) {
        _out!.add(windowRms(w) < rmsGate ? null : detectPitch(w, sampleRate));
      }
    }, onError: _out!.addError, onDone: _out!.close);
    return _out!.stream;
  }

  Future<void> stop() async {
    await _rawSub?.cancel();
    _rawSub = null;
    await _rec.stop();
    await _out?.close();
    _out = null;
  }
}
