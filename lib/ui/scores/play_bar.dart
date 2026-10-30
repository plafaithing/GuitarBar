import 'package:flutter/material.dart';

import '../theme.dart';

/// 播放控制条（v1：播放/停止 + 进度；变速/AB/多轨为 M5）。
class PlayBar extends StatelessWidget {
  const PlayBar(
      {super.key,
      required this.playing,
      required this.positionSeconds,
      required this.durationSeconds,
      required this.onToggle,
      this.busy = false});
  final bool playing;
  final double positionSeconds;
  final double durationSeconds;
  final VoidCallback onToggle;

  /// 渲染/加载忙碌（真实谱 0.3-1s，Task 15 备案）：按钮换 16×16 spinner
  /// 并禁点（onPressed: null），视觉与交互一致。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
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
                : Icon(playing ? Icons.stop : Icons.play_arrow, color: p.ink)),
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
    );
  }
}
