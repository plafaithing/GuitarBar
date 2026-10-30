import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/score/score_repository.dart';
import '../../data/database.dart';
import '../theme.dart';
import 'score_detail_page.dart';

/// 曲谱库：源文件仓库（导入即归档即查看），识谱/演奏是叠加增强。
class ScoresPage extends StatefulWidget {
  const ScoresPage({super.key, this.repoFactory});
  // widget 测试注入用；null = 走默认 path_provider 路径。
  final ScoreRepository Function()? repoFactory;

  @override
  State<ScoresPage> createState() => _ScoresPageState();
}

class _ScoresPageState extends State<ScoresPage> {
  ScoreRepository? _repo;
  List<Score>? _scores;
  // 页数缓存：列表行显示用，_reload 时算一次（避免每行每帧同步 IO）。
  Map<int, int>? _pageCounts;
  // 导入进行中：禁用导入按钮，防大 PDF 转图期间重复导入。
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initRepo();
  }

  Future<void> _initRepo() async {
    try {
      // repoFactory 注入时不走 path_provider（测试环境无插件，会抛异常）。
      final factory = widget.repoFactory;
      final ScoreRepository repo;
      if (factory != null) {
        repo = factory();
      } else {
        if (!mounted) return;
        final db = context.read<AppDatabase>();
        repo = await ScoreRepository.createDefault(db);
      }
      if (!mounted) return;
      setState(() => _repo = repo);
      await _reload();
    } catch (_) {
      // 测试环境无 path_provider 插件：停在加载态。
    }
  }

  Future<void> _reload() async {
    final repo = _repo;
    if (repo == null) return;
    final list = await repo.listScores();
    final counts = <int, int>{
      for (final s in list) s.id: repo.files.pagePngs(s.id).length,
    };
    if (mounted) {
      setState(() {
        _scores = list;
        _pageCounts = counts;
      });
    }
  }

  Future<void> _importFile() async {
    final repo = _repo;
    if (repo == null || _busy) return;
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(
          label: '乐谱文件', extensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp']),
    ]);
    if (file == null || !mounted) return;
    final name = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final title = await _askTitle(name);
    if (title == null || title.trim().isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await repo.importScore(title: title.trim(), source: File(file.path));
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFolder() async {
    final repo = _repo;
    if (repo == null || _busy) return;
    final dirPath = await getDirectoryPath();
    if (dirPath == null || !mounted) return;
    final images = Directory(dirPath)
        .listSync()
        .whereType<File>()
        .where((f) => ScoreRepository.imageExts
            .contains(p.extension(f.path).replaceFirst('.', '').toLowerCase()))
        .toList()
      ..sort((a, b) => ScoreRepository.naturalCompare(
          p.basename(a.path), p.basename(b.path)));
    if (images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件夹里没有图片（png/jpg/jpeg/webp）')));
      return;
    }
    final title = await _askTitle(p.basename(dirPath));
    if (title == null || title.trim().isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await repo.importImages(title: title.trim(), images: images);
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askTitle(String initial) => showDialog<String>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController(text: initial);
          return AlertDialog(
            title: const Text('导入曲谱'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: '曲名'),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, ctrl.text),
                  child: const Text('导入')),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scores = _scores;
    final repo = _repo;
    return Scaffold(
      backgroundColor: p.ground,
      appBar: AppBar(title: const Text('曲谱库')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Spacer(),
            // child 参数放忙碌/空闲图标（builder 重建时复用），按钮本体在
            // builder 内构建（onPressed 需闭包捕获 controller）。
            MenuAnchor(
              menuChildren: [
                MenuItemButton(
                    onPressed: repo == null || _busy ? null : _importFile,
                    child: const Text('导入文件（图片/PDF）')),
                MenuItemButton(
                    onPressed: repo == null || _busy ? null : _importFolder,
                    child: const Text('导入文件夹（多图合成多页）')),
              ],
              builder: (ctx, controller, child) => FilledButton.icon(
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                icon: child,
                label: const Text('导入'),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_file, size: 18),
            ),
          ]),
          const SizedBox(height: 16),
          if (repo == null || scores == null)
            const Center(child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator()))
          else if (scores.isEmpty)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.library_music_outlined, size: 48, color: p.muted),
                  const SizedBox(height: 12),
                  Text('还没有曲谱，点右上角导入图片或 PDF',
                      style: TextStyle(fontSize: 14, color: p.muted)),
                ]),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: scores.length,
                itemBuilder: (ctx, i) {
                  final s = scores[i];
                  // Material 行容器：ListTile 需 Material 祖先（波纹），
                  // 且不透明底色必须走 Material.color，否则触发
                  // "ListTile background color may be invisible" 断言。
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: p.panel,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: p.border)),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        title: Text(s.title,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: p.ink)),
                        subtitle: Text(
                            '${s.sourceType == 'pdf' ? 'PDF' : '图片'} · '
                            '${_pageCounts?[s.id] ?? 0} 页 · '
                            '${s.irJson == null ? '未识谱' : '已识谱'}',
                            style: TextStyle(fontSize: 12, color: p.muted)),
                        trailing: Icon(Icons.chevron_right,
                            size: 20, color: p.muted),
                        onTap: () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      ScoreDetailPage(scoreId: s.id)));
                          if (mounted) _reload();
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }
}
