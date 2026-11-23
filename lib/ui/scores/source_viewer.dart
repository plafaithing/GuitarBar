import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// 源文件纯查看器（13.4 通道二选一：图片/PDF 走纯查看器，手势对齐主流看图）。
///
/// 手势全手写分派（不用 InteractiveViewer：其内置滚轮缩放经 PointerSignalResolver
/// 先注册先赢，嵌套时外层"纯滚轮翻页"永远收不到滚轮事件）：
/// - 横看（分页，默认）：垂直滚轮逐页翻 + 横向拖动；触摸单指横拉同一路径；
///   缩放态翻页锁定（滚轮与拖动自动改为平移）。**循环翻页**（2026-11-23
///   用户需求）：末页右滑回第一页重头查看（PageView 无限页 + 取模显示）。
/// - 竖看（连续滚动，随时切换）：全部页竖排 fit 宽度，滚轮/拖动连续滚动；
///   **滚到底继续滚 → 回第一页重头看**（overscroll 累积阈值跳顶）。
/// - 缩放（仅横看）：Ctrl+滚轮（锚点视口中心）/ 双指捏合（锚点指间）/
///   双击（2.5x 居中 ↔ 复位）。竖看为连续流读，不做矩阵缩放。
/// - 平移：横看缩放态单指/鼠标拖动，clamp 到内容边界。
/// - gpxSourceText：源文件文本模式（单页等宽文本；滚轮滚动、拖动平移、复制按钮）。
enum _ViewMode { paged, scroll }

class SourceViewer extends StatefulWidget {
  const SourceViewer({super.key, required this.pagePngs, this.gpxSourceText});
  final List<File> pagePngs;

  /// gpx 源文件文本（非空 = 文本查看模式：单页、无翻页控件）。
  final String? gpxSourceText;

  /// 变换节点 key（widget 测试定位本组件的缩放矩阵用；框架树里还有
  /// 其他 Transform，find.byType 会误取）。
  static const transformKey = ValueKey('sourceViewerTransform');

  @override
  State<SourceViewer> createState() => _SourceViewerState();
}

