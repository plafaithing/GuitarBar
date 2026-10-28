import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../audio/metronome_engine.dart';
import '../../audio/sound_engine.dart';
import '../../ui/theme.dart';

class MetronomePage extends StatefulWidget {
  const MetronomePage({super.key});
  @override
  State<MetronomePage> createState() => _MetronomePageState();
}

class _MetronomePageState extends State<MetronomePage> {
  late final MetronomeEngine _engine = MetronomeEngine(SoundEngine.I);
  final _taps = <DateTime>[];
  Timer? _stepTimer;

  static const _timeSigs = [(2, '2/4'), (3, '3/4'), (4, '4/4'), (6, '6/8')];
  static const _subs = [(1, '四分'), (2, '八分'), (3, '三连音'), (4, '十六分')];

  @override
  void dispose() {
    _stepTimer?.cancel();
    _engine.stop(); // Task 11 审查要求：离开页面必须停引擎
    super.dispose();
  }

  Future<void> _toggle() async {
    _engine.running ? await _engine.stop() : await _engine.start();
    setState(() {});
  }

  /// 步进（T1）：单击 ±1、长按 100ms 连续；clamp 到转盘域 30–240。
  void _stepBpm(int d) {
    final cfg = _engine.cfg;
    setState(() => _engine.cfg = MetronomeConfig(
        bpm: (cfg.bpm + d).clamp(30, 240).toDouble(),
        beatsPerBar: cfg.beatsPerBar,
        subdivision: cfg.subdivision));
  }

