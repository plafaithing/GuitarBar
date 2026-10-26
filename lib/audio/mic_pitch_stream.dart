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
///
/// 已知问题：Realtek SST 阵列在 44100/1 配置下可能挂起采集线程（进程无法
/// 终止），故候选表 48k 优先以规避该配置。
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

  /// 采集格式候选轮换表 (sampleRate, channels)：
  /// 48000/1 优先——Realtek SST 阵列原生格式；44100/1 配置已在用户机器上
  /// 实测挂起音频驱动线程（进程僵尸化无法终止），从首试起规避该配置。
  /// 某些组合 MediaFoundation 打开成功但只产数字静音（chunks 流动而 rms 恒 0），
  /// 按表轮换直到 rms>0 并锁定。
  static const _formatCandidates = [
    (48000, 1),
    (48000, 2),
    (44100, 1),
    (16000, 1),
    (96000, 1),
    (44100, 2),
  ];
  int _formatIndex = 0;
  bool _formatLocked = false;
  bool _rotating = false;
  int _zeroWindows = 0;
  String? _deviceId;

  /// 当前采集格式文本（诊断行显示）。
  String currentFormatText = '';

  /// 连续全静音（rms==0）窗口计数（诊断行显示）。
  int get zeroWindows => _zeroWindows;

  /// 最近一个 chunk 的前 16 字节 hex：全 00 = 真数字静音；非零乱值 = 格式误读。
  String lastChunkHex = '';

  /// 系统输入设备列表（供调音页设备选择器）。
  Future<List<InputDevice>> listDevices() => _rec.listInputDevices();

  Future<Stream<double?>> start({String? deviceId}) async {
    if (_busy || _rawSub != null) throw StateError('已在监听中');
    _busy = true;
    _deviceId = deviceId;
    try {
      if (!await _rec.hasPermission()) {
        throw StateError('麦克风权限被拒绝');
      }
      _out ??= StreamController<double?>();
      await _openRaw();
      return _out!.stream;
    } catch (_) {
      _busy = false;
      rethrow;
    }
  }

  /// 按当前轮换表格式打开底层录音流并接到 [_out]（页面流跨轮换持续有效）。
  Future<void> _openRaw() async {
    final (rate, ch) = _formatCandidates[_formatIndex];
    currentFormatText = '${rate}Hz/${ch}ch';
    chunkCount = 0;
    lastRms = 0;
    _zeroWindows = 0;
    lastChunkHex = '';
    _windower = PitchWindower(windowSamples: 4096, hopSamples: 2048);
    final raw = await _rec.startStream(RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: rate,
        numChannels: ch,
        // 平台端只消费 device.id；label 为必填字段，UI 不读它，传空串占位。
        device: _deviceId == null
            ? null
            : InputDevice(id: _deviceId!, label: '')));
    _rawSub = raw.listen((chunk) {
      chunkCount++;
      lastChunkHex = chunk
          .take(16)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      final i16 = Int16List.view(
          chunk.buffer, chunk.offsetInBytes, chunk.lengthInBytes ~/ 2);
      // 多声道交错：按声道步长取首声道，能量与音高检测都按单声道。
      final doubles = ch == 1
          ? [for (final v in i16) v / 32768.0]
          : [for (var i = 0; i < i16.length; i += ch) i16[i] / 32768.0];
      for (final w in _windower.add(doubles)) {
        final rms = windowRms(w);
        lastRms = rms;
        if (rms == 0) {
          _zeroWindows++;
        } else {
          _zeroWindows = 0;
          _formatLocked = true; // 有声：格式有效，停止轮换
        }
        _out!.add(rms < rmsGate ? null : detectPitch(w, rate));
      }
      if (!_formatLocked && !_rotating && _zeroWindows >= 15) {
        // 约 0.7s 纯数字静音：当前格式无效，自动换下一格式（页面流不断）。
        _rotating = true;
        unawaited(_rotateFormat().whenComplete(() => _rotating = false));
      }
    }, onError: _out!.addError, onDone: () {
      // 设备端自行结束（拔麦/权限收回）：清状态允许重启，否则永久变砖。
      _rawSub = null;
      _busy = false;
      _out!.close();
    });
  }

  /// 轮换到下一个采集格式；格式打不开（PlatformException）继续下一个；
  /// 表用尽停在最后一个（有界，不死循环）。
  Future<void> _rotateFormat() async {
    while (true) {
      if (_formatIndex >= _formatCandidates.length - 1) {
        _formatLocked = true;
        return;
      }
      _formatIndex++;
      await _rawSub?.cancel();
      _rawSub = null;
      await _rec.stop();
      try {
        await _openRaw();
        return;
      } on Exception {
        // 该格式打不开：继续试下一个。
      }
    }
  }

  Future<void> stop() async {
    await _rawSub?.cancel();
    _rawSub = null;
    await _rec.stop();
    await _out?.close();
    _out = null;
    _busy = false;
    _formatLocked = false;
    _rotating = false;
    _formatIndex = 0; // 重启/切设备后回到第一格式重新轮换
    _zeroWindows = 0;
  }

  /// 页面销毁时必须调用以停麦并释放录音资源
  Future<void> dispose() => _rec.dispose();
}