class _SourceViewerState extends State<SourceViewer>
    with SingleTickerProviderStateMixin {
  static const double _minScale = 1;
  static const double _maxScale = 6;
  static const double _doubleTapScale = 2.5;
  static const double _flickVelocity = 350; // px/s，甩动翻页阈值
  static const double _loopOverscroll = 260; // 竖看到底继续滚的回顶阈值（px）
  static const int _pageBase = 100000; // 无限 PageView 的起始偏移（防负页）

  late final PageController _controller;
  late final ScrollController _scroll;
  late final AnimationController _matrixAnim; // 双击缩放/复位的补间
  Animation<Matrix4>? _matrixTween;
  int _index = 0;
  _ViewMode _mode = _ViewMode.paged; // 横看/竖看（随时切换）
  double _loopAccum = 0; // 竖看到底后继续滚动的累积量
  // 当前页变换（p' = p·s + t）；翻页复位 identity——主流看图翻页回开头。
  Matrix4 _matrix = Matrix4.identity();

  // 原始 pointer 事件追踪：Listener 不参与手势竞技场、收到全部事件；
  // PageView 物理 NeverScrollable 后其 Scrollable 不注册滚轮（shouldAcceptUserOffset
  // false 早退），滚轮独享；按钮是 Stack 兄弟节点、命中优先，tap 不进拖动。
  final Map<int, Offset> _pointers = {}; // pointerId → 最近位置（悬停不追踪）
  // 翻页拖动（非缩放态横拖 → jumpTo 驱动 + 简易甩动速度）。
  double? _pageDragStartOffset;
  Offset? _pageDragStartPos;
  Offset? _pageDragLastPos;
  Duration _pageDragLastTime = Duration.zero;
  double _pageDragVelocity = 0;
  // 平移（缩放态拖动 / 文本模式拖动）。
  Matrix4? _panStartMatrix;
  Offset? _panStartPos;
  // 双指捏合起始（span/focal/矩阵快照）。
  double? _pinchStartSpan;
  Offset? _pinchStartFocal;
  Matrix4? _pinchStartMatrix;

  final GlobalKey _textKey = GlobalKey(); // 文本内容实测尺寸（clamp 用）

  bool get _isTextMode => widget.gpxSourceText != null;
  int get _pageCount => widget.pagePngs.length;
  bool get _zoomed => _matrix.getMaxScaleOnAxis() > _minScale + 0.001;
  bool get _isScrollMode => _mode == _ViewMode.scroll && !_isTextMode;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: _pageBase);
    _scroll = ScrollController();
    _matrixAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180))
      ..addListener(() {
        if (_matrixTween != null) {
          setState(() => _matrix = _matrixTween!.value);
        }
      });
    // 首图宽高比（竖看页高估算用；一次解析即够——页图同尺寸导出）。
    if (widget.pagePngs.isNotEmpty) {
      final stream =
          Image.file(widget.pagePngs.first).image.resolve(const ImageConfiguration());
      late final ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        final w = info.image.width, h = info.image.height;
        if (w > 0 && h > 0 && mounted) {
          setState(() => _aspectCache = w / h);
        }
        stream.removeListener(listener);
      });
      stream.addListener(listener);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _matrixAnim.dispose();
    super.dispose();
  }

  // ---- 矩阵工具（p' = p·s + t 复合；translate 在前 scale 在后）----

  Matrix4 _compose(Offset t, double s) => Matrix4.identity()
    ..translateByDouble(t.dx, t.dy, 0, 1)
    ..scaleByDouble(s, s, s, 1);

  Offset _translation(Matrix4 m) {
    final v = m.getTranslation();
    return Offset(v.x, v.y);
  }

  double _clampD(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);

  /// 平移 clamp 到内容边界（content 缺省 = 视口尺寸，页图 letterbox 也算内容）。
  Offset _clampT(Offset t, double s, Size vp, {Size? content}) {
    final cw = content?.width ?? vp.width;
    final ch = content?.height ?? vp.height;
    return Offset(
      _clampD(t.dx, math.min(0, vp.width - cw * s), 0),
      _clampD(t.dy, math.min(0, vp.height - ch * s), 0),
    );
  }

  /// 以锚点（视口坐标）缩放：锚点下的内容点保持不动。
  Matrix4 _zoomedMatrix(Matrix4 from, double scale, Offset anchor, Size vp,
      {Size? content}) {
    final s = from.getMaxScaleOnAxis();
    final t = _translation(from);
    final c = Offset((anchor.dx - t.dx) / s, (anchor.dy - t.dy) / s);
    return _compose(
        _clampT(Offset(anchor.dx - c.dx * scale, anchor.dy - c.dy * scale),
            scale, vp,
            content: content),
        scale);
  }

  Matrix4 _pannedMatrix(Matrix4 from, Offset delta, Size vp, {Size? content}) {
    final s = from.getMaxScaleOnAxis();
    final t = _translation(from);
    return _compose(
        _clampT(Offset(t.dx + delta.dx, t.dy + delta.dy), s, vp,
            content: content),
        s);
  }

  void _animateMatrix(Matrix4 target) {
    _matrixTween =
        Matrix4Tween(begin: _matrix, end: target).animate(CurvedAnimation(
            parent: _matrixAnim, curve: Curves.easeOutCubic));
    _matrixAnim
      ..reset()
      ..forward();
  }

  // ---- 指针分派 ----

  Size get _viewport => context.size ?? Size.zero;
  Size? get _textContentSize => _textKey.currentContext?.size;

  /// 两个追踪指针的间距/中点（捏合用）。
  double _span() {
    final it = _pointers.values.iterator..moveNext();
    final a = it.current;
    it.moveNext();
    return (it.current - a).distance;
  }

  Offset _focal() {
    final it = _pointers.values.iterator..moveNext();
    final a = it.current;
    it.moveNext();
    return Offset((a.dx + it.current.dx) / 2, (a.dy + it.current.dy) / 2);
  }

  /// 单指起始：页模式非缩放态 → 翻页拖动；竖看交给 ListView 原生滚动
  ///（不做矩阵平移，避免与滚动竞争）；缩放态 / 文本模式 → 平移。
  void _beginDrag(Offset pos, Duration timeStamp) {
    if (_isScrollMode) return;
    if (!_isTextMode && !_zoomed) {
      final pos0 = _controller.position;
      _pageDragStartOffset = pos0.hasContentDimensions ? pos0.pixels : null;
      _pageDragStartPos = pos;
      _pageDragLastPos = pos;
      _pageDragLastTime = timeStamp;
      _pageDragVelocity = 0;
    } else {
      _pageDragStartOffset = null;
      _panStartMatrix = _matrix;
      _panStartPos = pos;
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    _matrixAnim.stop();
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      // 进入捏合：翻页/平移让位，快照指间与矩阵
      _pageDragStartOffset = null;
      _panStartMatrix = null;
      _pinchStartSpan = _span();
      _pinchStartFocal = _focal();
      _pinchStartMatrix = _matrix;
    } else if (_pointers.length == 1) {
      _beginDrag(e.localPosition, e.timeStamp);
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return; // 鼠标悬停（无按下）不追踪
    _pointers[e.pointer] = e.localPosition;
    final vp = _viewport;
    if (vp == Size.zero) return;

    if (_pinchStartMatrix != null && _pointers.length >= 2) {
      // 捏合：起始 focal 的内容点跟随当前指间（缩放+平移一并完成）
      final s0 = _pinchStartMatrix!.getMaxScaleOnAxis();
      final t0 = _translation(_pinchStartMatrix!);
      final ratio = _pinchStartSpan! > 0 ? _span() / _pinchStartSpan! : 1.0;
      final s = _clampD(s0 * ratio, _minScale, _maxScale);
      final c = Offset((_pinchStartFocal!.dx - t0.dx) / s0,
          (_pinchStartFocal!.dy - t0.dy) / s0);
      final f = _focal();
      setState(() {
        _matrix = _compose(
            _clampT(Offset(f.dx - c.dx * s, f.dy - c.dy * s), s, vp,
                content: _isTextMode ? _textContentSize : null),
            s);
      });
    } else if (_pageDragStartOffset != null && _pageDragStartPos != null) {
      // 非缩放态横拖 → 驱动翻页（jumpTo，物理关闭；无限页无边界 clamp）
      final pos0 = _controller.position;
      if (!pos0.hasContentDimensions) return;
      pos0.jumpTo(_pageDragStartOffset! -
          (e.localPosition.dx - _pageDragStartPos!.dx));
      // 简易甩动速度（低通平滑）：offset 增速，向左拖为正 → 下一页
      final dt = (e.timeStamp - _pageDragLastTime).inMicroseconds / 1e6;
      if (dt > 0) {
        final v = -(e.localPosition.dx - _pageDragLastPos!.dx) / dt;
        _pageDragVelocity = _pageDragVelocity * 0.6 + v * 0.4;
      }
      _pageDragLastPos = e.localPosition;
      _pageDragLastTime = e.timeStamp;
    } else if (_panStartMatrix != null && _panStartPos != null) {
      // 缩放态 / 文本模式拖动 → 平移（以按下点为锚整体跟随）
      final s = _panStartMatrix!.getMaxScaleOnAxis();
      final t0 = _translation(_panStartMatrix!);
      final delta = e.localPosition - _panStartPos!;
      setState(() {
        _matrix = _compose(
            _clampT(Offset(t0.dx + delta.dx, t0.dy + delta.dy), s, vp,
                content: _isTextMode ? _textContentSize : null),
            s);
      });
    }
  }

  void _endPointer(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length == 1) {
      // 捏合剩单指 → 按当前态重锚定（未缩放回翻页拖动、已缩放转平移）
      _pinchStartMatrix = null;
      _beginDrag(_pointers.values.first, e.timeStamp);
      return;
    }
    if (_pointers.isNotEmpty) return;
    // 全部抬起
    _panStartMatrix = null;
    _panStartPos = null;
    _pinchStartMatrix = null;
    if (_pageDragStartOffset != null) {
      _pageDragStartOffset = null;
      _pageDragStartPos = null;
      _settlePage();
    }
    // 缩放掉回 1：页模式 snap 回 identity；文本模式保留滚动位（ty 即滚动），
    // 只按 s=1 重新 clamp。
    if (_matrix.getMaxScaleOnAxis() <= _minScale + 0.001) {
      if (_isTextMode) {
        final vp = _viewport;
        if (vp != Size.zero) {
          setState(() {
            _matrix = _compose(
                _clampT(_translation(_matrix), 1, vp,
                    content: _textContentSize),
                1);
          });
        }
      } else if (_matrix != Matrix4.identity()) {
        _animateMatrix(Matrix4.identity());
      }
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta;
    final d = delta.dy != 0 ? delta.dy : delta.dx; // 横向滚轮（触控板横扫）同翻页
    if (d == 0) return;
    final vp = _viewport;
    if (vp == Size.zero) return;
    _matrixAnim.stop();
    if (HardwareKeyboard.instance.isControlPressed) {
      // Ctrl+滚轮缩放（锚点视口中心，任务规格）
      final s = _matrix.getMaxScaleOnAxis();
      final next = _clampD(s + (d > 0 ? -0.1 : 0.1), _minScale, _maxScale);
      final content = _isTextMode ? _textContentSize : null;
      setState(() {
        _matrix = _zoomedMatrix(
            _matrix, next, Offset(vp.width / 2, vp.height / 2), vp,
            content: content);
      });
    } else if (_isTextMode || _zoomed) {
      // 文本模式 / 页模式缩放态：滚轮垂直平移（缩放态翻页锁定）
      final content = _isTextMode ? _textContentSize : null;
      setState(() {
        _matrix = _pannedMatrix(_matrix, Offset(0, -d), vp, content: content);
      });
    } else if (_isScrollMode) {
      // 竖看：滚轮交给内层 ListView 原生滚动；此处只处理**到底循环**——
      // 已在最大滚动位仍向下滚 → 累积超过阈值回第一页。
      if (_scroll.hasClients &&
          _scroll.position.pixels >=
              _scroll.position.maxScrollExtent - 2 &&
          d > 0) {
        _loopAccum += d;
        if (_loopAccum >= _loopOverscroll) {
          _loopAccum = 0;
          _scroll.jumpTo(0);
          if (mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(
                  content: Text('已重头查看'), duration: Duration(seconds: 1)));
          }
        }
      } else {
        _loopAccum = 0;
      }
    } else {
      _go(d > 0 ? 1 : -1); // 下/右滚 = 下一页（循环）
    }
  }

  void _onDoubleTap() {
    final vp = _viewport;
    if (vp == Size.zero || _isScrollMode) return; // 竖看不做矩阵缩放
    _matrixAnim.stop();
    if (_zoomed) {
      _animateMatrix(Matrix4.identity());
    } else {
      // 2.5x 居中：内容点 c（此时 t=0,s=1）放大后仍居中
      final s = _doubleTapScale;
      final c = Offset(vp.width / 2, vp.height / 2);
      _animateMatrix(_compose(Offset(-c.dx * (s - 1), -c.dy * (s - 1)), s));
    }
  }

  // ---- 翻页（横看 · 无限循环）----

  /// 逐页翻（滚轮/按钮共用）；快速连滚按当前动画目标累加（page 取整）。
  void _go(int delta) {
    if (_pageCount == 0 || !_controller.hasClients) return;
    final page = _controller.page;
    _animateToPage((page?.round() ?? _pageBase) + delta); // 无 clamp = 循环
  }

  void _animateToPage(int page) {
    if (_pageCount == 0 || !_controller.hasClients) return;
    _controller.animateToPage(page,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic);
  }

  /// 拖动结束归位：快甩顺速度方向翻一页，慢拖四舍五入对齐。
  void _settlePage() {
    final pos0 = _controller.position;
    if (!pos0.hasContentDimensions) return;
    final vpW = pos0.viewportDimension;
    if (vpW <= 0) return;
    final current = pos0.pixels / vpW;
    final target = _pageDragVelocity.abs() > _flickVelocity
        ? (_pageDragVelocity > 0 ? current.floor() + 1 : current.floor())
        : current.round();
    _animateToPage(target);
  }

  // ---- 文本模式 ----

  Future<void> _copySource() async {
    final text = widget.gpxSourceText;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制源文件全文')));
    }
  }

  /// 横看 ↔ 竖看切换：保留当前页（竖看跳到当前页顶部，页高按首图
  /// 宽高比估算）。
  void _toggleMode() {
    setState(() {
      if (_mode == _ViewMode.paged) {
        _mode = _ViewMode.scroll;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scroll.hasClients) return;
          _scroll.jumpTo(math.max(0, _index * _pageHeight - 8));
        });
      } else {
        _mode = _ViewMode.paged;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_controller.hasClients) return;
          _controller.jumpTo((_pageBase + _index).toDouble());
        });
      }
    });
  }

  double? _aspectCache; // 首图宽高比（竖看页高估算）

  /// 竖看模式下单页渲染高度（视口宽 ÷ 首图宽高比；比例未载入时按视口高兜底）。
  double get _pageHeight {
    final vp = _viewport;
    if (vp == Size.zero) return 400;
    if (_aspectCache != null && _aspectCache! > 0) {
      return vp.width / _aspectCache!;
    }
    return vp.height;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (_isTextMode) return _buildTextMode(p);
    if (_pageCount == 0) {
      return Center(child: Text('没有页图', style: TextStyle(color: p.muted)));
    }
    final multi = _pageCount > 1;
    return Stack(children: [
      Positioned.fill(
        child: _isScrollMode
            ? NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  // 竖看到底后继续向下滚（ListBody 边界内 overscroll 通知）
                  // → 累积回顶（滚轮与触控拖动统一走此通道）。
                  if (n is OverscrollNotification && n.overscroll > 0) {
                    _loopAccum += n.overscroll;
                    if (_loopAccum >= _loopOverscroll) {
                      _loopAccum = 0;
                      _scroll.jumpTo(0);
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(const SnackBar(
                              content: Text('已重头查看'),
                              duration: Duration(seconds: 1)));
                      }
                    }
                  } else if (n is ScrollUpdateNotification) {
                    _loopAccum = 0;
                  }
                  return false;
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _endPointer,
                  onPointerCancel: _endPointer,
                  onPointerSignal: _onPointerSignal,
                  child: ListView.builder(
                    controller: _scroll,
                    itemCount: _pageCount,
                    itemBuilder: (ctx, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Image.file(widget.pagePngs[i],
                          fit: BoxFit.fitWidth),
                    ),
                  ),
                ),
              )
            : Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _endPointer,
                onPointerCancel: _endPointer,
                onPointerSignal: _onPointerSignal,
                child: PageView.builder(
                  controller: _controller,
                  // **无限页循环**（2026-11-23 用户需求：末页右滑回第一页
                  // 重头查看）——itemCount 无限，取模显示真实页。
                  itemCount: null,
                  // 翻页手势全手写（滚轮/横拖/按钮）：物理恒关闭——既防拖动竞争，
                  // 也让 Scrollable 不注册滚轮（滚轮归外层 Listener 翻页）。
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (raw) => setState(() {
                    _index = ((raw - _pageBase) % _pageCount + _pageCount) %
                        _pageCount;
                    _matrixTween = null; // 先断补间（reset 触发 listener 不得回写）
                    _matrixAnim.reset();
                    _matrix = Matrix4.identity(); // 翻页复位缩放
                  }),
                  itemBuilder: (ctx, raw) {
                    final i = ((raw - _pageBase) % _pageCount + _pageCount) %
                        _pageCount;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: _onDoubleTap,
                      child: Transform(
                        key: SourceViewer.transformKey,
                        transform: _matrix,
                        child: Center(
                            child: Image.file(widget.pagePngs[i],
                                fit: BoxFit.contain)),
                      ),
                    );
                  },
                ),
              ),
      ),
      if (multi) ...[
        // 左右翻页按钮（横看；循环翻页下恒可用——末页右滑回第一页）。
        if (!_isScrollMode) ...[
          Positioned(
            left: 8,
            top: 0,
            bottom: 28,
            child: Center(
              child: _PageButton(
                  enabled: true,
                  icon: Icons.chevron_left,
                  onTap: () => _go(-1)),
            ),
          ),
          Positioned(
            right: 8,
            top: 0,
            bottom: 28,
            child: Center(
              child: _PageButton(
                  enabled: true,
                  icon: Icons.chevron_right,
                  onTap: () => _go(1)),
            ),
          ),
        ],
        // 页码 + 横看/竖看切换（随时变更，保留当前页）。
        Positioned(
          left: 0,
          right: 0,
          bottom: 6,
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: p.panel,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${_index + 1} / $_pageCount',
                    style: TextStyle(
                        fontSize: 12,
                        color: p.muted,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 10),
                InkWell(
                  onTap: _toggleMode,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                        _isScrollMode
                            ? Icons.swap_horiz
                            : Icons.view_agenda_outlined,
                        size: 16,
                        color: p.ink),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ],
    ]);
  }

  /// gpx 源文件文本视图：单页等宽文本，滚轮/拖动平移、捏合/双击/Ctrl+滚轮缩放。
  Widget _buildTextMode(GuitarBarPalette p) {
    return Stack(children: [
      Positioned.fill(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _endPointer,
          onPointerCancel: _endPointer,
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: _onDoubleTap,
            child: Transform(
              key: SourceViewer.transformKey,
              transform: _matrix,
              // 紧约束下 Padding 会被强制成视口大小，实测内容高度拿不到——
              // OverflowBox 松开高度约束让文本按内容自然撑开（宽度随父）。
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minHeight: 0,
                maxHeight: double.infinity,
                child: Padding(
                  key: _textKey,
                  padding: const EdgeInsets.all(16),
                  child: Text(widget.gpxSourceText!,
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          fontFamily: 'monospace',
                          color: p.ink)),
                ),
              ),
            ),
          ),
        ),
      ),
      // 底部复制按钮（源文件查看的唯一动作）。
      Positioned(
        left: 0,
        right: 0,
        bottom: 12,
        child: Center(
          child: FilledButton.icon(
            onPressed: _copySource,
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制'),
          ),
        ),
      ),
    ]);
  }
}

/// 半透明翻页按钮；禁用时隐藏（首/末页无前进方向）。
class _PageButton extends StatelessWidget {
  const _PageButton(
      {required this.enabled, required this.icon, required this.onTap});
  final bool enabled;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    final p = context.palette;
    return Material(
      color: p.panel.withValues(alpha: 0.85),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 22, color: p.ink),
        ),
      ),
    );
  }
}
