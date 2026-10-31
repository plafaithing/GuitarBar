import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/score/score_ir.dart';
import '../theme.dart';
import 'tab_layout.dart';

/// 六线谱视图：弦线/品数字/技法字母标注/小节线 + 置信度标记 + failed 小节
/// 可见化 + 播放头。1 弦在最上。dataHue 上数据（低置信度底），播放头 positive。
///
/// 渲染分层（播放滚动卡顿修复）：谱面静态层与播放头层各自 shouldRepaint——
/// 播放 50ms tick 只重画播放头竖线（RepaintBoundary 隔离），谱面层 ir 不变
/// 不重绘，且画时按滚动位置只录可视行。
class TabView extends StatefulWidget {
  const TabView(
      {super.key,
      required this.ir,
      this.playheadBeat,
      this.followPlayhead = false,
      this.onNoteTap,
      this.onFailedTap});
  final ScoreIr ir;

  /// 播放头位置（全曲拍位，Task 16 接线）；null = 不显示。
  final double? playheadBeat;

  /// 播放跟随（走查反馈 ②）：播放头滑出可视窗口时自动平滑滚动居中。
  final bool followPlayhead;
  final void Function(int measureIndex, int noteIndex, NoteIr note)? onNoteTap;
  final void Function(int measureIndex)? onFailedTap;

  @override
  State<TabView> createState() => _TabViewState();
}

class _TabViewState extends State<TabView> {
  final ScrollController _scroll = ScrollController();

  /// 最近一次布局的视口宽（跟随计算需要 rowsFor(宽)，didUpdateWidget
  /// 阶段拿不到约束，缓存 build/LayoutBuilder 时的值）。
  double? _width;

