import 'package:flutter/material.dart';

import '../theme.dart';

/// 播放控制条（v1：播放/暂停/停止 + 进度；变速/AB/多轨为 M5）。
class PlayBar extends StatelessWidget {
  const PlayBar(
      {super.key,
      required this.playing,
      required this.paused,
      required this.positionSeconds,
      required this.durationSeconds,
      required this.onToggle,
      required this.onStop,
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

  /// 渲染/加载忙碌（真实谱 0.3-1s，Task 15 备案）：按钮换 16×16 spinner
  /// 并禁点（onPressed: null），视觉与交互一致。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // 固定一行高（2026-10-31 走查修复：bottomSheet 槽的宽松约束下
    // Container 会被拉满可用高度盖住谱面——Scaffold 实测三形态复现；
    // IconButton 48 + padding 16 = 64）。
    return SizedBox(
      height: 64,
      child: Container(
        decoration: BoxDecoration(
          color: p.panel,
          border: Border(top: BorderSide(color: p.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          IconButton(
              onPressed: busy ? null : onToggle,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(playing && !paused ? Icons.pause : Icons.play_arrow,
                      color: p.ink)),
          // 小停止按钮：未播放无可停，禁点。
          IconButton(
              iconSize: 20,
              onPressed: (!playing || busy) ? null : onStop,
              icon: Icon(Icons.stop, color: p.ink)),
          Expanded(
            child: Slider(
              value: durationSeconds == 0
                  ? 0
                  : (positionSeconds / durationSeconds).clamp(0.0, 1.0),
              onChanged: null, // v1 不可拖动定位（AB 循环在 M5）
              activeColor: p.dataHue,
            ),
          ),
          Text(
            '${positionSeconds.toStringAsFixed(1)}/${durationSeconds.toStringAsFixed(1)}s',
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
