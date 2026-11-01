import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/sound_engine.dart';
import '../../audio/synth.dart';
import '../../core/music/chord_catalog.dart';
import '../../core/music/chord_parser.dart';
import '../../core/music/fingering.dart';
import '../../state/tuning_state.dart';
import '../../ui/theme.dart';
import '../../ui/tuner/preset_editor.dart';
import '../../ui/tuner/preset_sheet.dart';

class ChordPage extends StatefulWidget {
  const ChordPage({super.key});
  @override
  State<ChordPage> createState() => _ChordPageState();
}

class _ChordPageState extends State<ChordPage> {
  final _input = TextEditingController(text: 'Am7');
  List<ChordVoicing> _voicings = [];
  String? _error;
  bool _ready = false;
  late TuningState _tuning;
  String? _lastTuningId;

  // 当前查询的显示名（结果卡片标题；输入/浏览两模式统一回显）。
  String _displayName = 'Am7';

  // 当前子类中文名（浏览模式有值；输入模式经解析器无目录映射，不显示）。
  String? _chordTypeName;

  // 浏览模式（设计 §13.1）：默认进入浏览（2026-11-01 走查：新手查阅是
  // 主路径）；分类 → 子类 → 根音三级**级联下拉**（走查：chips 平铺占屏）。
  bool _browseMode = true;
  String _categoryName = '三和弦';
  String _suffix = ''; // 当前子类后缀（默认大三）。
  int? _rootPc; // 选定根音；null = 未选。

  @override
  void initState() {
    super.initState();
    _tuning = context.read<TuningState>();
    _lastTuningId = _tuning.current.id;
    // 预设变更自动重查：当前调弦 id 变化 → 用新 strings 重算指法。
    _tuning.addListener(_onTuningChanged);
    SoundEngine.I.init().then((_) {
      if (mounted) setState(() => _ready = true);
    }).onError((_, _) {
      // 音频初始化失败：_ready 保持 false，试听按钮维持禁用。
    });
  }

  void _onTuningChanged() {
    if (_tuning.current.id == _lastTuningId) return;
    _lastTuningId = _tuning.current.id;
    // 浏览模式有选定根音走目录查询；输入模式查过（有结果或错误）才重查。
    if (_browseMode && _rootPc != null) {
      _query(browseChord(_rootPc!, _suffix));
    } else if (_voicings.isNotEmpty || _error != null) {
      _search();
    }
  }

  /// 调弦入口：弹出预设选择浮层（与调音器共享全局预设语义）。
  void _showTuningSheet() {
    final mq = MediaQuery.of(context);
    final state = _tuning;
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
            // 和弦库入口的删除暂无确认弹窗（直接删，可撤销性依赖重进）；
            // 调音器入口带确认，差异待统一。
            onDelete: (t) => state.deleteCustom(t),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tuning.removeListener(_onTuningChanged);
    _input.dispose();
    super.dispose();
  }

  /// 公共查询：ParsedChord → 指法（输入解析与浏览枚举两条路汇于此）。
  void _query(ParsedChord c, {String? displayName}) {
    final state = context.read<TuningState>();
    if (displayName != null) _displayName = displayName;
    _voicings = FingeringGenerator(state.current.strings)
        .generate(rootPc: c.rootPc, toneClasses: chordToneClasses(c));
    _error = null;
    setState(() {});
  }

  void _search() {
    try {
      // 输入模式专属：字符串解析失败要回显错误；浏览路径 suffix 来自
      // 目录恒有效，不经此 try/catch。
      _chordTypeName = null; // 输入名无目录映射，卡片不显中文名
      _query(parseChord(_input.text),
          displayName: _input.text.trim());
    } on ArgumentError catch (e) {
      _voicings = [];
      _error = e.message?.toString() ?? '解析失败';
      setState(() {});
    }
  }

  // ---- 浏览模式（设计 §13.1）：三级级联下拉，选定根音即查询 ----

  void _browseSelect(int rootPc) {
    setState(() => _rootPc = rootPc);
    // 名字写回输入框，切回输入模式沿用。
    _input.text = chordDisplayName(rootPc, _suffix);
    _chordTypeName = _typeNameOf(_suffix);
    _query(browseChord(rootPc, _suffix),
        displayName: _input.text);
  }

