import 'package:flutter/material.dart';

import '../../core/score/score_ir.dart';

/// 六线谱布局几何：自适应换行、小节/音符定位。
/// 1 弦在最上（六线谱惯例），弦号 1→6 自上而下。
///
/// 行密度自适应（2026-11-01 走查三轮）：检测小节内最密连排（相邻音符
/// 最小拍距），密集小节所在行自动降为 2 小节/行——行内小节等宽（行宽
/// 均分），拍距随行宽拉大，连排间隔自动拉开。普通小节维持 3 小节/行。
class TabLayout {
  TabLayout(this.ir);
  final ScoreIr ir;

  // 弦距（2026-11-01 走查 18→22 弧线字母净空；2026-11-02 走查回调
  // 22→20——用户反馈太宽；20 下弧顶/字母/上弦数字恰好互不侵入）。
  static const stringGap = 20.0;
  // 40 = 28 + 12：谱上方三层布局（跳房子括号 / 小节号 / L.R.·P.M. 虚线）
  // 各层净空——L.R. 虚线抬高后不遮挡 1 弦品数字（2026-11-02 走查）。
  static const topPad = 40.0;
  static const bottomPad = 20.0;
  static const leftPad = 16.0;
  // 标准拍距（2026-11-01 走查二轮：52→64——Like A Star m71 "12×6" 同弦
  // 16 分连排两位数字 16px 叠死）。密集行由自适应再放大。
  static const pxPerBeat = 64.0;
  // 小节内音符净空：拍位 0 的音符中心离小节左竖线 ≥10px（两位品数字
  // 半宽 8px 不压线）；尾拍同理不越右竖线。
  static const notePad = 10.0;
  // 小节合并（2026-10-31 走查：对齐 Guitar Pro 连续谱面——小节间无缝、
  // 共用小节线，不再逐块间隙+底色）。
  static const measureGap = 0.0;
  static const rowGap = 32.0;

  // 相邻音符需要的最小水平间距：两位品数字 16px + 余量。密集检测以
  // "把这对音撑到 18px" 反推每拍所需像素。
  static const _minNoteGapPx = 18.0;

  // 连排降密度阈值（2026-11-01 走查用户定参二修）：同弦连排 ≥6（如
  // Like A Star m71 "12×6"）所在行降为 2 小节/行拉长拍距；<6 的短连排
  // 由拥挤修正趟排开（步长 16px 恰好两位数字），不降行密度。
  static const _runThreshold = 6;

  int get beatsPerBar => int.tryParse(ir.timeSignature.split('/')[0]) ?? 4;
  double get measureWidth => beatsPerBar * pxPerBeat;
  double get rowHeight => topPad + 5 * stringGap + bottomPad;

  /// 小节需要的宽度：**同弦连排链**检测（用户定参：链长 ≥8 才算密集）。
  /// 短连排（如 "12×6"）由修正趟 16px 步长排开不占额外宽度；长连排的
  /// 累积撑宽需求反推每拍像素。32 分极密封顶 2.8×标准宽。
  double _needWidth(MeasureIr m) {
    final byString = <int, List<double>>{};
    for (final n in m.notes) {
      byString.putIfAbsent(n.string, () => []).add(n.beat);
    }
    var maxRun = 0;
    var maxRunSpan = 0.0; // 最长链首尾拍距
    for (final beats in byString.values) {
      beats.sort();
      var run = 1;
      var runStart = beats.first;
      void close(double lastBeat) {
        if (run > maxRun) {
          maxRun = run;
          maxRunSpan = lastBeat - runStart;
        }
      }

      for (var i = 1; i < beats.length; i++) {
        // 16 分以内（含）算连排延续；32 分谱同式覆盖。
        if (beats[i] - beats[i - 1] <= 0.25 + 1e-9) {
          run++;
        } else {
          close(beats[i - 1]);
          run = 1;
          runStart = beats[i];
        }
      }
      close(beats.last);
    }
    if (maxRun < _runThreshold) return measureWidth;
    final span = maxRunSpan < 0.25 ? 0.25 : maxRunSpan;
    final needBeatPx = ((maxRun - 1) * _minNoteGapPx + 16.0) / span;
    final w = beatsPerBar * needBeatPx + notePad * 2;
    return w.clamp(measureWidth, measureWidth * 2.8);
  }

  // 布局结果缓存（rowsFor 在 paint/hit/follow 各处重复调用）。
  final Map<double, _RowLayout> _layoutCache = {};

  /// 行布局：每行小节 index 列表 + 该行小节宽（行宽均分，密集行更宽）。
  _RowLayout _layoutFor(double maxWidth) {
    return _layoutCache.putIfAbsent(maxWidth, () {
      final measures =
          ir.tracks.isEmpty ? const <MeasureIr>[] : ir.tracks.first.measures;
      final avail = maxWidth - leftPad * 2;
      final rows = <List<int>>[];
      final widths = <double>[];
      var cur = <int>[];
      var curNeed = 0.0;
      void flush() {
        if (cur.isEmpty) return;
        rows.add(cur);
        widths.add(avail / cur.length);
        cur = <int>[];
        curNeed = 0.0;
      }

      for (var i = 0; i < measures.length; i++) {
        final need = _needWidth(measures[i]);
        final n = cur.length + 1;
        // 等宽约束：行内全部小节的 needed 宽 ≤ 行均分宽才可同行。
        final maxNeed = curNeed > need ? curNeed : need;
        if (avail / n >= maxNeed) {
          cur.add(i);
          curNeed = maxNeed;
        } else {
          flush();
          cur.add(i);
          curNeed = need;
        }
      }
      flush();
      return _RowLayout(rows, widths);
    });
  }

  /// 自动换行：每行小节 index 列表。
  List<List<int>> rowsFor(double maxWidth) => _layoutFor(maxWidth).rows;

  /// [measureIndex] 所在行的小节宽（行级可变，密集行更宽）。
  double measureWidthAt(int measureIndex, double maxWidth) {
    final l = _layoutFor(maxWidth);
    for (var r = 0; r < l.rows.length; r++) {
      if (l.rows[r].contains(measureIndex)) return l.widths[r];
    }
    return measureWidth;
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
    // 行内等宽（measureGap=0 连续谱面）：用所在行的小节宽，非全局标准宽。
    return leftPad + c * measureWidthAt(measureIndex, maxWidth);
  }

  double noteX(int measureIndex, double beat, double maxWidth) {
    final rowW = measureWidthAt(measureIndex, maxWidth);
    // 拍距：小节两侧各留 notePad 净空后均分（行宽大则拍距自动拉长）。
    final beatPx = (rowW - notePad * 2) / beatsPerBar;
    return measureX(measureIndex, maxWidth) + notePad + beat * beatPx;
  }

  double stringY(int string, int row) =>
      row * (rowHeight + rowGap) + topPad + (string - 1) * stringGap;
}

/// rowsFor 的布局结果（行 → 小节列表 + 行内小节宽）。
class _RowLayout {
  _RowLayout(this.rows, this.widths);
  final List<List<int>> rows;
  final List<double> widths;
}
