import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// 源文件纯查看器：逐页图片翻页 + 缩放。零编辑、零研究——就是查看器。
/// 桌面交互（2026-10-30 走查修复）：PageView 默认鼠标拖不动、垂直滚轮对
/// 水平列表无效——翻页靠左右按钮 + 鼠标可拖（ScrollConfiguration 放开
/// mouse 设备），页码指示常驻底部。
class SourceViewer extends StatefulWidget {
  const SourceViewer({super.key, required this.pagePngs});
  final List<File> pagePngs;

  @override
  State<SourceViewer> createState() => _SourceViewerState();
}

class _SourceViewerState extends State<SourceViewer> {
  late final PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final target = (_index + delta).clamp(0, widget.pagePngs.length - 1);
    _controller.animateToPage(target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pagePngs.isEmpty) {
      return Center(
          child:
              Text('没有页图', style: TextStyle(color: context.palette.muted)));
    }
    final p = context.palette;
    final multi = widget.pagePngs.length > 1;
    return Stack(children: [
      // 鼠标拖动放开：默认 ScrollBehavior 的 dragDevices 只含触摸。
      ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse}),
        child: PageView.builder(
          controller: _controller,
          itemCount: widget.pagePngs.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (ctx, i) => InteractiveViewer(
            maxScale: 6,
            child: Center(
                child: Image.file(widget.pagePngs[i], fit: BoxFit.contain)),
          ),
        ),
      ),
      if (multi) ...[
        // 左右翻页按钮（桌面明确交互）。
        Positioned(
          left: 8,
          top: 0,
          bottom: 28,
          child: Center(
            child: _PageButton(
                enabled: _index > 0,
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
                enabled: _index < widget.pagePngs.length - 1,
                icon: Icons.chevron_right,
                onTap: () => _go(1)),
          ),
        ),
        // 页码指示。
        Positioned(
          left: 0,
          right: 0,
          bottom: 6,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: p.panel,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${_index + 1} / ${widget.pagePngs.length}',
                  style: TextStyle(
                      fontSize: 12,
                      color: p.muted,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ),
        ),
      ],
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
