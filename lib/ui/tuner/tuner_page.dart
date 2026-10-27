import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../audio/mic_pitch_stream.dart';
import '../../audio/sound_engine.dart';
import '../../audio/synth.dart';
import '../../core/music/builtin_tunings.dart';
import '../../core/music/note.dart';
import '../../core/music/tuning.dart';
// drift 生成的数据类 TuningPreset 与 core/music/tuning.dart 重名，hide 之。
import '../../data/database.dart' hide TuningPreset;
import '../../state/tuning_state.dart';
import '../../ui/theme.dart';

enum _TunerMode { guitar, chromatic }

class TunerPage extends StatefulWidget {
  const TunerPage({super.key});
  @override
  State<TunerPage> createState() => _TunerPageState();
}

class _TunerPageState extends State<TunerPage> {
  _TunerMode _mode = _TunerMode.guitar;
  int? _lockedString;
  bool _micOn = false;
  double? _freq;
  StreamSubscription<double?>? _sub;
  final _mic = MicPitchStream();
  // 最近一次麦克风打开错误（诊断行常驻显示，避免 SnackBar 一闪而过）。
  String? _lastError;
  // 输入设备（D2）：'' = 系统默认设备；选择持久化到 settings(key: micDeviceId)。
  List<InputDevice> _devices = [];
  String _selectedDeviceId = '';
  // 设备列表轮询（D4）：2s 一次，有变化才重建；插拔耳机实时可见。
  Timer? _devicePollTimer;
  // T1：未检测提示「弹拨任意琴弦开始调音」2 秒后自动淡出。
  Timer? _hintTimer;
  bool _showHint = true;

