import 'dart:math' as math;

import '../../core/score/score_ir.dart';

/// 行内音流元素：小节下标 / 音符 / 排布终位（x 可变——排布趟逐步修正）。
class RowFlowNote {
  RowFlowNote(this.mIdx, this.note, this.x, this.y);
  final int mIdx;
  final NoteIr note;
  double x;
  final double y;
}

/// 行内音流排布（2026-11-27 抽取）：dup 错开 → 反复符号间距 → 行首贴线
/// 保护 → grace 挂靠（主音让位）→ 拥挤链（同弦墨净空）→ 左推趟。
///
/// **渲染 paint 与折行判定（TabLayout.rowOverfull）共用本实现**——
/// 此前排布只在 paint 里做，布局层靠手写链模拟近似（行首贴线整小节
/// 平移、无挂靠让位波及、无 deco 左槽、无左推级联），行越紧两层偏差
/// 越大：折行判定认为放得下的行，渲染后出现近似同列/倒置（2026-11-27
/// app 曲库对照实锤）。同一份代码 = 判定与渲染零漂移。
///
/// 几何全部经回调注入（不读 TabLayout 实例）：paint 传最终排版的
/// measureX/measureWidth/noteX；折行判定传**候选行**的候选宽——
/// rowOverfull 在 _layoutFor 构建途中被调用，此时最终排版尚不存在。
/// [stringY] 只影响 y（折行判定不关心，传常量即可）。
List<RowFlowNote> buildRowFlow({
  required List<MeasureIr> measures,
  required List<int> row,
  required double notePad,
  required bool graceAsNormal,
  required double Function(int mIdx) measureX,
  required double Function(int mIdx) measureWidth,
  required double Function(int mIdx, double beat) noteX,
  required double Function(int string) stringY,
  required double Function(NoteIr note) inkHalf,
}) {
  final flow = <RowFlowNote>[];
  bool sameRow(int a, int b) => row.contains(a) && row.contains(b);
  for (final m in row.map((idx) => measures[idx])) {
    if (m.failed) continue; // failed 小节 notes 恒空（Task 10/11 契约）
    // —— 排布（2026-11-09 回退至 7568952 稳定版：组粒度重构引发
    // 18 小节后渲染消失与大量误连线，整体撤回。两趟原逻辑保留）——
    // dup 错开（2026-11-12 全库自检 Bluebird 实锤 4 对 0px 完全
    // 叠印后引入分级错开；2026-11-16 步长改墨宽感知 + 去右界钳
    // ——满格溢出由左推趟整组左移回界内）。
    final dupSeen = <String, int>{};
    final dupLastX = <String, double>{};
    final dupLastNote = <String, NoteIr>{};
    for (final n in m.notes) {
      final nx = noteX(m.index, n.beat);
      final ny = stringY(n.string);
      final key = '${n.string}@${n.beat.toStringAsFixed(3)}';
      // deco 装饰音不占拍位（2026-11-20 用户 制谱基准 对照实证：m4/m17
      // 的 tieE 须画在本体 10/7 **正下方同列**——装饰独立槽位在
      // 主音**左侧**，让出拍位；同弦多 deco 向左续排。制谱基准 精读
      // §2.5 同形态：装饰盒右缘距主音左缘 ~5px）。
      // b0 拍 deco 左移会压左竖线 → 钳到 notePad 净空（**主流路
      // 径非罕见**：全库 1334 处 b0 deco）。钳制后 dupLastX=bound
      // → 本体落 nx+step（右移 18px 同拍错列）——几何与改前逐位
      // 相同（deco 占拍位原形态），dsh 实证双探针不可见（同拍对
      // beatcol 跳过、跨弦 dy=20 超 y 扫描上限）；错列根治归排布
      // 升级批（与趟式三难债同批）。
      if (n.deco) {
        final seen = dupSeen.putIfAbsent(key, () => 0);
        dupSeen[key] = seen + 1;
        final prevX = dupLastX[key] ?? nx;
        final prevN = dupLastNote[key] ?? n;
        final step =
            math.max(18.0, 1.0 + inkHalf(prevN) + inkHalf(n));
        var x = seen == 0 ? nx - step : prevX - step;
        final leftBound =
            measureX(m.index) + notePad;
        if (x < leftBound) x = leftBound;
        dupLastX[key] = x;
        dupLastNote[key] = n;
        flow.add(RowFlowNote(m.index, n, x, ny));
        continue;
      }
      final idx = dupSeen.putIfAbsent(key, () => 0);
      dupSeen[key] = idx + 1;
      double x;
      if (idx == 0) {
        x = nx;
      } else {
        // 步长墨宽感知（2026-11-16 探针残类 "(5)"×"(0)"：固定 18px
        // 对括号 label（墨半 21）不足 → 需 1+前墨半+本墨半；普通一
        // 位数 15px 仍取 18 保持原节奏。**不再钳 available**（旧
        // 钳制在右界内强叠印 dx=3~16——2026-11-16 探针实证 12 处；
        // 满格溢出由左推趟整组左移回界内，前驱亏空级联左传）。
        final prevX = dupLastX[key] ?? nx;
        final prevN = dupLastNote[key] ?? n;
        final minStep =
            1.0 + inkHalf(prevN) + inkHalf(n);
        final step = math.max(18.0, minStep);
        x = prevX + step;
      }
      dupLastX[key] = x;
      dupLastNote[key] = n;
      flow.add(RowFlowNote(m.index, n, x, ny));
    }
  }
  // 同弦相邻拥挤（2026-11-12 dsh 三轮重写）：**按 mIdx@beat 组遍
  // 历，每组只处理一次**——旧按音遍历在组推移后把组内各弦 lastX
  // 写成组员自身 x，组员再被处理时"自己和比自己"恒真 → 每组多推
  // 17px（LAS 密集谱级联引爆的真正源头）。组位移 = 各弦约束取
  // max；lastX/lastNote **按小节 reset**（跨小节不传染，替代隐式
  // 22px 间隙兜底）；阈 = 9+前音半宽+本音半宽（纯数字对=17 与折
  // 行宽度校验对齐，幽灵/泛音宽字形自动加大）。推移**钳制在本小
  // 节右线内 12px**（小节归属铁律绝对优先；极端贴边接受，根治待
  // 排布升级）。
  final lastXAtString = <int, double>{};
  final lastNoteAtString = <int, NoteIr>{};
  final crowdGroups = <String, List<RowFlowNote>>{};
  for (final fl in flow) {
    crowdGroups['${fl.mIdx}@${fl.note.beat.toStringAsFixed(3)}'] ??= [];
    crowdGroups['${fl.mIdx}@${fl.note.beat.toStringAsFixed(3)}']!.add(fl);
  }
  // 反复符号间距（2026-11-09 用户反馈；2026-11-16 探针残类定序）：
  // repeatStart 小节的音**组**距左竖线 ≥22px、repeatEnd 末组距右
  // 竖线 ≥18px——组粒度整体移（保持同拍跨弦对齐不破坏）。
  // **趟序：必须在拥挤趟之前**——拥挤趟已按链排好净空，repeat 的
  // +22 组移会吃掉首组与后组的间隙（gtp 残类 "(2)"×"2" 恒 17px
  // 实锤：crowd 推 b0.5 至 +29 后 repeat 把首组 +12 压回 17）；
  // 提前跑则拥挤趟以移后位置为基准链，净空在链内重建。
  final groupsMB = <String, List<RowFlowNote>>{};
  for (final fl in flow) {
    (groupsMB['${fl.mIdx}@${fl.note.beat}'] ??= []).add(fl);
  }
  groupsMB.forEach((k, g) {
    final mIdx0 = int.parse(k.split('@').first);
    final m = measures[mIdx0];
    final mx = measureX(mIdx0);
    // 右边界（dsh 复测 P0 整改 2026-11-11）：mIdx0 是**行末小节**时
    // measureX(mIdx0+1) 会取到下一行 col0 的 x → 整组左移出屏；
    // 行末小节的右竖线 = 行内容宽（= 行末收尾竖线 endX 同款算式）。
    final sameRowNext =
        mIdx0 + 1 < measures.length && sameRow(mIdx0 + 1, mIdx0);
    final mxNext = sameRowNext
        ? measureX(mIdx0 + 1)
        : measureX(row.last) + measureWidth(row.last);
    // 左侧保护：本小节 repeatStart、或**前一小节 repeatEnd**（其右线
    // 即本小节左线，贴线的音是本小节首音组——2026-11-09 用户反馈
    // "end 符号右侧数字依旧贴着"的根因）→ 首音组距左线 ≥22px。
    // 同行限定（dsh 二轮）：prev 在上一行末时 end 符号画在上行末线，
    // 本行左线无标记，不做 +22 推移。
    final prevEnd = mIdx0 > 0 &&
    measures[mIdx0 - 1].repeatEnd &&
    sameRow(mIdx0 - 1, mIdx0);
    if (m.repeatStart || prevEnd) {
      final minX = g.map((f) => f.x).reduce(math.min);
      if (minX - mx < 22) {
        final shift = 22 - (minX - mx);
        for (final f in g) {
          f.x += shift;
        }
      }
    }
    if (m.repeatEnd) {
      final rightEdge =
          g.map((f) => f.x + 8).reduce(math.max); // label 右缘估宽 8
      if (mxNext - rightEdge < 18) {
        final shift = 18 - (mxNext - rightEdge);
        for (final f in g) {
          f.x -= shift;
        }
      }
    }
  });
  // 行首贴线保护（2026-11-12 用户走查：行首 <12> 墨缘压左竖线——
  // notePad=10 只保数字中心，宽字形墨半 11 压线）。**仅行首小节的
  // 首音组**组粒度右移至墨左缘距左竖线 ≥5px。放在拥挤趟**之前**：
  // 先推基准再跑链，同弦第二组基于推移后位置保持净空（dsh 复测
  // P1 整改：放拥挤趟后跑会吃掉已排好的 1px 净空 → 同弦墨重叠）。
  final firstM = row.first;
  final minBeatFirst = flow
      .where((fl) => fl.mIdx == firstM)
      .map((fl) => fl.note.beat)
      .fold<double?>(null, (acc, b) => acc == null || b < acc ? b : acc);
  if (minBeatFirst != null) {
    final headGroup =
        crowdGroups['$firstM@${minBeatFirst.toStringAsFixed(3)}'];
    if (headGroup != null) {
      final mxFirst = measureX(firstM);
      final minInk = headGroup
          .map((f) => f.x - inkHalf(f.note))
          .reduce(math.min);
      if (minInk < mxFirst + 5) {
        final shift = mxFirst + 5 - minInk;
        for (final f in headGroup) {
          f.x += shift;
        }
      }
    }
  }
  // 组处理序 = **时间序**（2026-11-12 Distance/Bluebird 实锤：多声
  // 部谱 m.notes 是文件序——后拍组先处理时，前拍组以"后拍音的 x"
  // 为 prev 被推过它 → 视觉 x 序与拍序倒置（b3.75 画在 b3.5 左
  // 边）。按小节+拍排序后推移链沿时间轴单调。
  final crowdOrder = <String>[];
  final crowdMeasures = <int>{};
  for (final fl in flow) {
    crowdMeasures.add(fl.mIdx);
  }
  for (final mIdx in crowdMeasures.toList()..sort()) {
    final beats = crowdGroups.keys
        .where((k) => k.startsWith('$mIdx@'))
        .map((k) => double.parse(k.split('@').last))
        .toList()
      ..sort();
    for (final b in beats) {
      crowdOrder.add('$mIdx@${b.toStringAsFixed(3)}');
    }
  }
  double mRightOf(int mIdx) =>
      measureX(mIdx) +
      measureWidth(mIdx) -
      12;
  // 链状态**跨小节贯穿**（2026-11-16 探针残类 "12"×"11"：按小节
  // reset 后小节末音与小节首拍音之间无链——两位数需 29px、括号需
  // 43px，而边界自然距仅 22px（notePad 10 + 界 12）→ 5~21px 重叠。
  // f.x 为行绝对坐标，链天然连续；位移仍受**本小节**右界钳制，
  // 满界组保位（delta=0），级联有界不传染。普通一位数对需 15px <
  // 22px 自然距 → LAS 等密集谱不受影响）。
  // per-string 拍序索引（2026-11-17 grace 挂靠配套）：组内音的
  // 拍序同弦前驱若为 grace（grace 挂靠该音左侧、不进链）→ gap
  // 加大 1+2×grace 半宽，保证 [前音…grace…主音] 不叠。
  final crowdByString = <int, List<RowFlowNote>>{};
  final crowdIdxOf = <RowFlowNote, int>{};
  final flowBeatOrder = List.of(flow)..sort((a, b) {
    final c = a.mIdx.compareTo(b.mIdx);
    if (c != 0) return c;
    final cb = a.note.beat.compareTo(b.note.beat);
    if (cb != 0) return cb;
    final cs = a.note.string.compareTo(b.note.string);
    return cs != 0 ? cs : a.x.compareTo(b.x);
  });
  for (final fl in flowBeatOrder) {
    final list = crowdByString.putIfAbsent(fl.note.string, () => []);
    crowdIdxOf[fl] = list.length;
    list.add(fl);
  }
  // grace 挂靠趟（2026-11-17 探针残类 Paganini 实证）：装饰音
  // **钉在主音（同弦下一非 grace 音）左侧**，不参与拥挤链——链
  // 把 grace 当普通音推时超界保位沉底（自然位 270、链位 359.7，
  // 与主音前的音贴 3.6px）；制谱基准 同款形态（grace 紧贴主音左）。
  // **串版本**（四轮探针 3706 处实证）：串内从主音往左依次排位，
  // 相邻 grace 净空 1px。
  // **谱级门**（时间.gp3 实证）：grace 占比 >25% 的谱（转换器
  // 产物全谱标志）制谱基准 按 slash 正常音排布——不挂靠、不跳链。
  // **趟序（2026-11-18 定案：拥挤链趟之前）**——挂靠让位（主音
  // 右移）后再跑链，链以让位后位置为基准把后继推开（m12 实证：
  // 链在挂靠前跑 → 让位挤后继 8.3px 无再平衡 → 违例；布局层
  // rowOverfull 的链模拟已含挂靠起点钳制口径，渲染趟序对齐后
  // 两层一致——规则 22）。
  if (!graceAsNormal) {
    // 已挂靠处理的 grace（并组 + 主音让位完成；旧独立钳制趟不得
    // 再回顶挂靠位——m2 dist=-0.7 压死的第二推手）。
    final attached = <RowFlowNote>{};
    for (final list in crowdByString.values) {
      var pending = <RowFlowNote>[]; // 顺拍序累积的 grace 串
      for (final fl in list) {
        if (fl.note.grace) {
          pending.add(fl);
          continue;
        }
        // 主音：pending 串从最靠主音的（reversed）往左依次挂靠。
        // **跨小节禁挂**（2026-11-17 第一次2.gp3 实证：m12 尾
        // grace 串挂到 m13 主音 → grace 拉过小节线 + 与左邻贴
        // 4px——小节归属铁律优先；跨小节 grace 串保持自然位走
        // 正常排布）。
        if (pending.isNotEmpty && pending.first.mIdx != fl.mIdx) {
          pending = [];
          continue;
        }
        var xRight = fl.x;
        var rightHalf = inkHalf(fl.note);
        for (final g in pending.reversed) {
          final gx = xRight -
              1.0 -
              inkHalf(g.note) -
              rightHalf;
          g.x = gx;
          xRight = gx;
          rightHalf = inkHalf(g.note);
        }
        // **挂靠原子绑定**（2026-11-18 m2 `<12>`×`2` dist=-0.7 压死
        // 实证）：钉位空间不足（挂靠位越左线被钳回）时旧模型只钳
        // grace 不动主音 → grace 被顶到主音位上；且 grace 不在主音
        // 组里，左推趟整组移动会甩下它。制谱基准 语义 = grace 是主音的
        // 附属：①grace 并入主音同拍组（后续整组移动原子联动）；
        // ②钳制冲突时主音组右移让位（bound 限幅右界-5-组右墨缘，
        // 空间不足移部分，残余进探针可见）；③同拍对齐不受影响
        // （grace 是挂靠音，本来就不要求同拍对齐）。
        final gkey = '${fl.mIdx}@${fl.note.beat.toStringAsFixed(3)}';
        final gList = crowdGroups[gkey]!;
        final mxL = measureX(fl.mIdx);
        final mw = measureWidth(fl.mIdx);
        final mainHalf = inkHalf(fl.note);
        // ② 先让位：钳制冲突时主音组右移（grace 尚未入组——并组后
        // 再移会带着 grace 一起移，相对位不变，白移）。bound 限幅
        // 右界-5-组右墨缘（不含 grace；空间不足移部分，残余进探针
        // 可见）。
        var needShift = 0.0;
        for (final g in pending) {
          final ink = inkHalf(g.note);
          final lo = mxL + 5 + ink;
          final hi = math.max(lo, mxL + mw - 5 - ink);
          final pinned = g.x.clamp(lo, hi).toDouble();
          // 方向感知（2026-11-18 m2 dist 18.6→14.3 退化实证）：
          // grace 被钳到主音**右侧**（挂靠位越左线，pinned > fl.x）
          // 时，dx = fl.x - pinned 为负，让位量 = gap - dx = gap +
          // |dx|（grace 要先跨回主音左侧再留净空）；旧 abs 公式把
          // 跨回段漏算 → 主音让位不足 → 重钉 clamp 又把 grace 顶
          // 回主音身上（差 = 主音半宽 4.3 实锤）。
          final dx = fl.x - pinned;
          final needDx = (1.0 + ink + mainHalf) - dx;
          if (needDx > needShift) needShift = needDx;
        }
        if (needShift > 0) {
          var gMaxInk = fl.x + mainHalf;
          for (final f2 in gList) {
            gMaxInk =
                math.max(gMaxInk, f2.x + inkHalf(f2.note));
          }
          final room = math.max(0.0, mxL + mw - 5 - gMaxInk);
          final s = math.min(needShift, room);
          if (s > 0) {
            // gList 已含主音与同拍全弦音（含并入的 grace）——主音
            // 不得再单加（双移 bug：主音领先同拍低音 15px、同拍
            // 对齐铁律破坏 + grace 反超低音近同列，2026-11-18 m12
            // 数据闭环实锤）。
            for (final f2 in gList) {
              f2.x += s;
            }
            // **不同拍不同列铁律**（2026-11-18 用户定案）：让位右移
            // 波及本小节内**全部更晚拍**的音（跨弦，grace 除外——
            // 钉主音左侧随组动）——只移同拍组会让早拍主音越过晚拍
            // 音自然位（m12 实证：b0.125 主音 226.5 > b0.625 泛音
            // 223.6，时序倒置视觉同列）。链趟在挂靠后会以新位置为
            // 基准平衡净空与右界。
            for (final f2 in flow) {
              if (f2.mIdx != fl.mIdx ||
                  f2.note.beat <= fl.note.beat ||
                  f2.note.grace) {
                continue;
              }
              f2.x += s;
            }
          }
        }
        // ③ 再钉位（按让位后的主音终位**重钉**——首钉用的是主音
        // 旧位）+ 并组（原子绑定：链趟/左推趟整组移动带上 grace；
        // 移出 grace 自然拍组——左推趟需防空组）。
        var xRight2 = fl.x;
        var rightHalf2 = mainHalf;
        for (final g in pending.reversed) {
          final ink = inkHalf(g.note);
          final lo = mxL + 5 + ink;
          final hi = math.max(lo, mxL + mw - 5 - ink);
          final gx =
              (xRight2 - 1.0 - ink - rightHalf2).clamp(lo, hi);
          g.x = gx.toDouble();
          xRight2 = gx;
          rightHalf2 = ink;
          crowdGroups[
                  '${g.mIdx}@${g.note.beat.toStringAsFixed(3)}']!
              .remove(g);
          gList.add(g);
          attached.add(g);
        }
        pending = [];
      }
      // 串尾无主音（行末 grace 串）：保持自然位（罕见，豁免兜底）。
    }
    // 界内钳制（2026-11-17 图 2 用户实证：小节末宽 grace 泛音墨
    // 缘压小节线——跨小节禁挂的自然位 grace 与挂靠位统一钳到墨
    // 缘距线 ≥5px；grace 无对齐约束，clamp 安全）。**只处理未挂靠
    // 的 grace**（attached 已并组钳过，再钳会把挂靠位顶回主音上）。
    for (final fl in flow) {
      if (!fl.note.grace || attached.contains(fl)) continue;
      final mxL = measureX(fl.mIdx);
      final mw = measureWidth(fl.mIdx);
      final ink = inkHalf(fl.note);
      final lo = mxL + 5 + ink;
      final hi = math.max(lo, mxL + mw - 5 - ink);
      fl.x = fl.x.clamp(lo, hi).toDouble();
    }
  }
  for (final k in crowdOrder) {
    final g = crowdGroups[k]!;
    var delta = 0.0;
    for (final f in g) {
      if (f.note.grace && !graceAsNormal) {
        continue; // grace 不参与链（挂靠趟重定位，见下方挂靠趟）
      }
      final prev = lastXAtString[f.note.string];
      final prevN = lastNoteAtString[f.note.string];
      if (prev == null || prevN == null) continue;
      // 对阈 = 1px 净空 + 前音墨半 + 本音墨半（2026-11-12 校正：
      // 旧 9+半宽+半宽 对一位数对算 17px——墨宽仅 8px 实需 9px——
      // 超需求推挤引发链条撞界/倒序/堆叠三连）。与布局层按列基
      // 准（一位数谱 10px/列、含两位数 17px/列）完全一致。
      var gap =
          1.0 + inkHalf(prevN) + inkHalf(f.note);
      final idx = crowdIdxOf[f]!;
      // 拍序前驱为 grace 串（连续 k 个，挂靠到 f 左侧）→ gap 按
      // 串总宽加大：主音 ≥ 前音右缘+1 + [1+2ΣgH+(k-1)] + 串宽，
      // 保证串插入后左右净空 ≥1px（推导见 rowOverfull 同款公式；
      // 2026-11-17 四轮探针）。graceAsNormal 时 grace 当普通音，
      // 不加大。
      final list = crowdByString[f.note.string]!;
      if (!graceAsNormal) {
        var k = 0;
        var sumGH = 0.0;
        var j = idx - 1;
        while (j >= 0 && list[j].note.grace) {
          k++;
          sumGH += inkHalf(list[j].note);
          j--;
        }
        if (k > 0) {
          gap += 1.0 + 2.0 * sumGH + (k - 1);
        }
      }
      final need = prev + gap - f.x;
      if (need > delta) delta = need;
    }
    if (delta > 0) {
      final bound = mRightOf(g.first.mIdx);
      final gMax = g.map((f) => f.x).reduce(math.max);
      if (gMax + delta > bound) {
        // 无空间整组推满（2026-11-12 Bluebird m62 实锤：前组已钳在
        // bound，后续组再钳到同一 bound → 同点叠印）。保持原位——
        // 自然列距虽 <17 但分散，远好于堆叠；也不越线。
        delta = 0;
      }
    }
    // 时序上限（2026-11-18 试错撤回）：链推右不越晚拍组左缘会卡掉
    // 同弦墨净空（探针 799 处墨叠实证）——时序单调与链净空在趟式
    // 框架内冲突，根治 = 排布模型整体升级（布局层时序口径 → 折行
    // 减密度），与「小节线保护」同批（CLAUDE.md 已记）。当前态：
    // LAS 型倒置已由挂靠让位波及修复；Promise 型倒置（跨小节链
    // 推右首拍音）与窄行近同列为已知债，探针计数不判罚。
    if (delta > 0) {
      for (final f in g) {
        f.x += delta;
      }
    }
    for (final f in g) {
      if (f.note.grace && !graceAsNormal) {
        continue; // grace 不当链锚（挂靠位 = 主音左侧，见挂靠趟）
      }
      if (f.x > (lastXAtString[f.note.string] ?? -1)) {
        lastXAtString[f.note.string] = f.x;
        lastNoteAtString[f.note.string] = f.note;
      }
    }
  }
  // 左推趟（2026-11-16 探针残类根治）：拥挤趟右推被小节右界挡死
  // （末拍组与界距恒≈0，delta=0 保位即残类 12 处 dx=3~16 叠印）
  // + dup 错开去钳后的右溢出——宽 label 对在右界内永远放不下。
  // **时间倒序**把亏空转给前驱组左移：整组移动保同拍跨弦对齐；
  // 左移只受左线头寸硬钳（墨左缘 ≥ mx+5，行首贴线铁律同界）；
  // 前驱的新亏空由倒序后续迭代级联左传，行首组到底仍不足的极端
  // 满格接受残差（排布升级前已知债，探针兜底可见）。
  final groupKeyOf = <RowFlowNote, String>{};
  crowdGroups.forEach((k, g) {
    for (final fl in g) {
      groupKeyOf[fl] = k;
    }
  });
  final sweepOrder = List.of(flow)..sort((a, b) {
    final c = a.mIdx.compareTo(b.mIdx);
    if (c != 0) return c;
    final cb = a.note.beat.compareTo(b.note.beat);
    if (cb != 0) return cb;
    final cs = a.note.string.compareTo(b.note.string);
    return cs != 0 ? cs : a.x.compareTo(b.x);
  });
  final byStringTime = <int, List<RowFlowNote>>{};
  final stringIndexOf = <RowFlowNote, int>{};
  for (final fl in sweepOrder) {
    final list = byStringTime.putIfAbsent(fl.note.string, () => []);
    stringIndexOf[fl] = list.length;
    list.add(fl);
  }
  void shiftGroupLeft(List<RowFlowNote> g, double d) {
    final mx = measureX(g.first.mIdx);
    var cap = double.infinity;
    for (final f in g) {
      cap = math.min(
          cap, f.x - inkHalf(f.note) - (mx + 5));
    }
    final s = math.min(d, cap);
    if (s > 0) {
      for (final f in g) {
        f.x -= s;
      }
    }
  }

  for (final k in crowdOrder.reversed) {
    final g = crowdGroups[k]!;
    if (g.isEmpty) continue; // 挂靠并组后 grace 旧组可空
    // ① 右溢出（dup 去钳错开等）整组左移回界内。
    final over =
        g.map((f) => f.x).reduce(math.max) - mRightOf(g.first.mIdx);
    if (over > 0) {
      shiftGroupLeft(g, over);
    }
    // ② 前驱亏空 → **前驱组**左移（本组不动，前驱让位；同组对
    // 跳过——dup 内距由错开趟保证）。亏空按**实际墨距**算：
    // dist=|f.x-p.x| ≥ gap 不推——拥挤趟的 x 序倒置（链右推被界
    // 钳后后组越过前组，2026-11-16 m25 实锤）虽倒置但墨距已足，
    // 旧式 p.x+gap-f.x 会把倒置对误判巨亏空、级联拉爆左线帽
    // （b1.0 拉到 42、b0.25 拉上 b0 同点）制造新重叠；dist<gap
    // 才推（倒置且重叠时推前驱左移至 f.x-gap 顺带复位时序）。
    for (final f in g) {
      final list = byStringTime[f.note.string]!;
      final idx = stringIndexOf[f]!;
      if (idx == 0) continue;
      final p = list[idx - 1];
      final pk = groupKeyOf[p];
      if (pk == k) continue;
      final gap =
          1.0 + inkHalf(p.note) + inkHalf(f.note);
      final dist = (f.x - p.x).abs();
      if (dist >= gap) continue;
      shiftGroupLeft(crowdGroups[pk]!, gap - dist);
    }
  }
  return flow;
}
