import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// 琴头插画 + 两侧音名方钮（调音页签名元素）。
///
/// 纯表现层：不读 TuningState，只接收已算好的音名、命中弦与回调，
/// 因此可以脱离数据库/麦克风单独渲染（见 test/headstock_test.dart）。
///
/// 构图照参考图：中央是深色玫瑰木琴头（冠形顶边 + 奶油双线包边 + 金饰镶嵌 +
/// 三排铬弦钮 + 弦枕/指板），左右各三个音名方钮，与三排弦钮同高。
/// 六个方钮与琴头、弦钮机械件的矩形**互不重叠**——旧版圆钮压在弦钮上的
/// 问题由 HeadstockMetrics 的几何保证，并有单测守着。
///
/// 尺寸随父约束自适应，所以 Windows 打样窗口与 iPad 11 寸（横/竖屏）
/// 共用同一份比例：给多少高度就用多少，宽度由内容反推。
class GuitarHeadstock extends StatelessWidget {
  const GuitarHeadstock({
    super.key,
    required this.labels,
    required this.hitIndex,
    required this.lockedIndex,
    required this.hasPitch,
    required this.cents,
    required this.onTapString,
  }) : assert(labels.length == 6, '琴头固定 6 根弦');

  /// 6 根弦的音名（低→高，如 `E2`），与 TuningState.current.strings 同序。
  final List<String> labels;

  /// 自动认弦命中的弦（0..5，-1 = 未命中）。
  final int hitIndex;

  /// 手动锁定的弦（null = 自动模式）。
  final int? lockedIndex;

  /// 是否已检到音高（否则整幅画不显示命中态）。
  final bool hasPitch;

  /// 相对目标弦的偏差音分。
  final int cents;

  /// 点第 i 根弦：播参考音 + 锁定。
  final ValueChanged<int> onTapString;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final inTune = hasPitch && cents.abs() <= 3;
    return LayoutBuilder(builder: (context, c) {
      final m = HeadstockMetrics.fit(c.biggest);
      return SizedBox.fromSize(
        size: m.canvas,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _HeadstockPainter(
                metrics: m,
                hitIndex: hasPitch ? hitIndex : -1,
                inTune: inTune,
                dataHue: p.dataHue,
                positive: p.positive,
              ),
            ),
          ),
          for (var i = 0; i < 6; i++)
            Positioned.fromRect(
              rect: m.buttonRects[i],
              child: _NoteButton(
                label: labels[i],
                side: m.buttonSide,
                hit: i == lockedIndex || (hasPitch && i == hitIndex),
                inTune: hasPitch && i == hitIndex && inTune,
                onTap: () => onTapString(i),
              ),
            ),
        ]),
      );
    });
  }
}

/// 琴头画布几何：painter 与交互方钮共用同一套数字，避免"画的"与"点的"错位。
///
/// 所有长度都由画布高度 h 派生，因此任意尺寸下比例不变。
class HeadstockMetrics {
  const HeadstockMetrics._({
    required this.canvas,
    required this.plate,
    required this.rowYs,
    required this.buttonRects,
    required this.buttonSide,
    required this.machineRects,
    required this.nutRect,
  });

  /// fit 的初值宽高比（实际宽度由内容反推，见 [forHeight]）。
  static const double aspect = 1.27;

  /// 按父约束取最大可用尺寸（高度吃满，宽度按内容反推）。
  ///
  /// 方钮边长有 44px 触控下限，极小尺寸下比按比例算出的更宽，所以要收敛
  /// 一次：宽度超出可用宽度时按比例回缩高度。
  factory HeadstockMetrics.fit(Size max) {
    final maxH = max.height.isFinite ? max.height : max.width / aspect;
    final maxW = max.width.isFinite ? max.width : maxH * aspect;
    var h = math.min(maxH, maxW / aspect);
    if (!h.isFinite || h <= 0) h = 300;
    var m = HeadstockMetrics.forHeight(h.clamp(160.0, 720.0));
    for (var i = 0; i < 2 && m.canvas.width > maxW + 0.5; i++) {
      h = h * maxW / m.canvas.width;
      m = HeadstockMetrics.forHeight(h.clamp(120.0, 720.0));
    }
    return m;
  }

