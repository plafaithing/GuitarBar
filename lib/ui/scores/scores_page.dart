import 'dart:async' show unawaited;
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/score/score_repository.dart';
import '../../data/database.dart';
import '../gbar_background.dart';
import '../theme.dart';
import 'score_detail_page.dart';
import 'score_sorting.dart';

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
  // 批量导入进度（null = 非批量态；'3/10 文件名' 显示于导入按钮旁）。
  String? _batchProgress;
  // 曲谱库打开失败信息（null = 正常）——转圈态不再静默吞异常。
  String? _initError;
  // 搜索与类型筛选（2026-11-03 走查三件套）。
  final _searchCtrl = TextEditingController();
  String? _typeFilter;
  // 字母索引条（2026-11-04 用户需求，iPhone 通讯录式）：点击字母定位
  // 到对应组的第一个文件。各组 header 挂 GlobalKey 供定位；A-Z/# 一次性
  // 预建（dsh P3：不在 build 中做副作用）。
  final _scrollCtrl = ScrollController();
  final _sectionKeys = <String, GlobalKey>{
    for (final l in ['A','B','C','D','E','F','G','H','I','J','K','L','M',
      'N','O','P','Q','R','S','T','U','V','W','X','Y','Z','#']) l: GlobalKey(),
  };

  void _scrollToSection(String letter) {
    final key = _sectionKeys[letter];
    final headerCtx = key?.currentContext;
    if (headerCtx == null) return;
    // 限定只滚本页列表（dsh P3：Scrollable.ensureVisible 会连外层
    // 可滚动祖先一起滚；未来嵌入外层滚动容器时不越权）。
    final ro = headerCtx.findRenderObject();
    if (ro is RenderObject && _scrollCtrl.hasClients) {
      unawaited(_scrollCtrl.position.ensureVisible(ro,
          duration: const Duration(milliseconds: 250), alignment: 0.0));
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

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
    } catch (e) {
      // 数据库打开失败（如启动时被外部进程锁 → 只读降级探测抛错）不再
      // 静默吞——显示明确错误 + 重试入口（2026-11-02 走查：静默转圈迷雾）。
      // 测试环境无 path_provider 插件也会走这里：错误原样展示。
      if (mounted) {
        setState(() => _initError = '曲谱库打开失败：$e');
      }
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
    // 上次导入目录记忆（2026-11-04 用户需求）：打开位置 = 上次成功导入处。
    final initialDir = await repo.lastImportDir();
    // 多选批量导入（2026-11-03 走查三件套）：单文件继续走原流程。
    final files = await openFiles(
        initialDirectory: initialDir,
        acceptedTypeGroups: [
          const XTypeGroup(
              label: '乐谱文件（GTP/PDF/图片）',
              extensions: ['gpx', 'gp5', 'pdf', 'png', 'jpg', 'jpeg', 'webp']),
        ]);
    if (files.isEmpty || !mounted) return;
    // 目录记忆：取第一个文件所在文件夹（多选跨目录时以首个为准）。
    final firstDir = p.dirname(files.first.path);
    if (firstDir.isNotEmpty) unawaited(repo.saveLastImportDir(firstDir));
    if (files.length > 1) {
      await _importBatch(files.map((f) => File(f.path)).toList());
      return;
    }
    final file = files.single;
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

  /// 批量导入执行（多选文件）：逐个导入（标题=文件名），SnackBar 汇总
  /// （成功数用 importFiles 返回值，失败名单列出——dsh 复测 P1）。
  Future<void> _importBatch(List<File> files) async {
    final repo = _repo;
    if (repo == null || !mounted) return;
    setState(() => _busy = true);
    final failedNames = <String>[];
    try {
      final okCount = await repo.importFiles(files,
          onProgress: (done, total, name, error) {
        if (error != null) failedNames.add(name);
        if (mounted) {
          setState(() => _batchProgress =
              '${error != null ? '✗ ' : ''}$done/$total $name');
        }
      });
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(failedNames.isEmpty
                ? '批量导入完成（$okCount 个文件）'
                : '批量导入完成：成功 $okCount，失败 ${failedNames.length}'
                    '（${failedNames.join('、')}）')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _batchProgress = null;
        });
      }
    }
  }

  Future<void> _importFolder() async {
    final repo = _repo;
    if (repo == null || _busy) return;
    final initialDir = await repo.lastImportDir();
    final dirPath = await getDirectoryPath(initialDirectory: initialDir);
    if (dirPath == null || !mounted) return;
    unawaited(repo.saveLastImportDir(dirPath)); // 文件夹导入：记忆其本身
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
          // pop 返回后 dispose 会撞退出动画期间的 used-after-disposed，
          // 故保持对话框自持 controller（一次性，量级可忽略）。
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
      // v2：透明 Scaffold + 统一光晕背景层（全产品单一背景来源）。
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('曲谱库')),
      body: GbarBackground(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (_batchProgress != null)
              Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(children: [
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    // Flexible + 省略号：长文件名窄窗口不溢出（dsh P3）。
                    Flexible(
                        child: Text(_batchProgress!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(fontSize: 12, color: p.muted))),
                  ])),
            const Spacer(),
            // child 参数放忙碌/空闲图标（builder 重建时复用），按钮本体在
            // builder 内构建（onPressed 需闭包捕获 controller）。
            MenuAnchor(
              menuChildren: [
                MenuItemButton(
                    onPressed: repo == null || _busy ? null : _importFile,
                    child: const Text('导入文件（gpx/gp5/PDF/图片）')),
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
          // 搜索 + 类型筛选（2026-11-03 走查三件套；2026-11-04 类型下拉
          // 移到搜索框最左侧——用户要求，默认全部）。实时过滤无需回车；
          // × 同时清文字与筛选。
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                  color: p.panel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.border)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _typeFilter,
                  // 显式样式（2026-11-04 走查：默认继承色在 panel 底上
                  // 对比不足看不清）；选中与 hint 同字号防宽度跳变。
                  style: TextStyle(fontSize: 14, color: p.ink),
                  // 未选时走 hint（"全部类型"）；null item 供点开菜单后
                  // 从任意类型切回全部（2026-11-04 走查：删了 null item
                  // 后无法回"全部"，只能靠 × 清空——加回，hint 管收起态
                  // 显示，item 管菜单可选）。
                  hint: Text('全部类型',
                      style: TextStyle(fontSize: 14, color: p.muted)),
                  icon: Icon(Icons.expand_more, size: 18, color: p.ink),
                  dropdownColor: p.panel,
                  borderRadius: BorderRadius.circular(10),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('全部类型')),
                    DropdownMenuItem(value: 'gtp', child: Text('GTP')),
                    DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                    DropdownMenuItem(value: 'image', child: Text('图片')),
                  ],
                  onChanged: (v) => setState(() => _typeFilter = v),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: '按曲名搜索…',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  suffixIcon: (_searchCtrl.text.isEmpty && _typeFilter == null)
                      ? null
                      : IconButton(
                          tooltip: '清空',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            _typeFilter = null;
                            setState(() {});
                          }),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          if (_initError != null)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline, size: 48, color: p.negative),
                  const SizedBox(height: 12),
                  Text(_initError!,
                      style: TextStyle(fontSize: 13, color: p.ink)),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () {
                      setState(() => _initError = null);
                      _initRepo();
                    },
                    child: const Text('重试'),
                  ),
                ]),
              ),
            )
          else if (repo == null || scores == null)
            const Expanded(
                child: Center(
                    child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator())))
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
              child: Builder(builder: (ctx) {
                // 实时过滤（2026-11-03 走查三件套）：名字模糊（大小写
                // 不敏感）+ 类型筛选（下拉值）。
                final query = _searchCtrl.text.trim().toLowerCase();
                final filtered = scores.where((s) {
                  final matchQ =
                      query.isEmpty || s.title.toLowerCase().contains(query);
                  final matchT =
                      _typeFilter == null || s.sourceType == _typeFilter;
                  return matchQ && matchT;
                }).toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text('无匹配曲谱',
                        style: TextStyle(fontSize: 14, color: p.muted)),
                  );
                }
                // 首字母分组（2026-11-04 用户需求，iPhone 通讯录式）：
                // 英文名按首字母、中文名按拼音首字母，同组英文在前；
                // 右侧索引条点击定位到组第一个文件。
                final sections = groupScoresByLetter(filtered);
                final items = <_ListItem>[
                  for (final sec in sections) ...[
                    _ListItem.header(sec.letter, sec.scores.length),
                    for (final s in sec.scores) _ListItem.row(s),
                  ],
                ];
                return Stack(children: [
                  // 非懒 ListView（dsh P1-1：懒构建下视口外的组头
                  // currentContext 为 null，索引条定位会静默失败）。
                  // 曲谱量级几十条，全量构建无压力。
                  SingleChildScrollView(
                    controller: _scrollCtrl,
                    // 右侧留索引条宽度，底部留呼吸。
                    padding: const EdgeInsets.only(right: 40, bottom: 24),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < items.length; i++)
                            _buildItem(ctx, p, items[i], i),
                        ]),
                  ),
                  // 字母索引条（右侧悬浮，iPhone 通讯录式）：只显示有
                  // 内容的字母，点击滚动定位到该组 header。overlay 玻璃
                  // 底 + Material 包裹（波纹可见）+ 加大命中区。
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 5),
                      decoration: BoxDecoration(
                          color: p.overlay,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: p.border)),
                      child: Material(
                        color: Colors.transparent,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final sec in sections)
                              InkWell(
                                onTap: () => _scrollToSection(sec.letter),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Center(
                                    child: Text(sec.letter,
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: p.primary)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ]);
              }),
            ),
          ],
        ),
      ),
        ),
    );
  }

  /// 列表条目构建（组头 / 曲谱行）：从 build 抽出复用。
  Widget _buildItem(BuildContext ctx, GuitarBarPalette p, _ListItem it, int i) {
    if (it.isHeader) {
      return Container(
        key: _sectionKeys[it.header],
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.only(top: i == 0 ? 4 : 14, bottom: 8),
        child: Row(children: [
          Text(it.header!,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: p.primary)),
          const SizedBox(width: 8),
          Text('${it.headerCount} 份',
              style: TextStyle(fontSize: 11, color: p.muted)),
        ]),
      );
    }
    final s = it.score!;
    // 行卡片回退（2026-11-04 走查：上一版 surface 白底不符）——恢复
    // panel 底 + 10 圆角。需 Material 祖先（波纹）且底色走 Material.color，
    // 否则触发 "ListTile background color may be invisible" 断言。
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.panel,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: p.border)),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: Text(s.title,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w500, color: p.ink)),
          // GTP 导入无页图概念（谱面即数据），徽标不显示页数段。
          // 13.4 后图片/PDF 不再识谱：徽标显示"可播放/查看器"
          //（GTP 有 IR 可播放；图片/PDF 是纯查看器条目）。
          subtitle: Text(
              '${s.sourceType == 'pdf' ? 'PDF' : s.sourceType == 'gtp' ? 'GTP' : '图片'}'
              '${s.sourceType == 'gtp' ? '' : ' · ${_pageCounts?[s.id] ?? 0} 页'}'
              ' · ${s.irJson == null ? '查看器' : '可播放'}',
              style: TextStyle(fontSize: 12, color: p.muted)),
          // 行尾菜单（2026-10-30 用户反馈补删除）：桌面惯例三点菜单，删除
          // 带确认防误删整份谱。「打开原谱」已删（2026-11-04 用户走查：
          // 与点行进入完全同路径，冗余）。
          trailing: PopupMenuButton<String>(
            tooltip: '更多',
            icon: Icon(Icons.more_horiz, size: 20, color: p.muted),
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'rename', child: Text('重命名')),
              const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
            onSelected: (v) {
              if (v == 'rename') _renameScore(s);
              if (v == 'delete') _confirmDelete(s);
            },
          ),
          onTap: () async {
            await Navigator.push(context,
                MaterialPageRoute(builder: (_) => ScoreDetailPage(scoreId: s.id)));
            if (mounted) _reload();
          },
        ),
      ),
    );
  }

  /// 重命名（2026-11-03 用户需求）：保存时校验——trim 后非空（两侧
  /// 不能是空格），内部空格允许；同文件类型内唯一（不同类型允许同名）。
  /// 校验失败留在对话框内显示错误，不关窗。
  Future<void> _renameScore(Score s) async {
    final repo = _repo;
    final scores = _scores;
    if (repo == null || scores == null || !mounted) return;
    final ctrl = TextEditingController(text: s.title);
    String? error;
    String? validate(String raw) {
      final name = raw.trim();
      if (name.isEmpty) return '曲名不能为空';
      final dup = scores.any((o) =>
          o.id != s.id && o.sourceType == s.sourceType && o.title == name);
      if (dup) return '同类型已有同名曲谱「$name」';
      return null;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('重命名'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
                labelText: '曲名', hintText: '两侧不留空格', errorText: error),
            onChanged: (_) {
              // 用户改动后清掉上次的错误提示（校验仍以保存时点为准）。
              if (error != null) setDialog(() => error = null);
            },
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () {
                  final e = validate(ctrl.text);
                  if (e != null) {
                    setDialog(() => error = e);
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final name = ctrl.text.trim();
    // 注：局部 controller 不在 pop 返回后 dispose——对话框退出动画期间
    // TextField 仍引用它（used-after-disposed 崩溃，测试实锤）。正规修法
    // 是局部 StatefulWidget，为一次性对话框不值得（dsh P3 权衡不修）。
    if (name == s.title) return; // 未变化
    try {
      await repo.updateTitle(s.id, name);
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('重命名失败：$e')));
      }
    }
  }

  /// 删除确认（对齐识谱模型配置页的确认模式）→ 行+文件+页图全清。
  Future<void> _confirmDelete(Score s) async {
    final repo = _repo;
    if (repo == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除曲谱'),
        content: Text(
            '确定删除「${s.title}」？原谱文件与识谱结果将一并删除，不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await repo.deleteScore(s.id);
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$e')));
      }
    }
  }
}

/// 列表扁平项：组头（字母+计数）或曲谱行——单一 ListView 混排两种高度。
class _ListItem {
  const _ListItem.header(this.header, this.headerCount) : score = null;
  const _ListItem.row(this.score)
      : header = null,
        headerCount = 0;
  final String? header;
  final int headerCount;
  final Score? score;
  bool get isHeader => header != null;
}