  @override
  void didUpdateWidget(covariant TabView old) {
    super.didUpdateWidget(old);
    final beat = widget.playheadBeat;
    if (!widget.followPlayhead || beat == null || beat == old.playheadBeat) {
      return;
    }
    // 帧末再滚：届时本帧布局已完成，_width 与滚动位置均为新值。
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow(beat));
  }

  /// 播放跟随：播放头所在行中心 → 平滑滚到可视区居中（250ms）。
  /// 仅播放头滑出可视窗口（留一行高缓冲）时触发——50ms 刷新里播放头
  /// 在窗口内移动不触发，避免动画反复打断手动滚动。
  void _follow(double beat) {
    if (!_scroll.hasClients) return;
    final w = _width;
    if (w == null) return;
    final layout = TabLayout(widget.ir);
    final measureCount =
        widget.ir.tracks.isEmpty ? 0 : widget.ir.tracks.first.measures.length;
    if (measureCount == 0) return;
    // 曲末拍位恰好等于总拍数时 locate 会落空，clamp 到最后一个小节。
    final measure =
        (beat / layout.beatsPerBar).floor().clamp(0, measureCount - 1);
    final row = layout.locate(measure, w).$1;
    final y =
        row * (layout.rowHeight + TabLayout.rowGap) + layout.rowHeight / 2;
    final pos = _scroll.position;
    // 窗口内（含居中后的静止位置）不动。
    if (y >= pos.pixels &&
        y <= pos.pixels + pos.viewportDimension - layout.rowHeight) {
      return;
    }
    final target =
        (y - pos.viewportDimension / 2).clamp(0.0, pos.maxScrollExtent);
    // 目标即当前位置：免空动画。
    if ((target - pos.pixels).abs() < 0.5) return;
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(builder: (ctx, box) {
      final layout = TabLayout(widget.ir);
      final w = box.maxWidth;
      _width = w;
      // GestureDetector 放滚动区内：hit test 链自动换算，localPosition 即内容
      // 坐标，滚动后命中不错位；tap 与垂直 drag 分属不同轴互不干扰。
      // behavior=opaque 冗余但更防御（RenderCustomPaint.hitTestSelf 对未重写
      // hitTest 的 painter 本就返回 true，deferToChild 已可命中；opaque 兜底
      // 覆盖 painter 未来重写 hitTest 的情况）。
      // 双层 CustomPaint（不能合并为一个 painter/foregroundPainter：同一
      // RenderObject 任一变更整体重绘）：谱面层 ir 不变时 shouldRepaint=false
      // 不重绘；播放头层包 RepaintBoundary，50ms tick 只重录本层一条竖线。
      return SingleChildScrollView(
        controller: _scroll,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _hitTest(d.localPosition, w),
          child: SizedBox(
            width: w,
            height: layout.sizeFor(w).height,
            child: Stack(children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ScorePainter(
                      layout: layout,
                      ir: widget.ir,
                      scroll: _scroll,
                      stringLine: p.border,
                      fretText: p.ink,
                      barLine: p.border,
                      confBg: p.dataHue.withValues(alpha: 0.12),
                      failedText: p.negative,
                      pageNum: p.muted),
                ),
              ),
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _PlayheadPainter(
                        layout: layout,
                        playheadBeat: widget.playheadBeat,
                        playhead: p.positive),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }

  /// 点击命中：找最近的弦线（|dy| < stringGap/2），再找该弦上最近的音符
  /// （|dx| < pxPerBeat/2）。failed 小节整块可点。
  void _hitTest(Offset local, double maxWidth) {
    final layout = TabLayout(widget.ir);
    final tracks = widget.ir.tracks;
    if (tracks.isEmpty ||
        (widget.onNoteTap == null && widget.onFailedTap == null)) {
      return;
    }
    for (final m in tracks.first.measures) {
      final mx = layout.measureX(m.index, maxWidth);
      if (local.dx < mx - TabLayout.measureGap / 2 ||
          local.dx > mx + layout.measureWidth) {
        continue;
      }
      final row = layout.locate(m.index, maxWidth).$1;
      if (m.failed) {
        // 行纵向校验：多行布局下同列不同行 x 相同，必须限定 dy 在本行弦区。
        final rowTop = layout.stringY(1, row);
        final rowBottom = layout.stringY(6, row);
        if (local.dy >= rowTop - 8 && local.dy <= rowBottom + 8) {
          widget.onFailedTap?.call(m.index);
          return;
        }
        continue;
      }
      for (var i = 0; i < m.notes.length; i++) {
        final n = m.notes[i];
        final nx = layout.noteX(m.index, n.beat, maxWidth);
        final ny = layout.stringY(n.string, row);
        if ((local.dx - nx).abs() < TabLayout.pxPerBeat / 2 &&
            (local.dy - ny).abs() < TabLayout.stringGap / 2) {
          widget.onNoteTap?.call(m.index, i, n);
          return;
        }
      }
    }
  }
}

/// 静态谱面层：弦线/小节线/品数字/技法字母/置信度底/failed 标记/图例。
/// 播放头不在此层（见 _PlayheadPainter）。滚动时 SingleChildScrollView 整棵
/// 重绘会重跑 paint()，因此这里按当前 scroll offset 只画可视行（加一行缓冲），
/// 全量 2600 音符降为窗口内约 4 行；谱面层因此不能包 RepaintBoundary——
/// 缓存层会让裁剪区过期。ir 不变时 shouldRepaint=false，播放 tick 不重绘。
class _ScorePainter extends CustomPainter {
  _ScorePainter({
    required this.layout,
    required this.ir,
    required this.scroll,
    required this.stringLine,
    required this.fretText,
    required this.barLine,
    required this.confBg,
    required this.failedText,
    required this.pageNum,
  });

  final TabLayout layout;
  final ScoreIr ir;

  /// 仅 paint 里读当前滚动位置裁可视行；滚动重绘由 viewport 触发，
  /// 不参与 shouldRepaint。
  final ScrollController scroll;

  final Color stringLine, fretText, barLine, confBg, failedText, pageNum;

  @override
  void paint(Canvas canvas, Size size) {
    final rows = layout.rowsFor(size.width);
    final measures =
        ir.tracks.isEmpty ? const <MeasureIr>[] : ir.tracks.first.measures;

    // 可视行区间（加一行缓冲）：painter 画布坐标即内容坐标
    // （内容 y = 视口 y + scrollOffset）。
    final stride = layout.rowHeight + TabLayout.rowGap;
    final scrollOffset = scroll.hasClients ? scroll.offset : 0.0;
    final viewportH =
        scroll.hasClients ? scroll.position.viewportDimension : size.height;
    final firstRow = math.max(0, (scrollOffset / stride).floor() - 1);
    final lastRow = math.min(
        rows.length - 1, ((scrollOffset + viewportH) / stride).ceil() + 1);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, scrollOffset, size.width, viewportH));
    for (var r = firstRow; r <= lastRow; r++) {
      final rowTop = layout.stringY(1, r);
      final rowBottom = layout.stringY(6, r);
      // 弦线（1 弦最上）。
      for (var s = 1; s <= 6; s++) {
        final y = layout.stringY(s, r);
        canvas.drawLine(Offset(TabLayout.leftPad, y),
            Offset(size.width - TabLayout.leftPad, y),
            Paint()..color = stringLine);
      }
      for (final m in rows[r].map((idx) => measures[idx])) {
        final mx = layout.measureX(m.index, size.width);
        final mw = layout.measureWidth;
        // 低置信度底（failed 不画底，画标记）。
        if (!m.failed && m.confidence < 0.6) {
          canvas.drawRect(
              Rect.fromLTWH(mx, rowTop - 8, mw, rowBottom - rowTop + 16),
              Paint()..color = confBg);
        }
        // 小节号。
        _text(canvas, '${m.index + 1}', Offset(mx, rowTop - 16),
            TextStyle(
                fontSize: 10,
                color: pageNum,
                fontFeatures: [FontFeature.tabularFigures()]));
        // 左右小节竖线。
        canvas.drawLine(Offset(mx, rowTop), Offset(mx, rowBottom),
            Paint()..color = barLine);
        canvas.drawLine(Offset(mx + mw, rowTop), Offset(mx + mw, rowBottom),
            Paint()..color = barLine);
        if (m.failed) {
          _text(canvas, '未识别', Offset(mx + mw / 2, (rowTop + rowBottom) / 2),
              TextStyle(fontSize: 12, color: failedText));
          continue;
        }
        // 同拍同弦多声部音符计数（2026-10-31 走查修复"12 写两遍"）：
        // 指弹谱两个声部在同一拍弹同一弦同一品是合法数据（GP8 错开显示），
        // 渲染层第二个及后续音符 x 偏移 12px 防止文字重叠。
        final seenAt = <String, int>{}; // (string@beatRounded) → 已画次数
        for (final n in m.notes) {
          final nx = layout.noteX(m.index, n.beat, size.width);
          final ny = layout.stringY(n.string, r);
          final key = '${n.string}@${n.beat.toStringAsFixed(1)}';
          final dupCount = seenAt.putIfAbsent(key, () => 0);
          seenAt[key] = dupCount + 1;
          final dx = dupCount * 12.0; // 第 2/3 个音右偏 12/24px
          _text(canvas, '${n.fret}', Offset(nx + dx, ny),
              TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: fretText,
                  fontFeatures: [FontFeature.tabularFigures()]));
          // 技法字母标注（走查反馈 ③）：H=泛音 s=滑音 x=闷 b=弯 h/p=击勾，
          // 字母本身即标注——品数字右上角小字，muted 色，弦线/小节线不动。
          final tech = n.technique;
          if (tech != null) {
            _text(canvas, tech, Offset(nx + dx + 9, ny - 8),
                TextStyle(fontSize: 9, color: pageNum));
          }
        }
      }
    }
    canvas.restore();
    // 图例（低置信度底色示意）：画布右上角，避开第 1 小节号；
    // 右缘与弦线右端（size.width - leftPad）对齐。内容锚定（y≈6），
    // 滚出视口即不可见，与裁剪前行为一致。
    canvas.drawRect(
        Rect.fromLTWH(size.width - 70, 6, 10, 10), Paint()..color = confBg);
    _text(canvas, '低置信度', Offset(size.width - 36, 11),
        TextStyle(fontSize: 10, color: pageNum));
  }

  /// TextPainter 全局缓存（播放滚动卡顿修复 ②）：品数字仅 0-24、技法字母
  /// 数个、小节号 ≤ 小节数，键含字号/字重/色值/数字特性位数，条目有界
  /// （浅暗两套色板各一份）不清理。小节号与图例同为 10 号 muted 色，
  /// 靠 fontFeatures 位数区分键。
  static final Map<String, TextPainter> _textCache = {};

  static TextPainter _cachedText(String s, TextStyle style) {
    final key = '$s|${style.fontSize}|${style.fontWeight}|'
        '${style.color?.toARGB32()}|${style.fontFeatures?.length ?? 0}';
    return _textCache.putIfAbsent(
        key,
        () => TextPainter(
              text: TextSpan(text: s, style: style),
              textDirection: TextDirection.ltr,
            )..layout());
  }

  void _text(Canvas canvas, String s, Offset at, TextStyle style) {
    final tp = _cachedText(s, style);
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ScorePainter old) =>
      // 明暗切换重绘：palette 为 const 单例、7 色同源，代理比较 stringLine 足够。
      // 播放 tick 重建 painter（ir 同实例）返回 false，不触发谱面重绘。
      old.stringLine != stringLine || !identical(old.ir, ir);
}