  /// 步进圆钮（40px 圆、1.5px ink 描边、透明底；长按连续步进）。
  Widget _stepButton(IconData icon, int d) {
    final enabled = !_engine.running;
    return GestureDetector(
      onTap: enabled ? () => _stepBpm(d) : null,
      onLongPressStart: enabled
          ? (_) {
              _stepTimer?.cancel();
              _stepTimer = Timer.periodic(
                  const Duration(milliseconds: 100), (_) => _stepBpm(d));
            }
          : null,
      onLongPressEnd: (_) => _stepTimer?.cancel(),
      onLongPressCancel: () => _stepTimer?.cancel(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: context.palette.ink,
                width: 1.5)),
        alignment: Alignment.center,
        child: Icon(icon,
            size: 20,
            color: enabled
                ? context.palette.ink
                : context.palette.muted),
      ),
    );
  }

  /// 转盘点按（T2 v1）：角度反算 BPM（30–240 线性映射 300° 弧），取整。
  void _dialTapUp(TapUpDetails d, double dial) {
    final c = dial / 2;
    final v = d.localPosition - Offset(c, c);
    var a = math.atan2(v.dy, v.dx); // [-π, π]，顺时针为正
    const start = 2 * math.pi * 120 / 360; // 左下起点（30 BPM）
    const sweep = 2 * math.pi * 300 / 360; // 300° 弧
    while (a < start) {
      a += 2 * math.pi;
    }
    if (a > start + sweep) a = start + sweep; // 落在底部开口区 → 封顶
    final bpm = 30 + (a - start) / sweep * 210;
    final cfg = _engine.cfg;
    setState(() => _engine.cfg = MetronomeConfig(
        bpm: bpm.round().clamp(30, 240).toDouble(),
        beatsPerBar: cfg.beatsPerBar,
        subdivision: cfg.subdivision));
  }

  void _tap() {
    _taps.add(DateTime.now());
    if (_taps.length > 8) _taps.removeAt(0);
    final bpm = bpmFromTaps(_taps);
    if (bpm > 0) {
      setState(() => _engine.cfg = MetronomeConfig(
          bpm: bpm.clamp(30, 240).toDouble(),
          beatsPerBar: _engine.cfg.beatsPerBar,
          subdivision: _engine.cfg.subdivision));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cfg = _engine.cfg;
    // 转盘直径：可用宽 0.9，上限 340（页面竖向预算内）。
    return Scaffold(
      appBar: AppBar(title: const Text('节拍器')),
      body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        // T1 步进行：− / 大号 BPM / +，下方小字。
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _stepButton(Icons.remove, -1),
          const SizedBox(width: 24),
          Text(cfg.bpm.toStringAsFixed(0),
              style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w600,
                  color: palette.ink,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 24),
          _stepButton(Icons.add, 1),
        ]),
        Text('每分钟节拍数', style: TextStyle(fontSize: 12, color: palette.muted)),
        const SizedBox(height: 16),
        // T2 转盘（M2：currentTick 驱动 beatProgress，已过刻度 positive 绿跳、
        // 循环回绕；停止时恒 0 全 muted）+ 中央播放键（追加：80px/icon 48）。
        ValueListenableBuilder<int>(
          valueListenable: _engine.currentTick,
          builder: (_, tick, _) => LayoutBuilder(builder: (context, c) {
            final dial = math.min(c.maxWidth * 0.9, 340.0);
            final beatProgress =
                tick < 0 ? 0.0 : (tick % cfg.beatsPerBar) / cfg.beatsPerBar;
            final flashIsDownbeat = tick >= 0 && tick % cfg.beatsPerBar == 0;
            // F2：闪光衰减——key 绑 currentTick，每次 tick 变化重启动画
            // （begin 1.0 → end 0.0，时长 = 拍时长 ms）；停止时 tick 不变、
            // 动画走完停在 0（全 muted）。
            return SizedBox(
              width: dial,
              height: dial,
              child: GestureDetector(
                onTapUp:
                    _engine.running ? null : (d) => _dialTapUp(d, dial),
                child: Stack(fit: StackFit.expand, children: [
                  TweenAnimationBuilder<double>(
                    key: ValueKey(tick),
                    tween: Tween(begin: 1.0, end: 0.0),
                    duration: Duration(
                        milliseconds: (60000 / cfg.bpm).round()),
                    builder: (_, flash, _) => CustomPaint(
                      painter: _MetronomeDialPainter(
                          bpm: cfg.bpm.clamp(30, 240).toDouble(),
                          beatProgress: beatProgress,
                          flash: flash,
                          flashIsDownbeat: flashIsDownbeat,
                          palette: palette),
                    ),
                  ),
                  Center(
                    child: IconButton(
                      onPressed: _toggle,
                      iconSize: 48,
                      constraints: const BoxConstraints(
                          minWidth: 80, minHeight: 80),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                          _engine.running ? Icons.pause : Icons.play_arrow,
                          color: palette.positive)),
                  ),
                ]),
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        // T4/T5 + M1/M3：拍号胶囊与细分下拉——label Text 并排常显（禁用只
        // 灰 Dropdown 本体），箭头 ink、菜单深浅底随 palette。
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('拍号', style: TextStyle(fontSize: 12, color: palette.muted)),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: palette.ink)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: cfg.beatsPerBar,
                dropdownColor: palette.surface,
                elevation: 2,
                borderRadius: BorderRadius.circular(8),
                icon: Icon(Icons.expand_more, color: palette.ink),
                // F1：运行中禁用但数值/箭头保持全色（disabledHint 替代
                // value 显示，覆盖 M3 禁用淡出）。
                style: TextStyle(fontSize: 14, color: palette.ink),
                iconEnabledColor: palette.ink,
                iconDisabledColor: palette.ink,
                disabledHint: Text(
                    _timeSigs
                        .firstWhere((e) => e.$1 == cfg.beatsPerBar)
                        .$2,
                    style: TextStyle(fontSize: 14, color: palette.ink)),
                items: [
                  for (final (b, l) in _timeSigs)
                    DropdownMenuItem(value: b, child: Text(l))
                ],
                onChanged: _engine.running
                    ? null
                    : (b) => setState(() => _engine.cfg = MetronomeConfig(
                        bpm: cfg.bpm,
                        beatsPerBar: b!,
                        subdivision: cfg.subdivision)),
              ),
            ),
          ),
          const SizedBox(width: 24),
          Text('细分', style: TextStyle(fontSize: 12, color: palette.muted)),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: cfg.subdivision,
            dropdownColor: palette.surface,
            elevation: 2,
            borderRadius: BorderRadius.circular(8),
            icon: Icon(Icons.expand_more, color: palette.ink),
            style: TextStyle(fontSize: 14, color: palette.ink),
            iconEnabledColor: palette.ink,
            iconDisabledColor: palette.ink,
            disabledHint: Text(
                _subs.firstWhere((e) => e.$1 == cfg.subdivision).$2,
                style: TextStyle(fontSize: 14, color: palette.ink)),
            items: [
              for (final (s, l) in _subs)
                DropdownMenuItem(value: s, child: Text(l))
            ],
            onChanged: _engine.running
                ? null
                : (s) => setState(() => _engine.cfg = MetronomeConfig(
                    bpm: cfg.bpm,
                    beatsPerBar: cfg.beatsPerBar,
                    subdivision: s!)),
          ),
          const SizedBox(width: 24),
          OutlinedButton.icon(
              onPressed: _tap,
              icon: const Icon(Icons.back_hand, size: 16),
              label: const Text('Tap 点速')),
        ]),
      ]),
      ),
    );
  }
}

