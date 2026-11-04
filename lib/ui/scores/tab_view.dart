import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/score/score_ir.dart';
import '../theme.dart';
import 'tab_layout.dart';

/// �?��谱�?图：弦线/品数�?�?法字母标�?小节�?+ �?��度标�?+ failed 小节
/// �??�?+ �?��头�?? 弦在�?上�?�dataHue 上数�?��低置信度底），播放头 positive�?
///
/// 渲染分层（播放滚动卡顿修复）：谱面静态层与播放头层各�?shouldRepaint—�??
/// �?�� 50ms tick �?��画播放头竖线（RepaintBoundary 隔�?），谱面�?ir 不变
/// 不重绘，且画时按滚动位置�?���??行�??
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

  /// �?��头位�?��全曲拍位，Task 16 接线）；null = 不显示�??
  final double? playheadBeat;

  /// �?��跟随（走查反�?②）：播放头滑出�??窗口时自动平滑滚动居�???
  final bool followPlayhead;

  /// 点击音�?�?026-11-01 走查改为从�?音起�?��编辑移到长按）�??
  final void Function(int measureIndex, int noteIndex, NoteIr note)? onNoteTap;
  final void Function(int measureIndex)? onFailedTap;

  /// 长按音�?：编辑入口（原点击编辑�?义�?位给点音起播）�??
  final void Function(int measureIndex, int noteIndex, NoteIr note)?
      onNoteLongPress;

  @override
  State<TabView> createState() => _TabViewState();
}

class _TabViewState extends State<TabView> {
  final ScrollController _scroll = ScrollController();

  /// �?近一次布�?的�?口�?（跟随�?算需�?rowsFor(�?，didUpdateWidget
  /// 阶�?拿不到约束，缓存 build/LayoutBuilder 时的值）�?
  double? _width;

