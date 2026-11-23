import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/sound_engine.dart';
import '../../audio/synth.dart';
import '../../core/music/note.dart';
import '../../core/music/scale.dart';
import '../../state/tuning_state.dart';
import '../../ui/gbar_background.dart';
import '../../ui/theme.dart';
import '../../ui/tuner/preset_editor.dart';
import '../../ui/tuner/preset_sheet.dart';

class FretboardPage extends StatefulWidget {
  const FretboardPage({super.key});

  /// 根音橙（2026-11-23 用户：palette.positive 绿色在指板上不显——
  /// 换参考站同款暖橙，指板音名/chips/标题/文案统一；全 app positive
  /// 语义色不动）。
  static const Color rootOrange = Color(0xFFF08C2E);

  @override
  State<FretboardPage> createState() => _FretboardPageState();
}

class _FretboardPageState extends State<FretboardPage> {
  int _rootPc = 0; // C（2026-11-23 用户定默认：C 大调）
  ScaleType _scale = ScaleType.major;
  bool _showSolfege = false;
  final _player = SoundEngine.I;
  bool _ready = false;

  // 15 品（与参考站 openguitarchords 一致——真实品距几何下 19 品的高
  // 把位品距 <10px 音名会叠印；2026-11-22 用户定样"样式完全模仿"）。
  static const _frets = 15;
  static const _pcNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

  @override
  void initState() {
    super.initState();
    _player.init().then((_) {
      if (mounted) setState(() => _ready = true);
    }).onError((_, _) {});
  }

