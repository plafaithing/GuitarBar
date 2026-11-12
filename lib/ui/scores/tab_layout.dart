import 'dart:math' as math;

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

  int get beatsPerBar => int.tryParse(ir.timeSignature.split('/')[0]) ?? 4;

  /// 小节级拍数（2026-11-10 Flower 1/4 pickup 修复）：MeasureIr 带
  /// timeSignature 用之，否则继承全曲。小节宽按各自拍数（1/4 前奏小节
  /// = 1/4 标准宽，音位不再错位）。
  int beatsOfBar(int measureIndex) {
    if (measureIndex < 0 ||
        measureIndex >= ir.tracks.first.measures.length) {
      return beatsPerBar;
    }
    final sig = ir.tracks.first.measures[measureIndex].timeSignature;
    if (sig == null) return beatsPerBar;
    return int.tryParse(sig.split('/')[0]) ?? beatsPerBar;
  }

  double get measureWidth => beatsPerBar * pxPerBeat;
  double measureWidthOf(int measureIndex) =>
      beatsOfBar(measureIndex) * pxPerBeat;
  double get rowHeight => topPad + 5 * stringGap + bottomPad;

  /// 音符 label 墨半宽（拥挤阈/需求宽共用）：一位数 ~8px、两位数 ~16px、
  /// 幽灵括号 ~21px、泛音尖括号 ~20px。
  static double inkHalf(NoteIr n) {
    if (n.ghost) return 12;
    if (n.technique == 'H') return 11;
    if (n.fret >= 10) return 8;
    return 4;
  }

  List<MeasureIr> get measures =>
      ir.tracks.isEmpty ? const <MeasureIr>[] : ir.tracks.first.measures;

  // 布局结果缓存（rowsFor 在 paint/hit/follow 各处重复调用）。
  // （2026-11-12 折行 = 五档密度 ∩ 链模拟宽度校验 ∩ 2~5 铁律；
  //  旧 needWidth/"每行最多 4 小节"机制均已演进，见 _layoutFor 注释。）
  final Map<double, _RowLayout> _layoutCache = {};

  /// 行布局：每行小节 index 列表 + 该行小节宽（行宽均分，密集行更宽）。
  ///
  /// 折行规则（2026-11-12 用户铁律定案）：**除最后一行外每行 2~5 小节**。
  /// 密度档（行内最大单小节音列数）>32→≤2、>20→≤3、>14→≤4、否则≤5；
  /// 叠加链模拟宽度校验（下方 rowFits）；cur 已有 1 小节时不得 flush
  /// （哪怕超宽——压缩接受，单行独占根除）。
  _RowLayout _layoutFor(double maxWidth) {
    return _layoutCache.putIfAbsent(maxWidth, () {
      final measures =
          ir.tracks.isEmpty ? const <MeasureIr>[] : ir.tracks.first.measures;
      final avail = maxWidth - leftPad * 2;

      // 链模拟（2026-11-12 六修·精确判据）：完全复刻拥挤趟——组链位
      // = max(组内自然位, 同弦链前 + 墨阈和)；返回链条最大 x（相对小
      // 节左缘）。判据：链尾 ≤ 右界内 12px。Σ亏空求和判据过严——亏空
      // 会被后续大间隙吸收不累积（LAS m77 一对 0.125 拍距被误判成
      // 整小节 1/行）。
      double chainMaxX(MeasureIr m, double beatPx) {
        if (m.notes.isEmpty) return 0;
        final byBeat = <double, List<NoteIr>>{};
        for (final n in m.notes) {
          byBeat.putIfAbsent(n.beat, () => []).add(n);
        }
        final beats = byBeat.keys.toList()..sort();
        final lastChainX = <int, double>{};
        final lastChainN = <int, NoteIr>{};
        var maxX = 0.0;
        for (final b in beats) {
          var gx = 0.0;
          for (final n in byBeat[b]!) {
            final prev = lastChainX[n.string];
            final natural = notePad + n.beat * beatPx;
            final want = prev == null
                ? natural
                : math.max(natural,
                    prev + 1.0 + inkHalf(lastChainN[n.string]!) + inkHalf(n));
            if (want > gx) gx = want;
          }
          for (final n in byBeat[b]!) {
            lastChainX[n.string] = gx; // 组整组落位
            lastChainN[n.string] = n;
          }
          if (gx > maxX) maxX = gx;
        }
        return maxX;
      }

      bool rowFits(List<int> members, double width) {
        for (final mi in members) {
          final bpm = (width - notePad * 2) / beatsOfBar(mi);
          if (chainMaxX(measures[mi], bpm) > width - 12) return false;
        }
        return true;
      }

      final rows = <List<int>>[];
      final widths = <double>[];
      var cur = <int>[];

      var maxBarInCur = 0; // 行内最大单小节音列数
      void flush() {
        if (cur.isEmpty) return;
        rows.add(cur);
        widths.add(avail / cur.length);
        cur = <int>[];
        maxBarInCur = 0;
      }

      for (var i = 0; i < measures.length; i++) {
        final noteCount = measures[i].notes.length;
        // 密度档上限（2026-11-10 五档；2026-11-12 用户铁律封顶 5）：
        // 行内最大单小节音列数 >32 → ≤2；>20 → ≤3；>14 → ≤4；否则 ≤5。
        final maxAfter = math.max(maxBarInCur, noteCount);
        var maxBars = maxAfter > 32
            ? 2
            : maxAfter > 20
                ? 3
                : maxAfter > 14
                    ? 4
                    : 5;
        // **每行 2~5 小节铁律**（2026-11-12 用户定案，末行豁免）：
        // cur 已有 1 小节时不得 flush（哪怕新小节超宽——压缩接受）；
        // ≥2 且超密度档/超宽才换行。单行独占（旧 m100/m1 现象）根除。
        final wouldBreak = cur.isNotEmpty &&
            !rowFits([...cur, i], avail / (cur.length + 1));
        if (cur.length + 1 > maxBars || (wouldBreak && cur.length >= 2)) {
          flush();
        }
        cur.add(i);
        maxBarInCur = math.max(maxBarInCur, noteCount);
      }
      flush();
      return _RowLayout(rows, widths);
    });
  }

  /// 自动换行：每行小节 index 列表。
  List<List<int>> rowsFor(double maxWidth) => _layoutFor(maxWidth).rows;

  /// 谱面排版宽度上限（2026-11-09 gp8 对照：宽屏下行宽随容器铺满导致
  /// 每行小节数过多——上限 1300px，超出部分居中留白，gp8 同款密度）。
  static double effectiveWidth(double containerWidth) =>
      containerWidth > 1300 ? 1300 : containerWidth;

  /// 谱面水平居中偏移（容器宽 - 排版宽）/2；hitTest 反算时同样扣除。
  static double horizontalOffset(double containerWidth) =>
      (containerWidth - effectiveWidth(containerWidth)) / 2;

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
    // 拍数用**小节级**（2026-11-10 pickup 修复：1/4 小节内 2 音按
    // 1 拍均分，不再按 4/4 压到左半）。
    final beatPx = (rowW - notePad * 2) / beatsOfBar(measureIndex);
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
