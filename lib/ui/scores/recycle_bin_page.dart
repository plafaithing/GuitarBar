import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/score/score_repository.dart';
import '../../data/database.dart';
import '../gbar_background.dart';
import '../theme.dart';

/// 回收站（2026-11-05 用户定案）：软删曲谱列表——恢复 / 彻底删除 /
/// 清空；条目 30 天后由启动时 purgeExpired 自动清理。
class RecycleBinPage extends StatefulWidget {
  const RecycleBinPage({super.key, this.repoFactory});
  final ScoreRepository Function()? repoFactory;

  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends State<RecycleBinPage> {
  ScoreRepository? _repo;
  List<Score>? _items;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final factory = widget.repoFactory;
    final ScoreRepository repo;
    if (factory != null) {
      repo = factory();
    } else {
      if (!mounted) return;
      repo = await ScoreRepository.createDefault(context.read<AppDatabase>());
    }
    if (!mounted) return;
    setState(() => _repo = repo);
    await _reload();
  }

  Future<void> _reload() async {
    final repo = _repo;
    if (repo == null) return;
    final list = await repo.listRecycleBin();
    if (mounted) setState(() => _items = list);
  }

  Future<void> _restore(Score s) async {
    await _repo?.restoreScore(s.id);
    await _reload();
  }

  Future<void> _purge(Score s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底删除'),
        content: Text('「${s.title}」将从回收站永久删除，文件一并清除，不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('彻底删除')),
        ],
      ),
    );
    if (ok != true) return;
    await _repo?.purgeScore(s.id);
    await _reload();
  }

  Future<void> _emptyBin() async {
    final items = _items;
    if (items == null || items.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空回收站'),
        content: Text('将永久删除全部 ${items.length} 份曲谱及文件，不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    for (final s in List.of(items)) {
      await _repo?.purgeScore(s.id);
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = _items;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('回收站'), actions: [
        if (items != null && items.isNotEmpty)
          TextButton.icon(
              onPressed: _emptyBin,
              icon: Icon(Icons.delete_sweep_outlined, color: p.negative),
              label: Text('清空', style: TextStyle(color: p.negative))),
      ]),
      body: GbarBackground(
        child: items == null
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
                ? Center(
                    child: Text('回收站是空的',
                        style: TextStyle(fontSize: 14, color: p.muted)))
                : ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: items.length,
                    itemBuilder: (ctx, i) {
                      final s = items[i];
                      final d = s.deletedAt;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: p.panel,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: p.border)),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            title: Text(s.title,
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: p.ink)),
                            subtitle: Text(
                                d == null
                                    ? ''
                                    : '删除于 ${d.year}/${d.month}/${d.day} · '
                                        '保留 ${7 - DateTime.now().difference(d).inDays} 天（超期自动清理）',
                                style: TextStyle(
                                    fontSize: 12, color: p.muted)),
                            trailing: Row(mainAxisSize: MainAxisSize.min,
                                children: [
                              IconButton(
                                  tooltip: '恢复',
                                  icon: Icon(Icons.restore,
                                      size: 20, color: p.ink),
                                  onPressed: () => _restore(s)),
                              IconButton(
                                  tooltip: '彻底删除',
                                  icon: Icon(Icons.delete_forever_outlined,
                                      size: 20, color: p.negative),
                                  onPressed: () => _purge(s)),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
