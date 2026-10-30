import 'package:flutter/material.dart';

import '../../core/score/score_ir.dart';
import '../theme.dart';
import 'tab_layout.dart';

/// 六线谱视图：弦线/品数字/小节线 + 置信度标记 + failed 小节可见化 + 播放头。
/// 1 弦在最上。dataHue 上数据（低置信度底），播放头 positive。
class TabView extends StatelessWidget {
  const TabView({super.key, required this.ir, this.playheadBeat,
      this.onNoteTap, this.onFailedTap});
  final ScoreIr ir;

  /// 播放头位置（全曲拍位，Task 16 接线）；null = 不显示。
  final double? playheadBeat;
  final void Function(int measureIndex, int noteIndex, NoteIr note)? onNoteTap;
  final void Function(int measureIndex)? onFailedTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(builder: (ctx, box) {
      final layout = TabLayout(ir);
      final w = box.maxWidth;
      // GestureDetector 放滚动区内：hit test 链自动换算，localPosition 即内容
      // 坐标，滚动后命中不错位；tap 与垂直 drag 分属不同轴互不干扰。
      // behavior=opaque 冗余但更防御（RenderCustomPaint.hitTestSelf 对未重写
      // hitTest 的 painter 本就返回 true，deferToChild 已可命中；opaque 兜底
      // 覆盖 painter 未来重写 hitTest 的情况）。
      return SingleChildScrollView(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _hitTest(d.localPosition, w),
          child: SizedBox(
            width: w,
            height: layout.sizeFor(w).height,
            child: CustomPaint(
              painter: _TabPainter(
                  layout: layout,
                  ir: ir,
                  playheadBeat: playheadBeat,
                  stringLine: p.border,
                  fretText: p.ink,
                  barLine: p.border,
                  confBg: p.dataHue.withValues(alpha: 0.12),
                  failedText: p.negative,
                  playhead: p.positive,
                  pageNum: p.muted),
            ),
          ),
        ),
      );
    });
  }

  /// 点击命中：找最近的弦线（|dy| < stringGap/2），再找该弦上最近的音符
  /// （|dx| < pxPerBeat/2）。failed 小节整块可点。
  void _hitTest(Offset local, double maxWidth) {
    final layout = TabLayout(ir);
    final tracks = ir.tracks;
    if (tracks.isEmpty || (onNoteTap == null && onFailedTap == null)) return;
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
          onFailedTap?.call(m.index);
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
          onNoteTap?.call(m.index, i, n);
          return;
        }
      }
    }
  }
}

class _TabPainter extends CustomPainter {
  _TabPainter({
    required this.layout,
    required this.ir,
    required this.playheadBeat,
    required this.stringLine,
    required this.fretText,
    required this.barLine,
    required this.confBg,
    required this.failedText,
    required this.playhead,
    required this.pageNum,
  });

  final TabLayout layout;
  final ScoreIr ir;
  final double? playheadBeat;
  final Color stringLine, fretText, barLine, confBg, failedText, playhead, pageNum;

  @override
  void paint(Canvas canvas, Size size) {
    final rows = layout.rowsFor(size.width);
    final measures =
        ir.tracks.isEmpty ? const <MeasureIr>[] : ir.tracks.first.measures;

    for (var r = 0; r < rows.length; r++) {
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
        for (final n in m.notes) {
          _text(canvas, '${n.fret}',
              Offset(layout.noteX(m.index, n.beat, size.width),
                  layout.stringY(n.string, r)),
              TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: fretText,
                  fontFeatures: [FontFeature.tabularFigures()]));
        }
      }
    }
    // 播放头（全曲拍 → 小节/行内位置）。
    if (playheadBeat != null) {
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
      if (found) {
        final x = TabLayout.leftPad +
            col * (layout.measureWidth + TabLayout.measureGap) +
            inMeasure * TabLayout.pxPerBeat;
        final y0 = layout.stringY(1, row) - 10;
        final y1 = layout.stringY(6, row) + 10;
        canvas.drawLine(Offset(x, y0), Offset(x, y1),
            Paint()..color = playhead..strokeWidth = 2);
      }
    }
    // 图例（低置信度底色示意）：画布右上角，避开第 1 小节号；
    // 右缘与弦线右端（size.width - leftPad）对齐。
    canvas.drawRect(
        Rect.fromLTWH(size.width - 70, 6, 10, 10), Paint()..color = confBg);
    _text(canvas, '低置信度', Offset(size.width - 36, 11),
        TextStyle(fontSize: 10, color: pageNum));
  }

  void _text(Canvas canvas, String s, Offset at, TextStyle style) {
    final tp = TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _TabPainter old) =>
      old.playheadBeat != playheadBeat ||
      // 明暗切换重绘：palette 为 const 单例、7 色同源，代理比较 stringLine 足够。
      old.stringLine != stringLine ||
      !identical(old.ir, ir);
}
