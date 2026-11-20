import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/score/score_ir.dart';
import '../theme.dart';
import 'tab_layout.dart';

///
///
///
/// 渲染分层（播放滚动卡顿修复）：谱面静态层与播放头层各
///
/// 不重绘，且画时按滚动位置
class TabView extends StatefulWidget {
  const TabView(
      {super.key,
      required this.ir,
      this.playheadBeat,
      this.followPlayhead = false,
      this.loopABeats,
      this.onNoteTap,
      this.onFailedTap,
      this.onNoteLongPress});
  final ScoreIr ir;

  ///
  final double? playheadBeat;

  ///
  final bool followPlayhead;

  /// AB 循环段谱面标记（2026-11-19 用户需求：AB 设定后谱面可见区间）：
  /// 线性拍位对（A, B），单端已设时另一端 null（画单端竖线+字母）。
  final (double?, double?)? loopABeats;

  /// 点击音
  final void Function(int measureIndex, int noteIndex, NoteIr note)? onNoteTap;
  final void Function(int measureIndex)? onFailedTap;

  /// 长按音
  final void Function(int measureIndex, int noteIndex, NoteIr note)?
      onNoteLongPress;

  @override
  State<TabView> createState() => _TabViewState();
}

class _TabViewState extends State<TabView> {
  final ScrollController _scroll = ScrollController();

  ///
  /// 阶
  double? _width;