  /// 直接按画布高度构造（测试与预览用）；宽度由内容反推。
  factory HeadstockMetrics.forHeight(double h) {
    final plateTop = 0.012 * h;
    final plateBottom = 0.792 * h; // 弦枕顶边（下方 20% 留给琴颈）
    final plateH = plateBottom - plateTop;
    final plateW = plateH * 0.62; // 参考图琴头宽高比

    final shaft = 0.040 * h; // 弦钮轴杆
    final knobW = 0.072 * h; // 外伸蝶形钮
    final gap = 0.056 * h; // 蝶形钮与方钮的空隙
    final pitch = plateH * 0.227; // 三排弦钮行距（参考图比例）
    // 边长取行距的 78%，并保 44px 触控下限（iPad 手指点按）；但绝不能超过
    // 行距本身（否则上下两钮会叠在一起，极端小尺寸下宁可缩钮也不叠）。
    final buttonSide = math.min(math.max(44.0, pitch * 0.78), pitch * 0.88);

    final half = plateW / 2 + shaft + knobW + gap + buttonSide;
    final w = half * 2 * 1.02; // 两侧各留 2% 余量
    final canvas = Size(w, h);
    final cx = w / 2;
    final plate =
        Rect.fromLTRB(cx - plateW / 2, plateTop, cx + plateW / 2, plateBottom);

    final rowYs = [
      for (final f in const [0.148, 0.375, 0.602]) plateTop + plateH * f,
    ];

    // 方钮列固定在中轴两侧（不随琴头收腰偏移），与参考图一致。
    final colOffset = plateW / 2 + shaft + knobW + gap + buttonSide / 2;

    final buttonRects = <Rect>[
      for (var i = 0; i < 6; i++)
        Rect.fromCenter(
          center: Offset(cx + (i <= 2 ? -colOffset : colOffset),
              rowYs[i <= 2 ? 2 - i : i - 3]),
          width: buttonSide,
          height: buttonSide,
        ),
    ];
    final machineRects = <Rect>[
      for (var row = 0; row < 3; row++)
        for (final left in const [true, false])
          _machineRect(row, left, plate, rowYs, h, shaft, knobW),
    ];
    final nutRect = Rect.fromCenter(
      center: Offset(cx, plateBottom + 0.008 * h),
      // 弦枕是琴头底边的收口（比板底略宽，把板底硬角吃进去）。
      width: plateW * 0.795,
      height: 0.026 * h,
    );
    return HeadstockMetrics._(
      canvas: canvas,
      plate: plate,
      rowYs: rowYs,
      buttonRects: buttonRects,
      buttonSide: buttonSide,
      machineRects: machineRects,
      nutRect: nutRect,
    );
  }

  final Size canvas;
  final Rect plate;

  /// 三排弦钮的 y（左列自上而下 = 弦 2/1/0，右列 = 弦 3/4/5）。
  final List<double> rowYs;

  /// 六个音名方钮的矩形，下标即弦序（0 = 低音 E）。
  final List<Rect> buttonRects;

  /// 方钮边长。
  final double buttonSide;

  /// 六个外伸蝶形弦钮的矩形（下标 = row*2 + (左 ? 0 : 1)）。
  final List<Rect> machineRects;

  /// 弦枕矩形。
  final Rect nutRect;

  /// 弦钮行 → 弦序：左列自上而下 2/1/0，右列自上而下 3/4/5。
  static int stringAt(int row, bool left) => left ? 2 - row : 3 + row;

  static Rect _machineRect(int row, bool left, Rect plate, List<double> rowYs,
      double h, double shaft, double knobW) {
    final y = rowYs[row];
    final edge = plateHalfAt(y, plate);
    final x = left
        ? plate.center.dx - edge - shaft - knobW / 2
        : plate.center.dx + edge + shaft + knobW / 2;
    return Rect.fromCenter(
        center: Offset(x, y), width: knobW, height: 0.112 * h);
  }

