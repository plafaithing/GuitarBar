import 'package:flutter/material.dart';

import '../../core/score/score_ir.dart';

/// 六线谱布局几何（纯函数，可测）：自动换行、小节/音符定位。
/// 1 弦在最上（六线谱惯例），弦号 1→6 自上而下。
class TabLayout {
  TabLayout(this.ir);
  final ScoreIr ir;

  // 弦距（2026-11-01 走查：18→22，弧线上拱后 H/P 字母在弧内侧需要
  // 上方净空，GP8 视觉间距也更宽）。
  static const stringGap = 22.0;
  static const topPad = 28.0;
  static const bottomPad = 20.0;
  static const leftPad = 16.0;
  // 拍距（2026-11-01 走查二轮：52→64——Like A Star m71 "12×6" 同弦
  // 16 分连排两位数字 16px 叠死，64 下 16 分距 14.75px + 修正步长 15
  // 可排开；每行仍 3 小节：(800-32)/256=3）。
  static const pxPerBeat = 64.0;
  // 小节内音符净空：拍位 0 的音符中心离小节左竖线 ≥10px（两位品数字
  // 半宽 8px 不压线）；尾拍同理不越右竖线。
  static const notePad = 10.0;
  // 小节合并（2026-10-31 走查：对齐 Guitar Pro 连续谱面——小节间无缝、
  // 共用小节线，不再逐块间隙+底色）。
  static const measureGap = 0.0;
  // 32 = 26 + 6：行底标注区（L.R./P.M. 虚线，GP8 画在谱底下方）让位，
  // 避开下一行小节号（下一行 rowTop - 16）。
  static const rowGap = 32.0;

  int get beatsPerBar => int.tryParse(ir.timeSignature.split('/')[0]) ?? 4;
  double get measureWidth => beatsPerBar * pxPerBeat;
  double get rowHeight => topPad + 5 * stringGap + bottomPad;

  /// 小节内有效拍距：两侧各留 [notePad] 净空后均分。
  double get _effectiveBeatPx =>
      (measureWidth - notePad * 2) / beatsPerBar;

  /// 自动换行：每行小节 index 列表。
  List<List<int>> rowsFor(double maxWidth) {
    final perRow = (((maxWidth - leftPad * 2 + measureGap) /
                (measureWidth + measureGap))
            .floor())
        .clamp(1, 1 << 31);
    final total = ir.tracks.isEmpty ? 0 : ir.tracks.first.measures.length;
    final rows = <List<int>>[];
    for (var i = 0; i < total; i += perRow) {
      rows.add([
        for (var k = i; k < (i + perRow).clamp(0, total); k++) k
      ]);
    }
    return rows;
  }

  Size sizeFor(double maxWidth) {
    final rows = rowsFor(maxWidth);
    final h = rows.isEmpty
        ? rowHeight
        : rows.length * rowHeight + (rows.length - 1) * rowGap;
    return Size(maxWidth, h);
  }

  /// 小节所在行与小节列。
  (int row, int col) locate(int measureIndex, double maxWidth) {
    final rows = rowsFor(maxWidth);
    for (var r = 0; r < rows.length; r++) {
      final c = rows[r].indexOf(measureIndex);
      if (c >= 0) return (r, c);
    }
    return (0, 0);
  }

  double measureX(int measureIndex, double maxWidth) {
    final (_, c) = locate(measureIndex, maxWidth);
    return leftPad + c * (measureWidth + measureGap);
  }

  double noteX(int measureIndex, double beat, double maxWidth) =>
      measureX(measureIndex, maxWidth) +
      notePad +
      beat * _effectiveBeatPx;

  double stringY(int string, int row) =>
      row * (rowHeight + rowGap) + topPad + (string - 1) * stringGap;
}
