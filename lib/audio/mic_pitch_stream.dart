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

/// 窗口 RMS（有效值），供静音门限使用；[rmsGate] 默认 0.0005 ≈ -66 dBFS
double windowRms(List<double> w) {
  if (w.isEmpty) return 0;
  var sum = 0.0;
  for (final v in w) {
    sum += v * v;
  }
  return math.sqrt(sum / w.length);
}

/// 低于此 RMS 的窗口视为静音，产出 null（挡住 50Hz 工频嗡声等 idle 噪底）。
/// 0.0005 ≈ -66 dBFS：只挡真正的数字静音/设备底噪。SST 阵列关闭音频增强后
/// 实际电平低（-30~-46 dBFS 信号、窗口 RMS 可低至 0.000x），会低于旧门限
/// 0.005（-46 dBFS）而被整体吞掉，故下调（用户实测反馈权威值 -30dBFS 峰值）。
///
/// 注意：轮换的「静音窗」计数用的是 rms == 0（严格数字静音），与本门限解耦——
/// 若跟随门限，安静环境的非零底噪会误触发格式轮换。
const rmsGate = 0.0005;

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

  /// 累计出窗数（诊断）：音高流事件链是否活着的直接指标——
  /// chunks 在涨而 windowCount 恒 0 = 「chunk → 窗口器」之间断链。
  int windowCount = 0;

  /// 最近一个 chunk 的样本数（lengthInBytes ~/ 2）。
  int lastChunkSamples = 0;

  /// 最近一次出窗的窗口样本数（应为 windowSamples=4096）。
  int lastWindowSamples = 0;

  /// 回调内最近一次异常（Error/Exception 一并捕获；诊断行显示）。
  /// 历史教训：Error（如对已关闭控制器 add 的 StateError）不进 onError、
  /// 页面 catch Exception 也接不住，静默飞走导致整条音高流假死。
  String callbackErr = '';

  /// [callbackErr] 对应堆栈前 300 字符。
  String callbackErrSt = '';

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
    windowCount = 0;
    lastChunkSamples = 0;
    lastWindowSamples = 0;
    callbackErr = '';
    callbackErrSt = '';
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
      try {
        chunkCount++;
        lastChunkSamples = chunk.lengthInBytes ~/ 2;
        lastChunkHex = chunk
            .take(16)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(' ');
        // ByteData.getInt16 不要求 2 字节对齐——record 的 chunk 是大缓冲
        // 子视图，offsetInBytes 可为奇数；Int16List.view 对奇偏移创建即抛
        // RangeError（真凶：该块样本全丢、音高流假死）。
        final bd = ByteData.sublistView(chunk);
        final doubles = ch == 1
            ? [
                for (var i = 0; i < chunk.lengthInBytes ~/ 2; i++)
                  bd.getInt16(i * 2, Endian.little) / 32768.0
              ]
            : [
                for (var i = 0; i + ch * 2 <= chunk.lengthInBytes; i += ch * 2)
                  bd.getInt16(i, Endian.little) / 32768.0
              ];
        for (final w in _windower.add(doubles)) {
          windowCount++;
          lastWindowSamples = w.length;
          final rms = windowRms(w);
          lastRms = rms;
          if (rms == 0) {
            _zeroWindows++;
          } else {
            _zeroWindows = 0;
            _formatLocked = true; // 有声：格式有效，停止轮换
          }
          // 空安全调用：设备端 done 后 _out 已置空，迟到的 chunk 不再炸。
          _out?.add(rms < rmsGate ? null : detectPitch(w, rate));
        }
        if (!_formatLocked && !_rotating && _zeroWindows >= 15) {
          // 约 0.7s 纯数字静音：当前格式无效，自动换下一格式（页面流不断）。
          _rotating = true;
          unawaited(_rotateFormat().whenComplete(() => _rotating = false));
        }
      } catch (e, st) {
        // Error 与 Exception 一并显形；不 rethrow——单块异常不中断后续块
        // （下一块数据自会验证），但真相进诊断行，不再静默飞走。
        callbackErr = e.toString();
        callbackErrSt =
            st.toString().substring(0, st.toString().length.clamp(0, 300));
      }
    }, onError: _out!.addError, onDone: () {
      // 设备端自行结束（拔麦/权限收回）：清状态允许重启，否则永久变砖。
      // _out 置空与 stop() 对齐——否则后续 _out!.add 对已关闭控制器抛
      // StateError（Error 子类），每个窗口全炸且无人接住，音高流假死。
      _rawSub = null;
      _busy = false;
      _out?.close();
      _out = null;
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
