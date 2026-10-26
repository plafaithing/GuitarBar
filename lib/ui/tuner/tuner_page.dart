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

  @override
  void initState() {
    super.initState();
    unawaited(_initDevices());
  }

  @override
  void dispose() {
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
                      color: GuitarBarColors.muted,
                      fontFeatures: const [FontFeature.tabularFigures()]))),
          IconButton(
              // 右上 = 一键新建自定义（编辑器）；左上入口 = 选/管预设。
              onPressed: () => _showEditor(context, state),
              tooltip: '新建自定义调弦',
              icon: const Icon(Icons.add_circle_outline,
                  color: GuitarBarColors.ink)),
        ]),
        const SizedBox(height: 4),
        // 当前调弦小型入口（左上，无边框坐在地色上）：预设面板的常驻入口。
        // 竖排两行避免组名与调弦名横向连读（如 "Drop" + "Drop D"）。
        Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            onTap: () => _showPresetSheet(context, state),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              // 热区 ≥44px 高。
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.current.group.label,
                        style: const TextStyle(
                            fontSize: 12, color: GuitarBarColors.muted)),
                    const SizedBox(height: 2),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(state.current.name,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: GuitarBarColors.ink)),
                      const SizedBox(width: 4),
                      const Icon(Icons.expand_more,
                          size: 16, color: GuitarBarColors.muted),
                    ]),
                  ]),
            ),
          ),
        ),
        const Spacer(),
        // 音频流 ~20Hz 离散更新，150ms easeOut 插值消除指针跳变。
        TweenAnimationBuilder<double>(
          tween: Tween(end: cents.toDouble()),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          builder: (context, animCents, _) => SizedBox(
            width: 280,
            height: 280,
            child: Stack(alignment: Alignment.center, children: [
              Positioned.fill(
                child: CustomPaint(
                    painter: _DialPainter(cents: animCents, inTune: inTune)),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                // 签名元素（用户反馈 GuitarTuna 式表盘）：音名 52px/600 有意
                // 超出 48px 字号房规，属设计账本预留的升级位，不走主题角色。
                Text(
                    targetNote?.label(flats: _preferFlats(targetNote)) ?? '--',
                    style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w600,
                        color: GuitarBarColors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(height: 4),
                Text(
                    '${cents.abs()} 音分 ${cents > 0 ? '偏高' : cents < 0 ? '偏低' : ''}',
                    style: TextStyle(
                        fontSize: 18,
                        color: inTune
                            ? GuitarBarColors.positive
                            : GuitarBarColors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(height: 2),
                Text(
                    _freq == null
                        ? '未检测到声音'
                        : '${_freq!.toStringAsFixed(1)} Hz',
                    style: TextStyle(
                        fontSize: 14,
                        color: GuitarBarColors.muted,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ]),
          ),
        ),
        const Spacer(),
        if (_mode == _TunerMode.guitar)
          Row(children: [
            for (var i = 0; i < 6; i++) ...[
              Expanded(
                  child: _stringBlock(state, i,
                      bordered: _lockedString == null &&
                          _freq != null &&
                          i == autoIdx,
                      inTuneDot:
                          _freq != null && i == hitIdx && cents.abs() <= 3)),
              if (i < 5) const SizedBox(width: 8),
            ],
            const SizedBox(width: 12),
            // 行尾模式按钮：锁定时显「手动」（点击回自动）；自动态显「自动」
            // （muted 禁用，表示当前即是自动）。
            TextButton(
                onPressed: _lockedString == null
                    ? null
                    : () => setState(() => _lockedString = null),
                child: Text(_lockedString == null ? '自动' : '手动',
                    style: TextStyle(
                        fontSize: 12,
                        color: _lockedString == null
                            ? GuitarBarColors.muted
                            : GuitarBarColors.ink))),
          ]),
        const Spacer(),
        Center(
          child: FilledButton(
              onPressed: _toggleMic,
              child: Text(_micOn ? '停止' : '开始调音')),
        ),
        const SizedBox(height: 12),
        // 输入设备选择（长期保留）：默认设备是虚拟声卡时可一键切到真麦。
        Row(children: [
          const Icon(Icons.mic_none, size: 16, color: GuitarBarColors.muted),
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
              'chunks:${_mic.chunkCount}  rms:${_mic.lastRms.toStringAsFixed(4)}  dev:${_mic.currentDeviceName ?? '-'}  on:$_micOn',
              style: const TextStyle(
                  fontSize: 12,
                  color: GuitarBarColors.muted,
                  fontFeatures: [FontFeature.tabularFigures()])),
          if (_lastError != null)
            Text('err: $_lastError',
                style: const TextStyle(
                    fontSize: 12,
                    color: GuitarBarColors.negative,
                    fontFeatures: [FontFeature.tabularFigures()])),
        ],
      ]),
    );
  }

  /// 弦块：锁定弦块底 activePill（与自动高亮互斥，锁定优先）；未锁定时自动
  /// 认弦命中的弦加 dataHue 2px 边框（数据高亮）；命中弦到位（|cents| ≤ 3）
  /// 右上角 positive 绿点。
  Widget _stringBlock(TuningState state, int i,
      {required bool bordered, required bool inTuneDot}) {
    final locked = _lockedString == i;
    return Material(
      color: locked ? GuitarBarColors.activePill : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: bordered && !locked
            ? const BorderSide(color: GuitarBarColors.dataHue, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _onStringTap(state, i),
        child: SizedBox(
          height: 64,
          child: Stack(children: [
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${6 - i}弦',
                    style: const TextStyle(
                        fontSize: 12, color: GuitarBarColors.muted)),
                const SizedBox(height: 2),
                Text(state.current.strings[i].name,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: GuitarBarColors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
            if (inTuneDot)
              const Positioned(
                  top: 4,
                  right: 4,
                  child: SizedBox(
                      width: 8,
                      height: 8,
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              color: GuitarBarColors.positive,
                              shape: BoxShape.circle)))),
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

/// GuitarTuna 式圆形表盘：±50 音分映射 270° 弧（0 音分在正上方，底部开口），
/// 主刻度 -50/-25/0/+25/+50 带数值标签；弧线默认 border 灰、|cents| ≤ 3 整段
/// 转 positive 绿；dataHue 标记点（设计账本：数据色首次用于数据元素）在弧上
/// 指示当前偏差，细针（ink）从圆心指向标记。
class _DialPainter extends CustomPainter {
  _DialPainter({required this.cents, required this.inTune});
  final double cents;
  final bool inTune;

  /// cents ∈ [-50, 50] → 相对 12 点方向的偏角 ∈ [-135°, +135°]
  static double _angleOf(double c) =>
      -math.pi / 2 + (c / 50) * (3 * math.pi / 4);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // 留 24 外缘给刻度数值标签。
    final radius = math.min(size.width, size.height) / 2 - 24;

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = inTune ? GuitarBarColors.positive : GuitarBarColors.border;
    // 从左下端点（135°）顺时针画 270° 到右下端点（45°），开口朝正下方。
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        3 * math.pi / 4, 3 * math.pi / 2, false, arcPaint);

    final tickPaint = Paint()
      ..strokeWidth = 2
      ..color = GuitarBarColors.controlBorder;
    for (final c in const [-50, -25, 0, 25, 50]) {
      final dir = _direction(c.toDouble());
      canvas.drawLine(center + dir * (radius - 10),
          center + dir * radius, tickPaint);
      final tp = TextPainter(
          text: TextSpan(
              text: '$c',
              style: TextStyle(
                  fontSize: 11,
                  color: GuitarBarColors.muted,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          textDirection: TextDirection.ltr)
        ..layout();
      final labelCenter = center + dir * (radius + 14);
      tp.paint(canvas, labelCenter - Offset(tp.width / 2, tp.height / 2));
    }

    final dir = _direction(cents.clamp(-50.0, 50.0));
    final marker = center + dir * radius;
    canvas.drawLine(
        center,
        marker,
        Paint()
          ..strokeWidth = 2
          ..color = GuitarBarColors.ink);
    canvas.drawCircle(marker, 4, Paint()..color = GuitarBarColors.dataHue);
  }

  static Offset _direction(double c) {
    final a = _angleOf(c);
    return Offset(math.cos(a), math.sin(a));
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.cents != cents || old.inTune != inTune;
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
                                ? const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: GuitarBarColors.ink)
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
                            const Padding(
                                padding: EdgeInsets.only(right: 4),
                                child: Icon(Icons.check,
                                    color: GuitarBarColors.ink)),
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
                        leading: const Icon(Icons.add_circle_outline,
                            color: GuitarBarColors.ink),
                        title: Text('新建自定义调弦',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: GuitarBarColors.ink)),
                        trailing: const Icon(Icons.chevron_right,
                            color: GuitarBarColors.muted),
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
