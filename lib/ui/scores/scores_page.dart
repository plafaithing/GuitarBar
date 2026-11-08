import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/score/score_ir.dart';
import '../../core/score/score_repository.dart';
import '../../data/database.dart';
import '../gbar_background.dart';
import '../theme.dart';
import 'recycle_bin_page.dart';
import 'score_detail_page.dart';
import 'score_sorting.dart';
import 'tab_view.dart';

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
  // 多选模式（2026-11-05 用户定案：双端统一 iOS 信息 app 交互）。
  bool _selecting = false;
  final Set<int> _selected = {};
  // 左滑操作：当前左滑展开的行（全局只允许一行展开，开新行关旧行）。
  int? _swipedId;
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
        // 回收站超期清理（30 天）：后台执行不阻塞首屏。
        unawaited(repo.purgeExpired());
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

  /// 批量导入图片合并为一个曲谱（2026-11-06 用户需求，iOS 场景：文件
  /// 选择器选不了文件夹）：多选图片 → 拖拽排序对话框（预填文件名自然
  /// 排序）→ 命名 → importImages 合成多页。
  Future<void> _importImageBatch() async {
    final repo = _repo;
    if (repo == null || _busy) return;
    final initialDir = await repo.lastImportDir();
    final files = await openFiles(
        initialDirectory: initialDir,
        acceptedTypeGroups: [
          const XTypeGroup(
              label: '曲谱图片',
              extensions: ['png', 'jpg', 'jpeg', 'webp']),
        ]);
    if (files.isEmpty || !mounted) return;
    // 排序确认（预填自然排序——与文件夹导入同款）。
    final ordered = files
        .map((f) => File(f.path))
        .toList()
      ..sort((a, b) => ScoreRepository.naturalCompare(
          p.basename(a.path), p.basename(b.path)));
    final confirmed = await showDialog<List<File>>(
      context: context,
      builder: (ctx) => _ImageOrderDialog(files: ordered),
    );
    if (confirmed == null || confirmed.isEmpty || !mounted) return;
    final firstDir = p.dirname(confirmed.first.path);
    if (firstDir.isNotEmpty) unawaited(repo.saveLastImportDir(firstDir));
    final title = await _askTitle(
        p.basenameWithoutExtension(confirmed.first.path));
    if (title == null || title.trim().isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await repo.importImages(title: title.trim(), images: confirmed);
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
      // 多选模式垃圾桶（2026-11-05 iOS 交互）：右下角，带已选数量。
      floatingActionButton: _selecting && _selected.isNotEmpty
          ? FloatingActionButton.extended(
              heroTag: 'batchDelete',
              backgroundColor: p.negative,
              foregroundColor: Colors.white,
              onPressed: _deleteSelected,
              icon: const Icon(Icons.delete_outline),
              label: Text('删除 ${_selected.length}'))
          : null,
      appBar: AppBar(
          title: Text(_selecting
              ? (_selected.isEmpty ? '选择曲谱' : '已选 ${_selected.length} 项')
              : '曲谱库'),
          actions: [
            // 回收站入口（2026-11-05 用户定案：删除先进回收站 30 天自动清）。
            IconButton(
                tooltip: '回收站',
                icon: const Icon(Icons.delete_outline, size: 22),
                onPressed: repo == null
                    ? null
                    : () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const RecycleBinPage()));
                        if (mounted) _reload();
                      }),
            // 选择/对勾（双端统一 iOS 信息 app 交互）：进入与退出多选。
            IconButton(
                tooltip: _selecting ? '完成' : '选择',
                icon: Icon(_selecting ? Icons.check : Icons.checklist,
                    size: 22),
                onPressed: () {
                  if (_selecting) {
                    _exitSelecting();
                  } else if (_scores != null && _scores!.isNotEmpty) {
                    setState(() => _selecting = true);
                  }
                }),
          ]),
      body: CallbackShortcuts(
        // 桌面增强：Ctrl+A 全选 / Esc 退出多选（仅多选模式生效）。
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyA, control: true): () {
            if (!_selecting || scores == null) return;
            setState(() =>
                _selected.addAll(scores.map((s) => s.id)));
          },
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_selecting) _exitSelecting();
          },
        },
        child: GestureDetector(
          // 左滑后点其他任意位置收回展开行（2026-11-05 用户需求）：
          // 行内点击被内层消费，只有点空白/组头等非交互区才冒泡到这。
          onTap: () {
            if (_swipedId != null) setState(() => _swipedId = null);
          },
          child: GbarBackground(
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
                // iOS 场景（2026-11-06 用户需求）：文件选择器选不了文件夹，
                // 多选图片合并为一个曲谱 + 导入前拖拽排序。
                MenuItemButton(
                    onPressed: repo == null || _busy ? null : _importImageBatch,
                    child: const Text('批量导入图片（合并为一个曲谱）')),
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
    return _buildScoreRow(ctx, p, s);
  }

  /// 曲谱行（2026-11-05 双端统一 iOS 交互）：
  /// - 多选模式：左侧圆形勾选键，点行=切换选中（三点菜单已删——左滑/
  ///   长按/多选三通道全覆盖）
  /// - 左滑露「重命名 / 删除」两枚 iOS 全高色块按钮（单行展开）
  /// - 长按：卡片式展开（首图预览 + 元信息），点浮层外关闭
  Widget _buildScoreRow(BuildContext ctx, GuitarBarPalette p, Score s) {
    final swiped = _swipedId == s.id;
    final checked = _selected.contains(s.id);
    // 前景行：swiped 时右移出按钮区宽（116px = 两按钮 72+72 交叠 28）。
    const swipeWidth = 116.0;
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.panel,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: p.border)),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          // 多选模式：勾选键占据 leading。
          leading: _selecting
              ? Icon(
                  checked ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 22,
                  color: checked ? p.primary : p.muted)
              : null,
          title: Text(s.title,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: p.ink)),
          subtitle: Text(
              '${s.sourceType == 'pdf' ? 'PDF' : s.sourceType == 'gtp' ? 'GTP' : '图片'}'
              '${s.sourceType == 'gtp' ? '' : ' · ${_pageCounts?[s.id] ?? 0} 页'}'
              ' · ${s.irJson == null ? '查看器' : '可播放'}',
              style: TextStyle(fontSize: 12, color: p.muted)),
          onTap: () async {
            if (_selecting) {
              setState(() => checked
                  ? _selected.remove(s.id)
                  : _selected.add(s.id));
              return;
            }
            _swipedId = null;
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ScoreDetailPage(scoreId: s.id)));
            if (mounted) _reload();
          },
          onLongPress: () => _showScoreCard(s),
        ),
      ),
    );
    // 左滑操作层：iOS 全高色块按钮（行同高、图标居中），前景平移露出。
    return GestureDetector(
      // 桌面右键同样开卡片（Windows 鼠标长按易抖动超拖动阈值被抢赢——
      // 用户实测"GTP 卡片打不开"根因；右键是桌面直觉）。
      onSecondaryTapUp: (_) => _showScoreCard(s),
      onHorizontalDragUpdate: _selecting
          ? null
          : (d) {
              if (d.delta.dx < -2 && _swipedId != s.id) {
                setState(() => _swipedId = s.id);
              } else if (d.delta.dx > 2 && _swipedId == s.id) {
                setState(() => _swipedId = null);
              }
            },
      child: Stack(children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Spacer(),
                _swipeButton(p, Icons.edit_outlined, '重命名',
                    () => _renameScore(s), p.primary),
                _swipeButton(p, Icons.delete_outline, '删除',
                    () => _confirmDelete(s), p.negative),
              ]),
            ),
          ),
        ),
        AnimatedSlide(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          offset: swiped
              ? const Offset(-swipeWidth / 600, 0)
              : Offset.zero,
          child: row,
        ),
      ]),
    );
  }

  /// 左滑露出的 iOS 式操作按钮：全高色块（图标+文字居中，底色按动作
  /// 语义：重命名=primary 墨色、删除=negative 红）。
  Widget _swipeButton(GuitarBarPalette p, IconData icon, String label,
      VoidCallback onTap, Color bg) {
    return InkWell(
      onTap: () {
        _swipedId = null;
        onTap();
      },
      child: Container(
        width: 72,
        color: bg,
        alignment: Alignment.center,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 22, color: p.ground),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: p.ground)),
        ]),
      ),
    );
  }

  /// 长按卡片展开（2026-11-05 用户定案）：首图预览 + 元信息，
  /// 点浮层外任意处关闭；卡内快捷操作（打开/重命名/删除）。
  /// GTP 无页图——**渲染谱面预览**（TabView 按卡片宽自适应重排，
  /// 纯 widget 绘制无音频引擎；2026-11-05 用户反馈"GTP 卡片显示为
  /// 空"修复）。
  Future<void> _showScoreCard(Score s) async {
    final repo = _repo;
    if (repo == null || !mounted) return;
    final p = context.palette;
    final pages = repo.files.pagePngs(s.id);
    // GTP：同步解码 irJson（几十小节 JSON ms 级）供谱面预览。
    ScoreIr? gtpIr;
    if (s.sourceType == 'gtp' && s.irJson != null) {
      try {
        gtpIr = ScoreIr.fromJson(
            jsonDecode(s.irJson!) as Map<String, dynamic>);
      } catch (_) {}
    }
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '曲谱卡片',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      pageBuilder: (ctx, _, _) => Center(
        child: Material(
          color: p.panel,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: p.border)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            // 2026-11-05 用户反馈：卡片放大、主要显示内容、去文件名称。
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // 预览（主内容）：image/pdf 取页图首图；GTP 渲染谱面
              //（TabView 按卡片宽重排，纵向可滚看前段）；两者皆无才显
              // 类型徽标。
              SizedBox(
                height: 320,
                width: double.infinity,
                child: pages.isNotEmpty
                    ? Image.file(pages.first, fit: BoxFit.contain)
                    : gtpIr != null
                        ? Material(
                            color: p.ground,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(8),
                              child: TabView(ir: gtpIr),
                            ),
                          )
                        : Container(
                            color: p.ground,
                            alignment: Alignment.center,
                            child: Icon(Icons.library_music_outlined,
                                size: 72, color: p.muted),
                          ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      '${s.sourceType == 'pdf' ? 'PDF' : s.sourceType == 'gtp' ? 'GTP' : '图片'}'
                      '${s.sourceType == 'gtp' ? '' : ' · ${_pageCounts?[s.id] ?? 0} 页'}'
                      ' · ${s.irJson == null ? '查看器' : '可播放'}'
                      ' · 导入于 ${s.createdAt.year}/${s.createdAt.month}/${s.createdAt.day}',
                      style: TextStyle(fontSize: 12, color: p.muted)),
                  const SizedBox(height: 16),
                  Row(children: [
                    FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      ScoreDetailPage(scoreId: s.id)));
                        },
                        icon: const Icon(Icons.open_in_full, size: 16),
                        label: const Text('打开')),
                    const Spacer(),
                    IconButton(
                        tooltip: '重命名',
                        icon: Icon(Icons.edit_outlined, color: p.ink),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _renameScore(s);
                        }),
                    IconButton(
                        tooltip: '删除',
                        icon: Icon(Icons.delete_outline, color: p.negative),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _confirmDelete(s);
                        }),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// 批量删除（多选模式右下角垃圾桶）：确认框（数量+前几项标题）后
  /// 逐个删除，失败不中断；完成退出多选并刷新。
  Future<void> _deleteSelected() async {
    final repo = _repo;
    final scores = _scores;
    if (repo == null || _selected.isEmpty || !mounted) return;
    final picked =
        scores!.where((s) => _selected.contains(s.id)).toList();
    final preview = picked
        .take(3)
        .map((s) => s.title)
        .join('、');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除 ${picked.length} 份曲谱'),
        content: Text('将删除：$preview'
            '${picked.length > 3 ? ' 等 ${picked.length} 份' : ''}，'
            '原谱文件与识谱结果一并删除，不可恢复。'),
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
    var failed = 0;
    for (final s in picked) {
      try {
        await repo.deleteScore(s.id);
      } catch (_) {
        failed++;
      }
    }
    if (mounted) {
      setState(() {
        _selecting = false;
        _selected.clear();
        _swipedId = null;
      });
      await _reload();
      if (failed > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除完成，$failed 份失败')));
      }
    }
  }

  /// 退出多选（右上角对勾 / Esc）。
  void _exitSelecting() {
    setState(() {
      _selecting = false;
      _selected.clear();
      _swipedId = null;
    });
  }

  /// 重命名（2026-11-03 用户需求）：trim 后非空（两侧不能是空格），
  /// 内部空格允许。撞同类型重名时**自动递增**（2026-11-07 用户反馈：
  /// 与导入同款——`名` → `名 (2)`、`名 (3)`，同类型内唯一，不同类型
  /// 允许同名），SnackBar 提示实际保存名。
  Future<void> _renameScore(Score s) async {
    final repo = _repo;
    final scores = _scores;
    if (repo == null || scores == null || !mounted) return;
    final ctrl = TextEditingController(text: s.title);
    String? error;
    String? validate(String raw) {
      final name = raw.trim();
      if (name.isEmpty) return '曲名不能为空';
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
    // 同类型重名自动递增（2026-11-07 用户反馈，与导入同款语义）：
    // `名` → `名 (1)`、`名 (2)`…（从 (1) 起；排除自己，同类型内唯一）。
    final taken = scores
        .where((o) => o.id != s.id && o.sourceType == s.sourceType)
        .map((o) => o.title)
        .toSet();
    var finalName = name;
    var i = 1;
    while (taken.contains(finalName)) {
      finalName = '$name ($i)';
      i++;
    }
    try {
      await repo.updateTitle(s.id, finalName);
      await _reload();
      if (mounted && finalName != name) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('同类型已有同名，已保存为「$finalName」')));
      }
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

