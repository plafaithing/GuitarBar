import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';

/// 源文件纯查看器：逐页图片翻页 + 双指缩放。零编辑、零研究——就是查看器。
class SourceViewer extends StatelessWidget {
  const SourceViewer({super.key, required this.pagePngs});
  final List<File> pagePngs;

  @override
  Widget build(BuildContext context) {
    if (pagePngs.isEmpty) {
      return Center(
          child:
              Text('没有页图', style: TextStyle(color: context.palette.muted)));
    }
    return PageView.builder(
      itemCount: pagePngs.length,
      itemBuilder: (ctx, i) => InteractiveViewer(
        maxScale: 6,
        child: Center(
            child: Image.file(pagePngs[i], fit: BoxFit.contain)),
      ),
    );
  }
}