  @override
  void initState() {
    super.initState();
    unawaited(_initDevices());
    _devicePollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_refreshDevices());
    });
    _hintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showHint = false);
    });
  }

  @override
  void dispose() {
    _devicePollTimer?.cancel();
    _hintTimer?.cancel();
    _sub?.cancel();
    unawaited(_mic.dispose()); // 页面销毁必须停麦
    super.dispose();
  }

  Future<void> _toggleMic() async {
    if (_micOn) {
      await _sub?.cancel();
      _sub = null;
      await _mic.stop();
      _micOn = false;
      _freq = null;
    } else {
      try {
        _mic.currentDeviceName = _deviceDisplayName(_selectedDeviceId);
        final stream = await _mic.start(
            deviceId: _selectedDeviceId.isEmpty ? null : _selectedDeviceId);
        _sub = stream.listen(
          (f) {
            if (mounted) setState(() => _freq = f);
          },
          // 错误契约（见 MicPitchStream）：错误原样转发、结束时收到 done。
          onError: (Object _) {
            if (mounted) setState(() => _freq = null);
          },
          onDone: () {
            if (mounted) {
              _micOn = false;
              setState(() {});
            }
          },
        );
        _micOn = true;
        _lastError = null; // 重开成功，清掉上次的错误
      } on StateError catch (e) {
        _lastError = e.message;
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      } on Exception catch (e) {
        // 打开设备失败（权限/设备被占用/虚拟声卡异常等，多为 PlatformException）：
        // 错误存入诊断行常驻显示，不让异常静默飞走。
        _lastError = e.toString();
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('麦克风打开失败: $e'),
              duration: const Duration(seconds: 5)));
        }
      }
    }
    if (mounted) setState(() {});
  }

  /// 读取已保存设备 + 系统输入设备列表；保存的设备已消失则回系统默认。
  Future<void> _initDevices() async {
    final db = context.read<AppDatabase>();
    final row = await (db.select(db.settings)
            ..where((t) => t.key.equals('micDeviceId')))
        .getSingleOrNull();
    final saved = row?.value ?? '';
    final devices = await _mic.listDevices();
    if (!mounted) return;
    final exists = saved.isEmpty || devices.any((d) => d.id == saved);
    setState(() {
      _devices = devices;
      _selectedDeviceId = exists ? saved : '';
    });
    // T2：打开软件即自动开始调音（持久化设备/系统默认；切换设备走
    // _onDeviceChanged 的 stop→重开，无需再动）。
    if (mounted && !_micOn) await _toggleMic();
  }

  /// 切换输入设备：立即持久化；若在监听则先停再用新设备重开。
  Future<void> _onDeviceChanged(String? deviceId) async {
    if (deviceId == null) return;
    setState(() => _selectedDeviceId = deviceId);
    final db = context.read<AppDatabase>();
    await db.into(db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(key: 'micDeviceId', value: deviceId));
    if (!mounted || !_micOn) return;
    await _sub?.cancel();
    _sub = null;
    await _mic.stop();
    if (!mounted) return;
    _micOn = false;
    _freq = null;
    setState(() {});
    await _toggleMic();
  }

  String _deviceDisplayName(String id) {
    if (id.isEmpty) return '系统默认设备';
    for (final d in _devices) {
      if (d.id == id) return d.label;
    }
    return '未知设备';
  }

  /// 设备列表实时刷新（D4）：重新枚举输入设备，id 集合有变化才 setState；
  /// 选中设备被拔则回退系统默认（监听中的流会自然 done，不强制切流）。
  Future<void> _refreshDevices() async {
    final devices = await _mic.listDevices();
    if (!mounted) return;
    if (devices.map((d) => d.id).toSet() == _devices.map((d) => d.id).toSet()) {
      return; // 无变化不重建
    }
    final removed = _selectedDeviceId.isNotEmpty &&
        !devices.any((d) => d.id == _selectedDeviceId);
    setState(() {
      _devices = devices;
      if (removed) _selectedDeviceId = '';
    });
    if (removed) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('设备已移除，已回退系统默认')));
    }
  }

  (int, int)? _nearestString() {
    if (_freq == null) return null;
    final strings = context.read<TuningState>().current.strings;
    final a4 = context.read<TuningState>().a4;
    int best = -1, bestCents = 1 << 30;
    for (var i = 0; i < strings.length; i++) {
      final c = centsOff(_freq!, strings[i].frequency(a4));
      if (c.abs() < bestCents.abs()) {
        bestCents = c;
        best = i;
      }
    }
    return (best, bestCents);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TuningState>();
    int cents = 0;
    int autoIdx = -1; // 自动认弦命中的弦（未锁定时高亮用）
    Note? targetNote;
    if (_freq != null) {
      if (_mode == _TunerMode.chromatic) {
        targetNote =
            Note(69 + (12 * math.log(_freq! / state.a4) / math.ln2).round());
        cents = centsOff(_freq!, targetNote.frequency(state.a4));
      } else {
        final idx = _lockedString ?? (_nearestString()?.$1 ?? -1);
        autoIdx = idx;
        if (idx >= 0) {
          targetNote = state.current.strings[idx];
          cents = centsOff(_freq!, targetNote.frequency(state.a4));
        }
      }
    }
    final inTune = _freq != null && cents.abs() <= 3;
    // 当前命中弦（锁定优先，-1 = 未命中），弦块高亮/到位点用它。
    final hitIdx = _lockedString ?? autoIdx;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Row(children: [
          SegmentedButton<_TunerMode>(
            segments: const [
              ButtonSegment(value: _TunerMode.guitar, label: Text('吉他模式')),
              ButtonSegment(value: _TunerMode.chromatic, label: Text('半音调音器')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const Spacer(),
          IconButton(
              onPressed: () => _showA4Dialog(context, state),
              tooltip: 'A4 参考音高',
              icon: Text('A4=${state.a4.toStringAsFixed(0)}',
                  style: TextStyle(
                      fontSize: 14,
                      color: context.palette.muted,
                      fontFeatures: const [FontFeature.tabularFigures()]))),
          IconButton(
              // 右上 = 一键新建自定义（编辑器）；左上入口 = 选/管预设。
              onPressed: () => _showEditor(context, state),
              tooltip: '新建自定义调弦',
              icon: Icon(Icons.add_circle_outline,
                  color: context.palette.ink)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: () => _showPresetSheet(context, state),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  // 热区 ≥44px 高。
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.current.group.label,
                            style: TextStyle(
                                fontSize: 12,
                                color: context.palette.muted)),
                        const SizedBox(height: 2),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(state.current.name,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: context.palette.ink)),
                          const SizedBox(width: 4),
                          Icon(Icons.expand_more,
                              size: 16, color: context.palette.muted),
                        ]),
                      ]),
                ),
              ),
            ),
          ),
          // 自动/手动开关（行尾）：开 = 自动认弦；关 = 手动（锁定当前
          // 命中的弦，未检测则锁 6 弦，随后可点钮换弦）。标签随状态切字。
          Text(_lockedString == null ? '自动' : '手动',
              style:
                  TextStyle(fontSize: 12, color: context.palette.muted)),
          Switch(
            value: _lockedString == null,
            onChanged: (auto) => setState(() => _lockedString = auto
                ? null
                : (autoIdx >= 0 ? autoIdx : 0)),
          ),
        ]),
        const SizedBox(height: 8),
        // 网格区（T3/T4/T5）：调弦名行下方到琴头上方——小方格网格底 +
        // 中央参考竖线（基准）+ 固定目标环/小尖 + 随偏差滑动的指示线。
        Stack(children: [
          Positioned.fill(
            child: CustomPaint(
                painter: _GridPainter(ink: context.palette.ink)),
          ),
          Column(children: [
            _gaugeArea(cents.toDouble(), inTune, _freq != null),
            const SizedBox(height: 8),
            _statusPill(targetNote, cents),
          ]),
        ]),
        const SizedBox(height: 12),
        if (_mode == _TunerMode.guitar)
          _headstockSection(state,
              hitIdx: hitIdx, cents: cents, hasFreq: _freq != null),
        const SizedBox(height: 12),
        // 输入设备选择（长期保留）：默认设备是虚拟声卡时可一键切到真麦。
        Row(children: [
          Icon(Icons.mic_none, size: 16, color: context.palette.muted),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _selectedDeviceId,
              isDense: true,
              decoration: const InputDecoration(
                labelText: '输入设备',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              // 展开时强制刷新一次，保证点开看到的永远是最新列表。
              onTap: () => unawaited(_refreshDevices()),
              items: [
                const DropdownMenuItem(value: '', child: Text('系统默认设备')),
                for (final d in _devices)
                  DropdownMenuItem(
                      value: d.id,
                      child: Text(d.label, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (id) => unawaited(_onDeviceChanged(id)),
            ),
          ),
        ]),
        if (kDebugMode) ...[
          const SizedBox(height: 4),
          // 诊断行（D1，临时）：chunks=0 且 on:false → 打开设备就失败（看 err 行）；
          // chunks=0 且 on:true → 设备/权限在系统层被挡；rms 长期 <0.005 →
          // 默认设备是虚拟声卡；rms 正常但音高 null → 检测 bug。
          Text(
              'chunks:${_mic.chunkCount}  窗:${_mic.windowCount}  cs:${_mic.lastChunkSamples}  ws:${_mic.lastWindowSamples}  rms:${_mic.lastRms.toStringAsFixed(6)}  dev:${_mic.currentDeviceName ?? '-'}  on:$_micOn',
              style: TextStyle(
                  fontSize: 12,
                  color: context.palette.muted,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          // 格式自适应轮换（D3）：fmt 当前格式 / 静音窗 连续 rms==0 窗数 /
          // hex 最近 chunk 前 16 字节（全 00 = 真数字静音；非零乱值 = 格式误读）。
          Text(
              'fmt:${_mic.currentFormatText}  静音窗:${_mic.zeroWindows}  hex:${_mic.lastChunkHex}',
              style: TextStyle(
                  fontSize: 12,
                  color: context.palette.muted,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          if (_lastError != null)
            Text('err: $_lastError（重进调音页或重启应用重试）',
                style: TextStyle(
                    fontSize: 12,
                    color: context.palette.negative,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          // 回调内异常（Error/Exception 一并捕获）：非空即说明音频处理链在
          // 回调层炸过，配合 窗/cs/ws 定位断链层。
          if (_mic.callbackErr.isNotEmpty) ...[
            Text('cberr: ${_mic.callbackErr}',
                style: TextStyle(
                    fontSize: 12,
                    color: context.palette.negative,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            Text(_mic.callbackErrSt,
                style: TextStyle(
                    fontSize: 10, color: context.palette.muted)),
          ],
        ],
      ]),
    );
  }

  /// 仪表区（高 96）：水平轨道 + ♭/♯ 两端；固定目标环（放大镜式靶心，内写
  /// 音分数）+ 环下小尖，两者恒在水平中央；2px ink 指示线随检测音分左右
  /// 平滑滑动（±50 音分映射轨道全宽）——指示线与中央小尖对齐即准。
  Widget _gaugeArea(double cents, bool inTune, bool hasFreq) {
    return SizedBox(
      height: 96,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: cents.clamp(-50.0, 50.0)),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        builder: (context, anim, _) => LayoutBuilder(
            builder: (context, constraints) {
          final w = constraints.maxWidth;
          const margin = 40.0; // ♭/♯ 字宽留白
          final x = w / 2 + (anim / 50) * (w / 2 - margin);
          return Stack(fit: StackFit.expand, children: [
            Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Row(children: [
                  const SizedBox(width: 12),
                  Text('♭',
                      style: TextStyle(
                          fontSize: 20, color: context.palette.muted)),
                  Expanded(
                      child: Container(
                          height: 1.5, color: context.palette.muted)),
                  Text('♯',
                      style: TextStyle(
                          fontSize: 20, color: context.palette.muted)),
                  const SizedBox(width: 12),
                ])),
            // 移动指示线（2px ink 实色，比 T4 中央参考线更深），随偏差滑动。
            Positioned(
                top: 0,
                bottom: 0,
                left: x - 1,
                child: Container(
                    width: 2, color: context.palette.ink)),
            // 固定目标环：直径 44，3px ink 描边（暗板即白描边），环内透明底 +
            // 当前音分数（色随 |cents| 三段渐变）。
            Positioned(
                top: 24,
                left: w / 2 - 22,
                child: _targetRing(anim, hasFreq)),
            // 环下小尖（GuitarTuna 定位针），正对水平中央。
            Positioned(top: 68, left: w / 2 - 6, child: _needleTip()),
          ]);
        }),
      ),
    );
  }

  /// 目标环（V1）：不透明实底随 |cents| 渐变——未检测 surface 白/暗板；
  /// ≤3 positive 绿；3~25 绿→黄插值；>25 黄→红。数字色按填充亮度自适应
  /// （亮底 ink / 暗底白）；描边 3.5px 主题 ink（暗板即白描边）。
  Widget _targetRing(double animCents, bool hasFreq) {
    final abs = animCents.abs();
    final p = context.palette;
    final Color fill;
    if (!hasFreq) {
      fill = p.surface;
    } else if (abs <= 3) {
      fill = p.positive;
    } else if (abs <= 25) {
      fill = Color.lerp(p.positive, const Color(0xFFE6B800), (abs - 3) / 22)!;
    } else {
      fill = Color.lerp(const Color(0xFFE6B800), p.negative,
          ((abs - 25) / 25).clamp(0.0, 1.0))!;
    }
    final numColor = fill.computeLuminance() > 0.5 ? p.ink : Colors.white;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: Border.all(color: p.ink, width: 3.5)),
      alignment: Alignment.center,
      child: Text(hasFreq ? '${abs.round().clamp(0, 50)}' : '--',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: numColor,
              fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }

  Widget _needleTip() => SizedBox(
      width: 12,
      height: 8,
      child: CustomPaint(painter: _TipPainter(ink: context.palette.ink)));

  /// 状态 pill（页面主答元素）：固定深色胶囊（浅深两主题下都是深底白字，
  /// GuitarTuna 同款）——未检测显示引导文案 2 秒后淡出，检测中显示当前
  /// 音名 40px/600 白字 + 音分小字。
  Widget _statusPill(Note? targetNote, int cents) {
    return Center(
      child: AnimatedOpacity(
        opacity: targetNote != null || _showHint ? 1 : 0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          decoration: BoxDecoration(
              color: const Color(0xE6141414),
              borderRadius: BorderRadius.circular(32)),
          child: targetNote == null
              ? Text('弹拨任意琴弦开始调音',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(targetNote.label(flats: _preferFlats(targetNote)),
                      style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ])),
                  const SizedBox(width: 10),
                  Text(
                      '${cents.abs()} 音分 ${cents > 0 ? '偏高' : cents < 0 ? '偏低' : ''}',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ]),
        ),
      ),
    );
  }

  /// 琴头区（签名元素）：风格化琴头插画居中，左右两列圆形弦钮
  /// （左列 D A E = 4/5/6 弦，右列 G B E = 3/2/1 弦），点击 = 播参考音 + 锁定。
  Widget _headstockSection(TuningState state,
      {required int hitIdx, required int cents, required bool hasFreq}) {
    Widget knobColumn(List<int> indices) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final i in indices)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: _stringKnob(state, i,
                    hit: i == _lockedString || (hasFreq && i == hitIdx),
                    inTune: hasFreq && i == hitIdx && cents.abs() <= 3)),
        ]);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      knobColumn(const [2, 1, 0]),
      const SizedBox(width: 8),
      SizedBox(
          width: 250,
          height: 320,
          child: CustomPaint(painter: _HeadstockPainter())),
      const SizedBox(width: 8),
      knobColumn(const [3, 4, 5]),
    ]);
  }

  /// 圆形弦钮（直径 64）三态互斥（到位 > 检测命中 > 未检测），数据驱动的
  /// 状态色：到位 → pillPositiveBg 底 + positive 边框与文字；命中 → dataHue
  /// 浅调底 + dataHue 边框；未检测 → surface 白底 + controlBorder 细边。
  Widget _stringKnob(TuningState state, int i,
      {required bool hit, required bool inTune}) {
    final Color bg;
    final Color borderColor;
    final Color textColor;
    if (inTune) {
      bg = context.palette.pillPositiveBg;
      borderColor = context.palette.positive;
      textColor = context.palette.positive;
    } else if (hit) {
      // dataHue 浅调：alphaBlend 随主题自适应（亮色 ≈ #EAE1D9，暗色自动生成暗琥珀底）。
      bg = Color.alphaBlend(
          context.palette.dataHue.withValues(alpha: 0.18),
          context.palette.surface);
      borderColor = context.palette.dataHue;
      textColor = context.palette.ink;
    } else {
      bg = context.palette.surface;
      borderColor = context.palette.controlBorder;
      textColor = context.palette.ink;
    }
    return InkWell(
      onTap: () => _onStringTap(state, i),
      customBorder: const CircleBorder(),
      child: AnimatedScale(
        // 到位微缩（按下感），偏离回弹。
        scale: inTune ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bg,
              border: Border.all(
                  color: borderColor, width: inTune || hit ? 2 : 1)),
          alignment: Alignment.center,
          child: Text(state.current.strings[i].name,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      ),
    );
  }

  /// 点弦块：播放参考音 + 锁定该弦；已锁定再点仅重复播音，解锁走「自动」按钮。
  void _onStringTap(TuningState state, int i) {
    unawaited(_playReference(state, i));
    if (_lockedString != i) setState(() => _lockedString = i);
  }

  /// 播放第 i 弦参考音（pluck 0.8 满幅直接播）；播完 1.3s 后释放音源，
  /// 连点各自短生命周期，不累积音源。
  Future<void> _playReference(TuningState state, int i) async {
    final src = await SoundEngine.I
        .loadPcm(pluck(state.current.strings[i].frequency(state.a4)));
    SoundEngine.I.play(src);
    unawaited(Future<void>.delayed(const Duration(milliseconds: 1300))
        .then((_) => SoundEngine.I.disposeSource(src)));
  }

  bool _preferFlats(Note n) =>
      ['A#', 'C#', 'D#', 'F#', 'G#'].contains(n.name.substring(0, n.name.length - 1));

  void _showA4Dialog(BuildContext context, TuningState state) {
    double v = state.a4;
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('A4 参考音高'),
      content: StatefulBuilder(builder: (context, setD) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${v.toStringAsFixed(1)} Hz'),
          Slider(value: v, min: 430, max: 450, divisions: 40,
              label: v.toStringAsFixed(1),
              onChanged: (x) => setD(() => v = x)),
        ],
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () { state.setA4(v); Navigator.pop(context); },
            child: const Text('确定')),
      ],
    ));
  }

  /// 预设选择对话框：宽 360、高度随内容（超 480 才内部滚动，不再有底部空白）。
  void _showPresetSheet(BuildContext context, TuningState state) {
    showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('调弦预设'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 480),
                child: SizedBox(width: 360, child: _PresetSheet(state: state)),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('关闭')),
              ],
            ));
  }
}