/// 节拍器转盘（T2）：210 根密集细刻度覆盖 300°（底部 60° 开口），30–240
/// BPM 线性映射（30 左下起点、240 右下终点、顺时针经顶），五档主刻度标签，
/// 当前 BPM 处 positive 绿圈（20px、3px 描边、透明芯）。纯显示，点按反算
/// 在页面层。
class _MetronomeDialPainter extends CustomPainter {
  _MetronomeDialPainter({
    required this.bpm,
    required this.beatProgress,
    required this.flash,
    required this.flashIsDownbeat,
    required this.palette,
  });

  final double bpm;

  /// M2：当前拍在 300° 弧内的进度（0..1，拍级简化：tick % beatsPerBar /
  /// beatsPerBar）；0 = 停止/拍首（全 muted），随拍推进已过刻度变绿、循环回绕。
  final double beatProgress;

  /// F2：拍闪光强度（0..1，Tween 1→0 按拍时长衰减；停止恒 0）。
  final double flash;

  /// F2：本次闪光是否小节头拍（黄 #E6B800）——其余拍 positive 绿。
  final bool flashIsDownbeat;

  final GuitarBarPalette palette;

  static const _start = 2 * math.pi * 120 / 360; // 左下起点（30 BPM）
  static const _sweep = 2 * math.pi * 300 / 360; // 300° 弧

  /// BPM → 弧上角度（canvas 角，顺时针为正）。
  static double angleOf(double bpm) =>
      _start + (bpm - 30) / 210 * _sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 18;

    // 密集细刻度环（M2 已过段 positive 2px + F2 整环闪光：全环向闪光色
    // lerp（flash×0.8），按拍时长衰减回基准色，循环跳动）。
    final flashColor =
        flashIsDownbeat ? const Color(0xFFE6B800) : palette.positive;
    for (var i = 0; i < 210; i++) {
      final prog = i / 210;
      final lit = beatProgress > 0 && prog <= beatProgress;
      final base = lit ? palette.positive : palette.muted;
      final a = _start + i / 210 * _sweep;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
          center + dir * (radius - 10),
          center + dir * radius,
          Paint()
            ..strokeWidth = lit ? 2.0 : 1.0
            ..color = Color.lerp(base, flashColor, flash * 0.8)!);
    }

    // 主刻度标签（角度位置内侧）。
    for (final b in const [30.0, 75.0, 135.0, 195.0, 240.0]) {
      final a = angleOf(b);
      final pos = center + Offset(math.cos(a), math.sin(a)) * (radius - 28);
      final tp = TextPainter(
          text: TextSpan(
              text: b.toStringAsFixed(0),
              style: TextStyle(
                  fontSize: 12,
                  color: palette.muted,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }

    // 绿圈标记（当前 BPM 角度位置）。
    final a = angleOf(bpm);
    final marker = center + Offset(math.cos(a), math.sin(a)) * (radius - 5);
    canvas.drawCircle(
        marker,
        10,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = palette.positive);
  }

  @override
  bool shouldRepaint(_MetronomeDialPainter oldDelegate) =>
      oldDelegate.bpm != bpm ||
      oldDelegate.beatProgress != beatProgress ||
      oldDelegate.flash != flash ||
      oldDelegate.flashIsDownbeat != flashIsDownbeat ||
      oldDelegate.palette != palette;
}
