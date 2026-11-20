import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/score/score_ir.dart';
import '../theme.dart' show kUiFontFamily, kUiFontFallback;

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

  /// 小节内容拍数（2026-11-18 用户反馈"按比例平铺"）：尾休止小节的
  /// 音按比例**铺满小节**——contentBeats = 音的最大 (beat+duration)，
  /// 上限 beatsPerBar（满小节/超满小节不变）。noteX、rowOverfull 链
  /// 模拟共用（规则 22 口径一致），小节框宽仍按 beatsOfBar（小节线
  /// 对齐不变），仅内部音位按比例展开。
  double contentBeatsOf(int measureIndex) {
    final beats = beatsOfBar(measureIndex).toDouble();
    if (measureIndex < 0 ||
        measureIndex >= ir.tracks.first.measures.length) {
      return beats;
    }
    var last = 0.0;
    for (final n in ir.tracks.first.measures[measureIndex].notes) {
      final end = n.beat + n.duration;
      if (end > last) last = end;
    }
    return last <= 0 || last >= beats ? beats : last;
  }

  double get measureWidth => beatsPerBar * pxPerBeat;
  double measureWidthOf(int measureIndex) =>
      beatsOfBar(measureIndex) * pxPerBeat;
  double get rowHeight => topPad + 5 * stringGap + bottomPad;

  /// 线性轴小节四分拍数（2026-11-19 Prologue"指针到了不响"根治）：
  /// **只服务播放头线性轴**（linearStarts/measureAtBeat）——拍号 N/D 按
  /// N×4/D 计（6/8 = 3 四分拍，score_ir.measureQuarterBeats 唯一事实
  /// 源），与音符 beat/duration 同口径。**视觉盒宽仍用 beatsOfBar**
  /// （分子口径 + contentBeats 按比例平铺，渲染零变化）。
  double get linearBeatsPerBar => measureQuarterBeats(ir.timeSignature);

  double linearBeatsOfBar(int measureIndex) {
    if (measureIndex < 0 ||
        measureIndex >= ir.tracks.first.measures.length) {
      return linearBeatsPerBar;
    }
    final sig = ir.tracks.first.measures[measureIndex].timeSignature;
    return measureQuarterBeats(sig, fallback: linearBeatsPerBar);
  }

  /// 线性小节起始拍表（2026-11-19 变拍号播放头修复）：每小节按**实际
  /// 拍数**累计（sample_player.linearBeatAt 输出口径一致——规则 22
  /// 同源原则）。变拍号谱（LAS/哆啦A梦/Prologue pickup 1/4）此前
  /// painter/_follow 反算用全局 4 除 → 播放头错小节、跟页错行、
  /// 指针与声音错位（用户三报实证）。2026-11-19 二轮：改四分拍口径
  /// （X/8 按分子累计时 6/8 小节线性跨度 2x，指针爬出小节盒）。
  late final List<double> linearStarts = _computeLinearStarts();

  List<double> _computeLinearStarts() {
    final out = <double>[];
    var acc = 0.0;
    for (var i = 0; i < measures.length; i++) {
      out.add(acc);
      acc += linearBeatsOfBar(i);
    }
    return out;
  }

  /// 线性拍位 → 小节 index（反查：beat ∈ [linearStarts[m],
  /// linearStarts[m]+linearBeatsOfBar(m))；曲末 clamp 最后一节）。
  int measureAtBeat(double beat) {
    if (measures.isEmpty) return 0;
    if (beat < 0) return 0;
    for (var m = 0; m < measures.length; m++) {
      if (beat < linearStarts[m] + linearBeatsOfBar(m)) return m;
    }
    return measures.length - 1;
  }

  /// 音符 label 文本（**tab_view 数字分支的唯一事实源**——paint 与
  /// inkHalf 共用，新增展示形态只改这里，杜绝两处口径漂移）。
  /// 口径（gp8 判定 B 复刻，spec §2.2 + 2026-11-16 Prologue 实证）：
  /// x / ghost "(N)" / tie 延续音（**gp8 逐弧实证 2026-11-19，121 例零
  /// 反例**：跨小节续接〔小节首拍 tieE〕→ "(N)"（隔 5 拍也显示）；
  /// 小节内 tieE → **完全隐藏**（无数字无弧）；唯一例外 = tieE 所在拍
  /// 含装饰音 → 裸数字（tieAnchor 解析层回写——m4 3弦0/m17 2弦3）。
  /// 锚点音〔hopo/滑音/颤音/trill/bend〕保持裸数字）/ 泛音 `<N>` /
  /// 普通数字。
  static String tabLabel(NoteIr n) {
    if (n.technique == 'x') return 'x';
    if (n.ghost) return '(${n.fret})';
    if (n.tieEnd && !n.hopoEnd) {
      final anchored = n.tieAnchor ||
          n.hopoStart ||
          n.slide != null ||
          n.vibrato ||
          n.trill ||
          n.bend != null;
      if (anchored) return '${n.fret}';
      if (n.beat <= 1e-9) return '(${n.fret})';
      return '';
    }
    if (n.technique == 'H') return '<${n.fret}>';
    return '${n.fret}';
  }

  static final Map<String, double> _inkWidthCache = <String, double>{};

  /// 真实墨宽：与 paint 同款样式实测（fontSize/w600/tabularFigures +
  /// 主题字体 family——tab_view._text 同款注入，两处口径漂移即重叠）。
  static double _measureInk(String s, double fontSize, bool grace) {
    return _inkWidthCache.putIfAbsent('$s|$fontSize|$grace', () {
      final tp = TextPainter(
        text: TextSpan(
            text: s,
            style: TextStyle(
                fontSize: fontSize,
                fontStyle: grace ? FontStyle.italic : FontStyle.normal,
                fontWeight: grace ? FontWeight.w500 : FontWeight.w600,
                fontFamily: kUiFontFamily,
                fontFamilyFallback: kUiFontFallback,
                fontFeatures: [FontFeature.tabularFigures()])),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp.width;
    });
  }

  /// 音符 label 墨半宽：**按真实 TextPainter 墨宽**（2026-11-16 重叠
  /// 探针实证：旧常数一位数 4 vs 真实 7，系统性少 3px → 拥挤阈失效
  /// 数字重叠 3134 处）。隐藏 label（tie 中段延续音）= 0 墨宽。
  static double inkHalf(NoteIr n) {
    final s = tabLabel(n);
    if (s.isEmpty) return 0;
    return _measureInk(s, n.grace ? 10 : 14, n.grace) / 2;
  }

  /// 非音符文本的实测墨宽（capo 标签等；普通 w600 样式，与 paint 的
  /// 粗体字重一致，斜体略窄偏保守）。2026-11-16 capo×小节号残类新增。
  static double textInkWidth(String s, double fontSize) =>
      _measureInk(s, fontSize, false);

  List<MeasureIr> get measures =>
      ir.tracks.isEmpty ? const <MeasureIr>[] : ir.tracks.first.measures;

  // 布局结果缓存（rowsFor 在 paint/hit/follow 各处重复调用）。
  // （2026-11-12 折行 = 五档密度 ∩ 链模拟宽度校验 ∩ 2~5 铁律；
  //  旧 needWidth/"每行最多 4 小节"机制均已演进，见 _layoutFor 注释。）
  final Map<double, _RowLayout> _layoutCache = {};

  /// 行首贴线保护的右移量（相对 mx；复刻 tab_view 行首保护算式：
  /// 最小拍组的 minInk < mx+5 → 整组右移至墨左缘距线 5px）。
  double headShiftRel(MeasureIr m, double bpm) {
    double minBeat = double.infinity;
    for (final n in m.notes) {
      if (n.beat < minBeat) minBeat = n.beat;
    }
    var minInk = double.infinity;
    for (final n in m.notes) {
      if (n.beat == minBeat) {
        minInk = math.min(minInk, notePad + n.beat * bpm - inkHalf(n));
      }
    }
    return math.max(0.0, 5.0 - minInk);
  }

  /// 谱面级 grace 门（2026-11-17 时间.gp3 实证）：转换器产物把大量
  /// 音标成 grace（占比 31%、每小节 8 个全标）——gp8 对这类按 slash
  /// 正常音排布，**挂靠/链跳过模型不适用**；真装饰音谱（哆啦A梦式
  /// 零星 grace）占比极低。>25% → 全谱 grace 当普通音排布。布局与
  /// 渲染共用此判据（口径漂移即失效——规则 22）。
  late final bool graceAsNormal = _computeGraceAsNormal();

  bool _computeGraceAsNormal() {
    var total = 0;
    var grace = 0;
    for (final m in measures) {
      for (final n in m.notes) {
        total++;
        if (n.grace) grace++;
      }
    }
    return total > 0 && grace / total > 0.25;
  }

  /// 行级链模拟（2026-11-16 全量探针实证升级）：完全复刻实际排布趟
  /// ——dup 错开（步长 max(18, 1+前墨半+本墨半)）→ 跨小节贯穿拥挤链
  /// （绝对坐标，组粒度右推 + 小节右界挡保位）→ 行首贴线偏移。
  /// 任一成员小节的链尾绝对 x 超出自身右界内 12px → 该行放不下。
  /// 旧 per-measure chainMaxX 判据漏跨小节入链与 dup 占位，边界 case
  /// 判 TRUE 实际叠（狩猎曲泛音三连 dx 8 实锤）。
  bool rowOverfull(List<int> members, double width) {
    final lastX = <int, double>{};
    final lastN = <int, NoteIr>{};
    for (var c = 0; c < members.length; c++) {
      final mi = members[c];
      final m = measures[mi];
      final mx = leftPad + c * width;
      final bpm = (width - notePad * 2) / contentBeatsOf(mi);
      final head = c == 0 ? headShiftRel(m, bpm) : 0.0;
      // dup 错开模拟（flow 构建同款，per-measure）
      final dupSeen = <String, int>{};
      final dupLastX = <String, double>{};
      final dupLastNote = <String, NoteIr>{};
      final posOf = <NoteIr, double>{};
      for (final n in m.notes) {
        final key = '${n.string}@${n.beat.toStringAsFixed(3)}';
        final nx = mx + notePad + head + n.beat * bpm;
        final idx = dupSeen.putIfAbsent(key, () => 0);
        dupSeen[key] = idx + 1;
        double x;
        if (idx == 0) {
          x = nx;
        } else {
          final prevX = dupLastX[key] ?? nx;
          final prevN = dupLastNote[key] ?? n;
          x = prevX +
              math.max(18.0, 1.0 + inkHalf(prevN) + inkHalf(n));
        }
        dupLastX[key] = x;
        dupLastNote[key] = n;
        posOf[n] = x;
      }
      // 拥挤链模拟（crowd 趟同款：组粒度右推 + 右界挡保位；grace
      // 挂靠模型同款——grace 不进链、主音 gap 加大 1+2×grace 半宽）
      final byBeat = <double, List<NoteIr>>{};
      for (final n in m.notes) {
        byBeat.putIfAbsent(n.beat, () => []).add(n);
      }
      final beats = byBeat.keys.toList()..sort();
      final bound = mx + width - 12;
      var rowMaxAbs = 0.0;
      final graceAsNormal = this.graceAsNormal;
      final graceRunLen = <int, int>{};
      final graceRunSum = <int, double>{};
      // grace 串的 gap 加量（与 crowd 趟/挂靠趟同款推导）：
      // Δ = 1 + 2×Σ(串内 grace 墨半) + (k-1)。graceAsNormal 时不生效
      // （grace 当普通音参与链）。
      double graceDelta(int s) {
        final k = graceRunLen[s] ?? 0;
        if (k == 0) return 0;
        return 1.0 + 2.0 * (graceRunSum[s] ?? 0) + (k - 1);
      }

      for (final b in beats) {
        final g = byBeat[b]!;
        var delta = 0.0;
        // 挂靠起点钳制（2026-11-18 规则 22 口径对齐）：渲染层挂靠趟的
        // 主音让位 = 主音起点 ≥ mx+5+2×串墨+串长+主音半宽（grace 左缘
        // 距线 5 + 串宽 + 净空 1 + 主音半宽）。链模拟不加此口径 → 折行
        // 误判 5 小节窄行放得下（LAS m12 残类 8.3px 缺口实证）。
        for (final f in g) {
          if (f.grace && !graceAsNormal) continue;
          final k = graceRunLen[f.string] ?? 0;
          if (k > 0) {
            final minStart = mx +
                5 +
                2 * (graceRunSum[f.string] ?? 0) +
                k +
                inkHalf(f);
            if (posOf[f]! < minStart) posOf[f] = minStart;
          }
        }
        for (final f in g) {
          if (f.grace && !graceAsNormal) {
            continue; // grace 不进链（crowd 趟同款）
          }
          final prev = lastX[f.string];
          final prevN = lastN[f.string];
          if (prev == null || prevN == null) continue;
          var gap = 1.0 + inkHalf(prevN) + inkHalf(f);
          if (!graceAsNormal && (graceRunLen[f.string] ?? 0) > 0) {
            gap += graceDelta(f.string);
          }
          final need = prev + gap - posOf[f]!;
          if (need > delta) delta = need;
        }
        final gMax = g.map((f) => posOf[f]!).reduce(math.max);
        if (delta > 0 && gMax + delta > bound) {
          // 保位（crowd 同款）。保位后任一成员与前驱缺口 >2px 的对
          // 按探针口径（dx < 墨半和-1）必违例 → 该行不可满足，计入
          // 结构性豁免（2026-11-16 全量探针实证：保位链尾不越界但
          // 组间互叠——旧判据只查越界漏掉此形态，违例爆回 4.7 万）。
          for (final f in g) {
            if (f.grace && !graceAsNormal) continue;
            final prev = lastX[f.string];
            final prevN = lastN[f.string];
            if (prev == null || prevN == null) continue;
            var gap = 1.0 + inkHalf(prevN) + inkHalf(f);
            if (!graceAsNormal && (graceRunLen[f.string] ?? 0) > 0) {
              gap += graceDelta(f.string);
            }
            final need = prev + gap - posOf[f]!;
            if (need > 2.0) return true;
          }
          delta = 0;
        }
        for (final f in g) {
          if (delta > 0) posOf[f] = posOf[f]! + delta;
        }
        for (final f in g) {
          if (f.grace && !graceAsNormal) {
            // grace 自然位贴身检查（2026-11-17 八轮探针残类 21 处：
            // 跨小节禁挂后 grace 保持自然位，窄行下与左邻链位贴身
            // ——链推右只会更贴，结构性不可满足 → 计入豁免）。
            final prev = lastX[f.string];
            final prevN = lastN[f.string];
            if (prev != null && prevN != null) {
              final gap = 1.0 + inkHalf(prevN) + inkHalf(f);
              final dist = (posOf[f]! - prev).abs();
              if (dist < gap) return true;
            }
            continue;
          }
          if (posOf[f]! > (lastX[f.string] ?? -1)) {
            lastX[f.string] = posOf[f]!;
            lastN[f.string] = f;
          }
          if (posOf[f]! > rowMaxAbs) rowMaxAbs = posOf[f]!;
        }
        for (final f in g) {
          if (f.grace && !graceAsNormal) {
            graceRunLen[f.string] = (graceRunLen[f.string] ?? 0) + 1;
            graceRunSum[f.string] =
                (graceRunSum[f.string] ?? 0) + inkHalf(f);
          } else {
            graceRunLen[f.string] = 0;
            graceRunSum[f.string] = 0;
          }
        }
      }
      if (rowMaxAbs > bound) return true;
    }
    return false;
  }

  /// 是否存在"折行被迫压缩"的超宽行——**全量探针的结构性豁免判据**
  /// （2026-11-16）：2~5 铁律强迫超宽行进多小节行（cur=1 时不
  /// flush），连排密度 × 墨阈数学上放不下 → 数字接触不可排布避免
  /// （gp8 靠窄音乐字体才放得下）。该类谱×宽组合豁免判罚但仍计数。
  bool hasOverfullMeasure(double maxWidth) {
    final l = _layoutFor(maxWidth);
    for (var r = 0; r < l.rows.length; r++) {
      if (rowOverfull(l.rows[r], l.widths[r])) return true;
      // 含 grace 的行（挂靠模式）：grace 终位由渲染层挂靠趟决定，
      // 布局层不可精确预测（2026-11-17 九轮残类 14 处实证：挂靠位
      // 贴身 vs 模拟自然位不贴的口径差）→ 保守豁免。
      if (!graceAsNormal) {
        for (final mi in l.rows[r]) {
          if (measures[mi].notes.any((n) => n.grace)) return true;
        }
      }
    }
    return false;
  }

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

      bool rowFits(List<int> members, double width) {
        return !rowOverfull(members, width);
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
        // ≥2 且超密度档/超宽才换行。
        // **2026-11-18 用户指令升级（不遮挡优先）**：cur=1 且 2 小节
        // 行放不下（rowOverfull）→ **允许 1 小节行**（行宽翻倍换零遮
        // 挡——LAS 类 32 分密集谱的结构性挤压根除；"至少保证每个音
        // 每个符号正常显示不遮挡"优先于每行下限）。
        final wouldBreak = cur.isNotEmpty &&
            !rowFits([...cur, i], avail / (cur.length + 1));
        if (cur.length + 1 > maxBars ||
            (wouldBreak &&
                (cur.length >= 2 ||
                    rowOverfull([...cur, i], avail / (cur.length + 1))))) {
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
    // 1 拍均分，不再按 4/4 压到左半）。**分母 = contentBeats**
    // （2026-11-18 用户反馈"按比例平铺"：尾休止小节的音按比例铺满
    // 小节——满小节 contentBeats = beatsPerBar 不变）。
    final beatPx = (rowW - notePad * 2) / contentBeatsOf(measureIndex);
    // 播放头休止段钳制（2026-11-19 dsh 终审 P1-1）：inMeasure 轴走满
    // 小节线性跨度，而平铺布局把内容压到前段——尾休止段指针会爬出
    // 小节盒侵入下一小节再 snap 回（4/4 尾休止自 11-18 平铺起即带）。
    // 钳到 contentBeats：音符 beat ≤ contentBeats 恒成立（音符布局
    // 零变化），指针休止段停在末音位不越界。
    final clamped = math.min(beat, contentBeatsOf(measureIndex));
    return measureX(measureIndex, maxWidth) + notePad + clamped * beatPx;
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