  /// 琴头板在高度 y 处的半宽（侧边随高度收窄，与 painter 的轮廓同源）。
  static double plateHalfAt(double y, Rect plate) {
    final t = ((y - plate.top) / plate.height).clamp(0.0, 1.0);
    final f = t < 0.30
        ? 0.945 + 0.055 * (t / 0.30)
        : 1.0 - 0.28 * math.pow((t - 0.30) / 0.70, 1.3);
    return plate.width / 2 * f;
  }

  /// 弦枕上第 i 弦（0 = 低音 E）的 x。
  double nutX(int i) => nutRect.left + nutRect.width * (i + 1) / 7;

  /// 第 i 弦在琴头面（六角螺母处）的压弦柱 x。
  double postX(int i) {
    final left = i <= 2;
    final row = left ? 2 - i : i - 3;
    final edge = plateHalfAt(rowYs[row], plate);
    return left
        ? plate.center.dx - edge + plate.width * 0.115
        : plate.center.dx + edge - plate.width * 0.115;
  }
}

/// 单个音名方钮：圆角方块 + 大字母，三态（到位 > 命中 > 静置）。
/// 底色随主题：浅色板用浅底深字、深色板用深底浅字（与页面同调）。
class _NoteButton extends StatelessWidget {
  const _NoteButton({
    required this.label,
    required this.side,
    required this.hit,
    required this.inTune,
    required this.onTap,
  });

  final String label;
  final double side;
  final bool hit;
  final bool inTune;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // 按配色本体的明度判断深浅：theme.dart 的 ColorScheme 明暗与色板是反着
    // 建的（深色板用 ColorScheme.light），所以不能读 Theme.brightness。
    final dark = p.ground.computeLuminance() < 0.5;
    // 按钮只显示音名本身（不带八度）：八度对调音没有作用，反而挤小字号。
    final letter = _pitchClass(label);

    final Color bg;
    final Color border;
    final Color ink;
    if (inTune) {
      bg = dark ? const Color(0xFF12251A) : p.pillPositiveBg;
      border = p.positive;
      ink = dark ? Color.lerp(p.positive, Colors.white, 0.35)! : p.pillPositiveInk;
    } else if (hit) {
      bg = Color.alphaBlend(
          p.dataHue.withValues(alpha: dark ? 0.22 : 0.14),
          dark ? const Color(0xFF26231D) : p.surface);
      border = p.dataHue;
      ink = dark ? Color.lerp(p.dataHue, Colors.white, 0.42)! : p.dataHue;
    } else {
      bg = dark ? const Color(0xFF322E27) : p.surface;
      border = dark ? const Color(0xFF4A453C) : p.controlBorder;
      ink = dark ? const Color(0xFFC9C3B7) : p.ink;
    }
    final radius = side * 0.305;