/// 播放头层（全曲拍 → 小节/行内位置画一条竖线）：独立 CustomPaint +
/// RepaintBoundary，50ms tick 只重录本层，谱面层不随之重绘。
class _PlayheadPainter extends CustomPainter {
  _PlayheadPainter({
    required this.layout,
    required this.playheadBeat,
    required this.playhead,
  });

  final TabLayout layout;
  final double? playheadBeat;
  final Color playhead;

  @override
  void paint(Canvas canvas, Size size) {
    if (playheadBeat == null) return;
    final rows = layout.rowsFor(size.width);
    final beatPerBar = layout.beatsPerBar;
    final measure = (playheadBeat! / beatPerBar).floor();
    final inMeasure = playheadBeat! - measure * beatPerBar;
    var row = 0, col = 0, found = false;
    for (var r = 0; r < rows.length && !found; r++) {
      final c = rows[r].indexOf(measure);
      if (c >= 0) {
        row = r;
        col = c;
        found = true;
      }
    }
    if (!found) return;
    final x = TabLayout.leftPad +
        col * (layout.measureWidth + TabLayout.measureGap) +
        inMeasure * TabLayout.pxPerBeat;
    final y0 = layout.stringY(1, row) - 10;
    final y1 = layout.stringY(6, row) + 10;
    canvas.drawLine(Offset(x, y0), Offset(x, y1),
        Paint()..color = playhead..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _PlayheadPainter old) =>
      old.playheadBeat != playheadBeat || old.playhead != playhead;
}