  @override
  void didUpdateWidget(covariant TabView old) {
    super.didUpdateWidget(old);
    final beat = widget.playheadBeat;
    if (!widget.followPlayhead || beat == null || beat == old.playheadBeat) {
      return;
    }
    // 帧末再滚：届时本帧布�?已完成，_width 与滚动位�?��为新值�??
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow(beat));
  }

  /// �?��跟随：播放头�?在�?�?�� �?平滑滚到�??区居�?��250ms）�??
  /// 仅播放头滑出�??窗口（留�?行高缓冲）时触发—�??0ms 刷新里播放头
  /// 在窗口内移动不触发，避免动画反�?打断手动滚动�?
  void _follow(double beat) {
    if (!_scroll.hasClients) return;
    final w = _width;
    if (w == null) return;
    final layout = TabLayout(widget.ir);
    final measureCount =
        widget.ir.tracks.isEmpty ? 0 : widget.ir.tracks.first.measures.length;
    if (measureCount == 0) return;
    // 曲末拍位恰好等于总拍数时 locate 会落空，clamp 到最后一�?��节�??
    final measure =
        (beat / layout.beatsPerBar).floor().clamp(0, measureCount - 1);
    final row = layout.locate(measure, w).$1;
    final y =
        row * (layout.rowHeight + TabLayout.rowGap) + layout.rowHeight / 2;
    final pos = _scroll.position;
    // 窗口内（�?���?��的静�?���?��不动�?
    if (y >= pos.pixels &&
        y <= pos.pixels + pos.viewportDimension - layout.rowHeight) {
      return;
    }
    final target =
        (y - pos.viewportDimension / 2).clamp(0.0, pos.maxScrollExtent);
    // �?��即当前位�?��免空动画�?
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
      // GestureDetector 放滚动区内：hit test 链自动换算，localPosition 即内�?
      // 坐标，滚动后命中不错位；tap 与垂�?drag 分属不同轴互不干扰�??
      // behavior=opaque 冗余但更防御（RenderCustomPaint.hitTestSelf 对未重写
      // hitTest �?painter �?��返回 true，deferToChild 已可命中；opaque 兜底
      // 覆盖 painter �?��重写 hitTest 的情况）�?
      // 双层 CustomPaint（不能合并为�?�?painter/foregroundPainter：同�?
      // RenderObject 任一变更整体重绘）：谱面�?ir 不变�?shouldRepaint=false
      // 不重绘；�?��头层�?RepaintBoundary�?0ms tick �?��录本层一条竖线�??
      return SingleChildScrollView(
        controller: _scroll,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _hitTest(d.localPosition, w, tap: true),
          onLongPressEnd: (d) => _hitTest(d.localPosition, w, tap: false),
          child: SizedBox(
            width: w,
            // 底部缓冲 = PlayBar 高（64，bottomSheet 常驻�?��）：滚动�?
            // 底时�?后一行完整可见（2026-11-01 走查）�??
            height: layout.sizeFor(w).height + 64,
            child: Stack(children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ScorePainter(
                      layout: layout,
                      ir: widget.ir,
                      scroll: _scroll,
                      // 弦线加深�?026-11-02 走查：浅色模�?p.border �?��
                      // 看不清，p.muted �?��）�??
                      stringLine: p.muted,
                      fretText: p.ink,
                      // 小节线加深（2026-11-01 走查：p.border �?��看不出，
                      // GP8 小节线与音�?同黑）�??
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

  /// 点击/长按命中：找�?近的弦线（|dy| < stringGap/2），再找该弦上最近的
  /// 音�?（|dx| < 11）�?�x 容差 11 而非 pxPerBeat/2：绘制层有同弦近邻修�?
  /// （拥挤音右移 14px），容差须小于修正�?长，否则点击�??后的音错命中
  /// 前一音；也须小于同拍同弦 12px 错开步长�?
  void _hitTest(Offset local, double maxWidth, {required bool tap}) {
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
        // 行纵向校验：多�?布局下同列不同�? x 相同，必须限�?dy 在本行弦区�??
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

/// 静�?�谱面层：弦�?小节�?品数�?�?法字�?�?��度底/failed 标�?/图例�?
/// �?��头不在�?层（�?_PlayheadPainter）�?�滚动时 SingleChildScrollView 整棵
/// 重绘会重�?paint()，因此这里按当前 scroll offset �?���??行（加一行缓冲）�?
/// 全量 2600 音�?降为窗口内约 4 行；谱面层因此不能包 RepaintBoundary—�??
/// 缓存层会让�?�?��过期。ir 不变�?shouldRepaint=false，播�?tick 不重绘�??
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

  /// �?paint 里�?当前滚动位置裁可视�?；滚动重绘由 viewport 触发�?
  /// 不参�?shouldRepaint�?
  final ScrollController scroll;

  final Color stringLine, fretText, barLine, failedText, pageNum;

  /// 标注线画笔（GP8 tabSlurThickness × MusicalFont 默�? scale 1.625
  /// 视�?等效 �?px；helper 方法共享）�??
  late final Paint _markLine = Paint()
    ..color = fretText
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rows = layout.rowsFor(size.width);
    final measures =
        ir.tracks.isEmpty ? const <MeasureIr>[] : ir.tracks.first.measures;

    // �??行区间（加一行缓冲）：painter 画布坐标即内容坐�?
    // （内�?y = 视口 y + scrollOffset）�??
    final stride = layout.rowHeight + TabLayout.rowGap;
    final scrollOffset = scroll.hasClients ? scroll.offset : 0.0;
    final viewportH =
        scroll.hasClients ? scroll.position.viewportDimension : size.height;
    final firstRow = math.max(0, (scrollOffset / stride).floor() - 1);
    final lastRow = math.min(
        rows.length - 1, ((scrollOffset + viewportH) / stride).ceil() + 1);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, scrollOffset, size.width, viewportH));
    for (var r = firstRow; r <= lastRow; r++) {
      final rowTop = layout.stringY(1, r);
      final rowBottom = layout.stringY(6, r);
      // 弦线�? 弦最上）—�?�整行连�?��对齐 Guitar Pro 连续谱面样式）�??
      for (var s = 1; s <= 6; s++) {
        final y = layout.stringY(s, r);
        canvas.drawLine(Offset(TabLayout.leftPad, y),
            Offset(size.width - TabLayout.leftPad, y),
            Paint()..color = stringLine);
      }
      // 小节线（2026-10-31 小节合并：measureGap=0 后相邻小节共用竖线，
      // �?��每小节左边界画一�?+ 行末收尾线；低置信度底色块随 AI 通道
      // 放弃�?并移除�?��?�GTP confidence=0 曾�?全部小节带底色成块状）�??
      // 行内音流（标注弧�?虚线的两�?��找用）：按谱面序收集�??音�?�?
      final flow = <_FlowNote>[];
      for (final m in rows[r].map((idx) => measures[idx])) {
        final mx = layout.measureX(m.index, size.width);
        final mw = layout.measureWidthAt(m.index, size.width);
        // 结尾跳房子（GP8 "N." �?��）：谱最上层�?�� + 左�?"N."�?
        if (m.endings.isNotEmpty) {
          final label = m.endings.map((e) => '$e').join('.');
          final lineY = rowTop - 36.0;
          canvas.drawLine(Offset(mx + 6, lineY),
              Offset(mx + mw - 6, lineY), Paint()..color = barLine);
          _text(canvas, '$label.', Offset(mx + 12, lineY - 4),
              TextStyle(fontSize: 10, color: barLine));
        }
        // 小节号（谱上方�?二层）�??
        _text(canvas, '${m.index + 1}', Offset(mx, rowTop - 26),
            TextStyle(
                fontSize: 10,
                color: pageNum,
                fontFeatures: [FontFeature.tabularFigures()]));
        // 左小节竖线；反�?起�?（Repeat start�? 双竖�?+ 弦区上下圆点
        //�?026-11-02 走查：GP8 反�?记号 v1 缺失）�??
        canvas.drawLine(Offset(mx, rowTop), Offset(mx, rowBottom),
            Paint()..color = barLine);
        if (m.repeatStart) {
          // GP8 反�?起�? �?：细线在正线左�?�?*点在正线内侧**（指向反复�?）�??
          canvas.drawLine(Offset(mx - 4, rowTop), Offset(mx - 4, rowBottom),
              Paint()
                ..color = barLine
                ..strokeWidth = 3.5);
          final dot = Paint()..color = barLine;
          canvas.drawCircle(Offset(mx + 6, rowTop + 8), 2.2, dot);
          canvas.drawCircle(Offset(mx + 6, rowBottom - 8), 2.2, dot);
        }
        // 反�?结束 :‖：点在正线内侧（反复�?�?侧），细线在右�?�?
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
        // 同拍同弦多声部错�?�?026-10-31 走查�??"12 写两�?）保留在
        // 收集时；16 分音近邻拥挤统一在下方修正趟处理�?
        final seenAt = <String, int>{}; // (string@beatRounded) �?已画次数
        for (final n in m.notes) {
          final nx = layout.noteX(m.index, n.beat, size.width);
          final ny = layout.stringY(n.string, r);
          final key = '${n.string}@${n.beat.toStringAsFixed(1)}';
          final dupCount = seenAt.putIfAbsent(key, () => 0);
          seenAt[key] = dupCount + 1;
          final dx = dupCount * 12.0; // �?2/3 �?��右偏 12/24px
          flow.add(_FlowNote(m.index, n, nx + dx, ny));
        }
      }
      // 同弦相邻拥挤�??趟（2026-11-01 走查：Like A Star "12×6" 同弦
      // 16 分连排两位数字叠死）：同弦按时间序，与前�?�?x �?<16px 的音
      // 右移�?prev+16（�?�?= 两位品数字�?，短连排 <8 �?��此排�?�?
      // �? 长连排由行密度自适应降为 2 小节/行）�?
      final lastXAtString = <int, double>{};
      for (final fl in flow) {
        final prev = lastXAtString[fl.note.string];
        if (prev != null && fl.x - prev < 16 && fl.x >= prev) {
          fl.x = prev + 16;
        }
        lastXAtString[fl.note.string] = fl.x;
      }
      // 文字层（�??后坐标）：品数字 + �?法标�?��2026-11-02 GP8 对齐整改）�??
      for (final fl in flow) {
        final n = fl.note;
        // 闷击（gpif Muted）：GP8 �?"x" **替代**品数字（非数�?角标）�??
        // ghost（AntiAccent）：�?��品数�?(3)�?
        // tie �?���?��GP8 **不印品数�?*（延�?��无新按弦，弧线到空位）；
        // 击勾�?��音（hopoEnd）照常印（重新发声）�?
        final String label;
        if (n.technique == 'x') {
          label = 'x';
        } else if (n.ghost) {
          label = '(${n.fret})';
        } else if (n.tieEnd && !n.hopoEnd) {
          label = '';
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
        // �?��泛音（HarmonicType）：GP8 = 品数�?*正上方小圆圈**（替�?
        // 早期 H 角标）；点弦 T 在数字�?上方（GP8 同�?）�?�AI 通道�?
        // h/p/s/b 字母保持右上角（gpx 通道由弧�?�?��表达不产字母）�??
        if (n.technique == 'H') {
          canvas.drawCircle(
              Offset(fl.x, fl.y - 13),
              3,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.2
                ..color = fretText);
        }
        if (n.tap) {
          _text(canvas, 'T', Offset(fl.x, fl.y - 13),
              TextStyle(fontSize: 10, color: fretText));
        }
        // 轻量标注�?��批（2026-11-02 GP8 标识符�?照）：重�?> / �?�� ·
        // 在数字上方（GP8 位置），颤音 tr 右上角，装饰音小号斜体数字�??
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
      _paintMarks(canvas, flow, rowTop, rowBottom, size.width);
      // 行末收尾竖线（最后一小节的右边界；�?级小节�?—�?�密集�?更�?）�??
      // 反�?结束（Repeat end�? 圆点 + 双竖线（点在行末线左）�??
      final lastMeasure = rows[r].last;
      final lastM = measures[lastMeasure];
      final endX = layout.measureX(lastMeasure, size.width) +
          layout.measureWidthAt(lastMeasure, size.width);
      if (lastM.repeatEnd) {
        final dot = Paint()..color = barLine;
        canvas.drawCircle(Offset(endX + 10, rowTop + 8), 2.2, dot);
        canvas.drawCircle(Offset(endX + 10, rowBottom - 8), 2.2, dot);
        canvas.drawLine(Offset(endX + 5, rowTop), Offset(endX + 5, rowBottom),
            Paint()..color = barLine);
      }
      canvas.drawLine(Offset(endX, rowTop), Offset(endX, rowBottom),
          Paint()..color = barLine);
    }
    canvas.restore();
  }

  /// 标注绘制层（2026-10-31 GP8 标注补齐）：
  /// - 琶音/�?��/拨片方向：Beat 级标�?��画在该拍音群左侧（GP8 位置�?
  /// - tie/击勾�?连滑音：GP8 Slur 模型弧线（�?注�?下），击勾弦弧下�?H/P
  /// - 定滑�?shift：品数字上方�?�� + 右�?�?��尖；揉弦 vibrato：SMuFL 尖峰�?��
  /// - 延音 L.R. / 闷音 P.M.�?*谱上�?*虚线区间（GP8 位置�?026-11-01
  ///   走查�?��对齐；原行底位置�?6 弦品数字叠印�?
  void _paintMarks(Canvas canvas, List<_FlowNote> flow, double rowTop,
      double rowBottom, double rowWidth) {
    final endX = rowWidth - TabLayout.leftPad;
    final line = _markLine;
    // 音流序扫描：每个标注音找同弦/连续终点�?
    for (var i = 0; i < flow.length; i++) {
      final f = flow[i];
      final n = f.note;
      final nextSameString = _nextSameString(flow, i);
      final x1 = nextSameString?.x ?? (f.x + 22); // 无后继：�?���?
      final clipped = x1.clamp(f.x + 8, endX);

      // —�??琶音 / �?�� / 拨片方向（Beat 级，2026-11-01 走查补齐）�?��??
      // gpif Beat 层编码：<Arpeggio>Up|Down</Arpeggio>、Brush/PickStroke
      // Direction（Like A Star 实测）�?�琶�?竖波�?��、扫�?竖直�?���?
      // 拨片=音�?上方 V/^，均在�?拍音群左侧，同拍群�?画一次�??
      if (n.arpeggio != null || n.brush != null || n.pickStroke != null) {
        final isGroupHead = i == 0 ||
            flow[i - 1].mIdx != f.mIdx ||
            flow[i - 1].note.beat != n.beat;
        if (isGroupHead) {
          // 同拍音群（跨声部）：y 范围 = 群内�?�?�?低弦�?
          var yMin = f.y, yMax = f.y, xMin = f.x;
          for (final g in flow) {
            if (g.mIdx == f.mIdx && g.note.beat == n.beat) {
              yMin = math.min(yMin, g.y);
              yMax = math.max(yMax, g.y);
              xMin = math.min(xMin, g.x);
            }
          }
          final span = math.max(yMax - yMin, TabLayout.stringGap.toDouble());
          // 竖标 x：音群左�?10px，但**不得压小节左竖线**�?026-11-01
          // 走查：拍�?0 音群�?xMin-10 恰在小节线上）�?��?�钳到线�?4px�?
          final barX = layout.measureX(f.mIdx, rowWidth);
          final x = math.max(xMin - 10, barX + 4);
          if (n.arpeggio != null) {
            _wavyLine(canvas, x, yMin - 6, yMin - 6 + span + 12,
                up: n.arpeggio == 'up');
          } else if (n.brush != null) {
            _arrowLine(canvas, x, yMin - 6, yMin - 6 + span + 12,
                down: n.brush == 'down');
          }
          // Beat 级文字三件（2026-11-02 GP8 对照）：力度/淡入�?Wah—�??
          // 行底区（rowBottom + 6，L.R./P.M. 移谱上方后的空位）�??
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
            // 拨片方向：下�?V / 上拨 ^，画在群首音符上方�??
            final cy = yMin - 16;
            final path = Path()
              ..moveTo(xMin - 4, n.pickStroke == 'down' ? cy - 4 : cy + 4)
              ..lineTo(xMin, cy)
              ..lineTo(xMin + 4, n.pickStroke == 'down' ? cy - 4 : cy + 4);
            canvas.drawPath(path, _markLine);
          }
        }
      }

      // —�??弧线族：tie / 击勾�?/ 连滑�?—�??
      // GP8 am::painting::Slur 模型逆向�?��（AMPainting.dll computeIdealSlurControl
      // Points/makeSlur 反编译）：三次贝塞尔，p0/p1=音�?�?��；控制点沿连线内�?
      // max(0.05×dx, 0.36×dx×e^(-0.0144dx))；弧高系数同�?0.36、跨�?0.426
      // （SlurParameters{0.36,0.5,0.05,0.04} 默�?值）× 弦距�?
      // 方向�?026-11-01 走查）：**上拱**—�?�下拱弧顶压品数字�?线（用户点名），
      // 上拱弧顶在弦线上�?0.75×h�?.9px（stringGap 22），恰在上一弦数字底�?
      // 之下的弦间空隙里�?
      if (n.tieStart || n.hopoStart || n.legatoStart) {
        final next = nextSameString;
        final xEnd = (next?.x ?? f.x + 22).clamp(f.x + 8, endX).toDouble();
        final yEnd = next?.y ?? f.y;
        final dx = (xEnd - f.x).abs().toDouble();
        final dy = (yEnd - f.y).abs().toDouble();
        final unit = TabLayout.stringGap.toDouble();
        final h =
            (dy > 0.25 ? 0.36 + 0.14 * math.exp(-0.75) : 0.36) * unit;
        final inset = math
            .max(0.05 * dx, 0.36 * dx * math.exp(-0.0144 * dx))
            .clamp(0.0, dx / 3);
        final path = Path()
          ..moveTo(f.x, f.y)
          ..cubicTo(f.x + inset, f.y - h, xEnd - inset, yEnd - h, xEnd, yEnd);
        canvas.drawPath(path, line);
        // 击勾弦字母：品升 H / 品降 P（连滑音弧线无字母，GP8 同�?）�?��??
        // 弧线内侧（弧顶之下�?�品数字之上）�??
        if (n.hopoStart) {
          final dest = next?.note;
          final letter = dest == null ? 'H' : (dest.fret > n.fret ? 'H' : 'P');
          _text(canvas, letter, Offset((f.x + xEnd) / 2, f.y - 10),
              TextStyle(fontSize: 9, color: fretText));
        }
      }

      // —�??定滑音：数字上方�?�� + �?��（shift）�?��??
      // GP8 slide 参数族（slideYIntercept/slideHeight/slideThickness）：
      // 斜线走品数字上方（y-10，数字顶�?y-7 之上 3px），�?��指向滑向音�??
      if (n.slide == 'shift') {
        final y = f.y - 10;
        canvas.drawLine(Offset(f.x + 8, y), Offset(clipped - 8, y), line);
        final tip = Offset(clipped - 8, y);
        canvas.drawLine(tip, tip + const Offset(-4, -2.6), line);
        canvas.drawLine(tip, tip + const Offset(-4, 2.6), line);
      }

      // —�??揉弦：SMuFL Bravura wiggle 风格尖峰�?���?—�??
      // （GP8 �?GPBravura 字体�?vibrato glyph：峰�?0.25×弦距�?
      // 周期 0.5×弦距，约 2.5 �?��期）
      if (n.vibrato) {
        const cycles = 2.5;
        final period = TabLayout.stringGap * 0.5;
        final peak = TabLayout.stringGap * 0.25;
        final w = period * cycles;
        final yBase = f.y + 9.0;
        final path = Path()..moveTo(f.x - w / 2, yBase);
        final nSeg = (cycles * 2).ceil();
        for (var k = 0; k < nSeg; k++) {
          final xMid = f.x - w / 2 + (k + 0.5) * (w / nSeg);
          path.lineTo(xMid, yBase + (k.isEven ? -peak : peak));
          path.lineTo(f.x - w / 2 + (k + 1) * (w / nSeg), yBase);
        }
        canvas.drawPath(path, line);
      }

      // —�??延音 L.R.：同弦连�?letRing 段（段�?标文字）—�??
      if (n.letRing) {
        final prevSameString = i > 0 ? _prevSameString(flow, i) : null;
        final isSegmentHead = prevSameString?.note.letRing != true;
        // 段尾 = 同弦下一�?�� letRing 音；�?���?letRing 则延到�?�???
        var segEnd = endX;
        var j = i + 1;
        while (j < flow.length) {
          if (flow[j].note.string == n.string) {
            if (!flow[j].note.letRing) {
              segEnd = flow[j].x;
            }
            break;
          }
          j++;
        }
        if (isSegmentHead) {
          // GP8 位置：L.R. 文字+虚线在谱上方（小节号之下、弦 1 之上），
          // 原�?底位�?�� 6 弦品数字叠印�?026-11-01 走查�?��）�??
          _dashed(canvas, Offset(f.x + 4, rowTop - 11),
              Offset(segEnd.clamp(f.x + 4, endX), rowTop - 11));
          _text(canvas, 'L.R.', Offset(f.x + 16, rowTop - 15),
              TextStyle(fontSize: 9, color: fretText));
        }
      }

      // —�??闷音 P.M.：谱面序连续 palmMute �?—�??
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
          // GP8 位置：P.M. 文字+虚线在谱上方（同 L.R.）�??
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

  /// 手绘虚线（Canvas 无内�?dash）：dash 4 / gap 3�?
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

  /// TextPainter 全局缓存（播放滚动卡顿修�?②）：品数字�?0-24、技法字�?
  /// 数个、小节号 �?小节数，�?��字号/字重/色�??数字特�?�位数，条目有界
  /// （浅暗两套色板各�?份）不清理�?�小节号与图例同�?10 �?muted 色，
  /// �?fontFeatures 位数区分�???
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
      // 明暗切换重绘：palette �?const 单例�? 色同源，代理比较 stringLine 足�?�?
      // �?�� tick 重建 painter（ir 同实例）返回 false，不触发谱面重绘�?
      old.stringLine != stringLine || !identical(old.ir, ir);

  /// 竖直波浪线（琶音，GP8 tab 样式）：周期 7px、峰 ±3px�?
  /// [up] 时尖�?��上拨方向小尖）画在上�?��否则下�?�?
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
    // 方向尖�?�?
    final tipY = up ? y1 : y2;
    final dir = up ? -1.0 : 1.0;
    path.moveTo(x - 3.5, tipY - dir * 5);
    path.lineTo(x, tipY);
    path.lineTo(x + 3.5, tipY - dir * 5);
    canvas.drawPath(path, _markLine);
  }

  /// 竖直�?��线（�?�� Brush）：[down] 时尖�?��下�?（向下扫），否则上�?�?
  void _arrowLine(Canvas canvas, double x, double y1, double y2,
      {required bool down}) {
    canvas.drawLine(Offset(x, y1), Offset(x, y2), _markLine);
    final tipY = down ? y2 : y1;
    final dir = down ? 1.0 : -1.0;
    canvas.drawLine(Offset(x - 3.5, tipY - dir * 5), Offset(x, tipY), _markLine);
    canvas.drawLine(Offset(x + 3.5, tipY - dir * 5), Offset(x, tipY), _markLine);
  }
}

/// 行内音流元素：音�?+ 已算好的谱面坐标（含同拍同弦错开偏移）�??
class _FlowNote {
  _FlowNote(this.mIdx, this.note, this.x, this.y);
  final int mIdx;
  final NoteIr note;
  double x; // �?��：同弦相邻拥挤修正趟会右�?
  final double y;
}

/// �?��头层（全曲拍 �?小节/行内位置画一条竖线）：独�?CustomPaint +
/// RepaintBoundary�?0ms tick �?��录本层，谱面层不随之重绘�?
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
    final rows = layout.rowsFor(size.width);
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
    // �?noteX 同�?�?��（�?级小节�? + notePad + 行级拍距），�?��头与
    // 音�?对齐（密集�?拍距�?��拉长，播放头跟随）�??
    final x = layout.noteX(
        measure.clamp(0, rows.last.last),
        inMeasure,
        size.width);
    final y0 = layout.stringY(1, row) - 10;
    final y1 = layout.stringY(6, row) + 10;
    canvas.drawLine(Offset(x, y0), Offset(x, y1),
        Paint()..color = playhead..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _PlayheadPainter old) =>
      old.playheadBeat != playheadBeat || old.playhead != playhead;
}