  /// 调弦入口（与和弦库同款）：弹出预设选择浮层（全局预设语义）。
  void _showTuningSheet() {
    final mq = MediaQuery.of(context);
    final state = context.read<TuningState>();
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
            // 指板入口的删除暂无确认弹窗（与和弦库入口一致，待统一）。
            onDelete: (t) => state.deleteCustom(t),
          ),
        ),
      ),
    );
  }

  Future<void> _tapCell(TuningState state, int stringIdx, int fret) async {
    final midi = state.current.strings[stringIdx].midi + fret;
    if (!_ready) return;
    final src =
        await _player.loadPcm(pluck(Note(midi).frequency(state.a4)));
    _player.play(src);
    Future.delayed(const Duration(seconds: 2),
        () => _player.disposeSource(src)); // 1.2s 音频 + 200ms 余量
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TuningState>();
    final palette = context.palette;
    final grid = fretboardGrid(state.current.strings, _rootPc, _scale, frets: _frets);
    final majorPcs = scalePitchClasses(_rootPc, ScaleType.major);
    final tuning = state.current.strings;
    return Scaffold(
      // v2：透明 + 统一光晕背景层。
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('指板音阶')),
      body: GbarBackground(child: Padding(
        // 水平 0：指板图**横向占满**（2026-11-23 用户澄清——琴颈拉长
        // 是横向；控件行/信息卡各自带水平边距）。
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
            DropdownButton<int>(
              value: _rootPc,
              dropdownColor: context.palette.panel,
              items: [
                for (var pc = 0; pc < 12; pc++)
                  DropdownMenuItem(value: pc, child: Text(_pcNames[pc]))
              ],
              onChanged: (v) => setState(() => _rootPc = v!),
            ),
            const SizedBox(width: 16),
            DropdownButton<ScaleType>(
              value: _scale,
              dropdownColor: context.palette.panel,
              items: [
                for (final s in ScaleType.values)
                  DropdownMenuItem(value: s, child: Text(s.label))
              ],
              onChanged: (s) => setState(() => _scale = s!),
            ),
            const SizedBox(width: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('音名')),
                ButtonSegment(value: true, label: Text('唱名')),
              ],
              selected: {_showSolfege},
              onSelectionChanged: (s) => setState(() => _showSolfege = s.first),
            ),
            const SizedBox(width: 8),
            // 调弦入口（与和弦库同款）：tap 打开预设浮层（全局预设共享）。
            IconButton(
                onPressed: _showTuningSheet,
                tooltip: '切换调弦预设',
                icon: const Icon(Icons.tune)),
            Text(state.current.name,
                style: TextStyle(fontSize: 12, color: palette.muted)),
          ]),
          ),
          const SizedBox(height: 15),
          // 指板图**横向占满**屏宽（2026-11-23 用户澄清：琴颈拉长是
          // 横向）；高度固定紧凑（品号行 + 6 弦，弦距 28px）。
          SizedBox(
            height: 186,
            width: double.infinity,
            child: LayoutBuilder(builder: (context, c) {
              return GestureDetector(
                onTapUp: (d) {
                  // 品距几何反查（hitCell 与 painter 同款几何）。
                  final hit = _FretboardPainter.hitCell(
                      d.localPosition, _frets, c.maxWidth, c.maxHeight);
                  if (hit != null) {
                    unawaited(_tapCell(state, hit.$1, hit.$2));
                  }
                },
                child: CustomPaint(
                  size: Size(c.maxWidth, c.maxHeight),
                  painter: _FretboardPainter(
                      grid: grid,
                      frets: _frets,
                      width: c.maxWidth,
                      height: c.maxHeight,
                      showSolfege: _showSolfege,
                      rootPc: _rootPc,
                      majorPcs: majorPcs,
                      stringNames: [
                        for (final n in tuning) _pcNames[n.pitchClass]
                      ],
                      palette: palette),
                ),
              );
            }),
          ),
          const SizedBox(height: 15),
          // —— 音阶信息卡（参考站 openguitarchords 同款内容：构成音 /
          // 音级 / 音程模式 / 听感用途 / 练法提示——页面不空）——
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: palette.panel,
                borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Text(_pcNames[_rootPc],
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: FretboardPage.rootOrange)),
                const SizedBox(width: 8),
                Text('${_scale.label}音阶',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600,
                        color: palette.ink)),
                const Spacer(),
                Text('音程模式 ${intervalPattern(_scale)}（W=全音，H=半音）',
                    style: TextStyle(fontSize: 12, color: palette.muted)),
              ]),
              const SizedBox(height: 10),
              // 构成音 chips（根音橙底，其余描边——参考站同款）。
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final pc in scalePitchClasses(_rootPc, _scale))
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                        color: pc == _rootPc
                            ? FretboardPage.rootOrange
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        border: pc == _rootPc
                            ? null
                            : Border.all(color: palette.border)),
                    child: Text(_pcNames[pc],
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: pc == _rootPc ? Colors.white : palette.ink)),
                  ),
              ]),
              const SizedBox(height: 10),
              Text(
                  '音级 ${degreesOf(_scale)} · ${_scale.feel}——${_scale.usage}',
                  style: TextStyle(fontSize: 12, color: palette.muted)),
              const SizedBox(height: 6),
              Text('练法提示：橙色是根音，先在每根弦上把它们找出来；再横向爬品、纵向走弦，把指型连成一片。',
                  style: TextStyle(fontSize: 12, color: palette.muted)),
            ]),
          ),
          ),
        ]),
      ),
      ),
    );
  }
}

class _FretboardPainter extends CustomPainter {
  _FretboardPainter(
      {required this.grid,
      required this.frets,
      required this.width,
      required this.height,
      required this.showSolfege,
      required this.rootPc,
      required this.majorPcs,
      required this.stringNames,
      required this.palette});
  final List<List<int?>> grid;
  final int frets;
  final double width, height;
  final bool showSolfege;
  final int rootPc;
  final List<int> majorPcs;
  final List<String> stringNames; // 弦名标注（当前调弦，6 弦低音在下）
  final GuitarBarPalette palette;

  // —— 布局（模仿 openguitarchords.com 指板图，2026-11-22 用户定样）：
  // 品距按 12 平均律真实几何递减；音 = 音名文字贴弦线（无圆点），根音
  // 橙色；品号顶部一行贴品线；弦名左侧列；琴枕粗线 ——
  static const _nameColW = 26.0; // 左侧弦名列宽
  static const _numRowH = 18.0; // 顶部品号行高
  static const _pcNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

  /// 品 f 的品线 x（真实几何：f=0 = 琴枕）。**scaleLen 按 frets 缩放**
  /// ——末品线距右缘 15px（2026-11-23 用户定值：留一点空白 + 整体
  /// 按比例重排——缩放几何自动重布品线）。
  static double fretX(int f, int frets, double width) {
    const rightMargin = 20.0; // 0.5cm ≈ 20 logical px（用户定值 2026-11-23）
    final avail = width - _nameColW - rightMargin;
    final span = 1 - math.pow(2, -frets / 12);
    final scaleLen = avail / span;
    return _nameColW + scaleLen * (1 - math.pow(2, -f / 12));
  }

