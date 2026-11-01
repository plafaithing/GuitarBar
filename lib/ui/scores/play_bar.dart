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
      height: 64,
      child: Container(
        decoration: BoxDecoration(
          // 半透明（2026-10-31 用户反馈：播放条不过分遮挡曲谱，50% 透明度）。
          color: p.panel.withValues(alpha: 0.5),
          border: Border(top: BorderSide(color: p.border)),
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
