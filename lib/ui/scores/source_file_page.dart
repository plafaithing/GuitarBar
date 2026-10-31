import 'package:flutter/material.dart';

import '../theme.dart';
import 'source_viewer.dart';

/// gpx 源文件查看页（13.4）：展示容器内解析出的 score.gpif XML（人类可读）。
/// 原始 .gpx 是压缩容器（BCFZ/zip）直接展示是乱码，故解出 gpif 再给查看器。
class SourceFilePage extends StatelessWidget {
  const SourceFilePage({super.key, required this.title, required this.xml});
  final String title;
  final String xml;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.ground,
      appBar: AppBar(title: Text('源文件 · $title')),
      body: SourceViewer(pagePngs: const [], gpxSourceText: xml),
    );
  }
}