/// 图片排序对话框（2026-11-06 批量导入图片合并）：ReorderableListView
/// 拖拽调整顺序（预填自然排序），缩略图 + 文件名；返回确认后的顺序，
/// 取消返回 null。
class _ImageOrderDialog extends StatefulWidget {
  const _ImageOrderDialog({required this.files});
  final List<File> files;

  @override
  State<_ImageOrderDialog> createState() => _ImageOrderDialogState();
}

class _ImageOrderDialogState extends State<_ImageOrderDialog> {
  late final List<File> _files = List.of(widget.files);

  @override
  Widget build(BuildContext context) {
    // 命名注意：path 包 import 为 p，palette 不得占用同名局部变量。
    final pal = context.palette;
    return AlertDialog(
      title: const Text('调整图片顺序'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: ReorderableListView.builder(
          itemCount: _files.length,
          // Flutter 3.47：onReorderItem 的 newIndex 已自动调整（无需
          // 手动 newIndex--，旧 onReorder 已弃用）。
          onReorderItem: (oldIndex, newIndex) {
            setState(() {
              final f = _files.removeAt(oldIndex);
              _files.insert(newIndex, f);
            });
          },
          itemBuilder: (ctx, i) {
            final f = _files[i];
            // 2026-11-07 用户反馈：去掉上/下移按钮（与序号重叠且拖拽
            // 通道已覆盖——ReorderableListView 按住行直接拖）；序号挪到
            // leading 数字徽章。
            return ListTile(
              key: ValueKey(f.path),
              leading: SizedBox(
                width: 74, // 序号徽章 24 + 间距 6 + 缩略图 44
                child: Row(children: [
                  Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: pal.panel,
                          shape: BoxShape.circle,
                          border: Border.all(color: pal.border)),
                      child: Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 11,
                              color: pal.ink,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]))),
                  const SizedBox(width: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.file(f,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        cacheWidth: 88,
                        errorBuilder: (_, _, _) =>
                            Icon(Icons.broken_image_outlined,
                                size: 24, color: pal.muted)),
                  ),
                ]),
              ),
              title: Text(p.basename(f.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: pal.ink)),
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _files),
            child: Text('以此顺序导入（${_files.length} 张）')),
      ],
    );
  }
}