  @override
  void didUpdateWidget(covariant TabView old) {
    super.didUpdateWidget(old);
    final beat = widget.playheadBeat;
    if (!widget.followPlayhead || beat == null || beat == old.playheadBeat) {
      return;
    }
    // 帧末再滚：届时本帧布
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow(beat));
  }

  ///
  /// 仅播放头滑出
  /// 在窗口内移动不触发，避免动画反
  void _follow(double beat) {
    if (!_scroll.hasClients) return;
    final w = _width;
    if (w == null) return;
    final layout = TabLayout(widget.ir);
    final measureCount =
        widget.ir.tracks.isEmpty ? 0 : widget.ir.tracks.first.measures.length;
    if (measureCount == 0) return;
    // 变拍号修复（2026-11-19）：measure 反查用实际拍累计表（painter
    // 同款——全局 4 除错小节 → 跟页行错/不动）。
    final measure = layout.measureAtBeat(beat).clamp(0, measureCount - 1);
    final row = layout.locate(measure, TabLayout.effectiveWidth(w)).$1;
    final y =
        row * (layout.rowHeight + TabLayout.rowGap) + layout.rowHeight / 2;
    final pos = _scroll.position;
    // **滚动动画进行中不重触发**（2026-11-19 用户"暂停后才跟页"实锤）：
    // 播放中 50ms tick 每次 didUpdateWidget 都调 _follow → animateTo
    // （250ms easeOutCubic 起步慢）反复被打断重开 → 视觉上页面不动；
    // 暂停后 beat 不变、最后一次动画完整跑完 → 页面才到位。修复：
    // isScrollingNotifier（animateTo/jumpTo 进行中 true）时跳过，本
    // 轮动画跑完后的下一 tick 若仍滑出窗口再起新动画（步进平滑跟页）。
    if (pos.isScrollingNotifier.value) return;
    // 窗口内（
    if (y >= pos.pixels &&
        y <= pos.pixels + pos.viewportDimension - layout.rowHeight) {
      return;
    }
    final target =
        (y - pos.viewportDimension / 2).clamp(0.0, pos.maxScrollExtent);
    //
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
      // 排版宽（dsh 二轮整改：SizedBox 高度/hit 坐标须与 paint 的
      // effectiveWidth 同源——>1300 宽屏下行数不同会裁切/命中错位）。
      final layoutW = TabLayout.effectiveWidth(w);
      // GestureDetector 放滚动区内：hit test 链自动换算，localPosition 即内
      // 坐标，滚动后命中不错位；tap 与垂
      // behavior=opaque 冗余但更防御（RenderCustomPaint.hitTestSelf 对未重写
      // hitTest
      // 覆盖 painter
      // 双层 CustomPaint（不能合并为
      // RenderObject 任一变更整体重绘）：谱面
      // 不重绘；
      return SingleChildScrollView(
        controller: _scroll,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _hitTest(d.localPosition, layoutW, tap: true),
          onLongPressEnd: (d) => _hitTest(d.localPosition, layoutW, tap: false),
          child: SizedBox(
            width: w,
            // 底部缓冲 = PlayBar 高（64，bottomSheet 常驻
            // 底时
            height: layout.sizeFor(layoutW).height + 64,
            child: Stack(children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ScorePainter(
                      layout: layout,
                      ir: widget.ir,
                      scroll: _scroll,
                      // 弦线加深
                      // 看不清，p.muted
                      stringLine: p.muted,
                      fretText: p.ink,
                      // 小节线加深（2026-11-01 走查：p.border
                      // GP8 小节线与音
                      barLine: p.ink,
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
                        loopABeats: widget.loopABeats,
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

  /// 点击/长按命中：找
  /// 音
  /// （拥挤音右移 14px），容差须小于修正
  /// 前一音；也须小于同拍同弦 12px 错开步长
  void _hitTest(Offset local0, double containerWidth, {required bool tap}) {
    // 谱面排版宽 1300 上限 + 居中偏移（命中反算需扣除 xOff）。
    final maxWidth = TabLayout.effectiveWidth(containerWidth);
    final local =
        Offset(local0.dx - TabLayout.horizontalOffset(containerWidth),
            local0.dy);
    final layout = TabLayout(widget.ir);
    final tracks = widget.ir.tracks;
    final hasNoteCb = tap
        ? widget.onNoteTap != null
        : widget.onNoteLongPress != null;
    if (tracks.isEmpty ||
        (!hasNoteCb && widget.onFailedTap == null)) {
      return;
    }
    for (final m in tracks.first.measures) {
      final mx = layout.measureX(m.index, maxWidth);
      if (local.dx < mx - TabLayout.measureGap / 2 ||
          local.dx > mx + layout.measureWidthAt(m.index, maxWidth)) {
        continue;
      }
      final row = layout.locate(m.index, maxWidth).$1;
      if (m.failed) {
        // 行纵向校验：多
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
        if ((local.dx - nx).abs() < 11 &&
            (local.dy - ny).abs() < TabLayout.stringGap / 2) {
          if (tap) {
            widget.onNoteTap?.call(m.index, i, n);
          } else {
            widget.onNoteLongPress?.call(m.index, i, n);
          }
          return;
        }
      }
    }
  }
}

/// 静
///
/// 重绘会重
/// 全量 2600 音
/// 缓存层会让
class _ScorePainter extends CustomPainter {
  _ScorePainter({
    required this.layout,
    required this.ir,
    required this.scroll,
    required this.stringLine,
    required this.fretText,
    required this.barLine,
    required this.failedText,
    required this.pageNum,
  });

  final TabLayout layout;
  final ScoreIr ir;

  ///
  /// 不参
  final ScrollController scroll;

  final Color stringLine, fretText, barLine, failedText, pageNum;

  /// 标注线画笔（GP8 tabSlurThickness × MusicalFont 默
  /// 视
  late final Paint _markLine = Paint()
    ..color = fretText
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    // 重叠探针捕获（项目铁律「数字不重叠」规则 18）：每帧 paint 开头
    // 清空再记——缓冲内容 = 最近一帧的真实墨盒。
    TabViewDebug.lastPaintedTexts = <TabPaintedText>[];
    TabViewDebug.lastFlow = <TabFlowDebug>[];
    // 谱面排版宽（2026-11-09 gp8 对照：上限 1300px 居中，超宽容器留白）。
    final layoutWidth = TabLayout.effectiveWidth(size.width);
    final xOff = TabLayout.horizontalOffset(size.width);
    final rows = layout.rowsFor(layoutWidth);
    final measures =
        ir.tracks.isEmpty ? const <MeasureIr>[] : ir.tracks.first.measures;

    //
    // （内
    final stride = layout.rowHeight + TabLayout.rowGap;
    final scrollOffset = scroll.hasClients ? scroll.offset : 0.0;
    final viewportH =
        scroll.hasClients ? scroll.position.viewportDimension : size.height;
    final firstRow = math.max(0, (scrollOffset / stride).floor() - 1);
    final lastRow = math.min(
        rows.length - 1, ((scrollOffset + viewportH) / stride).ceil() + 1);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(xOff, scrollOffset, layoutWidth, viewportH));
    canvas.translate(xOff, 0);
    // Capo 标注（2026-11-08 gp8 截图对照；2026-11-09 用户反馈：与小节
    // 号同行放其右侧——上方会撞调弦行，原位置遮挡小节号）。
    // x 避让（2026-11-16 探针残类 "capo:3"×"1"：固定 +40 未算小节号
    // 墨宽——两位小节号右缘 26、capo 左缘 17 反向压入）→ 首小节号
    // 实测墨宽 + 2px 净空起排。
    if (ir.capo > 0 && rows.isNotEmpty) {
      final capoLabel = 'capo:${ir.capo}';
      final firstNum =
          '${ir.tracks.first.measures.first.index + 1}';
      final capoX = TabLayout.leftPad +
          TabLayout.textInkWidth(firstNum, 10) / 2 +
          2 +
          TabLayout.textInkWidth(capoLabel, 13) / 2;
      _text(
          canvas,
          capoLabel,
          Offset(capoX, layout.stringY(1, 0) - 26),
          TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
              color: pageNum));
    }
    for (var r = firstRow; r <= lastRow; r++) {
      final rowTop = layout.stringY(1, r);
      final rowBottom = layout.stringY(6, r);
      // 弦线（dsh 二轮整改：终点=排版宽右缘，宽屏 >1300 时不再伸进
      // 居中留白区）
      for (var s = 1; s <= 6; s++) {
        final y = layout.stringY(s, r);
        canvas.drawLine(Offset(TabLayout.leftPad, y),
            Offset(layoutWidth - TabLayout.leftPad, y),
            Paint()..color = stringLine);
      }
      // 小节线（2026-10-31 小节合并：measureGap=0 后相邻小节共用竖线，
      //
      // 放弃
      // 行内音流（标注弧
      final flow = <_FlowNote>[];
      for (final m in rows[r].map((idx) => measures[idx])) {
        final mx = layout.measureX(m.index, layoutWidth);
        final mw = layout.measureWidthAt(m.index, layoutWidth);
        // 结尾跳房子（标准记谱形态，参考乐理规范：**Γ 形托架**——横线
        // + 左端竖线向下（L 顺时针转 90°，29px），数字 "N." 在横线上方；
        // 横线细而清晰框住该段。2026-11-09 用户反馈：整体上移、竖线加长）。
        if (m.endings.isNotEmpty) {
          final label = m.endings.map((e) => '$e.').join('.');
          final lineY = rowTop - 40.0;
          // 左端下垂竖线（段的开始标记，下探 29px 到谱顶区）。
          canvas.drawLine(Offset(mx + 6, lineY),
              Offset(mx + 6, lineY + 29), Paint()..color = barLine);
          canvas.drawLine(Offset(mx + 6, lineY),
              Offset(mx + mw - 6, lineY), Paint()..color = barLine);
          _text(canvas, label, Offset(mx + 12, lineY - 9),
              TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: barLine));
        }
        // 小节号（谱上方
        _text(canvas, '${m.index + 1}', Offset(mx, rowTop - 26),
            TextStyle(
                fontSize: 10,
                color: pageNum,
                fontFeatures: [FontFeature.tabularFigures()]));
        // 左小节竖线；反
        //
        canvas.drawLine(Offset(mx, rowTop), Offset(mx, rowBottom),
            Paint()..color = barLine);
        if (m.repeatStart) {
          // GP8 反
          canvas.drawLine(Offset(mx - 4, rowTop), Offset(mx - 4, rowBottom),
              Paint()
                ..color = barLine
                ..strokeWidth = 3.5);
          final dot = Paint()..color = barLine;
          canvas.drawCircle(Offset(mx + 6, rowTop + 8), 2.2, dot);
          canvas.drawCircle(Offset(mx + 6, rowBottom - 8), 2.2, dot);
        }
        // 反
        if (m.repeatEnd) {
          final rx = mx + mw;
          final dot = Paint()..color = barLine;
          canvas.drawCircle(Offset(rx - 6, rowTop + 8), 2.2, dot);
          canvas.drawCircle(Offset(rx - 6, rowBottom - 8), 2.2, dot);
          canvas.drawLine(Offset(rx + 4, rowTop), Offset(rx + 4, rowBottom),
              Paint()
                ..color = barLine
                ..strokeWidth = 3.5);
        }
        if (m.failed) {
          _text(canvas, '未识别', Offset(mx + mw / 2, (rowTop + rowBottom) / 2),
              TextStyle(fontSize: 12, color: failedText));
          continue;
        }
        // 整小节空休止符（2026-11-12 用户走查）：全休止方块挂第 4 弦
        // 线下缘（gp8 记谱惯例）。**段级休止不再画**（2026-11-18 用户
        // 反馈"太影响观感"→ 尾休止小节改**按比例平铺**：音符按
        // contentBeats 铺满小节，见 TabLayout.contentBeatsOf）。
        if (m.notes.isEmpty) {
          canvas.drawRect(
              Rect.fromCenter(
                  center: Offset(mx + mw / 2,
                      layout.stringY(4, r) - TabLayout.stringGap / 2 - 2),
                  width: 7,
                  height: 3.5),
              Paint()..color = fretText);
        }
        // —— 排布（2026-11-09 回退至 7568952 稳定版：组粒度重构引发
        // 18 小节后渲染消失与大量误连线，整体撤回。两趟原逻辑保留）——
        // dup 错开（2026-11-12 全库自检 Bluebird 实锤 4 对 0px 完全
        // 叠印后引入分级错开；2026-11-16 步长改墨宽感知 + 去右界钳
        // ——满格溢出由左推趟整组左移回界内）。
        final dupSeen = <String, int>{};
        final dupLastX = <String, double>{};
        final dupLastNote = <String, NoteIr>{};
        for (final n in m.notes) {
          final nx = layout.noteX(m.index, n.beat, layoutWidth);
          final ny = layout.stringY(n.string, r);
          final key = '${n.string}@${n.beat.toStringAsFixed(3)}';
          // deco 装饰音不占拍位（2026-11-20 用户 gp8 对照实证：m4/m17
          // 的 tieE 须画在本体 10/7 **正下方同列**——装饰独立槽位在
          // 主音**左侧**，让出拍位；同弦多 deco 向左续排。gp8 精读
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
                math.max(18.0, 1.0 + _labelHalfWidth(prevN) + _labelHalfWidth(n));
            var x = seen == 0 ? nx - step : prevX - step;
            final leftBound =
                layout.measureX(m.index, layoutWidth) + TabLayout.notePad;
            if (x < leftBound) x = leftBound;
            dupLastX[key] = x;
            dupLastNote[key] = n;
            flow.add(_FlowNote(m.index, n, x, ny));
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
                1.0 + _labelHalfWidth(prevN) + _labelHalfWidth(n);
            final step = math.max(18.0, minStep);
            x = prevX + step;
          }
          dupLastX[key] = x;
          dupLastNote[key] = n;
          flow.add(_FlowNote(m.index, n, x, ny));
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
      final crowdGroups = <String, List<_FlowNote>>{};
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
      final groupsMB = <String, List<_FlowNote>>{};
      for (final fl in flow) {
        (groupsMB['${fl.mIdx}@${fl.note.beat}'] ??= []).add(fl);
      }
      groupsMB.forEach((k, g) {
        final mIdx0 = int.parse(k.split('@').first);
        final m = measures[mIdx0];
        final mx = layout.measureX(mIdx0, layoutWidth);
        // 右边界（dsh 复测 P0 整改 2026-11-11）：mIdx0 是**行末小节**时
        // measureX(mIdx0+1) 会取到下一行 col0 的 x → 整组左移出屏；
        // 行末小节的右竖线 = 行内容宽（= 行末收尾竖线 endX 同款算式）。
        final sameRowNext = mIdx0 + 1 < measures.length &&
            layout.locate(mIdx0 + 1, layoutWidth).$1 ==
                layout.locate(mIdx0, layoutWidth).$1;
        final mxNext = sameRowNext
            ? layout.measureX(mIdx0 + 1, layoutWidth)
            : TabLayout.leftPad +
                rows[r]
                    .fold<double>(0.0,
                        (s, mi) => s + layout.measureWidthAt(mi, layoutWidth));
        // 左侧保护：本小节 repeatStart、或**前一小节 repeatEnd**（其右线
        // 即本小节左线，贴线的音是本小节首音组——2026-11-09 用户反馈
        // "end 符号右侧数字依旧贴着"的根因）→ 首音组距左线 ≥22px。
        // 同行限定（dsh 二轮）：prev 在上一行末时 end 符号画在上行末线，
        // 本行左线无标记，不做 +22 推移。
        final prevEnd = mIdx0 > 0 &&
            measures[mIdx0 - 1].repeatEnd &&
            layout.locate(mIdx0 - 1, layoutWidth).$1 ==
                layout.locate(mIdx0, layoutWidth).$1;
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
      final firstM = rows[r].first;
      final minBeatFirst = flow
          .where((fl) => fl.mIdx == firstM)
          .map((fl) => fl.note.beat)
          .fold<double?>(null, (acc, b) => acc == null || b < acc ? b : acc);
      if (minBeatFirst != null) {
        final headGroup =
            crowdGroups['$firstM@${minBeatFirst.toStringAsFixed(3)}'];
        if (headGroup != null) {
          final mxFirst = layout.measureX(firstM, layoutWidth);
          final minInk = headGroup
              .map((f) => f.x - _labelHalfWidth(f.note))
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
          layout.measureX(mIdx, layoutWidth) +
          layout.measureWidthAt(mIdx, layoutWidth) -
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
      final crowdByString = <int, List<_FlowNote>>{};
      final crowdIdxOf = <_FlowNote, int>{};
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
      // 与主音前的音贴 3.6px）；gp8 同款形态（grace 紧贴主音左）。
      // **串版本**（四轮探针 3706 处实证）：串内从主音往左依次排位，
      // 相邻 grace 净空 1px。
      // **谱级门**（时间.gp3 实证）：grace 占比 >25% 的谱（转换器
      // 产物全谱标志）gp8 按 slash 正常音排布——不挂靠、不跳链。
      // **趟序（2026-11-18 定案：拥挤链趟之前）**——挂靠让位（主音
      // 右移）后再跑链，链以让位后位置为基准把后继推开（m12 实证：
      // 链在挂靠前跑 → 让位挤后继 8.3px 无再平衡 → 违例；布局层
      // rowOverfull 的链模拟已含挂靠起点钳制口径，渲染趟序对齐后
      // 两层一致——规则 22）。
      if (!layout.graceAsNormal) {
        // 已挂靠处理的 grace（并组 + 主音让位完成；旧独立钳制趟不得
        // 再回顶挂靠位——m2 dist=-0.7 压死的第二推手）。
        final attached = <_FlowNote>{};
        for (final list in crowdByString.values) {
          var pending = <_FlowNote>[]; // 顺拍序累积的 grace 串
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
            var rightHalf = _labelHalfWidth(fl.note);
            for (final g in pending.reversed) {
              final gx = xRight -
                  1.0 -
                  _labelHalfWidth(g.note) -
                  rightHalf;
              g.x = gx;
              xRight = gx;
              rightHalf = _labelHalfWidth(g.note);
            }
            // **挂靠原子绑定**（2026-11-18 m2 `<12>`×`2` dist=-0.7 压死
            // 实证）：钉位空间不足（挂靠位越左线被钳回）时旧模型只钳
            // grace 不动主音 → grace 被顶到主音位上；且 grace 不在主音
            // 组里，左推趟整组移动会甩下它。gp8 语义 = grace 是主音的
            // 附属：①grace 并入主音同拍组（后续整组移动原子联动）；
            // ②钳制冲突时主音组右移让位（bound 限幅右界-5-组右墨缘，
            // 空间不足移部分，残余进探针可见）；③同拍对齐不受影响
            // （grace 是挂靠音，本来就不要求同拍对齐）。
            final gkey = '${fl.mIdx}@${fl.note.beat.toStringAsFixed(3)}';
            final gList = crowdGroups[gkey]!;
            final mxL = layout.measureX(fl.mIdx, layoutWidth);
            final mw = layout.measureWidthAt(fl.mIdx, layoutWidth);
            final mainHalf = _labelHalfWidth(fl.note);
            // ② 先让位：钳制冲突时主音组右移（grace 尚未入组——并组后
            // 再移会带着 grace 一起移，相对位不变，白移）。bound 限幅
            // 右界-5-组右墨缘（不含 grace；空间不足移部分，残余进探针
            // 可见）。
            var needShift = 0.0;
            for (final g in pending) {
              final ink = _labelHalfWidth(g.note);
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
                    math.max(gMaxInk, f2.x + _labelHalfWidth(f2.note));
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
              final ink = _labelHalfWidth(g.note);
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
          final mxL = layout.measureX(fl.mIdx, layoutWidth);
          final mw = layout.measureWidthAt(fl.mIdx, layoutWidth);
          final ink = _labelHalfWidth(fl.note);
          final lo = mxL + 5 + ink;
          final hi = math.max(lo, mxL + mw - 5 - ink);
          fl.x = fl.x.clamp(lo, hi).toDouble();
        }
      }
      for (final k in crowdOrder) {
        final g = crowdGroups[k]!;
        var delta = 0.0;
        for (final f in g) {
          if (f.note.grace && !layout.graceAsNormal) {
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
              1.0 + _labelHalfWidth(prevN) + _labelHalfWidth(f.note);
          final idx = crowdIdxOf[f]!;
          // 拍序前驱为 grace 串（连续 k 个，挂靠到 f 左侧）→ gap 按
          // 串总宽加大：主音 ≥ 前音右缘+1 + [1+2ΣgH+(k-1)] + 串宽，
          // 保证串插入后左右净空 ≥1px（推导见 rowOverfull 同款公式；
          // 2026-11-17 四轮探针）。graceAsNormal 时 grace 当普通音，
          // 不加大。
          final list = crowdByString[f.note.string]!;
          if (!layout.graceAsNormal) {
            var k = 0;
            var sumGH = 0.0;
            var j = idx - 1;
            while (j >= 0 && list[j].note.grace) {
              k++;
              sumGH += _labelHalfWidth(list[j].note);
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
          if (f.note.grace && !layout.graceAsNormal) {
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
      final groupKeyOf = <_FlowNote, String>{};
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
      final byStringTime = <int, List<_FlowNote>>{};
      final stringIndexOf = <_FlowNote, int>{};
      for (final fl in sweepOrder) {
        final list = byStringTime.putIfAbsent(fl.note.string, () => []);
        stringIndexOf[fl] = list.length;
        list.add(fl);
      }
      void shiftGroupLeft(List<_FlowNote> g, double d) {
        final mx = layout.measureX(g.first.mIdx, layoutWidth);
        var cap = double.infinity;
        for (final f in g) {
          cap = math.min(
              cap, f.x - _labelHalfWidth(f.note) - (mx + 5));
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
              1.0 + _labelHalfWidth(p.note) + _labelHalfWidth(f.note);
          final dist = (f.x - p.x).abs();
          if (dist >= gap) continue;
          shiftGroupLeft(crowdGroups[pk]!, gap - dist);
        }
      }
      // 【撤】时序保趟（2026-11-18 四版试错定论：7030/972/896/163——
      // 波及/钳界各引入新形态，三难[时序单调+墨净空+窄行容量]非趟式
      // 补丁可解，根治 = 排布模型整体升级[布局层时序口径→折行减密度]，
      // 与 CLAUDE.md「小节线保护」同批债）。倒置改由链趟时序上限单点
      // 修复（见链趟内注释）；近同列（正序 dx<4）为窄行/gp8 泛音链
      // 形态，探针计数记档不判罚。
      // Tap 短弧（2026-11-19 用户定案 + gp8 m1-m3 像素级读图裁决：
      // LeftHandTapView.slur 字段 = **每处 tap 自带短弧**，从左邻紧邻
      // 音（含 grace）连向 tap 音——"连结弧画在 grace 右上跨间隙接
      // 到主音左上，走字形上方空档"）。T 挪谱顶后 y-14 弧带 = 原 T
      // 位置。条件：**右端是 tap**（gp8 弧向 = 连向 tap 收弧；旧版
      // "至少一端 tap"连 tap→后音方向错 + 单发 tap 铺满行——11-12
      // 用户实锤；"两端都 tap"又把 grace→tap 主弧丢了——本轮用户
      // "原有 T 位置出现连音符号，这个没有"实锤）。拍距 ≤0.25 + 同
      // 弦紧邻（flowByTime 相邻对）——m40-43 的 0.5 拍距 tap 不连。
      // 层级（dsh 二轮 P1 整改 2026-11-11）：随标注层画在文字底下——
      // 弧 y-14~-19 与上弦数字带相交段由文字层覆盖；排序加弦号/x
      // 决胜（Dart sort 非稳定，同拍相邻对须确定）。
      final flowByTime = List.of(flow)..sort((a, b) {
        final c = a.mIdx.compareTo(b.mIdx);
        if (c != 0) return c;
        final cb = a.note.beat.compareTo(b.note.beat);
        if (cb != 0) return cb;
        final cs = a.note.string.compareTo(b.note.string);
        return cs != 0 ? cs : a.x.compareTo(b.x);
      });
      for (var i = 1; i < flowByTime.length; i++) {
        final cur = flowByTime[i], prev = flowByTime[i - 1];
        if ((cur.note.beat - prev.note.beat) > 0.25 + 1e-9) continue;
        if (!cur.note.tap) continue; // 右端 tap（弧连向 tap 收弧）
        if (cur.note.string != prev.note.string) continue; // 同弦（跨弦
        // 斜弧视觉近乎竖线，满屏干扰——2026-11-09 用户反馈去除；gp8
        // 的跨弦连线（4^0）为个例，规则待更多样本）。
        final left = prev, right = cur;
        final y0 = left.y - 14, y1 = right.y - 14;
        final x0 = left.x + _labelHalfWidth(left.note) + 1;
        var x1 = right.x - _labelHalfWidth(right.note) - 1;
        if (x1 - x0 < 4) x1 = x0 + 4; // 最小可见弧宽
        final arc = Path()
          ..moveTo(x0, y0)
          ..quadraticBezierTo(
              (x0 + x1) / 2, math.min(y0, y1) - 5, x1, y1);
        canvas.drawPath(arc, Paint()..color = fretText..strokeWidth = 1.2
          ..style = PaintingStyle.stroke);
      }
      _paintMarks(canvas, flow, rowTop, rowBottom, layoutWidth);
      // 探针音流镜像（残类定位用；纯记录，生产零行为差异）。
      TabViewDebug.lastFlow
          .addAll(flow.map((f) => TabFlowDebug(f.mIdx, f.note, f.x, f.y)));
      // 文字层（
      // T 椭圆同拍去重状态（和弦 tap 群一个 T）+ 相邻拍合并游标。
      final tapTDrawn = <String>{};
      double? lastTapTx;
      for (final fl in flow) {
        final n = fl.note;
        // 闷击（gpif Muted）：GP8
        // ghost（AntiAccent）：
        // tie
        // 击勾
        final String label;
        // label 构造唯一事实源 = TabLayout.tabLabel（与 inkHalf 共用，
        // 口径漂移即重叠——2026-11-16 探针实证教训）。泛音尖括号 `<12>`
        // 为 gp8 同款（2026-11-08 截图对照）。
        label = TabLayout.tabLabel(n);
        if (label.isNotEmpty) {
          _text(canvas, label, Offset(fl.x, fl.y),
              TextStyle(
                  fontSize: n.grace ? 10 : 14,
                  fontStyle: n.grace ? FontStyle.italic : FontStyle.normal,
                  fontWeight: n.grace ? FontWeight.w500 : FontWeight.w600,
                  color: fretText,
                  fontFeatures: [FontFeature.tabularFigures()]));
        }
        //
        // 早期 H 角标）；点弦 T 在数字
        // h/p/s/b 字母保持右上角（gpx 通道由弧
        // 泛音尖括号已并入数字 label（gp8 同款）；点弦 T = 椭圆圈 T
        //（2026-11-18 gp8 实测 LAS m33-38 裁决：六线谱有椭圆 (T)——
        // 推翻 11-08 "六线谱无 T" 判断；spec P1 LeftHandTapView decomp
        // 证据 + LAS LeftHandTapped×35 双证，弧上无字母）。
        // 人工泛音 AH 文字（gp8 同款，第 7 小节截图实锤）。
        if (n.harmonicType == 'artificial') {
          _text(canvas, 'AH', Offset(fl.x, fl.y - 13),
              TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: fretText));
        }
        if (n.tap) {
          // 椭圆 T 在**六线谱顶部**（2026-11-19 用户 LSA 原谱观察定案：
          // gp8 的 T 全部标在谱顶带，水平对齐 tap 音 x）——音上 y-13
          // 带留给连音标识（弧线/H/P）；音头顶实现压邻弦（m18 6 弦 T×
          // 5 弦音重叠：y-13 恰是 5 弦线）。
          // y = rowTop-30（rowTop 是 **1 弦线 y**——+8 会掉进 1/2 弦
          // 数字区压数字，52 处违例实证）：1 弦上 30px 独立带，与
          // L.R./P.M. 标签带（rowTop-15）净空 15px、与 H/P 字母带
          // （rowTop-17）dy=13 且 x 随 tap 音（tap×hopo 同 x 罕见，
          // 探针兜底）。
          // 同拍去重：和弦 tap 群（同拍多 tap 音）只画一个 T——
          // 逐音各画会同 x 叠死（m18/m35 (T)×(T) dx=0 实证）。
          final tapKey = '${fl.mIdx}@${n.beat.toStringAsFixed(3)}';
          if (tapTDrawn.add(tapKey)) {
            var tx = fl.x;
            // 小节号 x 避让（y 同带：小节号 rowTop-26 半宽按实测墨宽，
            // T 中心距小节号中心 < 半宽和+2 → 右移到小节号右缘+2；
            // m76/m78 (T)×"76" dx=10 实证）。
            final barNoHalf =
                TabLayout.textInkWidth('${fl.mIdx + 1}', 10) / 2;
            final mx = layout.measureX(fl.mIdx, layoutWidth);
            if ((tx - mx).abs() < barNoHalf + 8.5) {
              tx = mx + barNoHalf + 8.5 + 2;
            }
            // 相邻拍 T 合并（拍距 < 14px 的相邻 tap 只画一个——
            // gp8 密集区一个 T 代表一组；m58 dx=8.2/9.6 实证）。
            final merged =
                lastTapTx != null && (tx - lastTapTx).abs() < 14;
            if (!merged) {
              lastTapTx = tx;
              final c = Offset(tx, rowTop - 30);
              canvas.drawOval(
                  Rect.fromCenter(center: c, width: 13, height: 10),
                  Paint()
                    ..color = fretText
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 1.0);
              _text(canvas, 'T', c,
                  TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: fretText));
              // 椭圆盒替换文字盒（同中心双登记自撞——T×(T) 教训）：
              // 椭圆 13×10 为视觉真盒。
              if (TabViewDebug.lastPaintedTexts.isNotEmpty &&
                  TabViewDebug.lastPaintedTexts.last.text == 'T') {
                TabViewDebug.lastPaintedTexts.removeLast();
              }
              TabViewDebug.lastPaintedTexts.add(
                  TabPaintedText('(T)', c.dx, c.dy, 6.5, 5.0));
            }
          }
        }
        // 轻量标注
        // 在数字上方（GP8 位置），颤音 tr 右上角，装饰音小号斜体数字
        if (n.accent) {
          _text(canvas, '>', Offset(fl.x, fl.y - 12),
              TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fretText));
        }
        if (n.staccato) {
          // 同音符带 accent（>）时点右移 8px（2026-11-16 全量探针
          // 232 处实证：两标注同画 y-12 完全同位重叠；gp8 双标注
          // 错位排布，点偏离音符 x 但层级仍在音符上方）。
          final dotDx = n.accent ? 8.0 : 0.0;
          TabViewDebug.lastPaintedTexts.add(
              TabPaintedText('·断音', fl.x + dotDx, fl.y - 12, 2, 2));
          canvas.drawCircle(
              Offset(fl.x + dotDx, fl.y - 12), 2, Paint()..color = fretText);
        }
        if (n.trill) {
          _text(canvas, 'tr', Offset(fl.x + 10, fl.y - 8),
              TextStyle(
                  fontSize: 9,
                  fontStyle: FontStyle.italic,
                  color: pageNum));
        }
        final tech = n.technique;
        if (tech != null && tech != 'x' && tech != 'H') {
          _text(canvas, tech, Offset(fl.x + 9, fl.y - 8),
              TextStyle(fontSize: 9, color: pageNum));
        }
      }
      // 行末收尾竖线（最后一小节的右边界）。
      // 2026-11-12 修复 Flower m39 双点：旧代码在此对 lastM.repeatEnd
      // 再画一遍「粗线 + 外侧点对（endX+10）」，与上方 per-measure
      // repeatEnd 块（内侧点对 rx-6 + 粗线 rx+4）叠加 = 4 点。gp8
      // 反复终止形态仅内侧一对点；行末细线（本线）+ 粗线（per-measure
      // 块）即完整「细|粗」形态，行末块整体删除。
      final lastMeasure = rows[r].last;
      final endX = layout.measureX(lastMeasure, layoutWidth) +
          layout.measureWidthAt(lastMeasure, layoutWidth);
      canvas.drawLine(Offset(endX, rowTop), Offset(endX, rowBottom),
          Paint()..color = barLine);
    }
    canvas.restore();
  }

  /// 标注绘制层（2026-10-31 GP8 标注补齐）：
  /// - 琶音/
  /// - tie/击勾
  /// - 定滑
  /// - 延音 L.R. / 闷音 P.M.
  ///   走查
  void _paintMarks(Canvas canvas, List<_FlowNote> flow, double rowTop,
      double rowBottom, double rowWidth) {
    // rowWidth = 排版宽 layoutWidth（dsh 复测 P1 整改 2026-11-11：此前传
    // size.width，宽屏 >1300 时与 flow 坐标系错位——noteX/measureX 都
    // 依赖 maxWidth，超宽下行宽变化、拍距拉长）。
    final endX = rowWidth - TabLayout.leftPad;
    final line = _markLine;
    // 小节竖线 x 集（字母避让用；每行构建一次，替代逐弧重建）。
    final barXs = {
      for (final g in flow) layout.measureX(g.mIdx, rowWidth)
    };
    // 行级标注去重/避让状态（重叠探针 3134 处实证，2026-11-16）：
    // 力度带仅变化才画；谱上方 L.R./P.M. 共用带（rowTop-15）标签避让。
    String? lastDynamic;
    double? lastDynCx;
    double? lastDynHalf;
    // band 标签**候选**预收集（重叠探针实证 H×L.R. 残类：主循环按
    // flow 序画标签，hopoStart 音先于 letRing 段头时 bandLabelXs 尚空
    // → 字母避让扑空。改为循环前预收集全部段头候选——H/P 字母避让
    // 与绘制顺序无关；实际绘制再按 bandPaintedXs 贪心去重）。
    final bandLabelXs = <double>[];
    final bandPaintedXs = <double>[];
    // 1 弦 accent（>）x 集（全量探针 82 处实证：1 弦音的 accent 带
    // y-12 与 L.R./P.M. 标签带 rowTop-15 同层，dy 3 → 重叠；标签是
    // 注记，撞则让位，虚线仍画）。
    final rowTopAccentXs = <double>[];
    // 1 弦断音点（·）x 集（2026-11-19 桶2 探针 2 处实证：《姑娘》
    // P.M.×断音——11-16 accent 右移修复后点仍与顶带标签同层互撞；
    // 点属音符不动，标签让位。dotDx 与 accent 同款右移口径）。
    final rowTopStaccatoXs = <double>[];
    // 已画击勾弦字母盒（全量探针 22 处实证：连串 hopo 各段字母互撞
    // ——occupied 只查数字盒没查字母盒）。
    final paintedLetters = <({double x, double y})>[];
    for (var i = 0; i < flow.length; i++) {
      final fn = flow[i];
      final prevSame = i > 0 ? _prevSameString(flow, i) : null;
      if (fn.note.letRing && prevSame?.note.letRing != true) {
        bandLabelXs.add(fn.x + 16);
      }
      if (fn.note.palmMute && (i == 0 || !flow[i - 1].note.palmMute)) {
        bandLabelXs.add(fn.x + 16);
      }
      if (fn.note.accent && fn.y <= rowTop + 1) {
        rowTopAccentXs.add(fn.x);
      }
      if (fn.note.staccato && fn.y <= rowTop + 1) {
        rowTopStaccatoXs.add(fn.x + (fn.note.accent ? 8.0 : 0.0));
      }
    }
    // 音流序扫描：每个标注音找同弦/连续终点
    for (var i = 0; i < flow.length; i++) {
      final f = flow[i];
      final n = f.note;
      final nextSameString = _nextSameString(flow, i);
      // 孤立小弧修复（2026-11-12 用户走查 m4）：next==null = 标注终点
      // 跨行（同弦后继不在本行）——旧代码回退 f.x+22 画短段悬空。
      // gp8 跨行形态：段延伸到行末竖线收尾。slide 斜线（clipped）同款。
      final x1 = nextSameString?.x ?? (endX - 5); // 无后继：延伸到行末
      // clamp 防御（2026-11-10 Flower "只有一行"根因）：行末音 f.x+8
      // 可能 > endX，clamp(min>max) 抛 ArgumentError 中断整个 paint——
      // 后续行全部不画。先保序再夹。
      final lo = math.min(f.x + 8, endX);
      final clipped = x1.clamp(lo, math.max(lo, endX));

      // —
      // gpif Beat 层编码：<Arpeggio>Up|Down</Arpeggio>、Brush/PickStroke
      // Direction（Like A Star 实测）
      // 拨片=音
      if (n.arpeggio != null || n.brush != null || n.pickStroke != null) {
        final isGroupHead = i == 0 ||
            flow[i - 1].mIdx != f.mIdx ||
            flow[i - 1].note.beat != n.beat;
        if (isGroupHead) {
          // 同拍音群（跨声部）：y 范围 = 群内
          var yMin = f.y, yMax = f.y, xMin = f.x;
          var ownHalf = _labelHalfWidth(n);
          for (final g in flow) {
            if (g.mIdx == f.mIdx && g.note.beat == n.beat) {
              yMin = math.min(yMin, g.y);
              yMax = math.max(yMax, g.y);
              xMin = math.min(xMin, g.x);
              ownHalf = math.min(ownHalf, _labelHalfWidth(g.note));
            }
          }
          final span = math.max(yMax - yMin, TabLayout.stringGap.toDouble());
          // 竖标 x：音群左
          // 走查：拍
          // 竖标 x：音群左（2026-11-09 用户反馈：距小节竖线太近难辨认
          // ——4px → 18px）。
          final barX = layout.measureX(f.mIdx, rowWidth);
          // 竖标 x（2026-11-18 用户实证 Prologue 整行左压回退）：默认
          // 音群左 14px；落入前列数字盒时在**前列墨缘与本列数字左缘
          // 的窄缝取中**（gp8 杆居列间窄缝同款——数字窄+杆细无需让
          // 位；gap+12 让位方案致扫弦谱整行左压已回退）。
          var prevInkRight = double.negativeInfinity;
          for (final g in flow) {
            if (g.x < xMin - 0.5) {
              prevInkRight = math.max(
                  prevInkRight, g.x + _labelHalfWidth(g.note));
            }
          }
          const wing = 3.0;
          var x = math.max(xMin - 14, barX + 4);
          if (prevInkRight.isFinite) {
            final rodMin = prevInkRight + 1 + wing;
            final rodMax = xMin - ownHalf - 1 - wing;
            if (x < rodMin || x > rodMax) {
              x = ((prevInkRight + 1) + (xMin - ownHalf - 1)) / 2;
            }
          }
          // 小节归属铁律（2026-11-18 用户实证 Promise：组在小节首拍时
          // 取中点落进前一小节地盘）→ 杆下限 = 本小节左线右 1+翼。
          x = math.max(x, barX + 1 + wing);
          if (n.arpeggio != null) {
            // 杆底收回到最后一弦下 4px（2026-11-17 图 1 用户实证：底端
            // +6 的箭头尖侵入末弦数字带叠压 0）。
            _wavyLine(canvas, x, yMin - 6, yMin - 6 + span + 10,
                up: n.arpeggio == 'up');
          } else if (n.brush != null) {
            _arrowLine(canvas, x, yMin - 6, yMin - 6 + span + 10,
                down: n.brush == 'down');
          }
          // Beat 级文字三件（2026-11-02 GP8 对照）：力度/淡入
          // 行底区（真实行底 = 底弦 + bottomPad(20)，再 +6 进空隙带；
          // 2026-11-16 重叠探针实证：旧 rowBottom+6 的 rowBottom 是
          // 底弦 y——mf 带压底弦数字带 3px）。
          // 力度去重（gp8 语义：一次力度标注只画一次）：仅当与本行
          // 上一个已画力度不同才画——数据层每音重复携带同一力度，
          // 逐拍重画导致 mf×mf 相撞 + 同组双画（探针 3134 实证）。
          // 行底带游标（2026-11-16 探针残类）：同拍双标注（fff×
          // fade in）固定偏移互压 → 前者实测墨宽推游标；fade in/Wah
          // 改段头去重（数据层逐音携带 → 同段 7 连撞，与力度同病）。
          var bandX = x + 14.0;
          if (n.dynamicMark != null && n.dynamicMark != lastDynamic) {
            lastDynamic = n.dynamicMark;
            final dynHalf = TabLayout.textInkWidth(n.dynamicMark!, 11) / 2;
            var cx = bandX;
            // 行级游标（全量探针 14 处实证：相邻两个力度变化标注同带
            // 重叠——同音符内堆叠有 bandX，跨音符的相邻力度没有）。
            final ldCx = lastDynCx;
            final ldHalf = lastDynHalf;
            if (ldCx != null &&
                ldHalf != null &&
                cx - dynHalf < ldCx + ldHalf + 1) {
              cx = ldCx + ldHalf + 1 + dynHalf;
            }
            _text(canvas, n.dynamicMark!, Offset(cx, rowBottom + 26),
                TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    color: fretText));
            lastDynCx = cx;
            lastDynHalf = dynHalf;
            bandX = cx + dynHalf + 2;
          }
          if (n.fadding != null &&
              (i == 0 || flow[i - 1].note.fadding != n.fadding)) {
            final fadeLabel = n.fadding == 'in' ? 'fade in' : 'fade out';
            final fadeHalf = TabLayout.textInkWidth(fadeLabel, 9) / 2;
            _text(canvas, fadeLabel, Offset(bandX + fadeHalf, rowBottom + 26),
                TextStyle(
                    fontSize: 9,
                    fontStyle: FontStyle.italic,
                    color: fretText));
            bandX += fadeHalf * 2 + 2;
          }
          if (n.wah && (i == 0 || !flow[i - 1].note.wah)) {
            _text(canvas, 'Wah', Offset(bandX + 7, rowBottom + 26),
                TextStyle(fontSize: 9, fontStyle: FontStyle.italic, color: fretText));
          }
          if (n.pickStroke != null && n.brush == null) {
            // 拨片方向小箭头（2026-11-17 图 3 用户实证：扫弦杆自带
            // 端点箭头，顶上再画拨片小 V = 方向指示重复——gp8 的 TAB
            // 层不单独画拨片方向；brush 存在时省略，数据保留）。
            final cy = yMin - 16;
            final path = Path()
              ..moveTo(x - 4, n.pickStroke == 'down' ? cy - 4 : cy + 4)
              ..lineTo(x, cy)
              ..lineTo(x + 4, n.pickStroke == 'down' ? cy - 4 : cy + 4);
            canvas.drawPath(path, _markLine);
          }
        }
      }

      // —
      // 弧线（2026-11-12 晚二轮收敛，用户两轮回馈定案）：**弧该画——
      // 延音（tie）/击勾（hopo）/连滑（legato）都画**（用户走查月下
      // 之恋时弧是"该有"的——延音弧是记谱必需）；砍的只是**超长弧**
      // （用户 gp8 对照"没有"的是 2+ 拍长弧与跨行延伸弧）。一轮收紧
      // 版（tie 类型级停画 + 0.5 拍阈值）误杀大量本该有的小连音弧
      // （用户复测实锤"很多本该有的小连音弧都没有了"），二轮放宽：
      // ①tie/hopo/legato 全恢复画②拍距 **>1.5 拍**不画（跨小节累计
      // 拍数：保月下 40 条 1 拍 tie + Distance 0.5-1 拍弧 + 0.25 拍跨
      // 小节短 tie；砍 2+ 拍与 3.5 拍跨小节长弧）③终点跨行（next==
      // null）不画（"延伸到行末"规则作废——超长弧主源）。
      // 几何（2026-11-12 用户定案）：**画在数字头部上方**——端点 y-10
      // （数字带 ±8 → 顶部 y-8，净空 2px）、控制高 6 → 拱顶 ≈y-14.5。
      if (n.tieStart || n.hopoStart || n.legatoStart) {
        final next = nextSameString;
        // 纯延音 tie（非 hopo/legato）弧线门（gp8 判定复刻，spec §2.2
        // /§2.3）：**tieEnd 端数字可见（锚点符号或小节首拍）且同小节**
        // 才画——origin 端数字天然显示（tabLabel 的 tie 隐藏只作用于
        // tieEnd 延续音中段，普通音全显示；LAS m34 gp8 实测 2→(2) 的
        // origin 无符号照画弧实证）。数字隐藏（长链中段延续音）→ 弧随
        // 之消失（Prologue 190 tie TAB 弧≈0 实证；2026-11-19 回滚上轮
        // "全解耦"误改——解耦版致 Prologue/Promise 满屏弧）；跨小节
        // 不画（TabTiedGroups 按小节分桶）。
        // hopo/legato 弧不受此门（HoPoSlurView 独立类，gp8 TAB 照画）。
        // 2026-11-19 逐弧实证定案（121 例零反例）：**TAB 行从不画 tie
        // 弧**（弧只在五线谱行；TAB 上方仅装饰音 "sl" 弧）——pureTie
        // 弧恒不画；装饰音连接弧走 slide='shift' 的 sl 弧路径（独立）。
        final pureTie = n.tieStart && !n.hopoStart && !n.legatoStart;
        final tieArcAllowed = !pureTie;
        // 拍距（跨小节累计）：>1.5 拍的超长配对不画（用户 gp8 对照）。
        // next==null（终点跨行）必然远 → 同样不画。纯 tie 弧已过
        // tieArcAllowed 门（同小节+数字可见），不再受拍距限制
        //（spec §2.3 判据 = 音高相等链内相邻对）。
        var shortRange = false;
        if (next != null) {
          if (pureTie) {
            shortRange = tieArcAllowed;
          } else {
            var beatDist = 0.0;
            for (var mi = f.mIdx; mi < next.mIdx; mi++) {
              beatDist += layout.beatsOfBar(mi);
            }
            beatDist += next.note.beat - n.beat;
            shortRange = beatDist <= 1.5 + 1e-9;
          }
        }
        // clamp 防御（同 547：行末音 f.x+8 > endX 会抛 ArgumentError
        // 中断 paint）——先保序再夹。shortRange 必有 next（上方已判）。
        if (shortRange && next != null) {
        final xEnd = next.x.clamp(math.min(f.x + 8, endX),
                math.max(math.min(f.x + 8, endX), endX))
            .toDouble();
        final yBase = next.y;
        const dip = -10.0;
        // 拱顶公式 dip−0.75h（三次贝塞尔中点）：h=6 → 拱顶 y-14.5。
        const h = 6.0;
        final dx = (xEnd - f.x).abs().toDouble();
        final inset = math
            .max(0.05 * dx, 0.36 * dx * math.exp(-0.0144 * dx))
            .clamp(0.0, dx / 3);
        final path = Path()
          ..moveTo(f.x, f.y + dip)
          ..cubicTo(f.x + inset, f.y + dip - h, xEnd - inset,
              yBase + dip - h, xEnd, yBase + dip);
        canvas.drawPath(path, line);
        // 击勾弦字母：品升 H / 品降 P（连滑音弧线无字母，GP8 同款）。
        // 仅终点在本行（next!=null）时画——跨行弧终点品未知，H/P 判向
        // 无依据（2026-11-12 孤立小弧修复）。
        // gp8 实测政策：小字号（明显小于数字）+ 垂直≈上一弦线高度
        // （y-17：gp8 基准 y-19 下移 2px——同拍相邻弦都有 hopo 时上一
        // 弦弧顶（-22~-24）正好穿过 y-19 字母带（golden 探针实锤），
        // 下移后与弧顶净空 ≥2px 且不触自己弧顶）+ 水平卡进数字间空档
        // ——fs7，水平避让数字/AH 盒与小节竖线（中点优先 3px 步进，
        // 全占回退中点）。
        if (n.hopoStart) {
          const letterHalfW = 3.5, letterHalfH = 3.0;
          const dip2 = -17.0;
          final ly = f.y + dip2;
          // 占用判定（2026-11-16 探针残类 H×7/H×9：两位数字间零空隙，
          // 上带全占回退中点=压数字 → 重构为 ly 参数化，供弧下带复用）。
          bool occupied(double x, double lyTry) {
            if (x < f.x - 2 || x > xEnd + 2) {
              return true; // 字母留在本弧跨度附近（不甩出弧外）
            }
            if (x - letterHalfW < TabLayout.leftPad + 4 ||
                x + letterHalfW > endX - 5) {
              return true; // 行首/行末保护（布局铁律：不贴竖线）
            }
            for (final bl in barXs) {
              if ((bl - x).abs() < letterHalfW + 5) return true;
            }
            for (final g in flow) {
              final gn = g.note;
              final hw = _labelHalfWidth(gn) + 1;
              if (x + letterHalfW > g.x - hw &&
                  x - letterHalfW < g.x + hw &&
                  lyTry + letterHalfH > g.y - 6 &&
                  lyTry - letterHalfH < g.y + 6) {
                return true; // 数字盒
              }
              if (gn.harmonicType == 'artificial' &&
                  x + letterHalfW > g.x - 10 &&
                  x - letterHalfW < g.x + 10 &&
                  lyTry + letterHalfH > g.y - 18 &&
                  lyTry - letterHalfH < g.y - 8) {
                return true; // AH 盒
              }
              if (gn.accent &&
                  x + letterHalfW > g.x - 4.2 &&
                  x - letterHalfW < g.x + 4.2 &&
                  lyTry + letterHalfH > g.y - 16 &&
                  lyTry - letterHalfH < g.y - 8) {
                return true; // accent 盒（全量探针 P/H×> 87 处实证：
                // 字母带 y-17 与 accent y-12 半高 4 重叠）
              }
            }
            // 已画字母盒（连串 hopo 各段字母互撞——2026-11-16 全量
            // 探针 P×H/H×P 22 处实证）。
            for (final pl in paintedLetters) {
              if ((x - pl.x).abs() < 3.5 + letterHalfW &&
                  (lyTry - pl.y).abs() < 3.0 + letterHalfH) {
                return true;
              }
            }
            // L.R./P.M. 上带标签（重叠探针实证：1 弦 hopo 字母与
            // rowTop-15 带的 L.R./P.M. 同层互撞）。
            for (final bx in bandLabelXs) {
              if ((x - bx).abs() < 18 + letterHalfW &&
                  (lyTry - (rowTop - 15)).abs() < 6) {
                return true;
              }
            }
            return false;
          }

          final mid = (f.x + xEnd) / 2;
          var lx = mid;
          var lyFinal = ly;
          var found = false;
          // 上带搜索（中点优先 3px 步进）。
          for (var s = 0; s <= 10 && !found; s++) {
            if (!occupied(mid + s * 3.0, ly)) {
              lx = mid + s * 3.0;
              found = true;
            } else if (!occupied(mid - s * 3.0, ly)) {
              lx = mid - s * 3.0;
              found = true;
            }
          }
          if (!found) {
            // 弧下带回退（f.y+12：位于下一弦数字带上方——occupied 同款
            // 数字盒检查兜底，实压则判占）。AH/band 检查对下带天然失配
            // （均为上带区间），不误伤。
            final ly2 = f.y + 12.0;
            for (var s = 0; s <= 10 && !found; s++) {
              if (!occupied(mid + s * 3.0, ly2)) {
                lx = mid + s * 3.0;
                lyFinal = ly2;
                found = true;
              } else if (!occupied(mid - s * 3.0, ly2)) {
                lx = mid - s * 3.0;
                lyFinal = ly2;
                found = true;
              }
            }
          }
          if (found) {
            // 全占放弃字母（2026-11-16 铁律优先：绝不压数字——弧线仍在，
            // 只丢 H/P 方向注记；旧回退中点画法探针实证 2 处压数字）。
            final dest = next.note;
            final letter = dest.fret > n.fret ? 'H' : 'P';
            _text(canvas, letter, Offset(lx, lyFinal),
                TextStyle(fontSize: 7, color: fretText));
            paintedLetters.add((x: lx, y: lyFinal));
          }
        }
        } // shortRange && next != null
      }

      // —
      // GP8 slide 参数族（slideYIntercept/slideHeight/slideThickness）：
      // 2026-11-17 图 2 用户实证（贝司四线谱滑音组）：水平线+右向箭头
      // 头改为 **gp 同款短斜杠 + "sl." 文字**（spec §5 P1 遗留"slide
      // 缺 sl 文字"一并完成）；斜向按品升降：升滑 "/"、降滑 "\"。
      if (n.slide == 'shift') {
        // 同行斜曲线（2026-11-18 用户反馈：直线偏上、要斜曲线——gp8
        // 的 slide 本为轻微弧线（slideYIntercept/slideHeight 参数族）：
        // **中点过弦线**、两端 ±4px（跨在音对间隙中，与数字缘净空
        // ≥1.8px）；二阶贝塞尔实现，曲线中点恰落在弦线上）。
        // **纯 TAB 不画 "sl." 文字**（2026-11-18 探针 2 处实证：sl.
        // 无论放上带/下带均与某层标注互撞——上弦数字带/下弦 accent/
        // 本弦数字；gp8 的 sl. 属五线谱记谱层，TAB 层为纯斜线——
        // spec §5"slide 缺 sl"按记谱层口径关闭）。
        final up = (nextSameString?.note.fret ?? n.fret) > n.fret;
        final dy = up ? 4.0 : -4.0;
        final Path path;
        if (nextSameString != null) {
          final mid = (f.x + clipped) / 2;
          path = Path()
            ..moveTo(mid - 3, f.y + dy)
            // 控制点在弦线上方 dy 处（离开弦线——首版控制点与两端点
            // 共线曲率恒零，用户实测"依旧斜直线"实锤）→ 曲线中点弓出
            // 弦线 0.5dy，滑音手势（起步抬升-后段趋平）。
            ..quadraticBezierTo(mid, f.y - dy, mid + 3, f.y - dy);
        } else {
          // 跨行/无后继：长弧延伸到行末收尾（gp8 同款；控制点上移
          // 离弦线，同款弓形）。
          final x0 = f.x + _labelHalfWidth(n) + 2;
          final mid = (x0 + endX) / 2;
          path = Path()
            ..moveTo(x0, f.y + dy)
            ..quadraticBezierTo(mid, f.y - dy, endX - 4, f.y - dy);
        }
        canvas.drawPath(path, line);
      }

      // —
      // （GP8
      // 周期 0.5×弦距，约 2.5
      if (n.vibrato) {
        const cycles = 2.5;
        final period = TabLayout.stringGap * 0.5;
        final peak = TabLayout.stringGap * 0.25;
        final w = period * cycles;
        // 位置（2026-11-12 用户走查定案）：波浪线在**谱表上方**（gp8
        // 同款）——旧 f.y+9 画在音符下方弦间隙里。y=rowTop−14：字带
        // （±8.4）上方 0.6px 净空，与 L.R. 虚线（−11）同层仅在同音
        // letRing+vibrato 罕见组合相交，接受。
        final yBase = rowTop - 14.0;
        final path = Path()..moveTo(f.x - w / 2, yBase);
        final nSeg = (cycles * 2).ceil();
        for (var k = 0; k < nSeg; k++) {
          final xMid = f.x - w / 2 + (k + 0.5) * (w / nSeg);
          path.lineTo(xMid, yBase + (k.isEven ? -peak : peak));
          path.lineTo(f.x - w / 2 + (k + 1) * (w / nSeg), yBase);
        }
        canvas.drawPath(path, line);
      }

      // —
      if (n.letRing) {
        final prevSameString = i > 0 ? _prevSameString(flow, i) : null;
        final isSegmentHead = prevSameString?.note.letRing != true;
        // 段尾 = 同弦下一个**非 letRing** 音（2026-11-12 修复超长虚线：
        // 旧版找第一个同弦音就 break——若它也是 letRing（段内音），
        // segEnd 留默认 endX → 同弦 ≥2 个 letRing 音时虚线画到行末，
        // 636px 超长线根因。段内音跳过继续找，无段尾才到行末）。
        var segEnd = endX;
        var j = i + 1;
        while (j < flow.length) {
          if (flow[j].note.string == n.string) {
            if (!flow[j].note.letRing) {
              segEnd = flow[j].x;
              break;
            }
            // 段内 letRing 音：继续找段尾
          }
          j++;
        }
        if (isSegmentHead) {
          // GP8 位置：L.R. 文字+虚线在谱上方（小节号之下、弦 1 之上），
          // 原
          _dashed(canvas, Offset(f.x + 4, rowTop - 11),
              Offset(segEnd.clamp(f.x + 4, endX), rowTop - 11));
          // 文字避让（重叠探针实证：'L.R.' 实测 halfW=18 @fs9——相邻
          // 段 30px 间距也互撞）：与已画标签中心距 <38px 则跳过文字
          // ——虚线仍画（段线是主标记，标签只是注记）。
          final lrCx = f.x + 16;
          final lrCollide = bandPaintedXs.any((px) => (px - lrCx).abs() < 38) ||
              rowTopAccentXs.any((ax) => (ax - lrCx).abs() < 4.2 + 18) ||
              rowTopStaccatoXs.any((ax) => (ax - lrCx).abs() < 2.0 + 18);
          if (!lrCollide) {
            bandPaintedXs.add(lrCx);
            _text(canvas, 'L.R.', Offset(lrCx, rowTop - 15),
                TextStyle(fontSize: 9, color: fretText));
          }
        }
      }

      // —
      if (n.palmMute) {
        final isSegmentHead = i == 0 || !flow[i - 1].note.palmMute;
        var segEnd = endX;
        for (var j = i + 1; j < flow.length; j++) {
          if (!flow[j].note.palmMute) {
            segEnd = flow[j].x;
            break;
          }
        }
        if (isSegmentHead) {
          // GP8 位置：P.M. 文字+虚线在谱上方（同 L.R.）。文字避让同
          // L.R.（与 L.R./其他 P.M. 标签共用带，相撞跳过）。
          _dashed(canvas, Offset(f.x + 4, rowTop - 11),
              Offset(segEnd.clamp(f.x + 4, endX), rowTop - 11));
          final pmCx = f.x + 16;
          final pmCollide = bandPaintedXs.any((px) => (px - pmCx).abs() < 38) ||
              rowTopAccentXs.any((ax) => (ax - pmCx).abs() < 4.2 + 18) ||
              rowTopStaccatoXs.any((ax) => (ax - pmCx).abs() < 2.0 + 18);
          if (!pmCollide) {
            bandPaintedXs.add(pmCx);
            _text(canvas, 'P.M.', Offset(pmCx, rowTop - 15),
                TextStyle(fontSize: 9, color: fretText));
          }
        }
      }
    }
  }

  _FlowNote? _nextSameString(List<_FlowNote> flow, int i) {
    for (var j = i + 1; j < flow.length; j++) {
      if (flow[j].note.string == flow[i].note.string) return flow[j];
    }
    return null;
  }

  _FlowNote? _prevSameString(List<_FlowNote> flow, int i) {
    for (var j = i - 1; j >= 0; j--) {
      if (flow[j].note.string == flow[i].note.string) return flow[j];
    }
    return null;
  }

  /// 手绘虚线（Canvas 无内
  void _dashed(Canvas canvas, Offset from, Offset to) {
    const dash = 4.0, gap = 3.0;
    final paint = Paint()
      ..color = fretText
      ..strokeWidth = 1.0;
    final dx = to.dx - from.dx;
    if (dx <= 0) return;
    final dy = to.dy - from.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    final ux = dx / len, uy = dy / len;
    var t = 0.0;
    while (t < len) {
      final t2 = math.min(t + dash, len);
      canvas.drawLine(
          from + Offset(ux * t, uy * t), from + Offset(ux * t2, uy * t2), paint);
      t = t2 + gap;
    }
  }

  /// TextPainter 全局缓存（播放滚动卡顿修
  /// 数个、小节号
  /// （浅暗两套色板各
  ///
  /// label 墨半宽（拥挤阈/H P 字母避让/tap 弧锚点共用）——单一来源
  /// TabLayout.inkHalf（一位数 8/两位数 16 墨/幽灵 21/泛音 20）。
  static double _labelHalfWidth(NoteIr n) => TabLayout.inkHalf(n);

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
    // 谱面文字统一主题字体（与 ThemeData 全局应用 kUiFontFamily 一致）。
    // 2026-11-16 重叠探针实证：无 family 时测试环境落到 Ahem（每字形
    // 1em，"(2)" 虚胖 2 倍）→ 排布/探针全程失真；显式 family 后探针
    // 加载同款真字体文件，墨宽度量与生产一致。
    final styled = style.copyWith(
        fontFamily: kUiFontFamily, fontFamilyFallback: kUiFontFallback);
    final tp = _cachedText(s, styled);
    // 探针捕获：中心 ±（实宽一半、字号×0.36 近似墨高）——字高取墨高
    // 而非行高（行高含行距，会把 legit 的上下堆叠误判相交）。
    TabViewDebug.lastPaintedTexts.add(TabPaintedText(
        s, at.dx, at.dy, tp.width / 2, (styled.fontSize ?? 14) * 0.36));
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ScorePainter old) =>
      // 明暗切换重绘：palette
      //
      old.stringLine != stringLine || !identical(old.ir, ir);

  /// 竖直波浪线（琶音，GP8 tab 样式）：周期 7px、峰 ±3px
  /// [up] 时尖
  void _wavyLine(Canvas canvas, double x, double y1, double y2,
      {required bool up}) {
    const period = 7.0, amp = 3.0;
    final path = Path()..moveTo(x, y1);
    var y = y1;
    var k = 0;
    while (y + period < y2) {
      path.lineTo(x + (k.isEven ? amp : -amp), y + period / 2);
      y += period;
      path.lineTo(x, y);
      k++;
    }
    if (y2 > y) path.lineTo(x, y2);
    // 方向尖（翼 2.5，与 _arrowLine 同款——图 1 视觉贴身修正）
    final tipY = up ? y1 : y2;
    final dir = up ? -1.0 : 1.0;
    path.moveTo(x - 2.5, tipY - dir * 5);
    path.lineTo(x, tipY);
    path.lineTo(x + 2.5, tipY - dir * 5);
    canvas.drawPath(path, _markLine);
  }

  /// 竖直
  void _arrowLine(Canvas canvas, double x, double y1, double y2,
      {required bool down}) {
    canvas.drawLine(Offset(x, y1), Offset(x, y2), _markLine);
    final tipY = down ? y2 : y1;
    final dir = down ? 1.0 : -1.0;
    // 翼 2.5（2026-11-17 图 1 用户实证：翼 3.5 时箭头右缘与音群数字
    // 左缘仅 3.5px 视觉贴身；2.5 → 间隙 4.5px 分离可辨）。
    canvas.drawLine(Offset(x - 2.5, tipY - dir * 5), Offset(x, tipY), _markLine);
    canvas.drawLine(Offset(x + 2.5, tipY - dir * 5), Offset(x, tipY), _markLine);
  }
}

/// 行内音流元素：音
class _FlowNote {
  _FlowNote(this.mIdx, this.note, this.x, this.y);
  final int mIdx;
  final NoteIr note;
  double x; //
  final double y;
}

/// 重叠探针捕获（项目铁律「数字不重叠」规则 18，lessons.md 规则 18/19）：
/// [_ScorePainter] paint 时把每个文字 label 的真实墨盒记入
/// [TabViewDebug.lastPaintedTexts]，探针测试按真实几何判相交。
/// 生产路径零行为差异（纯记录）。
class TabViewDebug {
  /// 最近一帧 paint 的文字墨盒。centerX/centerY = label 中心；
  /// halfW = TextPainter 实宽一半；halfH = 字号 × 0.36 墨高近似。
  static List<TabPaintedText> lastPaintedTexts = <TabPaintedText>[];

  /// 最近一帧 paint 的音流（排布终位）镜像——残类定位用
  /// （label 墨盒只有 x，不知道对应哪个音符/字段）。
  static List<TabFlowDebug> lastFlow = <TabFlowDebug>[];
}

/// 探针捕获的单条音流元素（mIdx/终位 x,y/音符引用）。
class TabFlowDebug {
  TabFlowDebug(this.mIdx, this.note, this.x, this.y);
  final int mIdx;
  final NoteIr note;
  final double x;
  final double y;
}

/// 探针捕获的单条文字墨盒。
class TabPaintedText {
  TabPaintedText(this.text, this.centerX, this.centerY, this.halfW, this.halfH);
  final String text;
  final double centerX;
  final double centerY;
  final double halfW;
  final double halfH;

  @override
  String toString() =>
      '"$text" @(${centerX.toStringAsFixed(1)},${centerY.toStringAsFixed(1)})'
      ' ±(${halfW.toStringAsFixed(1)},${halfH.toStringAsFixed(1)})';
}

///
/// RepaintBoundary
class _PlayheadPainter extends CustomPainter {
  _PlayheadPainter({
    required this.layout,
    required this.playheadBeat,
    required this.loopABeats,
    required this.playhead,
  });

  final TabLayout layout;
  final double? playheadBeat;
  final (double?, double?)? loopABeats;
  final Color playhead;

  /// 拍位 → (行, x)。曲外返回 null。
  (int, double)? _beatPos(double beat, List<List<int>> rows, double lw,
      double xOff) {
    // 变拍号修复（2026-11-19）：measure 反查用**实际拍累计表**（全局
    // 4 除在 pickup/变拍号谱错小节——follow 失效/指针错行用户实证）。
    final measure = layout.measureAtBeat(beat);
    final inMeasure =
        beat - layout.linearStarts[measure.clamp(0, rows.last.last)];
    for (var r = 0; r < rows.length; r++) {
      if (rows[r].contains(measure)) {
        final x = xOff +
            layout.noteX(measure.clamp(0, rows.last.last), inMeasure, lw);
        return (r, x);
      }
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 谱面排版宽（与 _ScorePainter 同款 1300 上限 + 居中偏移）。
    final lw = TabLayout.effectiveWidth(size.width);
    final xOff = TabLayout.horizontalOffset(size.width);
    final rows = layout.rowsFor(lw);
    // AB 循环段（2026-11-19 用户需求：设定后谱面可见——区段高亮 +
    // A/B 端竖线与字母标；单端已设画单端竖线）。罩层 playhead@10%
    // 不遮数字（浅色背景级）。
    final (loopA, loopB) = loopABeats ?? (null, null);
    if (loopA != null || loopB != null) {
      final fill = Paint()..color = playhead.withValues(alpha: 0.10);
      final linePaint = Paint()
        ..color = playhead
        ..strokeWidth = 1.5;
      final spanA = loopA == null ? null : _beatPos(loopA, rows, lw, xOff);
      final spanB = loopB == null ? null : _beatPos(loopB, rows, lw, xOff);
      if (spanA != null && spanB != null) {
        final (rA, xA) = spanA;
        final (rB, xB) = spanB;
        for (var r = rA; r <= rB && r < rows.length; r++) {
          final y0 = layout.stringY(1, r) - 10;
          final y1 = layout.stringY(6, r) + 10;
          final left = r == rA ? xA : 0.0;
          final right = r == rB ? xB : size.width;
          if (right > left) {
            canvas.drawRect(Rect.fromLTRB(left, y0, right, y1), fill);
          }
        }
      }
      void drawEnd((int, double)? span, String letter) {
        if (span == null) return;
        final (r, x) = span;
        final y0 = layout.stringY(1, r) - 10;
        final y1 = layout.stringY(6, r) + 10;
        canvas.drawLine(Offset(x, y0), Offset(x, y1), linePaint);
        final tp = TextPainter(
          text: TextSpan(
              text: letter,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: playhead)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, y0 - 16));
      }

      drawEnd(spanA, 'A');
      drawEnd(spanB, 'B');
    }
    if (playheadBeat == null) return;
    // 变拍号修复（2026-11-19）：measure 反查用实际拍累计表（_beatPos
    // 同款——全局 4 除错小节）。
    final measure = layout.measureAtBeat(playheadBeat!);
    final inMeasure =
        playheadBeat! - layout.linearStarts[measure.clamp(0, rows.last.last)];
    var row = 0, found = false;
    for (var r = 0; r < rows.length && !found; r++) {
      if (rows[r].contains(measure)) {
        row = r;
        found = true;
      }
    }
    if (!found) return;
    //
    // 音
    final x = xOff +
        layout.noteX(
            measure.clamp(0, rows.last.last),
            inMeasure,
            lw);
    final y0 = layout.stringY(1, row) - 10;
    final y1 = layout.stringY(6, row) + 10;
    canvas.drawLine(Offset(x, y0), Offset(x, y1),
        Paint()..color = playhead..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _PlayheadPainter old) =>
      old.playheadBeat != playheadBeat ||
      old.playhead != playhead ||
      old.loopABeats != loopABeats;
}
