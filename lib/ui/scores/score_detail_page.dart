import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/score/score_files.dart';
import '../theme.dart';
import 'source_viewer.dart';

/// 曲谱详情：未识谱 = 纯查看器（一等使用方式）；谱面区由后续任务填充。
/// 宽屏：谱面 + 原图并排；窄屏：先只出查看器（谱面 Tab 由 Task 14 加入）。
class ScoreDetailPage extends StatefulWidget {
  const ScoreDetailPage({super.key, required this.scoreId});
  final int scoreId;

  @override
  State<ScoreDetailPage> createState() => _ScoreDetailPageState();
}

class _ScoreDetailPageState extends State<ScoreDetailPage> {
  List<File>? _pages;

  @override
  void initState() {
    super.initState();
    _loadPages();
  }

  Future<void> _loadPages() async {
    // 与 ScoresPage 同一路径约定：<support>/scores/<id>/ 的页图。
    // 经 ScoreFiles 读（不用手写目录遍历）。
    final dir = await getApplicationSupportDirectory();
    final files = ScoreFiles(Directory(p.join(dir.path, 'scores')));
    final pages = files.pagePngs(widget.scoreId);
    if (mounted) setState(() => _pages = pages);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pages = _pages;
    return Scaffold(
      backgroundColor: p.ground,
      appBar: AppBar(title: const Text('曲谱')),
      body: pages == null
          ? const Center(child: CircularProgressIndicator())
          : SourceViewer(pagePngs: pages),
    );
  }
}