    return Semantics(
      button: true,
      label: '$label 弦',
      child: AnimatedScale(
        scale: inTune ? 0.955 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: BorderSide(color: border, width: hit || inTune ? 1.6 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: side * 0.42,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// `D3` → `D`；`C#4` → `C#`；无法解析时原样返回。
  static String _pitchClass(String s) {
    final m = RegExp(r'^([A-Ga-g][#b]?)').firstMatch(s.trim());
    return m?.group(1) ?? s;
  }
}

// ── 插画配色：与页面主题无关的固定木色/金属色（同 theme.dart 的约定：
//    BuildContext 无关的插画直接用字面色，避免随主题漂移）。
const Color _woodTop = Color(0xFF8B5330);
const Color _woodMid = Color(0xFF6F3D1E);
const Color _woodDeep = Color(0xFF48260F);
const Color _binding = Color(0xFFE8DBBF);
const Color _purfling = Color(0xFF180D06);
const Color _inlayGold = Color(0xFFC39A46);
const Color _inlayLight = Color(0xFFEBCE86);
const Color _chrome = Color(0xFFC6C8CE);
const Color _chromeHi = Color(0xFFF4F5F8);
const Color _chromeMid = Color(0xFFA7A9B0);
const Color _chromeLow = Color(0xFF6B6D73);
const Color _stringSteel = Color(0xFFCFCBC2);
const Color _nutBone = Color(0xFFEDE1C6);
const Color _fingerboard = Color(0xFF2A190E);
const Color _fret = Color(0xFFB4B6BA);
const Color _trussRod = Color(0xFF241410);

/// 六根弦的相对直径（低音缠弦最粗 → 高音素弦最细）。
const List<double> _stringGauge = [1.00, 0.87, 0.75, 0.63, 0.52, 0.43];

/// 琴头绘制：木底渐变 → 木纹 → 边缘压暗 → 柔光 → 金饰 → 桁杆盖 →
/// 包边 → 指板（含品丝/过弦，底端淡出）→ 弦枕 → 弦钮机械件 → 六根弦 → 压弦柱。
class _HeadstockPainter extends CustomPainter {
  _HeadstockPainter({
    required this.metrics,
    required this.hitIndex,
    required this.inTune,
    required this.dataHue,
    required this.positive,
  });

  final HeadstockMetrics metrics;
  final int hitIndex;
  final bool inTune;
  final Color dataHue;
  final Color positive;

  @override
  void paint(Canvas canvas, Size size) {
    final m = metrics;
    final r = m.plate;
    final body = _platePath(r);
    final edge = _platePath(r, closeBottom: false);
    _paintWood(canvas, body, r);
    _paintInlay(canvas, r);
    _paintTrussRodCover(canvas, r);
    _paintBinding(canvas, edge);
    _paintNutAndFingerboard(canvas, m);
    _paintMachines(canvas, m);
    _paintStrings(canvas, m);
    _paintPosts(canvas, m);
  }

  // ── 琴头轮廓：冠形顶边（双肩 + 中央凹口）+ 侧边收窄到弦枕 ────────────
  //
  // [closeBottom] = false 时不画底边：底边由弦枕收口，包边也不能在板底横一道
  // 奶油线（否则弦枕下面多出第二条，看着像两根弦枕）。
  Path _platePath(Rect r, {bool closeBottom = true}) {
    double x(double v) => r.left + r.width * v;
    double y(double v) => r.top + r.height * v;
    final p = Path()
      ..moveTo(x(0.140), y(1.000))
      // 左侧：自下而上，先略外撑，再收进肩部。
      ..cubicTo(x(0.060), y(0.700), x(-0.012), y(0.290), x(0.000), y(0.092))
      // 左肩峰。
      ..cubicTo(x(0.028), y(0.040), x(0.072), y(0.026), x(0.108), y(0.036))
      // 肩下凹谷。
      ..cubicTo(x(0.160), y(0.052), x(0.214), y(0.080), x(0.276), y(0.078))
      // 上升到中央凹口左沿。
      ..cubicTo(x(0.360), y(0.074), x(0.428), y(0.030), x(0.470), y(0.010))
      // 中央凹口：向下的小 V（参考图"王冠"缺口），底略高于两侧肩峰。
      ..lineTo(x(0.500), y(0.034))
      ..lineTo(x(0.530), y(0.010))
      ..cubicTo(x(0.572), y(0.030), x(0.640), y(0.074), x(0.724), y(0.078))
      ..cubicTo(x(0.786), y(0.080), x(0.840), y(0.052), x(0.892), y(0.036))
      ..cubicTo(x(0.928), y(0.026), x(0.972), y(0.040), x(1.000), y(0.092))
      // 右侧：先略外撑，再向弦枕收窄。
      ..cubicTo(x(1.012), y(0.290), x(0.940), y(0.700), x(0.860), y(1.000));
    if (closeBottom) {
      p
        ..lineTo(x(0.140), y(1.000))
        ..close();
    }
    return p;
  }

  // ── 木底：竖向渐变 + 木纹 + 边缘压暗 + 顶部柔光 ──────────────────────
  void _paintWood(Canvas canvas, Path path, Rect r) {
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_woodTop, _woodMid, _woodDeep],
          stops: [0.0, 0.45, 1.0],
        ).createShader(r),
    );

    canvas.save();
    canvas.clipPath(path);
    // 直木纹：确定性正弦扰动（同尺寸每帧一致，不用随机数）。
    for (var i = 0; i < 28; i++) {
      final xBase = r.left + r.width * (i + 0.5) / 28;
      final grain = Path()..moveTo(xBase, r.top);
      for (var k = 1; k <= 8; k++) {
        grain.lineTo(xBase + math.sin(i * 1.9 + k * 0.85) * r.width * 0.005,
            r.top + r.height * k / 8);
      }
      final dark = i.isEven;
      canvas.drawPath(
        grain,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = dark ? 1.3 : 0.9
          ..color = dark ? const Color(0x14140803) : const Color(0x0CFFE2C0),
      );
    }
    // 玫瑰木的细密纵向导管。
    for (var i = 0; i < 60; i++) {
      final gx = r.left + r.width * ((i * 0.618) % 1.0);
      final gy = r.top + r.height * ((i * 0.377) % 1.0);
      canvas.drawLine(
        Offset(gx, gy),
        Offset(gx + 0.6, gy + r.height * 0.012),
        Paint()
          ..strokeWidth = 0.9
          ..color = const Color(0x121A0C04),
      );
    }
    // 边缘压暗：让板面有轻微弧面/厚度感（不靠外投影）。
    canvas.drawPath(
      path,
      Paint()
        ..shader = const RadialGradient(
          radius: 0.95,
          colors: [Color(0x00000000), Color(0x38190A03)],
          stops: [0.50, 1.0],
        ).createShader(r),
    );
    canvas.restore();

    // 顶部柔光（弧面感来自受光，不靠阴影）。
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.42],
        ).createShader(r),
    );
    canvas.restore();
  }

  // ── 金饰镶嵌：中央矛形 + 两侧叶片（实心，小尺寸下更清晰）──────────────
  void _paintInlay(Canvas canvas, Rect r) {
    final cx = r.center.dx;
    final cy = r.top + r.height * 0.115;
    final u = r.width;
    final gold = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [_inlayLight, _inlayGold, Color(0xFF8E6A24)],
      ).createShader(Rect.fromCenter(
          center: Offset(cx, cy), width: u * 0.46, height: u * 0.30));

    // 中央矛形。
    final spear = Path()
      ..moveTo(cx, cy - u * 0.062)
      ..cubicTo(cx + u * 0.026, cy - u * 0.022, cx + u * 0.032, cy + u * 0.030,
          cx, cy + u * 0.080)
      ..cubicTo(cx - u * 0.032, cy + u * 0.030, cx - u * 0.026, cy - u * 0.022,
          cx, cy - u * 0.062)
      ..close();
    canvas.drawPath(spear, gold);

    for (final s in const [-1.0, 1.0]) {
      // 外扫主叶。
      canvas.drawPath(
        Path()
          ..moveTo(cx + s * u * 0.030, cy + u * 0.014)
          ..cubicTo(cx + s * u * 0.052, cy - u * 0.046, cx + s * u * 0.098,
              cy - u * 0.062, cx + s * u * 0.122, cy - u * 0.038)
          ..cubicTo(cx + s * u * 0.102, cy - u * 0.014, cx + s * u * 0.070,
              cy + u * 0.008, cx + s * u * 0.030, cy + u * 0.014)
          ..close(),
        gold,
      );
      // 下方的小副叶。
      canvas.drawPath(
        Path()
          ..moveTo(cx + s * u * 0.026, cy + u * 0.030)
          ..cubicTo(cx + s * u * 0.056, cy + u * 0.024, cx + s * u * 0.078,
              cy + u * 0.036, cx + s * u * 0.082, cy + u * 0.056)
          ..cubicTo(cx + s * u * 0.058, cy + u * 0.052, cx + s * u * 0.036,
              cy + u * 0.046, cx + s * u * 0.026, cy + u * 0.030)
          ..close(),
        gold,
      );
      canvas.drawCircle(Offset(cx + s * u * 0.146, cy - u * 0.024),
          math.max(1.0, u * 0.009), gold);
    }
  }

  // ── 桁杆盖（黑色盾形 + 两颗螺钉）──────────────────────────────────────
  void _paintTrussRodCover(Canvas canvas, Rect r) {
    final cx = r.center.dx;
    final halfW = r.width * 0.072;
    final top = r.top + r.height * 0.735;
    final bottom = r.top + r.height * 0.965;
    final shape = Path()
      ..moveTo(cx, top)
      ..cubicTo(cx + halfW * 0.95, top, cx + halfW, top + r.height * 0.012,
          cx + halfW, top + r.height * 0.058)
      ..lineTo(cx + halfW * 0.84, bottom - r.height * 0.020)
      ..quadraticBezierTo(cx, bottom + r.height * 0.008,
          cx - halfW * 0.84, bottom - r.height * 0.020)
      ..lineTo(cx - halfW, top + r.height * 0.058)
      ..cubicTo(cx - halfW, top + r.height * 0.012, cx - halfW * 0.95, top, cx,
          top)
      ..close();
    canvas.drawPath(shape, Paint()..color = _trussRod);
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = const Color(0x4DFFFFFF),
    );
    for (final y in [
      top + r.height * 0.052,
      bottom - r.height * 0.042,
    ]) {
      final sr = math.max(2.0, r.width * 0.012);
      canvas.drawCircle(Offset(cx, y), sr, Paint()..color = _chromeMid);
      canvas.drawCircle(Offset(cx - sr * 0.2, y - sr * 0.2), sr * 0.62,
          Paint()..color = _chromeHi);
      canvas.drawLine(
        Offset(cx - sr * 0.8, y),
        Offset(cx + sr * 0.8, y),
        Paint()
          ..strokeWidth = math.max(0.8, sr * 0.28)
          ..color = _purfling,
      );
    }
  }

  // ── 包边：深色 purfling 宽一圈，奶油细边压在上面 → 双线包边 ──────────
  void _paintBinding(Canvas canvas, Path path) {
    final h = metrics.canvas.height;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(4.0, h * 0.0175)
        ..color = _purfling,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.4, h * 0.0115)
        ..color = _binding,
    );
  }

  // ── 指板（含品丝与过弦，底端淡出）+ 弦枕 ─────────────────────────────
  void _paintNutAndFingerboard(Canvas canvas, HeadstockMetrics m) {
    final h = m.canvas.height;
    final nut = m.nutRect;
    final fbTop = nut.bottom - 1;
    final fbBottom = h;
    // 琴颈比弦枕略窄，但必须把外侧两根弦包在里面（弦槽在 1/7..6/7 上）。
    final fbHalfTop = nut.width / 2 * 0.75;
    final fbHalfBottom = nut.width / 2 * 0.79;
    double fbHalfAt(double y) {
      final t = ((y - fbTop) / (fbBottom - fbTop)).clamp(0.0, 1.0);
      return fbHalfTop + (fbHalfBottom - fbHalfTop) * t;
    }

    // 指板向画布底端淡出（琴颈在真琴上一直延伸出去，硬切一刀像模型被切掉）。
    final fadeRect = Rect.fromLTRB(0, fbTop, m.canvas.width, fbBottom);
    canvas.saveLayer(fadeRect, Paint());
    final fb = Path()
      ..moveTo(nut.center.dx - fbHalfTop, fbTop)
      ..lineTo(nut.center.dx + fbHalfTop, fbTop)
      ..lineTo(nut.center.dx + fbHalfBottom, fbBottom)
      ..lineTo(nut.center.dx - fbHalfBottom, fbBottom)
      ..close();
    canvas.drawPath(fb, Paint()..color = _fingerboard);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, h * 0.005)
      ..color = _binding;
    canvas.drawLine(Offset(nut.center.dx - fbHalfTop, fbTop),
        Offset(nut.center.dx - fbHalfBottom, fbBottom), edge);
    canvas.drawLine(Offset(nut.center.dx + fbHalfTop, fbTop),
        Offset(nut.center.dx + fbHalfBottom, fbBottom), edge);
    // 品丝：间距随远离弦枕递增（画布只露出一小段琴颈，最多两三根）。
    var y = fbTop + h * 0.055;
    var step = h * 0.055;
    final fretPaint = Paint()
      ..strokeWidth = math.max(0.9, h * 0.0028)
      ..color = _fret;
    while (y < fbBottom) {
      final half = fbHalfAt(y);
      canvas.drawLine(Offset(nut.center.dx - half, y),
          Offset(nut.center.dx + half, y), fretPaint);
      y += step;
      step *= 1.55;
    }
    // 越过弦枕落在指板上的弦段。
    for (var i = 0; i < 6; i++) {
      final sx = m.nutX(i);
      final hit = hitIndex == i;
      canvas.drawLine(
        Offset(sx, fbTop),
        Offset(sx, fbBottom),
        Paint()
          ..strokeWidth = math.max(0.9, h * 0.0085 * _stringGauge[i]) *
              (hit ? 1.25 : 1.0)
          ..color = hit ? (inTune ? positive : dataHue) : _stringSteel,
      );
    }
    canvas.drawRect(
      fadeRect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          stops: [0.0, 0.45, 0.90],
        ).createShader(fadeRect),
    );
    canvas.restore();

    // 弦枕（奶油条，压住琴头底边）。
    canvas.drawRRect(
      RRect.fromRectAndRadius(nut, Radius.circular(h * 0.004)),
      Paint()..color = _nutBone,
    );
    canvas.drawLine(
      Offset(nut.left, nut.top + nut.height * 0.22),
      Offset(nut.right, nut.top + nut.height * 0.22),
      Paint()
        ..strokeWidth = 1.0
        ..color = const Color(0x33000000),
    );
    // 六条弦槽。
    for (var i = 0; i < 6; i++) {
      final sx = m.nutX(i);
      canvas.drawLine(
        Offset(sx, nut.top + 1),
        Offset(sx, nut.bottom - 1),
        Paint()
          ..strokeWidth = math.max(1.0, h * 0.0042)
          ..color = const Color(0x66402A14),
      );
    }
  }

  // ── 弦钮机械件：轴杆 + 外伸蝶形钮 ────────────────────────────────────
  void _paintMachines(Canvas canvas, HeadstockMetrics m) {
    final h = m.canvas.height;
    final shaftH = math.max(2.0, h * 0.016);
    for (var row = 0; row < 3; row++) {
      for (final left in const [true, false]) {
        final rect = m.machineRects[row * 2 + (left ? 0 : 1)];
        final y = m.rowYs[row];
        final edgeX = left
            ? m.plate.center.dx - HeadstockMetrics.plateHalfAt(y, m.plate)
            : m.plate.center.dx + HeadstockMetrics.plateHalfAt(y, m.plate);
        final shaftEnd = left ? rect.right : rect.left;
        final shaftRect = Rect.fromLTRB(math.min(edgeX, shaftEnd),
            y - shaftH / 2, math.max(edgeX, shaftEnd), y + shaftH / 2);
        canvas.drawRect(
          shaftRect,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_chromeHi, _chrome, _chromeLow],
            ).createShader(shaftRect),
        );
        // 蝶形钮：胶囊形（半径 = 半宽），左上受光、右下压暗的金属渐变。
        final rr =
            RRect.fromRectAndRadius(rect, Radius.circular(rect.width * 0.5));
        canvas.drawRRect(
          rr,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFF4F5F8),
                Color(0xFFD2D4D9),
                Color(0xFF9EA0A7),
                Color(0xFF74767C),
              ],
              stops: [0.0, 0.34, 0.70, 1.0],
            ).createShader(rect.inflate(2)),
        );
        canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..color = const Color(0x59000000),
        );
        // 顶部一道窄高光，读作"上缘反光"。
        canvas.drawArc(
          Rect.fromLTRB(rect.left + rect.width * 0.18, rect.top + 1,
              rect.right - rect.width * 0.18, rect.top + rect.height * 0.5),
          math.pi * 1.15,
          math.pi * 0.7,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, h * 0.005)
            ..color = Colors.white.withValues(alpha: 0.55),
        );
      }
    }
  }

  // ── 六根弦：弦枕 → 压弦柱（命中 dataHue / 到位 positive）──────────────
  void _paintStrings(Canvas canvas, HeadstockMetrics m) {
    final h = m.canvas.height;
    for (var s = 0; s < 6; s++) {
      final left = s <= 2;
      final row = left ? 2 - s : s - 3;
      final y = m.rowYs[row];
      final start = Offset(m.nutX(s), m.nutRect.top + m.nutRect.height * 0.45);
      final end = Offset(m.postX(s), y);
      final hit = hitIndex == s;
      final color = hit ? (inTune ? positive : dataHue) : _stringSteel;
      final w = math.max(0.9, h * 0.0085 * _stringGauge[s]) * (hit ? 1.25 : 1.0);
      canvas.drawLine(
        start,
        end,
        Paint()
          ..strokeWidth = w + math.max(1.0, h * 0.003)
          ..color = const Color(0x40000000),
      );
      canvas.drawLine(start, end, Paint()
        ..strokeWidth = w
        ..color = color);
      // 绕柱小弧。
      canvas.drawArc(
        Rect.fromCircle(center: end, radius: h * 0.019),
        left ? math.pi * 0.18 : math.pi * 0.62,
        math.pi * 1.2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..color = color,
      );
    }
  }

  // ── 压弦柱 + 六角螺母（盖在弦上，形成"弦绕柱"的收口）────────────────
  void _paintPosts(Canvas canvas, HeadstockMetrics m) {
    final h = m.canvas.height;
    final postR = math.max(2.2, h * 0.0145);
    final nutR = math.max(3.4, h * 0.0220);
    for (var row = 0; row < 3; row++) {
      final y = m.rowYs[row];
      for (final left in const [true, false]) {
        final s = HeadstockMetrics.stringAt(row, left);
        final postX = m.postX(s);
        final hit = hitIndex == s;
        final rim = hit ? (inTune ? positive : dataHue) : const Color(0xFF6C6E74);
        final hex = _hexPath(Offset(postX, y), nutR);
        final box = Rect.fromCircle(center: Offset(postX, y), radius: nutR);
        // 螺母侧面：左上亮、右下暗，别用纯白（纯白会像塑料垫圈）。
        canvas.drawPath(
          hex,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE4E6EA), Color(0xFFA9ABB1), Color(0xFF76787E)],
              stops: [0.0, 0.55, 1.0],
            ).createShader(box),
        );
        canvas.drawPath(
          hex,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, h * 0.0032)
            ..color = rim.withValues(alpha: hit ? 0.95 : 0.75),
        );
        // 柱头（弦绕在上面）：金属圆柱 + 顶面高光。
        canvas.drawCircle(
          Offset(postX, y),
          postR,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF1F2F5), Color(0xFFB9BBC1), Color(0xFF83858B)],
            ).createShader(
                Rect.fromCircle(center: Offset(postX, y), radius: postR)),
        );
        canvas.drawCircle(
          Offset(postX, y),
          postR,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(0.9, h * 0.0026)
            ..color = const Color(0x73000000),
        );
        canvas.drawCircle(
          Offset(postX - postR * 0.28, y - postR * 0.28),
          postR * 0.30,
          Paint()..color = Colors.white.withValues(alpha: 0.85),
        );
      }
    }
  }

  Path _hexPath(Offset c, double r) {
    final p = Path()..moveTo(c.dx + r, c.dy);
    for (var i = 1; i < 6; i++) {
      final a = i * math.pi / 3;
      p.lineTo(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
    }
    return p..close();
  }

  @override
  bool shouldRepaint(_HeadstockPainter old) =>
      old.hitIndex != hitIndex ||
      old.inTune != inTune ||
      old.dataHue != dataHue ||
      old.positive != positive ||
      old.metrics != metrics;
}