  void _selectSubtype(String suffix) {
    setState(() => _suffix = suffix);
    final root = _rootPc;
    if (root != null) {
      _input.text = chordDisplayName(root, suffix);
      _chordTypeName = _typeNameOf(suffix);
      _query(browseChord(root, suffix), displayName: _input.text);
    }
  }

  String? _typeNameOf(String suffix) {
    for (final cat in chordCategories) {
      for (final sub in cat.subtypes) {
        if (sub.suffix == suffix) return sub.name;
      }
    }
    return null;
  }

  void _selectCategory(String name) {
    setState(() {
      _categoryName = name;
      // 换大类默认选其第一个子类。
      _suffix = chordCategories
          .firstWhere((c) => c.name == name)
          .subtypes
          .first
          .suffix;
    });
    if (_rootPc != null) _selectSubtype(_suffix);
  }

  Future<void> _play(ChordVoicing v, PlayMode mode) async {
    final state = context.read<TuningState>();
    final pcm = voicingPcm(state.current.strings, v.frets, mode, a4: state.a4);
    final src = await SoundEngine.I.loadPcm(pcm);
    SoundEngine.I.play(src);
    // 播完（琶音最长约 2.3s）后释放音源；连点各自短生命周期，不累积音源。
    final ms = (pcm.length / 44100 * 1000).round() + 200;
    unawaited(Future<void>.delayed(Duration(milliseconds: ms))
        .then((_) => SoundEngine.I.disposeSource(src)));
  }

  /// 浏览面板：三级级联下拉（大类 → 子类 → 根音），选定根音即查
  /// （结果区复用输入模式）。2026-11-01 走查：chips 三行平铺占屏改下拉。
  List<Widget> _browsePanel(GuitarBarPalette p) {
    final category =
        chordCategories.firstWhere((c) => c.name == _categoryName);
    // 级联子类下拉显示"中文名（后缀示例）"。
    String subLabel(ChordSubtype s) =>
        s.suffix.isEmpty ? s.name : '${s.name}（${s.suffix}）';
    return [
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: const Key('chord-cat'),
            initialValue: _categoryName,
            decoration: const InputDecoration(labelText: '和弦分类'),
            items: [
              for (final cat in chordCategories)
                DropdownMenuItem(value: cat.name, child: Text(cat.name)),
            ],
            onChanged: (v) => _selectCategory(v!),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            key: const Key('chord-type'),
            initialValue: _suffix,
            decoration: const InputDecoration(labelText: '和弦类型'),
            items: [
              for (final sub in category.subtypes)
                DropdownMenuItem(
                    value: sub.suffix, child: Text(subLabel(sub))),
            ],
            onChanged: (v) => _selectSubtype(v!),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<int>(
            key: const Key('chord-root'),
            initialValue: _rootPc,
            decoration: const InputDecoration(labelText: '根音'),
            items: [
              for (final e in rootNames.entries)
                DropdownMenuItem(value: e.value, child: Text(e.key)),
            ],
            onChanged: (v) => _browseSelect(v!),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      if (_rootPc == null)
        Text('选定根音后显示指法（${category.name}共 ${category.subtypes.length} 类 × 12 根音）',
            style: TextStyle(fontSize: 12, color: p.muted)),
      const SizedBox(height: 8),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final state = context.watch<TuningState>();
    return Scaffold(
      appBar: AppBar(title: const Text('和弦库')),
      body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        // 模式切换：输入（乐手）/ 浏览（新手查阅，设计 §13.1）。
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('输入')),
            ButtonSegment(value: true, label: Text('浏览')),
          ],
          selected: {_browseMode},
          onSelectionChanged: (s) => setState(() => _browseMode = s.first),
        ),
        const SizedBox(height: 12),
        // 调弦入口：两模式共用，tap 打开预设浮层（全局预设，与调音器共享）。
        Row(children: [
          IconButton(
              onPressed: _showTuningSheet,
              tooltip: '切换调弦预设',
              icon: const Icon(Icons.tune)),
          Text(state.current.name,
              style: TextStyle(fontSize: 12, color: palette.muted)),
        ]),
        if (!_browseMode)
          Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                decoration: const InputDecoration(
                    labelText: '输入和弦名（如 Am7、F#m7b5）'),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _search, child: const Text('查询')),
          ]),
        if (_browseMode) ..._browsePanel(palette),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_error!, style: TextStyle(color: palette.negative))),
        Expanded(
          child: ListView.builder(
            itemCount: _voicings.length,
            itemBuilder: (_, i) {
              final v = _voicings[i];
              return Card(
                // P2：结果卡片比地色深一档（palette.panel）。
                color: context.palette.panel,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    // 卡片标题（2026-11-01 走查）：拼音名 + 中文类型名，
                    // 多张指法卡一眼可辨（参考 zhibojiaoshi 卡片结构）。
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: _displayName,
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: palette.ink)),
                        if (_chordTypeName != null)
                          TextSpan(
                              text: '  ${_chordTypeName!}',
                              style: TextStyle(
                                  fontSize: 12, color: palette.muted)),
                        TextSpan(
                            text: '  指法 ${i + 1}',
                            style: TextStyle(
                                fontSize: 12, color: palette.muted)),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                        width: 220,
                        height: 180,
                        child: CustomPaint(
                            painter: _ChordPainter(
                                frets: v.frets,
                                preferLowFret: i == 0,
                                palette: palette))),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      FilledButton.tonal(
                          onPressed:
                              _ready ? () => _play(v, PlayMode.pluckAll) : null,
                          child: const Text('同时')),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                          onPressed:
                              _ready ? () => _play(v, PlayMode.arpeggio) : null,
                          child: const Text('琶音')),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                          onPressed: _ready
                              ? () => _play(v, PlayMode.strumDown)
                              : null,
                          child: const Text('下扫')),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                          onPressed: _ready
                              ? () => _play(v, PlayMode.strumUp)
                              : null,
                          child: const Text('上扫')),
                    ]),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
      ),
    );
  }
}

