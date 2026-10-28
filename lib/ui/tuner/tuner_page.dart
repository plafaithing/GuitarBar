import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../audio/mic_pitch_stream.dart';
import '../../audio/sound_engine.dart';
import '../../audio/synth.dart';
import '../../core/music/note.dart';
import '../../core/music/tuning.dart';
// drift 生成的数据类 TuningPreset 与 core/music/tuning.dart 重名，hide 之。
import '../../data/database.dart' hide TuningPreset;
import '../../state/theme_settings.dart';
import '../../state/tuning_state.dart';
import '../../ui/theme.dart';
import 'guitar_headstock.dart';
import 'preset_editor.dart';
import 'preset_sheet.dart';

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
  // 单例（关机序列引用同一实例）：_mic 字段已移除。
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
    unawaited(MicPitchStream.I.stop()); // 单例复用：页面销毁只停流，释放留给关机序列
    super.dispose();
  }

  Future<void> _toggleMic() async {
    if (_micOn) {
      await _sub?.cancel();
      _sub = null;
      await MicPitchStream.I.stop();
      _micOn = false;
      _freq = null;
    } else {
      try {
        MicPitchStream.I.currentDeviceName = _deviceDisplayName(_selectedDeviceId);
        final stream = await MicPitchStream.I.start(
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
    final devices = await MicPitchStream.I.listDevices();
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
    await MicPitchStream.I.stop();
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
    final devices = await MicPitchStream.I.listDevices();
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

    // 页面高度自适应：琴头吃掉剩余竖向空间（iPad 11 寸横屏更饱满），
    // 窗口太矮时整页滚动而不是溢出（旧版在默认窗口即溢出 3px）。
    return LayoutBuilder(builder: (context, viewport) {
      final headHeight =
          ((viewport.maxHeight - 48) * 0.52).clamp(320.0, 640.0);
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: viewport.maxHeight),
          child: Padding(
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
              onPressed: () => showPresetEditor(context, state),
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
            // 样式继承主题 SwitchTheme（positive 绿轨 + 白 thumb），零本地覆盖。
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
          SizedBox(
            height: headHeight,
            child: GuitarHeadstock(
              labels: [for (final n in state.current.strings) n.name],
              hitIndex: hitIdx,
              lockedIndex: _lockedString,
              hasPitch: _freq != null,
              cents: cents,
              onTapString: (i) => _onStringTap(state, i),
            ),
          ),
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
        // 诊断行（I2）：默认隐藏，个人中心「调试模式」开关打开才显示。
        if (kDebugMode &&
            context.watch<ThemeSettingsState>().debugDiagnostics) ...[
          const SizedBox(height: 4),
          // 诊断行（D1，临时）：chunks=0 且 on:false → 打开设备就失败（看 err 行）；
          // chunks=0 且 on:true → 设备/权限在系统层被挡；rms 长期 <0.005 →
          // 默认设备是虚拟声卡；rms 正常但音高 null → 检测 bug。
          Text(
              'chunks:${MicPitchStream.I.chunkCount}  窗:${MicPitchStream.I.windowCount}  cs:${MicPitchStream.I.lastChunkSamples}  ws:${MicPitchStream.I.lastWindowSamples}  rms:${MicPitchStream.I.lastRms.toStringAsFixed(6)}  dev:${MicPitchStream.I.currentDeviceName ?? '-'}  on:$_micOn',
              style: TextStyle(
                  fontSize: 12,
                  color: context.palette.muted,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          // 格式自适应轮换（D3）：fmt 当前格式 / 静音窗 连续 rms==0 窗数 /
          // hex 最近 chunk 前 16 字节（全 00 = 真数字静音；非零乱值 = 格式误读）。
          Text(
              'fmt:${MicPitchStream.I.currentFormatText}  静音窗:${MicPitchStream.I.zeroWindows}  hex:${MicPitchStream.I.lastChunkHex}',
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
          if (MicPitchStream.I.callbackErr.isNotEmpty) ...[
            Text('cberr: ${MicPitchStream.I.callbackErr}',
                style: TextStyle(
                    fontSize: 12,
                    color: context.palette.negative,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            Text(MicPitchStream.I.callbackErrSt,
                style: TextStyle(
                    fontSize: 10, color: context.palette.muted)),
          ],
        ],
      ]),
          ),
        ),
      );
    });
  }

  /// 仪表区（高 96）：♭/♯ 两端；滑动目标环（不透明实底随 |cents| 渐变，
  /// 内写音分数）+ 环下小尖整体沿顶部虚拟轨道左右平滑滑动（±50 音分映射
  /// 全宽）——滑到与固定中央基准轴（网格层）重合即调准（环变绿）。
  Widget _gaugeArea(double cents, bool inTune, bool hasFreq) {
    return SizedBox(
      height: 84,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: cents.clamp(-50.0, 50.0)),
        duration: const Duration(milliseconds: 300),
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
                child: Padding(
                  // ♭/♯ 分居两端（无连线：轨道为虚拟滑动范围）。
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('♭',
                            style: TextStyle(
                                fontSize: 20, color: context.palette.muted)),
                        Text('♯',
                            style: TextStyle(
                                fontSize: 20, color: context.palette.muted)),
                      ]),
                )),
            // 滑动目标环 + 环下小尖：与中央基准轴重合即准。
            Positioned(top: 24, left: x - 22, child: _targetRing(anim, hasFreq)),
            Positioned(top: 68, left: x - 6, child: _needleTip()),
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

  /// 删除前确认；删除后预设面板保持打开（PresetSheet 监听 state 自动刷新）。
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

  /// 预设选择浮层：尺寸随窗口取（宽 320~420、高 420~640），超出内部滚动。
  void _showPresetSheet(BuildContext context, TuningState state) {
    final mq = MediaQuery.of(context);
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: (mq.size.width * 0.9).clamp(320.0, 420.0),
          height: (mq.size.height * 0.72).clamp(420.0, 640.0),
          child: PresetSheet(
            state: state,
            onSelect: (t) {
              state.select(t);
              Navigator.pop(dialogContext);
            },
            onCreate: () => showPresetEditor(dialogContext, state),
            onDuplicate: (t) => showPresetEditor(dialogContext, state, base: t),
            onDelete: (t) => _confirmDelete(dialogContext, state, t),
          ),
        ),
      ),
    );
  }
}

