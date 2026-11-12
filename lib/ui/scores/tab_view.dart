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
      this.onNoteTap,
      this.onFailedTap,
      this.onNoteLongPress});
  final ScoreIr ir;

  ///
  final double? playheadBeat;

  ///
  final bool followPlayhead;

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
    // 曲末拍位恰好等于总拍数时 locate 会落空，clamp 到最后一
    final measure =
        (beat / layout.beatsPerBar).floor().clamp(0, measureCount - 1);
    final row = layout.locate(measure, TabLayout.effectiveWidth(w)).$1;
    final y =
        row * (layout.rowHeight + TabLayout.rowGap) + layout.rowHeight / 2;
    final pos = _scroll.position;
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
    if (ir.capo > 0 && rows.isNotEmpty) {
      _text(
          canvas,
          'capo:${ir.capo}',
          Offset(TabLayout.leftPad + 40, layout.stringY(1, 0) - 26),
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
        // 整小节空休止符（2026-11-12 用户走查：「小波浪线」实为部分空拍的
        // 逐拍休止锯齿——源文件/gp8 里没有）。**部分空拍的逐拍休止已回滚**：
        // IR 的 duration 累计在真实谱上有洞（音的时值偏短/延音不回填），
        // 覆盖检测把有音的拍误判成空拍、成排画锯齿（误画率实测极高）；
        // gp8 的休止符基于节奏结构（Rhythm）而非 duration 累计，待解析层
        // 时值对齐后再启用。**仅保留整小节空**（notes.isEmpty 非 failed 是
        // 真数据，无误判）：全休止方块挂第 4 弦线下缘（gp8 记谱惯例）。
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
        // 小节右界（2026-11-12 LAS 越界整改）：dup 尾部级联曾无界越过
        // 小节线——错开位置钳制在右线内 12px（与拥挤趟同界）。**首音
        // 永不钳**（noteX 列位上限=右线−notePad，不会被 −12 界误钳）。
        final mRight = layout.measureX(m.index, layoutWidth) +
            layout.measureWidthAt(m.index, layoutWidth) -
            12;
        // dup 预数（2026-11-12 全库自检 Bluebird 实锤 4 对 0px 完全
        // 叠印：多 dup 末拍硬钳 min(nx+i×18, mRight) 把 2~3 个声部映
        // 到同一点——改**从右预留等比压缩**：每级步长 = min(18, 剩余
        // 空间÷剩余级数)，严格递增、全部线内；极端满格允许 ≤0.5px 级
        // 差底线（不可读性远差于 0.5px 越线）。
        final dupTotal = <String, int>{};
        for (final n in m.notes) {
          final key = '${n.string}@${n.beat.toStringAsFixed(3)}';
          dupTotal[key] = (dupTotal[key] ?? 0) + 1;
        }
        final dupSeen = <String, int>{};
        final dupLastX = <String, double>{};
        for (final n in m.notes) {
          final nx = layout.noteX(m.index, n.beat, layoutWidth);
          final ny = layout.stringY(n.string, r);
          final key = '${n.string}@${n.beat.toStringAsFixed(3)}';
          final idx = dupSeen.putIfAbsent(key, () => 0);
          dupSeen[key] = idx + 1;
          double x;
          if (idx == 0) {
            x = nx;
          } else {
            final remaining = dupTotal[key]! - idx; // 含当前级
            final prevX = dupLastX[key] ?? nx;
            final available = math.max(0.0, mRight - prevX);
            final step = math.min(18.0, available / remaining);
            x = math.max(prevX + 0.5, prevX + step);
          }
          dupLastX[key] = x;
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
      var crowdM = -1;
      for (final k in crowdOrder) {
        final g = crowdGroups[k]!;
        if (g.first.mIdx != crowdM) {
          lastXAtString.clear();
          lastNoteAtString.clear();
          crowdM = g.first.mIdx;
        }
        var delta = 0.0;
        for (final f in g) {
          final prev = lastXAtString[f.note.string];
          final prevN = lastNoteAtString[f.note.string];
          if (prev == null || prevN == null) continue;
          // 对阈 = 1px 净空 + 前音墨半 + 本音墨半（2026-11-12 校正：
          // 旧 9+半宽+半宽 对一位数对算 17px——墨宽仅 8px 实需 9px——
          // 超需求推挤引发链条撞界/倒序/堆叠三连）。与布局层按列基
          // 准（一位数谱 10px/列、含两位数 17px/列）完全一致。
          final gap =
              1.0 + _labelHalfWidth(prevN) + _labelHalfWidth(f.note);
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
        if (delta > 0) {
          for (final f in g) {
            f.x += delta;
          }
        }
        for (final f in g) {
          if (f.x > (lastXAtString[f.note.string] ?? -1)) {
            lastXAtString[f.note.string] = f.x;
            lastNoteAtString[f.note.string] = f.note;
          }
        }
      }
      // 反复符号间距（2026-11-09 用户反馈：数字与反复双竖线+圆点太近）：
      // repeatStart 小节的音**组**距左竖线 ≥22px、repeatEnd 末组距右竖线
      // ≥18px——组粒度整体移（保持同拍跨弦对齐不破坏）。
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
      // Tap 连线（2026-11-09 gp8 33/34 小节截图定案）：**相邻两个 tap
      // 音（间隔 ≤0.25 拍、同弦）之间的连音弧**——tap 链成串（`2~4~5`）。
      // 2026-11-12 收紧（用户走查实锤「源文件里没有」）：旧规则「至少
      // 一端 tap」把单发 tap 音也连上了线——LAS r13/r14 每行 15 段弧
      // 铺满整行（m40-43 的 5 tap/小节全被连），gp8 对纯 tap 不画弧
      // （gpif 里这些音 hopo/legato/tie 全空）。改为**两端都是 tap**
      // 才连（gp8 的 tap 链 2~4~5 = 相邻 tap 音），单发 tap 不连。
      // 层级（dsh 二轮 P1 整改 2026-11-11）：随标注层画在文字底下——
      // tap 弧 y-14~-19 会与上弦数字带（-28~-12）相交，字在上层盖住
      // 交集段；排序加弦号/x 决胜（Dart sort 非稳定，同拍相邻对须确定）。
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
        if (!cur.note.tap || !prev.note.tap) continue; // 两端都是 tap
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
      // 文字层（
      for (final fl in flow) {
        final n = fl.note;
        // 闷击（gpif Muted）：GP8
        // ghost（AntiAccent）：
        // tie
        // 击勾
        final String label;
        if (n.technique == 'x') {
          label = 'x';
        } else if (n.ghost) {
          label = '(${n.fret})';
        } else if (n.tieEnd && !n.hopoEnd) {
          label = '';
        } else if (n.technique == 'H') {
          // 泛音（2026-11-08 gp8 截图对照）：尖括号形式 `<12>`/`<4>`——
          // gp8 同款样式（替代旧 ○ 上标圈）。
          label = '<${n.fret}>';
        } else {
          label = '${n.fret}';
        }
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
        // 泛音尖括号已并入数字 label（gp8 同款）；点弦 T 仅五线谱语义
        //（2026-11-08 截图对照：gp8 六线谱无 T 标记）——六线谱不再画。
        // 人工泛音 AH 文字（gp8 同款，第 7 小节截图实锤）。
        if (n.harmonicType == 'artificial') {
          _text(canvas, 'AH', Offset(fl.x, fl.y - 13),
              TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: fretText));
        }
        // 轻量标注
        // 在数字上方（GP8 位置），颤音 tr 右上角，装饰音小号斜体数字
        if (n.accent) {
          _text(canvas, '>', Offset(fl.x, fl.y - 12),
              TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fretText));
        }
        if (n.staccato) {
          canvas.drawCircle(
              Offset(fl.x, fl.y - 12), 2, Paint()..color = fretText);
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
          for (final g in flow) {
            if (g.mIdx == f.mIdx && g.note.beat == n.beat) {
              yMin = math.min(yMin, g.y);
              yMax = math.max(yMax, g.y);
              xMin = math.min(xMin, g.x);
            }
          }
          final span = math.max(yMax - yMin, TabLayout.stringGap.toDouble());
          // 竖标 x：音群左
          // 走查：拍
          // 竖标 x：音群左（2026-11-09 用户反馈：距小节竖线太近难辨认
          // ——4px → 18px）。
          final barX = layout.measureX(f.mIdx, rowWidth);
          final x = math.max(xMin - 10, barX + 18);
          if (n.arpeggio != null) {
            _wavyLine(canvas, x, yMin - 6, yMin - 6 + span + 12,
                up: n.arpeggio == 'up');
          } else if (n.brush != null) {
            _arrowLine(canvas, x, yMin - 6, yMin - 6 + span + 12,
                down: n.brush == 'down');
          }
          // Beat 级文字三件（2026-11-02 GP8 对照）：力度/淡入
          // 行底区（rowBottom + 6，L.R./P.M. 移谱上方后的空位）
          if (n.dynamicMark != null) {
            _text(canvas, n.dynamicMark!, Offset(x + 14, rowBottom + 6),
                TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    color: fretText));
          }
          if (n.fadding != null) {
            _text(canvas, n.fadding == 'in' ? 'fade in' : 'fade out',
                Offset(x + 22, rowBottom + 6),
                TextStyle(fontSize: 9, fontStyle: FontStyle.italic, color: fretText));
          }
          if (n.wah) {
            _text(canvas, 'Wah', Offset(x + 16, rowBottom + 6),
                TextStyle(fontSize: 9, fontStyle: FontStyle.italic, color: fretText));
          }
          if (n.pickStroke != null) {
            // 拨片方向：下
            final cy = yMin - 16;
            final path = Path()
              ..moveTo(xMin - 4, n.pickStroke == 'down' ? cy - 4 : cy + 4)
              ..lineTo(xMin, cy)
              ..lineTo(xMin + 4, n.pickStroke == 'down' ? cy - 4 : cy + 4);
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
        // 拍距（跨小节累计）：>1.5 拍的超长配对不画（用户 gp8 对照）。
        // next==null（终点跨行）必然远 → 同样不画。
        var shortRange = false;
        if (next != null) {
          var beatDist = 0.0;
          for (var mi = f.mIdx; mi < next.mIdx; mi++) {
            beatDist += layout.beatsOfBar(mi);
          }
          beatDist += next.note.beat - n.beat;
          shortRange = beatDist <= 1.5 + 1e-9;
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
          bool occupied(double x) {
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
                  ly + letterHalfH > g.y - 6 &&
                  ly - letterHalfH < g.y + 6) {
                return true; // 数字盒
              }
              if (gn.harmonicType == 'artificial' &&
                  x + letterHalfW > g.x - 10 &&
                  x - letterHalfW < g.x + 10 &&
                  ly + letterHalfH > g.y - 18 &&
                  ly - letterHalfH < g.y - 8) {
                return true; // AH 盒
              }
            }
            return false;
          }

          final mid = (f.x + xEnd) / 2;
          var lx = mid;
          for (var s = 0; s <= 10; s++) {
            if (!occupied(mid + s * 3.0)) {
              lx = mid + s * 3.0;
              break;
            }
            if (!occupied(mid - s * 3.0)) {
              lx = mid - s * 3.0;
              break;
            }
          }
          final dest = next.note;
          final letter = dest.fret > n.fret ? 'H' : 'P';
          _text(canvas, letter, Offset(lx, ly),
              TextStyle(fontSize: 7, color: fretText));
        }
        } // shortRange && next != null
      }

      // —
      // GP8 slide 参数族（slideYIntercept/slideHeight/slideThickness）：
      // 斜线走品数字上方（y-10，数字顶
      if (n.slide == 'shift') {
        final y = f.y - 10;
        canvas.drawLine(Offset(f.x + 8, y), Offset(clipped - 8, y), line);
        final tip = Offset(clipped - 8, y);
        canvas.drawLine(tip, tip + const Offset(-4, -2.6), line);
        canvas.drawLine(tip, tip + const Offset(-4, 2.6), line);
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
          _text(canvas, 'L.R.', Offset(f.x + 16, rowTop - 15),
              TextStyle(fontSize: 9, color: fretText));
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
          // GP8 位置：P.M. 文字+虚线在谱上方（同 L.R.）
          _dashed(canvas, Offset(f.x + 4, rowTop - 11),
              Offset(segEnd.clamp(f.x + 4, endX), rowTop - 11));
          _text(canvas, 'P.M.', Offset(f.x + 16, rowTop - 15),
              TextStyle(fontSize: 9, color: fretText));
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
    final tp = _cachedText(s, style);
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
    // 方向尖
    final tipY = up ? y1 : y2;
    final dir = up ? -1.0 : 1.0;
    path.moveTo(x - 3.5, tipY - dir * 5);
    path.lineTo(x, tipY);
    path.lineTo(x + 3.5, tipY - dir * 5);
    canvas.drawPath(path, _markLine);
  }

  /// 竖直
  void _arrowLine(Canvas canvas, double x, double y1, double y2,
      {required bool down}) {
    canvas.drawLine(Offset(x, y1), Offset(x, y2), _markLine);
    final tipY = down ? y2 : y1;
    final dir = down ? 1.0 : -1.0;
    canvas.drawLine(Offset(x - 3.5, tipY - dir * 5), Offset(x, tipY), _markLine);
    canvas.drawLine(Offset(x + 3.5, tipY - dir * 5), Offset(x, tipY), _markLine);
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

///
/// RepaintBoundary
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
    // 谱面排版宽（与 _ScorePainter 同款 1300 上限 + 居中偏移）。
    final lw = TabLayout.effectiveWidth(size.width);
    final xOff = TabLayout.horizontalOffset(size.width);
    final rows = layout.rowsFor(lw);
    final beatPerBar = layout.beatsPerBar;
    final measure = (playheadBeat! / beatPerBar).floor();
    final inMeasure = playheadBeat! - measure * beatPerBar;
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
      old.playheadBeat != playheadBeat || old.playhead != playhead;
}