class _ChordPainter extends CustomPainter {
  _ChordPainter(
      {required this.frets, required this.preferLowFret, required this.palette});
  final List<int?> frets;
  final bool preferLowFret;
  final GuitarBarPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final fretted = frets.whereType<int>().where((f) => f > 0).toList();
    final minFret = preferLowFret || fretted.isEmpty
        ? 1
        : math.max(1, fretted.reduce((a, b) => a < b ? a : b));
    const visibleFrets = 5;
    final line = Paint()
      ..color = palette.ink
      ..strokeWidth = 1.5;
    final left = 30.0, right = size.width - 10;
    final top = 40.0, gap = (size.height - top - 10) / visibleFrets;
    final stringGap = (right - left) / 5;
    for (var s = 0; s < 6; s++) {
      final x = left + stringGap * s;
      canvas.drawLine(Offset(x, top), Offset(x, top + gap * visibleFrets), line);
    }
    for (var f = 0; f <= visibleFrets; f++) {
      final y = top + gap * f;
      canvas.drawLine(
          Offset(left, y),
          Offset(right, y),
          f == 0
              ? (Paint()
                ..color = palette.ink
                ..strokeWidth = 4)
              : line);
    }
    if (!preferLowFret && fretted.isNotEmpty) {
      final tp = TextPainter(
          text: TextSpan(
              text: '$minFret品',
              style: TextStyle(fontSize: 12, color: palette.muted)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(2, top + gap * 0.5));
    }
    final dot = Paint()..color = palette.dataHue;
    for (var s = 0; s < 6; s++) {
      final f = frets[s];
      final x = left + stringGap * s;
      if (f == null) {
        canvas.drawLine(
            Offset(x - 5, 22),
            Offset(x + 5, 32),
            Paint()
              ..color = palette.negative
              ..strokeWidth = 2);
        canvas.drawLine(
            Offset(x - 5, 32),
            Offset(x + 5, 22),
            Paint()
              ..color = palette.negative
              ..strokeWidth = 2);
      } else if (f == 0) {
        canvas.drawCircle(Offset(x, 27), 5, Paint()..color = palette.positive);
      } else {
        final row = f - minFret;
        if (row >= 0 && row < visibleFrets) {
          canvas.drawCircle(Offset(x, top + gap * (row + 0.5)), 9, dot);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ChordPainter oldDelegate) =>
      oldDelegate.frets != frets || oldDelegate.palette != palette;
}