/// 网格线与移动指示线的统一线宽（A1：两者粗细完全一致）。
const _gridStroke = 1.0;

/// 网格背景（T3）：~24px 小方格，以水平中央为轴线条不透明度从中央向
/// 两侧线性衰减至 0（GuitarTuna 深底白网格的浅/暗主题等价物——ink 基线
/// 低透明度）。设计纠正轮：全高中央竖轴恢复且固定（1.5px ink@18%，比
/// 网格清晰的"正中央"基准轴，滑动目标环与之重合即调准）。
class _GridPainter extends CustomPainter {
  _GridPainter({required this.ink});

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 24.0;
    const centerAlpha = 0.10; // 网格基线：中心 10%，向两侧线性衰减
    final paint = Paint()..strokeWidth = _gridStroke;
    double alphaAt(double x) =>
        centerAlpha * (1 - ((x - size.width / 2).abs() / (size.width / 2)))
            .clamp(0.0, 1.0);

    // 竖线：以水平中央为一条网格线向两侧展开。
    final half = size.width / 2;
    final kMax = (half / spacing).ceil();
    for (var k = -kMax; k <= kMax; k++) {
      final x = half + k * spacing;
      if (x <= 0 || x >= size.width) continue;
      final a = alphaAt(x);
      if (a <= 0.004) continue;
      paint.color = ink.withValues(alpha: a);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // 横线按 24px 分段，各段取其水平中心的透明度（相位从左缘起算）。
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

    // 固定中央基准轴（1.5px，比网格清晰、比滑动环浅）。
    canvas.drawLine(
        Offset(half, 0),
        Offset(half, size.height),
        Paint()
          ..strokeWidth = 1.5
          ..color = ink.withValues(alpha: 0.18));
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