/// 风格化琴头插画（签名元素，扁平语言不追求照片级）：暖木双色阶圆角梯形
/// 木板（帽形顶边），顶部浅色弦枕，6 根弦线从弦枕向下穿过琴颈，左右缘各
/// 3 个银灰旋钮圆点。dataHue 同族木色 = 主题性插画元素。
class _HeadstockPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const wood = Color(0xFF8A5A2B);
    const woodLight = Color(0xFFA06A35);
    const tunerMetal = Color(0xFFC7C2B8);
    const stringColor = Color(0xFFEFE9DC);

    // 木板主体：帽形顶边 + 两侧微内收到底。
    final body = Path()
      ..moveTo(w * 0.26, h * 0.18)
      ..quadraticBezierTo(w * 0.5, h * 0.02, w * 0.74, h * 0.18)
      ..lineTo(w * 0.71, h * 0.90)
      ..quadraticBezierTo(w * 0.5, h * 0.97, w * 0.29, h * 0.90)
      ..close();
    canvas.drawPath(body, Paint()..color = wood);

    // 右缘高光侧条（双色阶体积感，纯色无渐变）。
    final sheen = Path()
      ..moveTo(w * 0.52, h * 0.031)
      ..quadraticBezierTo(w * 0.735, h * 0.10, w * 0.74, h * 0.18)
      ..lineTo(w * 0.71, h * 0.90)
      ..quadraticBezierTo(w * 0.63, h * 0.94, w * 0.58, h * 0.925)
      ..close();
    canvas.drawPath(sheen, Paint()..color = woodLight);

    // 底部琴颈（同木色窄条向下出界，暗示接琴体）。
    canvas.drawRect(
        Rect.fromLTWH(w * 0.42, h * 0.90, w * 0.16, h * 0.10),
        Paint()..color = wood);

    // 弦枕（顶部浅色圆角条）。
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.37, h * 0.155, w * 0.26, h * 0.030),
            const Radius.circular(4)),
        Paint()..color = stringColor);

    // 弦线：弦枕下 6 根向琴颈收拢（浅色 1px）。
    final stringPaint = Paint()
      ..strokeWidth = 1
      ..color = stringColor;
    for (var i = 0; i < 6; i++) {
      final topX = w * (0.395 + i * 0.042);
      final bottomX = w * (0.445 + i * 0.022);
      canvas.drawLine(Offset(topX, h * 0.185), Offset(bottomX, h * 0.92),
          stringPaint);
    }

    // 左右缘各 3 个银灰旋钮圆点（跨缘，呼应外侧交互弦钮行高）。
    final knobPaint = Paint()..color = tunerMetal;
    for (final y in const [0.36, 0.55, 0.74]) {
      canvas.drawCircle(Offset(w * 0.265, h * y), 7, knobPaint);
      canvas.drawCircle(Offset(w * 0.735, h * y), 7, knobPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 网格背景（T3）：~24px 小方格，以水平中央为轴线条不透明度从中央向
/// 两侧线性衰减至 0（GuitarTuna 深底白网格的浅/暗主题等价物——ink 基线
/// 低透明度）。V2：中央参考竖线已删除——固定目标环 + 移动指示线已足够
/// 标示中央。
class _GridPainter extends CustomPainter {
  _GridPainter({required this.ink});

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 24.0;
    const centerAlpha = 0.10; // 网格基线：中心 10%，向两侧线性衰减
    final paint = Paint()..strokeWidth = 1;
    double alphaAt(double x) =>
        centerAlpha * (1 - ((x - size.width / 2).abs() / (size.width / 2)))
            .clamp(0.0, 1.0);

    for (var x = spacing; x < size.width; x += spacing) {
      final a = alphaAt(x);
      if (a <= 0.004) continue;
      paint.color = ink.withValues(alpha: a);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // 横线按 24px 分段，各段取其水平中心的透明度。
    for (var y = spacing; y < size.height; y += spacing) {
      for (var x = 0.0; x < size.width; x += spacing) {
        final a = alphaAt(x + spacing / 2);
        if (a <= 0.004) continue;
        paint.color = ink.withValues(alpha: a);
        canvas.drawLine(
            Offset(x, y),
            Offset(math.min(x + spacing, size.width), y),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => oldDelegate.ink != ink;
}

/// 固定目标环下方的小尖（朝下小三角，GuitarTuna 定位针样式）。
class _TipPainter extends CustomPainter {
  _TipPainter({required this.ink});

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_TipPainter oldDelegate) => oldDelegate.ink != ink;
}

class _PresetSheet extends StatelessWidget {
  const _PresetSheet({required this.state});
  final TuningState state;

  @override
  Widget build(BuildContext context) {
    final groups = TuningGroup.values;
    // 面板直接持有 state 未 watch，不包监听则增删预设后面板不刷新。
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 五组恒显示（含空的自定义组）：「新建自定义调弦」入口就住在
            // 自定义组里，组整体隐藏会让没建过预设的用户永远找不到它。
            for (final g in groups)
              ExpansionTile(
                  // 自定义组始终展开：面板一开就能看到「新建自定义调弦」。
                  initiallyExpanded:
                      g == TuningGroup.custom || state.current.group == g,
                  title: Text(g.label),
                  children: [
                    for (final t in [
                      ...builtinTunings.where((x) => x.group == g),
                      if (g == TuningGroup.custom) ...state.custom
                    ])
                      ListTile(
                        // 当前调弦：行尾 check + 标题加粗（比 selected 底色更可感知）。
                        title: Text(t.name,
                            style: state.current.id == t.id
                                ? TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: context.palette.ink)
                                : null),
                        subtitle:
                            Text(t.strings.map((n) => n.name).join(' ')),
                        selected: state.current.id == t.id,
                        onTap: () {
                          state.select(t);
                          Navigator.pop(context);
                        },
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          if (state.current.id == t.id)
                            Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Icon(Icons.check,
                                    color: context.palette.ink)),
                          if (g == TuningGroup.custom)
                            IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () =>
                                    _confirmDelete(context, state, t))
                          else
                            IconButton(
                                icon: const Icon(Icons.copy),
                                tooltip: '复制为新预设',
                                onPressed: () => _showEditor(context, state,
                                    base: t)),
                        ]),
                      ),
                    if (g == TuningGroup.custom)
                      ListTile(
                        leading: Icon(Icons.add_circle_outline,
                            color: context.palette.ink),
                        title: Text('新建自定义调弦',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: context.palette.ink)),
                        trailing: Icon(Icons.chevron_right,
                            color: context.palette.muted),
                        onTap: () => _showEditor(context, state),
                      ),
                  ],
                ),
          ],
        ),
      ),
    );
  }

  /// 删除前确认；删除后预设面板保持打开（ListenableBuilder 自动刷新列表）。
  void _confirmDelete(
      BuildContext context, TuningState state, TuningPreset t) {
    showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('删除预设'),
              content: Text('确定删除「${t.name}」？此操作不可撤销。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () {
                      state.deleteCustom(t);
                      Navigator.pop(dialogContext); // 只关确认框
                    },
                    child: const Text('删除')),
              ],
            ));
  }
}