  /// 弦 s 的弦线 y（1 弦最上——与曲谱页同惯例）。
  static double stringY(int s, double height) {
    final strH = (height - _numRowH) / 6;
    return _numRowH + (s + 0.5) * strH;
  }

  /// 命中反查：返回 (tuning 弦索引, fret)。
  /// 行映射：显示行 row（0=顶=1 弦）→ tuning 索引 5-row（tuning[0]=6 弦）。
  static (int, int)? hitCell(Offset pos, int frets, double width, double height) {
    final strH = (height - _numRowH) / 6;
    final row = ((pos.dy - _numRowH) ~/ strH).clamp(0, 5);
    // 音名骑在品丝线上（显示即所点）：找距 x 最近的品丝 = 品号。
    var best = 0;
    var bestD = double.infinity;
    for (var f = 0; f <= frets; f++) {
      final d = (pos.dx - fretX(f, frets, width)).abs();
      if (d < bestD) {
        bestD = d;
        best = f;
      }
    }
    return (5 - row, best);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 品线（真实几何递减；琴枕 f=0 粗线）。
    final linePaint = Paint()
      ..color = palette.border
      ..strokeWidth = 1;
    for (var f = 0; f <= frets; f++) {
      final x = fretX(f, frets, size.width);
      canvas.drawLine(Offset(x, _numRowH), Offset(x, size.height), linePaint);
      if (f == 0) {
        // 琴枕加粗（色不变）。
        canvas.drawLine(
            Offset(x, _numRowH), Offset(x, size.height),
            Paint()
              ..color = palette.ink
              ..strokeWidth = 2.5);
      }
    }
    // 弦线（6 条等距横线，从弦名右侧起）。
    for (var s = 0; s < 6; s++) {
      final y = stringY(s, size.height);
      canvas.drawLine(Offset(_nameColW + 2, y), Offset(size.width, y), linePaint);
      // 弦名（左侧列）。
      _label(canvas, stringNames[5 - s], Offset(6, y),
          fontSize: 11, color: palette.muted);
    }
    // 品号（顶部一行贴品线；0 = 琴枕不标）。
    for (var f = 1; f <= frets; f++) {
      final x = fretX(f, frets, size.width);
      _label(canvas, '$f', Offset(x, _numRowH - 9),
          fontSize: 10, color: palette.muted);
    }
    // 音（音阶内）= 音名文字贴弦线；根音橙色加粗。0 品音画在琴枕与
    // 1 品线之间（0 品列中点）。
    for (var s = 0; s < 6; s++) {
      for (var f = 0; f <= frets; f++) {
        final midi = grid[s][f];
        if (midi == null) continue;
        final isRoot = midi % 12 == rootPc;
        // 音名**骑在品丝线上**（参考站实测：音 x 与品线 x 重合，文字
        // 盖线——按弦位语义）；空弦音贴琴枕右侧 0.14 品距。
        final double x;
        if (f == 0) {
          x = fretX(0, frets, size.width) +
              (fretX(1, frets, size.width) - fretX(0, frets, size.width)) *
                  0.14;
        } else {
          x = fretX(f, frets, size.width);
        }
        // **弦序映射**：tuning[0] = 6 弦（低音）画在最下，1 弦在最上
        //（参考站同款；此前 grid[0] 画在顶行——弦序上下颠倒）。
        final y = stringY(5 - s, size.height);
        final label = showSolfege
            ? (majorPcs.contains(midi % 12)
                ? solfege[majorPcs.indexOf(midi % 12)]
                : _pcNames[midi % 12])
            : _pcNames[midi % 12];
        _label(canvas, label, Offset(x, y),
            fontSize: 13, // 2026-11-23 用户：字母放大 2 号（11→13）
            color: isRoot ? FretboardPage.rootOrange : palette.ink,
            bold: isRoot);
      }
    }
  }

  void _label(Canvas canvas, String text, Offset pos,
      {required double fontSize,
      required Color color,
      bool bold = false}) {
    final tp = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                fontSize: fontSize,
                color: color,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_FretboardPainter oldDelegate) => true;
}
