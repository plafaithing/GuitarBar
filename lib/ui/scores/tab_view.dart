import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/score/score_ir.dart';
import '../theme.dart';
import 'tab_layout.dart';
import 'row_flow.dart';

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
      this.positionListenable,
      this.followPlayhead = false,
      this.loopABeats,
      this.onNoteTap,
      this.onFailedTap,
      this.onNoteLongPress});
  final ScoreIr ir;

  /// 播放头拍位 listenable（2026-11-24 跟随针重构）：painter repaint
  /// 直连——notifier 变化**只重绘播放头层**（painter 的 repaint 参数），
  /// widget build 完全不动。旧 playheadBeat 构造参数路径每 16ms 重建
  /// 整个 TabView（LayoutBuilder 内全谱排版现算 + 全树 build）→ 60fps
  /// 掉帧 = 用户实测"跟随针跳着走"根因。
  final ValueListenable<double>? positionListenable;

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

  /// 排版缓存（2026-11-24 跟随针重构配套）：ir/宽度不变不重算——
  /// 旧 build 每帧 TabLayout(ir) 全谱排版现算，60fps 下开销灾难。
  TabLayout? _layoutCache;
  double? _layoutCacheW;
  ScoreIr? _layoutCacheIr;

  TabLayout _layoutFor(double w) {
    // 键必须含 ir（2026-11-25 dense 探针实锤）：换谱同宽返回旧谱 layout，
    // rows 含前谱成员 → measures[idx] 越界（RangeError）。
    if (_layoutCache == null ||
        _layoutCacheW != w ||
        !identical(_layoutCacheIr, widget.ir)) {
      _layoutCache = TabLayout(widget.ir);
      _layoutCacheW = w;
      _layoutCacheIr = widget.ir;
    }
    return _layoutCache!;
  }

  @override
  void initState() {
    super.initState();
    widget.positionListenable?.addListener(_onPlayheadBeat);
  }

  @override
  void didUpdateWidget(covariant TabView old) {
    super.didUpdateWidget(old);
    if (old.positionListenable != widget.positionListenable) {
      old.positionListenable?.removeListener(_onPlayheadBeat);
      widget.positionListenable?.addListener(_onPlayheadBeat);
      // 换绑即同步一次（新 listenable 已带当前值——与旧 playheadBeat
      // 构造参数路径的 didUpdateWidget 立即触发语义等价）。
      _onPlayheadBeat();
    }
  }

  @override
  void dispose() {
    widget.positionListenable?.removeListener(_onPlayheadBeat);
    _scroll.dispose();
    super.dispose();
  }

  /// 播放头拍位变化（notifier listener，不走 build）：跟随滚动调度。
  void _onPlayheadBeat() {
    if (!widget.followPlayhead || !mounted) return;
    final beat = widget.positionListenable?.value;
    if (beat == null) return;
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
    final layout = _layoutFor(w);
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
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(builder: (ctx, box) {
      final layout = _layoutFor(box.maxWidth);
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
                      // 制谱基准 小节线与音
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
                        positionListenable: widget.positionListenable,
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
    final layout = _layoutFor(containerWidth);
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
    }
    // 流音反查（2026-11-25 "部分音无法选中/点击命中前一列"修复，本轮
    // 升级为**优先**路径）：paint 最近一帧的**实际渲染位置**（lastFlow，
    // 含 dup 错开 14-18px、deco 独立槽、拥挤让位）就近匹配——基础拍位
    // noteX(beat) 与渲染位置在 dup/deco/拥挤段系统性错开（实测点击命中
    // 前一列），渲染位置是唯一真相。坐标系一致：lastFlow.x 与 local 均
    // 为谱面内坐标（paint 平移 xOff 绘制、hitTest 已扣 xOff）。
    if (TabViewDebug.lastFlow.isNotEmpty) {
      TabFlowDebug? best;
      var bestD = double.infinity;
      for (final f in TabViewDebug.lastFlow) {
        final d = (local.dx - f.x).abs() + (local.dy - f.y).abs();
        if (d < bestD) {
          bestD = d;
          best = f;
        }
      }
      if (best != null &&
          (local.dx - best.x).abs() < 14 &&
          (local.dy - best.y).abs() < TabLayout.stringGap / 2) {
        final measures = tracks.first.measures;
        if (best.mIdx < 0 || best.mIdx >= measures.length) return;
        final idx = measures[best.mIdx]
            .notes
            .indexWhere((n) => identical(n, best!.note));
        if (idx >= 0) {
          if (tap) {
            widget.onNoteTap?.call(best.mIdx, idx, best.note);
          } else {
            widget.onNoteLongPress?.call(best.mIdx, idx, best.note);
          }
          return;
        }
      }
    }
    // 兜底（lastFlow 空或未命中）：基础拍位匹配——谱面未画帧时可用。
    for (final m in tracks.first.measures) {
      final mx = layout.measureX(m.index, maxWidth);
      if (local.dx < mx - TabLayout.measureGap / 2 ||
          local.dx > mx + layout.measureWidthAt(m.index, maxWidth)) {
        continue;
      }
      final row = layout.locate(m.index, maxWidth).$1;
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

  /// 标注线画笔（制谱基准 tabSlurThickness × MusicalFont 默
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
    // 谱面排版宽（2026-11-09 制谱基准 对照：上限 1300px 居中，超宽容器留白）。
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
    // Capo 标注（2026-11-08 制谱基准 截图对照；2026-11-09 用户反馈：与小节
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
          // 制谱基准 反
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
        // 线下缘（制谱基准 记谱惯例）。**段级休止不再画**（2026-11-18 用户
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
      }
      // 行内音流排布：与折行判定（TabLayout.rowOverfull）共用同一
      // 实现 buildRowFlow（2026-11-27 抽取）。
      final flow = buildRowFlow(
        measures: measures,
        row: rows[r],
        notePad: TabLayout.notePad,
        graceAsNormal: layout.graceAsNormal,
        measureX: (mi) => layout.measureX(mi, layoutWidth),
        measureWidth: (mi) => layout.measureWidthAt(mi, layoutWidth),
        noteX: (mi, beat) => layout.noteX(mi, beat, layoutWidth),
        stringY: (s) => layout.stringY(s, r),
        inkHalf: TabLayout.inkHalf,
      );
      // 【撤】时序保趟（2026-11-18 四版试错定论：7030/972/896/163——
      // 波及/钳界各引入新形态，三难[时序单调+墨净空+窄行容量]非趟式
      // 补丁可解，根治 = 排布模型整体升级[布局层时序口径→折行减密度]，
      // 与 CLAUDE.md「小节线保护」同批债）。倒置改由链趟时序上限单点
      // 修复（见链趟内注释）；近同列（正序 dx<4）为窄行/制谱基准 泛音链
      // 形态，探针计数记档不判罚。
      // Tap 短弧（2026-11-19 用户定案 + 制谱基准 m1-m3 像素级读图裁决：
      // LeftHandTapView.slur 字段 = **每处 tap 自带短弧**，从左邻紧邻
      // 音（含 grace）连向 tap 音——"连结弧画在 grace 右上跨间隙接
      // 到主音左上，走字形上方空档"）。T 挪谱顶后 y-14 弧带 = 原 T
      // 位置。条件：**右端是 tap**（制谱基准 弧向 = 连向 tap 收弧；旧版
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
        // 斜弧视觉近乎竖线，满屏干扰——2026-11-09 用户反馈去除；制谱基准
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
        // 闷击（gpif Muted）：制谱基准
        // ghost（AntiAccent）：
        // tie
        // 击勾
        final String label;
        // label 构造唯一事实源 = TabLayout.tabLabel（与 inkHalf 共用，
        // 口径漂移即重叠——2026-11-16 探针实证教训）。泛音尖括号 `<12>`
        // 为 制谱基准 同款（2026-11-08 截图对照）。
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
        // 泛音尖括号已并入数字 label（制谱基准 同款）；点弦 T = 椭圆圈 T
        //（2026-11-18 制谱基准 实测 LAS m33-38 裁决：六线谱有椭圆 (T)——
        // 推翻 11-08 "六线谱无 T" 判断；spec P1 LeftHandTapView decomp
        // 证据 + LAS LeftHandTapped×35 双证，弧上无字母）。
        // 人工泛音 AH 文字（制谱基准 同款，第 7 小节截图实锤）。
        if (n.harmonicType == 'artificial') {
          _text(canvas, 'AH', Offset(fl.x, fl.y - 13),
              TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: fretText));
        }
        if (n.tap) {
          // 椭圆 T 在**六线谱顶部**（2026-11-19 用户 LSA 原谱观察定案：
          // 制谱基准 的 T 全部标在谱顶带，水平对齐 tap 音 x）——音上 y-13
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
            // 制谱基准 密集区一个 T 代表一组；m58 dx=8.2/9.6 实证）。
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
        // 在数字上方（制谱基准 位置），颤音 tr 右上角，装饰音小号斜体数字
        if (n.accent) {
          _text(canvas, '>', Offset(fl.x, fl.y - 12),
              TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fretText));
        }
        if (n.staccato) {
          // 同音符带 accent（>）时点右移 8px（2026-11-16 全量探针
          // 232 处实证：两标注同画 y-12 完全同位重叠；制谱基准 双标注
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
      // repeatEnd 块（内侧点对 rx-6 + 粗线 rx+4）叠加 = 4 点。制谱基准
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

  /// 标注绘制层（2026-10-31 制谱基准 标注补齐）：
  /// - 琶音/
  /// - tie/击勾
  /// - 定滑
  /// - 延音 L.R. / 闷音 P.M.
  ///   走查
  void _paintMarks(Canvas canvas, List<RowFlowNote> flow, double rowTop,
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
      // 制谱基准 跨行形态：段延伸到行末竖线收尾。slide 斜线（clipped）同款。
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
          // 的窄缝取中**（制谱基准 杆居列间窄缝同款——数字窄+杆细无需让
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
          // Beat 级文字三件（2026-11-02 制谱基准 对照）：力度/淡入
          // 行底区（真实行底 = 底弦 + bottomPad(20)，再 +6 进空隙带；
          // 2026-11-16 重叠探针实证：旧 rowBottom+6 的 rowBottom 是
          // 底弦 y——mf 带压底弦数字带 3px）。
          // 力度去重（制谱基准 语义：一次力度标注只画一次）：仅当与本行
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
            // 端点箭头，顶上再画拨片小 V = 方向指示重复——制谱基准 的 TAB
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
      // （用户 制谱基准 对照"没有"的是 2+ 拍长弧与跨行延伸弧）。一轮收紧
      // 版（tie 类型级停画 + 0.5 拍阈值）误杀大量本该有的小连音弧
      // （用户复测实锤"很多本该有的小连音弧都没有了"），二轮放宽：
      // ①tie/hopo/legato 全恢复画②拍距 **>1.5 拍**不画（跨小节累计
      // 拍数：保月下 40 条 1 拍 tie + Distance 0.5-1 拍弧 + 0.25 拍跨
      // 小节短 tie；砍 2+ 拍与 3.5 拍跨小节长弧）③终点跨行（next==
      // null）不画（"延伸到行末"规则作废——超长弧主源）。
      // 几何（2026-11-12 用户定案）：**画在数字头部上方**——端点 y-10
      // （数字带 ±8 → 顶部 y-8，净空 2px）、控制高 6 → 拱顶 ≈y-14.5。
      if (n.tieStart || n.hopoStart || n.legatoStart || n.slide == 'legato') {
        // slide=='legato'（GP5 连滑）入弧（2026-11-24 制谱基准 实证：
        // Distance m11/m12 4 组滑音 TAB 全部 = 斜线+上拱弧+斜体 sl
        // 三件套，弧画在 slide 起点→下一音之间；此前 gp5 只解析出
        // slide 字符串无渲染分支，"曲谱中没有体现"根因）。
        final next = nextSameString;
        // 纯延音 tie（非 hopo/legato）弧线门（制谱基准 判定复刻，spec §2.2
        // /§2.3）：**tieEnd 端数字可见（锚点符号或小节首拍）且同小节**
        // 才画——origin 端数字天然显示（tabLabel 的 tie 隐藏只作用于
        // tieEnd 延续音中段，普通音全显示；LAS m34 制谱基准 实测 2→(2) 的
        // origin 无符号照画弧实证）。数字隐藏（长链中段延续音）→ 弧随
        // 之消失（Prologue 190 tie TAB 弧≈0 实证；2026-11-19 回滚上轮
        // "全解耦"误改——解耦版致 Prologue/Promise 满屏弧）；跨小节
        // 不画（TabTiedGroups 按小节分桶）。
        // hopo/legato 弧不受此门（HoPoSlurView 独立类，制谱基准 TAB 照画）。
        // 2026-11-19 逐弧实证定案（121 例零反例）：**TAB 行从不画 tie
        // 弧**（弧只在五线谱行；TAB 上方仅装饰音 "sl" 弧）——pureTie
        // 弧恒不画；装饰音连接弧走 slide='shift' 的 sl 弧路径（独立）。
        final pureTie = n.tieStart && !n.hopoStart && !n.legatoStart;
        final tieArcAllowed = !pureTie;
        // 拍距（跨小节累计）：>1.5 拍的超长配对不画（用户 制谱基准 对照）。
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

        // 弧上标注（"sl" / H / P）共用的占用判定与半宽常量。
        const letterHalfW = 3.5, letterHalfH = 3.0;
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

        // 制谱基准 三件套之三（2026-11-24 实证）：legato 滑音的斜体 "sl"
        // 在弧顶上方（弧顶 dip-h=y-16，sl 基线 y-20）；斜体衬线小字。
        // shift 纯滑弦不带弧/sl（1454 分支只画斜线）。
        // 避让（2026-11-27 全量探针实证 情非得以.gp4）：sl 落在 y-20 =
        // 上一弦弦线高度，上方弦同 x 有数字即撞；1 弦上与 rowTop-15 的
        // L.R./P.M. 带同层。与 H/P 字母同一占用判定（中点优先 3px
        // 步进），全占则不画 sl——弧与斜线仍在（铁律：数字不被任何
        // 符号遮挡）。
        if (n.slide == 'legato') {
          final slY = f.y + dip - h - 4;
          final slMid = (f.x + xEnd) / 2;
          var slX = -1.0;
          for (var s = 0; s <= 10 && slX < 0; s++) {
            if (!occupied(slMid + s * 3.0, slY)) {
              slX = slMid + s * 3.0;
            } else if (!occupied(slMid - s * 3.0, slY)) {
              slX = slMid - s * 3.0;
            }
          }
          if (slX >= 0) {
            _text(canvas, 'sl', Offset(slX, slY),
                TextStyle(
                    fontSize: 8,
                    fontStyle: FontStyle.italic,
                    color: fretText));
            paintedLetters.add((x: slX, y: slY));
          }
        }
        // 击勾弦字母：品升 H / 品降 P（连滑音弧线无字母，制谱基准 同款）。
        // 仅终点在本行（next!=null）时画——跨行弧终点品未知，H/P 判向
        // 无依据（2026-11-12 孤立小弧修复）。
        // 制谱基准 实测政策：小字号（明显小于数字）+ 垂直≈上一弦线高度
        // （y-17：制谱基准 基准 y-19 下移 2px——同拍相邻弦都有 hopo 时上一
        // 弦弧顶（-22~-24）正好穿过 y-19 字母带（golden 探针实锤），
        // 下移后与弧顶净空 ≥2px 且不触自己弧顶）+ 水平卡进数字间空档
        // ——fs7，水平避让数字/AH 盒与小节竖线（中点优先 3px 步进，
        // 全占回退中点）。
        if (n.hopoStart) {
          const dip2 = -17.0;
          final ly = f.y + dip2;
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
      // 制谱基准 slide 参数族（slideYIntercept/slideHeight/slideThickness）：
      // 2026-11-17 图 2 用户实证（贝司四线谱滑音组）：水平线+右向箭头
      // 头改为 **gp 同款短斜杠 + "sl." 文字**（spec §5 P1 遗留"slide
      // 缺 sl 文字"一并完成）；斜向按品升降：升滑 "/"、降滑 "\"。
      // legato（GP5 连滑）同画数字间短斜线（2026-11-24 制谱基准 实证三件套
      // 之一：斜线+弧+sl；5→7 与 9→9 无记号——slide 只标起点音对）。
      if (n.slide == 'shift' || n.slide == 'legato') {
        // 同行斜曲线（2026-11-18 用户反馈：直线偏上、要斜曲线——制谱基准
        // 的 slide 本为轻微弧线（slideYIntercept/slideHeight 参数族）：
        // **中点过弦线**、两端 ±4px（跨在音对间隙中，与数字缘净空
        // ≥1.8px）；二阶贝塞尔实现，曲线中点恰落在弦线上）。
        // **纯 TAB 不画 "sl." 文字**（2026-11-18 探针 2 处实证：sl.
        // 无论放上带/下带均与某层标注互撞——上弦数字带/下弦 accent/
        // 本弦数字；制谱基准 的 sl. 属五线谱记谱层，TAB 层为纯斜线——
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
          // 跨行/无后继：长弧延伸到行末收尾（制谱基准 同款；控制点上移
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
      // （制谱基准
      // 周期 0.5×弦距，约 2.5
      if (n.vibrato) {
        const cycles = 2.5;
        final period = TabLayout.stringGap * 0.5;
        final peak = TabLayout.stringGap * 0.25;
        final w = period * cycles;
        // 位置（2026-11-12 用户走查定案）：波浪线在**谱表上方**（制谱基准
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
          // 制谱基准 位置：L.R. 文字+虚线在谱上方（小节号之下、弦 1 之上），
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
          // 制谱基准 位置：P.M. 文字+虚线在谱上方（同 L.R.）。文字避让同
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

  RowFlowNote? _nextSameString(List<RowFlowNote> flow, int i) {
    for (var j = i + 1; j < flow.length; j++) {
      if (flow[j].note.string == flow[i].note.string) return flow[j];
    }
    return null;
  }

  RowFlowNote? _prevSameString(List<RowFlowNote> flow, int i) {
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

  /// 竖直波浪线（琶音，制谱基准 tab 样式）：周期 7px、峰 ±3px
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
    required this.positionListenable,
    required this.loopABeats,
    required this.playhead,
  }) : super(repaint: positionListenable);

  final TabLayout layout;
  final ValueListenable<double>? positionListenable;
  final (double?, double?)? loopABeats;
  final Color playhead;

  /// 拍位 → (行, x)。曲外返回 null。
  /// 播放头 x（2026-11-25 铁律"播放位置与渲染一致"落地）：**流音实际
  /// 渲染位置优先**——dup 错开/deco 槽/拥挤让位后的 x 才是用户看到的
  /// 音位置，拍位线性 x（noteX）在密集段与渲染差 2-3 个音（用户实测
  /// "指针快 2-3 音"）。流音按线性拍就近匹配，未命中回落拍位 x。
  (int, double)? _beatPos(double beat, List<List<int>> rows, double lw,
      double xOff) {
    TabFlowDebug? best;
    var bestD = double.infinity;
    for (final f in TabViewDebug.lastFlow) {
      final fb = layout.linearStarts[f.mIdx.clamp(0, layout.linearStarts.length - 1)] +
          f.note.beat;
      final d = (fb - beat).abs();
      if (d < bestD) {
        bestD = d;
        best = f;
      }
    }
    if (best != null && bestD < 0.2) {
      for (var r = 0; r < rows.length; r++) {
        if (rows[r].contains(best.mIdx)) {
          return (r, xOff + best.x);
        }
      }
    }
    // 回落：拍位线性 x（流音空/谱面未画帧）。
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
    // 播放头拍位（2026-11-24 重构）：painter repaint 直连 listenable——
    // notifier 变化仅触发本层重绘（无 widget build），beat 从 value 取。
    final playheadBeat = positionListenable?.value;
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
      // 播放头拍位变化由 repaint listenable 驱动（构造参数），此处只
      // 覆盖低频项（AB 段/配色）。
      old.playhead != playhead || old.loopABeats != loopABeats;
}
