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

/// 窗口 RMS（有效值），供静音门限使用；[rmsGate] 默认 0.005 ≈ -46 dBFS
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
///
/// 错误契约：录音流错误会原样转发（onError）、底层设备自行结束时会收到 done；
/// 本流为单订阅流，只能 listen 一次。调用方 listen 需提供 onError/onDone。
class MicPitchStream {
  final AudioRecorder _rec = AudioRecorder();
  PitchWindower _windower =
      PitchWindower(windowSamples: 4096, hopSamples: 2048);
  StreamSubscription<Uint8List>? _rawSub;
  StreamController<double?>? _out;
  // 同步忙标志：守卫住 hasPermission/startStream 两次 await 间的重入
  // （Task 11 节拍器同款先例）。
  bool _busy = false;

  /// 诊断字段（调音页 debug 行用）：本次监听会话收到的 chunk 计数。
  int chunkCount = 0;

  /// 最近一个窗口的 RMS 实时值。
  double lastRms = 0;

  /// 当前录音设备显示名（调用方在 start 前赋值）。
  String? currentDeviceName;

  /// 系统输入设备列表（供调音页设备选择器）。
  Future<List<InputDevice>> listDevices() => _rec.listInputDevices();

  Future<Stream<double?>> start(
      {int sampleRate = 44100, String? deviceId}) async {
    if (_busy || _rawSub != null) throw StateError('已在监听中');
    _busy = true;
    try {
      if (!await _rec.hasPermission()) {
        throw StateError('麦克风权限被拒绝');
      }
      chunkCount = 0;
      lastRms = 0;
      final raw = await _rec.startStream(RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
          // 平台端只消费 device.id；label 为必填字段，UI 不读它，传空串占位。
          device: deviceId == null
              ? null
              : InputDevice(id: deviceId, label: '')));
      _windower = PitchWindower(windowSamples: 4096, hopSamples: 2048);
      _out = StreamController<double?>();
      _rawSub = raw.listen((chunk) {
        chunkCount++;
        final i16 = Int16List.view(
            chunk.buffer, chunk.offsetInBytes, chunk.lengthInBytes ~/ 2);
        final doubles = [for (final v in i16) v / 32768.0];
        for (final w in _windower.add(doubles)) {
          final rms = windowRms(w);
          lastRms = rms;
          _out!.add(rms < rmsGate ? null : detectPitch(w, sampleRate));
        }
      }, onError: _out!.addError, onDone: () {
        // 设备端自行结束（拔麦/权限收回）：清状态允许重启，否则永久变砖。
        _rawSub = null;
        _busy = false;
        _out!.close();
      });
      return _out!.stream;
    } catch (_) {
      _busy = false;
      rethrow;
    }
  }

  Future<void> stop() async {
    await _rawSub?.cancel();
    _rawSub = null;
    await _rec.stop();
    await _out?.close();
    _out = null;
    _busy = false;
  }

  /// 页面销毁时必须调用以停麦并释放录音资源
  Future<void> dispose() => _rec.dispose();
}
