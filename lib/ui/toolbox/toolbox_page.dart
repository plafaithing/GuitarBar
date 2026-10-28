import 'package:flutter/material.dart';

import '../theme.dart';
import 'metronome_page.dart';

/// 工具箱容器：面板行式列表，行高 56，后续新工具加行即扩展。
/// （和弦库/指板音阶行待 Task 14/15 页面落地后追加，保持本提交编译自洽。）
class ToolboxPage extends StatelessWidget {
  const ToolboxPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.border),
        ),
        child: Column(children: [
          _ToolRow(
              icon: Icons.av_timer_outlined,
              title: '节拍器',
              subtitle: '细分拍 · Tap 点速',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MetronomePage()))),
        ]),
      ),
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