/// 自定义调弦编辑器（顶层函数：预设对话框与顶部「新建自定义」入口共用）。
/// 命名 + 六根弦逐弦下拉选音 + 保存。
void _showEditor(BuildContext context, TuningState state,
    {TuningPreset? base}) {
  var name = base != null ? '${base.name} 副本' : '新调弦';
  var picked = List<Note>.from(base?.strings ??
      [Note.parse('E2'), Note.parse('A2'), Note.parse('D3'),
       Note.parse('G3'), Note.parse('B3'), Note.parse('E4')]);
  final allNotes = [for (var m = 28; m <= 88; m++) Note(m)];
  showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title: TextFormField(
                initialValue: name,
                onChanged: (v) => name = v,
                decoration: const InputDecoration(labelText: '预设名称')),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 6; i++)
                    DropdownButtonFormField<Note>(
                      // Flutter 3.47：value 已弃用，改用 initialValue。
                      initialValue: picked[i],
                      decoration: InputDecoration(labelText: '${6 - i} 弦'),
                      items: [
                        for (final n in allNotes)
                          DropdownMenuItem(value: n, child: Text(n.name))
                      ],
                      onChanged: (n) => picked[i] = n!,
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () {
                    final trimmed = name.trim();
                    if (trimmed.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(content: Text('预设名称不能为空')));
                      return;
                    }
                    state.addCustom(
                        trimmed, picked.map((n) => n.name).toList());
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('保存')),
            ],
          ));
}
