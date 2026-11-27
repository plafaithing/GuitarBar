import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';

import '../../core/score/score_ir.dart';
import '../theme.dart' show kUiFontFamily, kUiFontFallback;
import 'row_flow.dart';

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
  /// 口径（制谱基准 判定 B 复刻，spec §2.2 + 2026-11-16 Prologue 实证）：
  /// x / ghost "(N)" / tie 延续音（**制谱基准 逐弧实证 2026-11-19，121 例零
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
  /// 音标成 grace（占比 31%、每小节 8 个全标）——制谱基准 对这类按 slash
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

  /// 每小节物理最小宽（2026-11-27 折行普适性修复，求解器起点）：线性
  /// 拍位下非豁免拍对须满足 [nearColNeed]（按标签墨宽），δ = 最小非
  /// 豁免拍差 → bpm 下限 need/δ → 宽 = need/δ × contentBeats + 2×notePad。
  /// 豁免口径见 [_beatPairExempt]；无任何非豁免拍对的小节取保守基础宽。
  late final List<double> _minWidths = _computeMinWidths();

  static const _minWidthBase = 72.0; // 无拍差需求小节的基础宽

  /// 近似同列余量（px）：任一音中心距另一音标签墨缘至少这么远。
  static const nearColMargin = 4.0;

  /// 近似同列的搜索半径（px）：前驱离本音超过它就不可能违例（最宽标签
  /// `(12)`/`<12>` 墨半 ~22 + 余量）——逐对比较的提前终止界。
  static const _nearReach = 64.0;

  /// 近似同列判据——**唯一口径**（最小宽 / 解析初筛 _preWhy / 渲染终位
  /// 校验 _flowCheck / 诊断度量共用）：非豁免对的中心距须 ≥ **两音标签
  /// 墨半宽的较大者 + 余量**，即任一音的中心不落入另一音的标签范围。
  ///
  /// 为什么按墨宽而非定值（2026-11-27 用户实测校准）：旧口径是定值
  /// 18px，校准样本只有 LSA 的 `<12>`（墨半 ~20——前音落在它的覆盖
  /// 范围里，看着叠成一列）。套到一位数标签上严得离谱：Bluebird
  /// m1–m3 的十六分对（3弦2品→1弦空弦，隔两根弦）中心距 16.9px 时
  /// 字边仍有 8px 空隙，却被判近似同列 → 每小节最小宽 308px、三小节
  /// 放不进一行（用户："m1,m2,m3 不在一行的原因…感觉 m4~m7 可以在一
  /// 行"；月下之恋 m8–m11 同理，四小节一行时十六分间距 12.4px 可接受）。
  /// 按墨宽后：一位数→一位数 ≥8.3px；`2`→`<12>` ≥24px（LSA 被指出
  /// 的形态比旧口径更严）；`<12>`→`<12>` ≥24px（LSA m1 级联 26px 保留）。
  static double nearColNeed(NoteIr a, NoteIr b) =>
      math.max(inkHalf(a), inkHalf(b)) + nearColMargin;

  /// 近似同列豁免判定——**唯一口径**（解析初筛 _preWhy / 渲染终位校验
  /// _flowCheck 共用）：亚拍错位（拍差 < 1/16，装饰对 `<12>^2` 等合法
  /// 贴身，制谱基准 同款）或前音为装饰性短音（dur ≤ 0.15）。grace 不在此判
  /// （调用方先滤除；graceAsNormal 模式 grace 当普通音参与）。
  static bool nearColExempt(NoteIr prev, NoteIr next) =>
      (next.beat - prev.beat).abs() < 0.25 - 1e-9 || prev.duration <= 0.15;

  /// 拍组级豁免（最小宽用，与 nearColExempt 同义）：前组全部有效音都是
  /// 装饰短音才算豁免——组内只要有一个非短音，它与后拍音的对就须
  /// 满足 nearColNeed（音级口径下该对非豁免）。
  static bool _beatPairExempt(List<NoteIr> prev, double dBeat, bool an) {
    if (dBeat < 0.25 - 1e-9) return true; // 亚拍错位豁免
    final eff = [for (final n in prev) if (an || !n.grace) n];
    if (eff.isEmpty) return true; // 全 grace 拍
    return eff.every((n) => n.duration <= 0.15);
  }

  /// 从 [i] 起向前越过与前组构成豁免对的中间拍组，返回第一个**非豁免**
  /// 对的前组下标（无则 -1）。被豁免的短音/亚拍组夹在两拍之间时，
  /// 两端的拍对仍须满足 nearColNeed——相邻对全豁免不能让相隔一对漏网
  /// （Flower-openD m13 三连 16 分连跑实证：A~X~B 相邻对全豁免，
  /// A–B 拍差 1/3 却只隔 12.8px）。
  static int _prevNonExempt(
      List<double> beats, Map<double, List<NoteIr>> byBeat, int i, bool an) {
    var j = i - 1;
    while (j >= 0 &&
        _beatPairExempt(byBeat[beats[j]]!, beats[i] - beats[j], an)) {
      j--;
    }
    return j;
  }

  List<double> _computeMinWidths() {
    final out = <double>[];
    final an = graceAsNormal;
    for (var mi = 0; mi < measures.length; mi++) {
      final m = measures[mi];
      final byBeat = <double, List<NoteIr>>{};
      for (final n in m.notes) {
        byBeat.putIfAbsent(n.beat, () => []).add(n);
      }
      final beats = byBeat.keys.toList()..sort();
      // 各拍组有效音的最大标签墨半宽。
      final halfOf = <double, double>{};
      for (final b in beats) {
        var h = 0.0;
        for (final n in byBeat[b]!) {
          if (an || !n.grace) h = math.max(h, inkHalf(n));
        }
        halfOf[b] = h;
      }
      var bpmNeed = 0.0; // ≥ need/δ 的最大需求
      for (var i = 1; i < beats.length; i++) {
        final j = _prevNonExempt(beats, byBeat, i, an);
        if (j < 0) continue;
        final need = math.max(halfOf[beats[j]]!, halfOf[beats[i]]!) +
            nearColMargin;
        bpmNeed = math.max(bpmNeed, need / math.max(beats[i] - beats[j], 0.01));
      }
      out.add(math.max(
          _minWidthBase, bpmNeed * contentBeatsOf(mi) + notePad * 2));
    }
    return out;
  }

  /// 行首贴线保护占宽（2026-11-27）：行首小节首音组渲染时整组右移至墨
  /// 左缘距左竖线 ≥5px（首音 x = mx+notePad = mx+10 → 位移 = 墨半 −
  /// 5），位移压缩首个拍间距——首小节最小宽须把它算进去（否则贴最小
  /// 宽时首拍间距 <18px：Time travel m18 / 哆啦A梦 m35 实证 19→10px）。
  late final List<double> _headExtras = _computeHeadExtras();

  List<double> _computeHeadExtras() {
    final out = <double>[];
    for (final m in measures) {
      double? minBeat;
      var half = 0.0;
      for (final n in m.notes) {
        if (minBeat == null || n.beat < minBeat) {
          minBeat = n.beat;
          half = 0;
        }
        if (n.beat == minBeat) half = math.max(half, inkHalf(n));
      }
      out.add(math.max(0.0, half - 5));
    }
    return out;
  }

  /// 行级链模拟（2026-11-16 全量探针实证升级）：完全复刻实际排布趟
  /// ——dup 错开（步长 max(18, 1+前墨半+本墨半)）→ 跨小节贯穿拥挤链
  /// （绝对坐标，组粒度右推 + 小节右界挡保位）→ 行首贴线偏移。
  /// 任一成员小节的链尾绝对 x 超出自身右界内 12px → 该行放不下。
  /// 旧 per-measure chainMaxX 判据漏跨小节入链与 dup 占位，边界 case
  /// 判 TRUE 实际叠（狩猎曲泛音三连 dx 8 实锤）。
  /// 行内小节宽分配（2026-11-25 制谱基准 式内容自适应；2026-11-27 最小宽
  /// 保底重构）：**先保每小节物理最小宽**，剩余空间再按拍列数加权。
  ///
  /// 最小宽保底的根因（2026-11-27 全库 157 谱探针实锤）：纯加权把
  /// 稀疏小节压到物理必需以下——月下之恋 m4（3 拍列）在四小节行只分
  /// 到 131px，自身 0.5 拍列距 14.5px < 18px → 近似同列**假违例**拒行
  /// →"明明可以合并"（用户 2026-11-26 报）。最小宽 = 18/δ × 拍跨度
  /// （δ = 最小非豁免拍差，near-col 同口径豁免：亚拍错位/装饰短音），
  /// 保底后 near-col 自动过，放不下的行是真实物理不足（正确折行）。
  List<double> rowWidths(List<int> members, double avail) {
    // 首小节最小宽含行首贴线保护占宽（_headExtras）。
    final mins = [
      for (var c = 0; c < members.length; c++)
        _minWidths[members[c]] + (c == 0 ? _headExtras[members[c]] : 0)
    ];
    return _allocate(members, avail, mins);
  }

  /// 行宽分配器（给定各小节最小宽）：最小宽保底 + 剩余按拍列数加权 +
  /// 宽比钳制（不削破最小宽）。求解器按违例反馈抬高 mins 反复调用。
  List<double> _allocate(
      List<int> members, double avail, List<double> mins) {
    final weights = <double>[];
    var sum = 0.0;
    for (final mi in members) {
      final beats = measures[mi].notes.map((n) => n.beat).toSet().length;
      final wgt = math.max(2.0, beats.toDouble()); // 基准 2：稀疏小节不挤没
      weights.add(wgt);
      sum += wgt;
    }
    if (sum <= 0) {
      return [for (var i = 0; i < members.length; i++) avail / members.length];
    }
    var minSum = 0.0;
    for (final v in mins) {
      minSum += v;
    }
    if (minSum >= avail) {
      // 物理不可满足（Σ最小宽 > 行宽）：按最小宽比例分（诚实反映
      // 缺口），rowOverfull 的 near-col/链校验照常拒行折行。
      return [for (final v in mins) avail * v / minSum];
    }
    final rest = avail - minSum;
    final widths = [
      for (var i = 0; i < members.length; i++)
        mins[i] + rest * weights[i] / sum
    ];
    // 宽比钳制（2026-11-26 LSA m1 单行实证）：内容比真实超 2.5 时（m1
    // 三拍列 vs m2 九拍列 = 3.0），加权结果直接触发宽比违例 → 拒行 →
    // 稀疏小节被迫单独成行，违反"每行最少 2 小节"铁律。分配层削峰填
    // 谷化解：峰值钳到 2.4×谷值，削下的宽度按权重还给未钳成员（谷值
    // 成员永不被钳，钳制每轮严格收敛）；**钳制不削破最小宽**（物理
    // 必需优先于均衡）；rowOverfull 的 2.5 硬校验仍兜底（钳不动时是
    // 真实物理差异，拒行正确）。
    if (members.length >= 2) {
      for (var iter = 0; iter < 16; iter++) {
        final mn = widths.reduce(math.min);
        final cap = 2.4 * mn;
        final clamped = <int>{};
        var excess = 0.0;
        for (var i = 0; i < widths.length; i++) {
          // 钳制下界 = max(峰值钳, 最小宽)——物理必需优先于均衡。
          final floor = math.max(cap, mins[i]);
          if (widths[i] > floor) {
            excess += widths[i] - floor;
            widths[i] = floor;
            clamped.add(i);
          }
        }
        if (excess <= 0.5) break;
        var restSum = 0.0;
        for (var i = 0; i < widths.length; i++) {
          if (!clamped.contains(i)) restSum += weights[i];
        }
        for (var i = 0; i < widths.length; i++) {
          if (!clamped.contains(i)) {
            widths[i] += excess * weights[i] / math.max(restSum, 1e-9);
          }
        }
      }
    }
    return widths;
  }

  bool rowOverfull(List<int> members, List<double> widths) =>
      rowOverfullWhy(members, widths) != null;

  /// rowOverfull 的原因分解变体（2026-11-27 折行普适性诊断）：null =
  /// 该行放得下；非 null = 首个命中的违例原因短码。与 rowOverfull
  /// 同一代码路径（探针结论与生产判定不漂移）。
  ///
  /// 判定 = 解析初筛（_preWhy：线性拍位近似同列/宽比）
  /// **叠加**渲染终位校验（_flowCheck：调 paint 同一个 buildRowFlow
  /// 预测该行排布结果再判铁律）。后者是 2026-11-27 的决定性升级：
  /// 手写模拟与渲染的偏差（行首贴线只移首组、挂靠让位波及、deco
  /// 左槽、左推级联）不再漏进行——合并后非豁免近似同列 244→688 实证。
  @visibleForTesting
  String? rowOverfullWhy(List<int> members, List<double> widths) =>
      _preWhy(members, widths) ?? _flowCheck(members, widths).why;

  /// 渲染终位校验（2026-11-27）：调用渲染 paint **同一个** buildRowFlow
  /// 预测候选行的排布终位，在终位上校验铁律。返回首个违例原因、违例
  /// 小节集合、各违例小节的加宽缺口（px，求解器据此反馈）：
  /// - flow-overflow 音符中心越出本小节右界内 12px（小节归属）
  /// - flow-ink     同弦标签墨重叠（含跨小节——链状态跨小节贯穿）
  /// - flow-invert  时序倒置（晚拍画在早拍左侧 >1px）
  /// - flow-near    不同拍近似同列：非豁免对渲染后中心距 <18px（豁免
  ///                 口径与拍位校验一致——grace/亚拍错位/前拍装饰短音）
  ({String? why, Set<int> bad, Map<int, double> need}) _flowCheck(
      List<int> members, List<double> widths) {
    final xOf = <int, double>{};
    final wOf = <int, double>{};
    var acc = leftPad;
    for (var c = 0; c < members.length; c++) {
      xOf[members[c]] = acc;
      wOf[members[c]] = widths[c];
      acc += widths[c];
    }

    // 与 TabLayout.noteX 同式（候选宽代入——最终排版此刻尚不存在）。
    double beatX(int mi, double beat) {
      final cb = contentBeatsOf(mi);
      return xOf[mi]! +
          notePad +
          math.min(beat, cb) * (wOf[mi]! - notePad * 2) / cb;
    }

    final flow = buildRowFlow(
        measures: measures,
        row: members,
        notePad: notePad,
        graceAsNormal: graceAsNormal,
        measureX: (mi) => xOf[mi]!,
        measureWidth: (mi) => wOf[mi]!,
        noteX: beatX,
        stringY: (_) => 0,
        inkHalf: inkHalf);
    String? why;
    final bad = <int>{};
    final need = <int, double>{};
    void flag(int mi, String code, double deficit) {
      why ??= code;
      bad.add(mi);
      if (deficit > (need[mi] ?? 0)) need[mi] = deficit;
    }

    // 右界溢出 + 同弦墨重叠（全行两两；跨小节归后小节——后小节加宽
    // 才有空间让链把首拍组推离前小节末音）。
    for (var i = 0; i < flow.length; i++) {
      final a = flow[i];
      final over = a.x - (xOf[a.mIdx]! + wOf[a.mIdx]! - 12);
      if (over > 0.5) flag(a.mIdx, 'flow-overflow', over);
      for (var j = i + 1; j < flow.length; j++) {
        final b = flow[j];
        if (a.note.string != b.note.string) continue;
        final overlap =
            inkHalf(a.note) + inkHalf(b.note) - 1.0 - (a.x - b.x).abs();
        if (overlap > 0) {
          flag(a.mIdx == b.mIdx ? a.mIdx : b.mIdx, 'flow-ink', overlap);
        }
      }
    }
    // 倒置 + 近似同列（小节内，非 grace 主音按 x 序相邻对）。
    final an = graceAsNormal;
    final byM = <int, List<RowFlowNote>>{};
    for (final f in flow) {
      (byM[f.mIdx] ??= []).add(f);
    }
    for (final e in byM.entries) {
      final main = [
        for (final f in e.value)
          if (an || !f.note.grace) f
      ]..sort((p, q) => p.x.compareTo(q.x));
      for (var i = 1; i < main.length; i++) {
        final q = main[i];
        // 与 x 序上**所有够得着**的非豁免前驱逐对比（同拍跳过；豁免口径
        // 见 nearColExempt——只比相邻对会让被豁免短音夹在中间的两端拍对
        // 漏网）。不能只比最近一个前驱：同拍同 x 的宽标签兄弟会被跳过
        //（Distance m24："(5)" 与 "0" 同 x，后一拍音只与 "0" 比过）。
        for (var j = i - 1; j >= 0; j--) {
          final p = main[j];
          if ((q.note.beat - p.note.beat).abs() < 1e-6) continue; // 同拍
          // 豁免按**拍序**判（规则原意"前一个拍是装饰性短音"）：若按 x 序
          // 取左侧音当前音，被画到前一拍音左侧的 deco 槽位音会自己变成
          // "前音"而凭短时值豁免——不同拍的数字上下叠成一列却漏判
          //（第一次2.gp3 b0.75 "0" × b1.0 deco "3" dx≈-1 实证）。
          final db = q.note.beat - p.note.beat;
          final late = db > 0 ? q : p;
          final early = db > 0 ? p : q;
          if (nearColExempt(early.note, late.note)) continue;
          if (q.x - p.x > _nearReach) break; // 再往左都够不着
          final span = late.x - early.x; // 晚拍 − 早拍
          final need = nearColNeed(p.note, q.note);
          if (span >= need) continue;
          // 缺口换算成小节宽：Δbpm = 缺口/拍差 → Δ宽 = Δbpm × contentBeats。
          final deficit =
              (need - span) / db.abs() * contentBeatsOf(e.key);
          flag(e.key, span < -1.0 ? 'flow-invert' : 'flow-near', deficit);
        }
      }
    }
    return (why: why, bad: bad, need: need);
  }

  /// 行宽求解缓存（_layoutFor 对同一行先试加一成员、再 flush，重复求解）。
  final Map<String, ({List<double> widths, String? why})> _solveCache = {};

  /// 行宽求解（2026-11-27 折行普适性核心）：**闭环**——解析最小宽起步
  /// 分配 → 渲染 paint 同一个 buildRowFlow 预测排布 → 违例小节按缺口
  /// 加宽 → 重分配重试；直到预测渲染不违例，或最小宽总额超出行宽
  /// （真实放不下 → 拒行，调用方折行）。合并与否不再靠解析公式猜
  /// 渲染结果，而是"预测渲染干净才算放得下"。返回 (行宽, 拒因)。
  ({List<double> widths, String? why}) _solveRow(
      List<int> members, double avail) {
    final key = '${members.join(',')}|${avail.toStringAsFixed(1)}';
    return _solveCache.putIfAbsent(
        key, () => _solveRowUncached(members, avail));
  }

  /// 求解器测试入口（折行诊断探针用；生产走 _layoutFor）。
  @visibleForTesting
  ({List<double> widths, String? why}) solveRowForTest(
          List<int> members, double maxWidth) =>
      _solveRow(members, maxWidth - leftPad * 2);

  /// 诊断入口（折行探针用）：小节解析最小宽 / 行首贴线占宽。
  @visibleForTesting
  ({double min, double headExtra}) minInfoForTest(int mi) =>
      (min: _minWidths[mi], headExtra: _headExtras[mi]);

  /// 诊断入口（折行探针用）：候选行在给定行宽下的渲染终位校验明细。
  @visibleForTesting
  ({String? why, Set<int> bad, Map<int, double> need}) flowCheckForTest(
          List<int> members, List<double> widths) =>
      _flowCheck(members, widths);

  ({List<double> widths, String? why}) _solveRowUncached(
      List<int> members, double avail) {
    final mins = [
      for (var c = 0; c < members.length; c++)
        _minWidths[members[c]] + (c == 0 ? _headExtras[members[c]] : 0)
    ];
    var widths = _allocate(members, avail, mins);
    for (var attempt = 0; attempt < 10; attempt++) {
      final sim = _preWhy(members, widths);
      if (sim != null) return (widths: widths, why: sim);
      final fc = _flowCheck(members, widths);
      if (fc.why == null) return (widths: widths, why: null);
      if (fc.bad.isEmpty) return (widths: widths, why: fc.why);
      var minSum = 0.0;
      for (var c = 0; c < members.length; c++) {
        final mi = members[c];
        if (fc.bad.contains(mi)) {
          // 缺口 + 余量；至少 12% 自适应（缺口估算只对拍距类违例精确）。
          mins[c] += math.max((fc.need[mi] ?? 0) + 8, widths[c] * 0.12);
        }
        minSum += mins[c];
      }
      if (minSum >= avail) return (widths: widths, why: fc.why);
      widths = _allocate(members, avail, mins);
    }
    return (widths: widths, why: _flowCheck(members, widths).why ?? 'flow');
  }

  /// 解析初筛（与渲染无关的两条行级规则）：
  /// - near-col：线性拍位近似同列——不同拍的非豁免对拍位中心距 <
  ///   nearColNeed（按标签墨宽，见该函数注释；2026-11-25 用户铁律，
  ///   豁免：grace、亚拍错位 <1/16、前拍装饰短音）。
  ///   拍位 x 取 dup 错开**前**的 noteX——近似同列的根源是拍位排布本身
  ///   挤，dup 错开只是同拍补救。
  /// - ratio：行内最大/最小小节宽比 > 2.5（2026-11-25"不超宽小节"）。
  ///
  /// 位置类规则（同弦墨重叠/右界溢出/时序倒置/渲染后近似同列）全部由
  /// _flowCheck 用 paint 同一个 buildRowFlow 精确判定。旧手写链模拟
  /// （chain-overlap / overflow / grace-tight）是其近似版——漏掉行首
  /// 贴线只移首组、挂靠让位波及、deco 左槽、左推级联，行越紧偏差越大
  /// （2026-11-27 撤除：初筛用近似、真判用精确，两层口径不再并存）。
  String? _preWhy(List<int> members, List<double> widths) {
    final an = graceAsNormal;
    var accX = leftPad;
    for (var c = 0; c < members.length; c++) {
      final mi = members[c];
      final m = measures[mi];
      final mx = accX;
      accX += widths[c];
      final bpm = (widths[c] - notePad * 2) / contentBeatsOf(mi);
      final head = c == 0 ? headShiftRel(m, bpm) : 0.0;
      final nxOf = <NoteIr, double>{};
      for (final n in m.notes) {
        nxOf[n] = mx + notePad + head + n.beat * bpm;
      }
      final byBeat = <double, List<NoteIr>>{};
      for (final n in m.notes) {
        byBeat.putIfAbsent(n.beat, () => []).add(n);
      }
      final beats = byBeat.keys.toList()..sort();
      final beatXs = <NoteIr>[]; // 全部主音（按拍位 x 排序）
      for (final b in beats) {
        for (final f in byBeat[b]!) {
          if (f.grace && !an) continue;
          beatXs.add(f);
        }
      }
      beatXs.sort((a, b) => nxOf[a]!.compareTo(nxOf[b]!));
      // 每个音与它 x 序上**所有够得着的非豁免前驱**比（同拍/豁免对跳过
      // ——豁免口径见 nearColExempt；只比相邻对会让被豁免短音夹在中间的
      // 两端拍对、以及同拍同 x 的宽标签兄弟漏网）。grace 不进校验。
      for (var i = 1; i < beatXs.length; i++) {
        final q = beatXs[i];
        for (var j = i - 1; j >= 0; j--) {
          final p = beatXs[j];
          if (q.beat == p.beat) continue;
          // 豁免按拍序判（口径与 _flowCheck 一致）。
          final early = p.beat < q.beat ? p : q;
          final late = p.beat < q.beat ? q : p;
          if (nearColExempt(early, late)) continue;
          if (nxOf[q]! - nxOf[p]! > _nearReach) break;
          if (nxOf[q]! - nxOf[p]! < nearColNeed(p, q)) return 'near-col';
        }
      }
    }
    // 超宽小节校验（2026-11-25 用户规则："尽量每行不存在超宽小节，
    // 规则允许下尽量多的小节数"）：行内最大/最小小节宽 > 2.5 = 内容
    // 失衡（稀疏小节绑住密集小节的宽度）→ 该行不可取，折行重排。
    if (members.length >= 2) {
      final wMin = widths.reduce(math.min);
      final wMax = widths.reduce(math.max);
      if (wMax / math.max(wMin, 1) > 2.5) return 'ratio';
    }
    return null;
  }

  /// 是否存在"折行被迫压缩"的超宽行——**全量探针的结构性豁免判据**
  /// （2026-11-16）：2~5 铁律强迫超宽行进多小节行（cur=1 时不
  /// flush），连排密度 × 墨阈数学上放不下 → 数字接触不可排布避免
  /// （制谱基准 靠窄音乐字体才放得下）。该类谱×宽组合豁免判罚但仍计数。
  bool hasOverfullMeasure(double maxWidth) {
    final l = _layoutFor(maxWidth);
    for (var r = 0; r < l.rows.length; r++) {
      if (rowOverfull(l.rows[r], l.rowWidthsList[r])) return true;
      // （2026-11-27 撤除"含 grace 行即豁免"：原理由是布局层预测不了
      // grace 挂靠终位——现在折行判定与 paint 共用 buildRowFlow，预测
      // 即渲染；全库扫描实证该条也从未单独生效过——仅因 grace 被豁免
      // 的组合为 0。豁免只剩结构性一类：独占整行仍违例的被迫行。）
    }
    return false;
  }

  /// 行布局：每行小节 index 列表 + 该行小节宽（求解器按内容分配）。
  ///
  /// 折行规则（2026-11-12 用户铁律定案）：**除最后一行外每行 2~5 小节**。
  /// 密度档（行内最大单小节音列数）>32→≤2、>20→≤3、>14→≤4、否则≤5；
  /// 叠加行宽求解（_solveRow：解析初筛 + 渲染终位校验闭环）——候选行
  /// 预测渲染干净才算放得下；cur 已有 1 小节时不得 flush（哪怕违例
  /// ——单小节独占整行是结构性极限，2026-11-18 用户指令）。
  _RowLayout _layoutFor(double maxWidth) {
    return _layoutCache.putIfAbsent(maxWidth, () {
      final measures =
          ir.tracks.isEmpty ? const <MeasureIr>[] : ir.tracks.first.measures;
      final avail = maxWidth - leftPad * 2;

      final rows = <List<int>>[];
      final rowWidthsList = <List<double>>[];
      var cur = <int>[];

      var maxBarInCur = 0; // 行内最大单小节音列数
      void flush() {
        if (cur.isEmpty) return;
        rows.add(cur);
        // 强制行（单小节仍违例）取求解器最后一次分配——诚实反映缺口。
        rowWidthsList.add(_solveRow(cur, avail).widths);
        cur = <int>[];
        maxBarInCur = 0;
      }

      for (var i = 0; i < measures.length; i++) {
        // 密度档口径（2026-11-27 修正）：**拍列数**（去重 beat 数），
        // 非音符数——注释/设计一直说"音列数"，实现却用了 notes.length：
        // 和弦/双音谱音符数 2-3 倍于列数被误判超密（Bluebird 全 2 小节
        // 行、月下之恋行稀的实锤；157 谱全库重判：密度拒因 978→98）。
        final noteCount =
            measures[i].notes.map((n) => n.beat).toSet().length;
        // 密度档上限（2026-11-10 五档；2026-11-12 用户铁律封顶 5）：
        // 行内最大单小节音列数 >32 → ≤2；>20 → ≤3；>14 → ≤4；否则 ≤5。
        final maxAfter = math.max(maxBarInCur, noteCount);
        final maxBars = maxAfter > 32
            ? 2
            : maxAfter > 20
                ? 3
                : maxAfter > 14
                    ? 4
                    : 5;
        // **每行 2~5 小节铁律**（2026-11-12 用户定案，末行豁免）：
        // ≥2 且超密度档/预测渲染违例才换行。
        // **2026-11-18 用户指令升级（不遮挡优先）**：cur=1 且 2 小节
        // 行放不下 → **允许 1 小节行**（行宽翻倍换零遮挡——LAS 类 32
        // 分密集谱的结构性挤压根除；"至少保证每个音每个符号正常显示
        // 不遮挡"优先于每行下限）。
        if (cur.isNotEmpty &&
            (cur.length + 1 > maxBars ||
                _solveRow([...cur, i], avail).why != null)) {
          flush();
        }
        cur.add(i);
        maxBarInCur = math.max(maxBarInCur, noteCount);
      }
      flush();
      return _RowLayout(rows, rowWidthsList);
    });
  }

  /// 自动换行：每行小节 index 列表。
  List<List<int>> rowsFor(double maxWidth) => _layoutFor(maxWidth).rows;

  /// 行内小节宽列表（测试辅助；生产走 measureWidthAt/rowOverfull 内部）。
  @visibleForTesting
  List<double> rowWidthsForTest(List<int> members, double maxWidth) {
    final avail = maxWidth - leftPad * 2;
    return rowWidths(members, avail);
  }

  /// 谱面排版宽度上限（2026-11-09 制谱基准 对照：宽屏下行宽随容器铺满导致
  /// 每行小节数过多——上限 1300px，超出部分居中留白，制谱基准 同款密度）。
  static double effectiveWidth(double containerWidth) =>
      containerWidth > 1300 ? 1300 : containerWidth;

  /// 谱面水平居中偏移（容器宽 - 排版宽）/2；hitTest 反算时同样扣除。
  static double horizontalOffset(double containerWidth) =>
      (containerWidth - effectiveWidth(containerWidth)) / 2;

  /// [measureIndex] 所在行的小节宽（行级可变，密集行更宽）。
  double measureWidthAt(int measureIndex, double maxWidth) {
    final l = _layoutFor(maxWidth);
    for (var r = 0; r < l.rows.length; r++) {
      final c = l.rows[r].indexOf(measureIndex);
      if (c >= 0) return l.rowWidthsList[r][c];
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
    // 行内宽加权分配后（2026-11-25）各小节宽不等——x 必须按行宽列表
    // 累计（c × 单宽在加权下行内错位）。
    final l = _layoutFor(maxWidth);
    for (var r = 0; r < l.rows.length; r++) {
      final c = l.rows[r].indexOf(measureIndex);
      if (c >= 0) {
        var x = leftPad;
        for (var i = 0; i < c; i++) {
          x += l.rowWidthsList[r][i];
        }
        return x;
      }
    }
    return leftPad;
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
  _RowLayout(this.rows, this.rowWidthsList);
  final List<List<int>> rows;
  // 行 → 行内小节宽列表（制谱基准 式按内容加权分配，非均分）。
  final List<List<double>> rowWidthsList;
}
