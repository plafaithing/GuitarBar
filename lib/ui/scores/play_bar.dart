import 'package:flutter/material.dart';

import '../theme.dart';

/// 播放控制条（v1：播放/暂停/停止 + 进度；变速/AB/多轨为 M5）。
/// 进度条可拖动定位（2026-11-01 走查）：拖动中只更新视觉（_dragValue），
/// 松手才 seek——避免拖动过程连续触发现场声部切换的爆音。
class PlayBar extends StatefulWidget {
  const PlayBar(
      {super.key,
      required this.playing,
      required this.paused,
      required this.positionSeconds,
      required this.durationSeconds,
      required this.onToggle,
      required this.onStop,
      required this.onSeek,
      required this.rate,
      required this.onRateChanged,
      this.loopA,
      this.loopB,
      required this.onLoopA,
      required this.onLoopB,
      this.busy = false});
  final bool playing;

  /// 暂停中（playing 仍为真）：主按钮显示 play（恢复语义）。
  final bool paused;
  final double positionSeconds;
  final double durationSeconds;

  /// 播放/暂停切换（主按钮）。
  final VoidCallback onToggle;

  /// 停止（小按钮）：归零回开头（暂停≠归零）；暂停态也可停。
  final VoidCallback onStop;

  /// 拖动定位（松手回调，参数为目标秒；未播放时调用方负责起播）。
  final void Function(double seconds) onSeek;

  /// 速度倍率与回调（2026-11-01 跟练：变速播放）。
  final double rate;
  final void Function(double rate) onRateChanged;

  /// AB 循环：A=当前位打起点、B=当前位打终点；再点同钮清除。
  final double? loopA;
  final double? loopB;
  final VoidCallback onLoopA;
  final VoidCallback onLoopB;

  /// 渲染/加载忙碌（真实谱 0.3-1s，Task 15 备案）：按钮换 16×16 spinner
  /// 并禁点（onPressed: null），视觉与交互一致。
  final bool busy;

  @override
  State<PlayBar> createState() => _PlayBarState();
}

class _PlayBarState extends State<PlayBar> {
  /// 拖动中的临时值（0-1 比例）：非空时进度条显示它而非实时 position，
  /// 50ms tick 的回拉被压制；松手 seek 后清空回归实时。
  double? _dragRatio;

  /// 速度下拉（2026-11-10 用户需求：**播放中实时变速**——0.25-2.0 八档
  /// 精调；KS 降级路径在 detail page 里重渲染接续）。
  Widget _speedDropdown(
      BuildContext context, PlayBar w, GuitarBarPalette p) {
    const rates = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    return DropdownButton<double>(
      value: rates.contains(w.rate) ? w.rate : 1.0,
      underline: const SizedBox.shrink(),
      isDense: true,
      dropdownColor: p.panel,
      borderRadius: BorderRadius.circular(10),
      items: [
        for (final r in rates)
          DropdownMenuItem(
              value: r,
              child: Text('${r}x',
                  style: TextStyle(
                      fontSize: 12,
                      color: r == w.rate ? p.dataHue : p.muted))),
      ],
      // 播放中可选（实时变速——sample_player 在线重锚；不再禁用）。
      onChanged: (v) => w.onRateChanged(v!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final w = widget;
    final liveRatio = w.durationSeconds == 0
        ? 0.0
        : (w.positionSeconds / w.durationSeconds).clamp(0.0, 1.0);
    // 固定一行高（2026-10-31 走查修复：bottomSheet 槽的宽松约束下
    // Container 会被拉满可用高度盖住谱面——Scaffold 实测三形态复现；
    // IconButton 48 + padding 16 = 64）。
    return SizedBox(
      height: 72,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        decoration: BoxDecoration(
          // 圆角悬浮卡（2026-11-11 用户"背后色块"三轮定案：半透明
          // panel 在浅色下整体呈灰块观感（众数色 (227,225,220) 实测）
          // ——改**不透明 surface**：白卡自然悬浮，谱面透出的只有卡外
          // 区域；阴影取消（浅色下渲染成灰带）。
          color: p.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          IconButton(
              onPressed: w.busy ? null : w.onToggle,
              icon: w.busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(w.playing && !w.paused ? Icons.pause : Icons.play_arrow,
                      color: p.ink)),
          // 小停止按钮：未播放无可停，禁点。
          IconButton(
              iconSize: 20,
              onPressed: (!w.playing || w.busy) ? null : w.onStop,
              icon: Icon(Icons.stop, color: p.ink)),
          Expanded(
            child: Slider(
              value: _dragRatio ?? liveRatio,
              onChanged: w.busy || w.durationSeconds == 0
                  ? null
                  : (v) => setState(() => _dragRatio = v),
              onChangeEnd: (v) {
                w.onSeek(v * w.durationSeconds);
                setState(() => _dragRatio = null);
              },
              activeColor: p.dataHue,
            ),
          ),
          // 速度（2026-11-01 跟练三件套）：变速播放，慢练主用。
          _speedDropdown(context, w, p),
          // AB 循环：A 打起点、B 打终点，两钮同亮 = 循环中；点亮的再点清除。
          IconButton(
              tooltip: 'A 点（循环起点）',
              visualDensity: VisualDensity.compact,
              onPressed: w.onLoopA,
              icon: Text('A',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: w.loopA != null ? p.dataHue : p.muted))),
          IconButton(
              tooltip: 'B 点（循环终点）',
              visualDensity: VisualDensity.compact,
              onPressed: w.onLoopB,
              icon: Text('B',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: w.loopB != null ? p.dataHue : p.muted))),
          Text(
            '${w.positionSeconds.toStringAsFixed(1)}/${w.durationSeconds.toStringAsFixed(1)}s',
            style: TextStyle(
                fontSize: 12,
                color: p.muted,
                fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ]),
      ),
    );
  }
}
