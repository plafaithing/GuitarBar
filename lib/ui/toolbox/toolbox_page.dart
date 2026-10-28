import 'package:flutter/material.dart';

import '../theme.dart';
import 'chord_page.dart';
import 'fretboard_page.dart';
import 'metronome_page.dart';

/// 工具箱容器：面板行式列表，行高 56，后续新工具加行即扩展。
/// 指板音阶行已落地（Task 15）。
class ToolboxPage extends StatelessWidget {
  const ToolboxPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // V1：独立长条按钮（各自一块，间距 12）——整块面板容器已去。
    Widget tool(IconData icon, String title, String subtitle, Widget page) =>
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.border),
          ),
          child: _ToolRow(
              icon: icon,
              title: title,
              subtitle: subtitle,
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => page))),
        );
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        tool(Icons.music_note_outlined, '和弦库',
            '算法生成指法 · 随调弦联动 · 四种试听', const ChordPage()),
        tool(Icons.piano_outlined, '指板音阶', '根音+音阶 · 随调弦联动 · 点按发声',
            const FretboardPage()),
        tool(Icons.av_timer_outlined, '节拍器', '细分拍 · Tap 点速',
            const MetronomePage()),
      ]),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow(
      {required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Row(children: [
          const SizedBox(width: 16),
          Icon(icon, size: 20, color: palette.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: palette.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: palette.muted)),
                ]),
          ),
          Icon(Icons.chevron_right, size: 20, color: palette.muted),
          const SizedBox(width: 16),
        ]),
      ),
    );
  }
}
