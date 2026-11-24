import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../audio/sample_bank.dart';
import '../../audio/sample_player.dart';
import '../../audio/score_player.dart';
import '../../audio/score_renderer.dart';
import '../../audio/sound_engine.dart';
import '../../core/music/builtin_tunings.dart';
import '../../core/score/score_ir.dart';
import '../../core/score/score_repository.dart';
import '../../data/database.dart';
import '../gbar_background.dart';
import '../theme.dart';
import 'note_edit_sheet.dart';
import 'play_bar.dart';
import 'source_viewer.dart';
import 'tab_view.dart';

/// 曲谱详情（13.4 通道二选一）：GTP = 谱面全屏；图片/PDF = 纯查看器，
/// 历史 IR 数据仍可显示谱面。识谱 UI 已随 AI 通道放弃移除。
class ScoreDetailPage extends StatefulWidget {
  const ScoreDetailPage({super.key, required this.scoreId, this.repoFactory});
  final int scoreId;

  // widget 测试注入用；null = 走默认 path_provider 路径。
  final ScoreRepository Function()? repoFactory;

  @override
  State<ScoreDetailPage> createState() => _ScoreDetailPageState();
}

class _ScoreDetailPageState extends State<ScoreDetailPage> {
  ScoreRepository? _repo;
  Score? _row; // 当前行（标题/irJson）
  ScoreIr? _ir; // 谱面数据（null=无）
  List<File>? _pages;
  bool _writing = false; // 回写串行守卫：防连点两次，第二次基于旧 _ir 覆盖第一次编辑
  late final ScorePlayer _player;
  // GP8 真录钢弦采样路径（构造不触引擎；play 时才预载/调度）。
  late final SteelSampleBank _sampleBank;
  late final SampleScorePlayer _samplePlayer;
  bool _rendering = false; // 渲染忙碌（0.3-1s 真实谱）

  @override
  void initState() {
    super.initState();
    // 构造不触引擎（loadPcm/play 才会），initState 初始化安全。
    _player = ScorePlayer(SoundEngine.I, onEnded: _onPlayEnded);
    _sampleBank = SteelSampleBank(SoundEngine.I);
    _samplePlayer =
        SampleScorePlayer(SoundEngine.I, _sampleBank, onEnded: _onPlayEnded);
    _initRepo();
    // 渐进提速自动档回调（两播放器同接；KS 路径不触发渐进）。
    _samplePlayer.onAutoRate = _showAutoRate;
    _player.onAutoRate = _showAutoRate;
  }

  /// 渐进自动提速提示（播放器每档触发）。
  void _showAutoRate(double r) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text('渐进提速至 ${r.toStringAsFixed(2)}x'),
            duration: const Duration(seconds: 1)));
    }
  }

  /// 当前生效的播放器：采样播放/暂停中读采样播放器，否则读 KS 播放器
  /// （曲终/停止后回到 KS 播放器的预播放态：position 0、duration 0）。
  ScorePlayback get _activePlayer =>
      (_samplePlayer.playing || _samplePlayer.paused)
          ? _samplePlayer
          : _player;

  /// 曲终自动停止：tick 已同步清理播放态，这里只刷新按钮/进度。
  void _onPlayEnded() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_shutdownAudio());
    super.dispose();
  }

  /// 三条路径全 fire-and-forget（2026-11-01 走查"关闭 1s 内"：逐个 await
  /// 的原生释放——尤其 KS 整曲 PCM disposeSource——在主 isolate 排队拖慢
  /// 页面退出/窗口关闭；各自幂等，进程退出 OS 兜底回收）。
  Future<void> _shutdownAudio() async {
    unawaited(_player.stop());
    unawaited(_samplePlayer.stop());
    unawaited(_sampleBank.dispose());
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

  /// 页图 + 行 + IR 一并加载（编辑回写后复用）。
  Future<void> _reload() async {
    final repo = _repo;
    if (repo == null) return;
    final row = await repo.getScore(widget.scoreId);
    ScoreIr? ir;
    final raw = row?.irJson;
    if (raw != null) {
      try {
        ir = ScoreIr.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        ir = null; // 坏 IR 按无谱面数据处理
      }
    }
    final pages = repo.files.pagePngs(widget.scoreId);
    if (mounted) {
      // 播放中 _ir 被替换（编辑回写）：立即停播——旧调度/旧 PCM 对不上
      // 新 IR 的拍位（tempo 可能变）。stop 同步段先清句柄，下方 setState
      // 时按钮已回到播放态。
      if (_activePlayer.playing && !identical(_ir, ir)) {
        unawaited(_activePlayer.stop());
      }
      setState(() {
        _row = row;
        _ir = ir;
        _pages = pages;
      });
      // 采样预热（2026-11-08 gp8 对照：gp8 打开即预渲染，点播放立即出声
      // ——我们点播放才现载采样，首播延迟 1-3s）。后台预载本曲触到的
      // 全部采样，点播放时缓存全命中。
      if (ir != null && ir.tracks.isNotEmpty && ir.tuning.length == 6) {
        unawaited(_sampleBank.preloadFor(ir).catchError((_) {}));
      }
    }
  }

  /// 线性小节 [m] 起始四分拍（无展开结构谱的秒换算 fallback：
  /// per-measure 四分拍累计——2026-11-19 X/8 拍号口径统一，与
  /// TabLayout.linearStarts / sample_player.playbackOrderStarts 同源）。
  double _linearMeasureBeat(ScoreIr ir, int m) {
    final ms = ir.tracks.first.measures;
    final global = measureQuarterBeats(ir.timeSignature);
    var acc = 0.0;
    for (var i = 0; i < m && i < ms.length; i++) {
      acc += measureQuarterBeats(ms[i].timeSignature, fallback: global);
    }
    return acc;
  }

  /// 音符点选编辑：弹层确认后回写 IR（confidence=1 人工确认）并刷新。
  Future<void> _editNote(int m, int i, NoteIr n) async {
    final ir = _ir;
    if (ir == null) return;
    // 长按操作菜单（2026-11-19 AB 谱面点选主路径——业界标准：谱面
    // 直接点选区间端点；播头快捷键路径保留在 PlayBar A/B 钮）。
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('编辑音符'),
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.repeat_outlined),
            title: const Text('设为循环 A 点（起点）'),
            onTap: () => Navigator.pop(ctx, 'a'),
          ),
          ListTile(
            leading: const Icon(Icons.repeat_one_outlined),
            title: const Text('设为循环 B 点（终点）'),
            onTap: () => Navigator.pop(ctx, 'b'),
          ),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'a' || action == 'b') {
      // 音符精确秒（与 _playFromNote 同款换算：展开结构取首次遍次）。
      final active = _activePlayer;
      final start = active.startSecondsForBeat(
          m, n.beat);
      // 无展开结构 fallback：per-measure 四分拍累计（2026-11-19 X/8
      // 拍号口径统一——分子计拍此前 6/8 秒位 2x）。
      final secs =
          start ??
          (_linearMeasureBeat(ir, m) + n.beat) * 60.0 / ir.tempo;
      if (action == 'a') {
        active.loopA = secs;
      } else {
        active.loopB = secs;
      }
      // 误序容错（与 _setLoop 同款）。
      final a = active.loopA, b = active.loopB;
      if (a != null && b != null && b < a) {
        active.loopA = b;
        active.loopB = a;
      }
      setState(() {});
      return;
    }
    if (_repo == null || _writing) return;
    _writing = true;
    try {
      // 时值上限口径（2026-11-19 X/8 统一：四分拍 6/8=3——分子计拍
      // 此前允许写出 2x 超小节时值）。
      final beatsPerBar = measureQuarterBeats(ir.timeSignature).round();
      final result =
          await showNoteEditSheet(context, n, beatsPerBar: beatsPerBar);
      if (result == null || !mounted) return;
      final next = applyNoteEdit(ir, m, i, result);
      try {
        await _repo!.updateIrJson(widget.scoreId, jsonEncode(next.toJson()));
        await _reload();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('保存失败：$e')));
        }
      }
    } finally {
      _writing = false;
    }
  }

  /// failed 小节点击：重建为空小节，进入可编辑状态。
  Future<void> _clearMeasure(int m) async {
    final ir = _ir;
    if (ir == null || _repo == null || _writing) return;
    _writing = true;
    try {
      final next = applyMeasureClear(ir, m);
      try {
        await _repo!.updateIrJson(widget.scoreId, jsonEncode(next.toJson()));
        await _reload();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('小节已清空；音符补录将在后续版本提供')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('保存失败：$e')));
        }
      }
    } finally {
      _writing = false;
    }
  }

  /// 信息条调弦文案：IR 调弦与 20 组内置预设比对（音名集合），命中显示
  /// 预设名（如"标准调弦 Standard"），未命中显示音名（走查反馈：识别
  /// 出的调弦若在预设库中应标注）。
  String _tuningLabel(ScoreIr ir) {
    final names = [for (final s in ir.tuning) s.toUpperCase()];
    for (final preset in builtinTunings) {
      final presetNames = [
        for (final n in preset.strings) n.name.toUpperCase()
      ];
      if (names.length == presetNames.length) {
        var same = true;
        for (var i = 0; i < names.length; i++) {
          if (names[i] != presetNames[i]) {
            same = false;
            break;
          }
        }
        if (same) return '调弦 ${preset.name}';
      }
    }
    return '调弦 ${ir.tuning.join(' - ')}';
  }

  /// 播放/暂停切换（走查反馈 ①）：未播放 → 采样优先起播（预载失败降级
  /// 离线 KS 渲染）；在播 → 暂停（采样路径切声部冻结时间轴，PCM 路径
  /// soloud 冻结在暂停点）；暂停中 → 从暂停点继续。
  /// [startAt]：起播位置秒（点音起播/进度条拖动起播用，null=从头）。
  Future<void> _togglePlay({double? startAt}) async {
    final ir = _ir;
    if (ir == null || _rendering) return;
    final active = _activePlayer;
    if (active.paused) {
      active.resume();
      if (mounted) setState(() {});
      return;
    }
    if (active.playing) {
      active.pause();
      if (mounted) setState(() {});
      return;
    }
    setState(() => _rendering = true);
    // 同步渲染会阻塞主 isolate（0.3-1s）：先让 busy 帧（spinner）上屏
    // 再渲染，否则 spinner 与播放态同帧出现、忙碌反馈形同虚设。
    await WidgetsBinding.instance.endOfFrame;
    try {
      // 采样优先：GP8 真录钢弦逐音调度；返回 false（预载失败/无可发
      // 音符）降级离线 KS 渲染——"还没有可演奏的音符"提示也由该路径出。
      // startAt 先记入播放器的 pendingSeek（播放器内部 start 时生效）。
      if (startAt != null) {
        await _samplePlayer.seekToSecond(startAt);
      }
      if (!await _samplePlayer.play(ir)) {
        // 渲染在主 isolate 直接做（0.3-1s）：忙碌态由 _rendering 承担；
        // M5 变速重渲染时再 Isolate.run（Task 15 备案）。
        // 降级原因可见化（2026-11-23）：静默降级让「渐进不生效」类问题
        // 无从排查（用户实证）——原因一次性提示（缺失采样文件名等）。
        final reason = _samplePlayer.lastFailReason;
        if (mounted && reason != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('采样音色不可用（$reason），已切换合成音色'),
              duration: const Duration(seconds: 3)));
        }
        final rendered = renderScore(ir);
        if (rendered.seconds == 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('这份谱还没有可演奏的音符')));
          }
          return;
        }
        await _player.load(rendered);
        if (startAt != null) {
          // KS 路径：无 pendingSeek 机制内建（PCM 已加载），start 后立即 seek。
          await _player.start();
          await _player.seekToSecond(startAt);
        } else {
          await _player.start();
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('播放失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  /// 点击音符：从此音起播（2026-11-01 走查需求）。播放/暂停中即时跳转，
  /// 未播放则记起点起播；编辑入口移至长按（TabView.onNoteLongPress）。
  /// 反复结构谱：起播点映射到展开轴（该小节首次出现的遍次）。
  Future<void> _playFromNote(int m, int i, NoteIr n) async {
    final ir = _ir;
    if (ir == null || _rendering) return;
    // 线性谱面拍位（无展开结构 fallback 用；per-measure 四分拍累计
    // ——2026-11-19 X/8 拍号口径统一）。
    final linearBeat = _linearMeasureBeat(ir, m) + n.beat;
    final seconds = linearBeat * 60.0 / ir.tempo;
    final active = _activePlayer;
    // 精确定位到点击音符（2026-11-03 走查：停止/暂停后点音总是从所在
    // 小节开头播——startSecondsForMeasure 只有小节粒度，丢了小节内
    // 拍位）。展开结构谱：小节首次遍次起点 + 小节内拍偏移；线性谱：
    // 线性秒。暂停/停止/播放中三种状态一致用精确位置。
    final start = active.startSecondsForBeat(m, n.beat);
    if (active.playing || active.paused) {
      await active.seekToSecond(start ?? seconds);
      if (mounted) setState(() {});
      return;
    }
    await _togglePlay(startAt: start ?? seconds);
  }

  /// 进度条拖动定位（松手回调）：播放/暂停中即时 seek；未播放从该处起播。
  Future<void> _onSeek(double seconds) async {
    final active = _activePlayer;
    if (active.playing || active.paused) {
      await active.seekToSecond(seconds);
    } else {
      await _togglePlay(startAt: seconds);
    }
    if (mounted) setState(() {});
  }

  /// 速度切换（2026-11-11 实时变速终版）：**双路径一律声部级实时变速**
  /// ——采样路径重锚调度轴；KS 路径 setVoiceSpeed（句柄实时变速）。
  /// 均不停播、不重渲染、不 seek（旧 KS"停→重渲→seek"是用户实测
  /// "变速后停止从头播放"的根因：渲染阻塞 0.3-1s + seek 轴错位）。
  /// 采样变速自然变调（gp8 采样同此）；KS 声部变速同样变调。
  Future<void> _onRateChanged(double r) async {
    final active = _activePlayer;
    if (identical(active, _samplePlayer)) {
      _samplePlayer.setRate(r);
    } else {
      // KS（含未播放：_handle null 只记 _rate，起播即生效）。
      _player.rate = r;
      // 双播放器速率同步（下次切换路径不用重设）。
      _samplePlayer.rate = r;
    }
    if (mounted) setState(() {});
  }

  /// AB 打点：A=当前位记起点，B=当前位记终点；再点同钮清除。
  /// B < A 时交换（误序容错）。两钮均设 = 循环中。
  void _onLoopA() => _setLoop(isA: true);

  void _onLoopB() => _setLoop(isA: false);

  void _setLoop({required bool isA}) {
    final active = _activePlayer;
    if (isA) {
      active.loopA = active.loopA == null ? active.positionSeconds.value : null;
    } else {
      active.loopB = active.loopB == null ? active.positionSeconds.value : null;
    }
    final a = active.loopA, b = active.loopB;
    if (a != null && b != null && b < a) {
      active.loopA = b;
      active.loopB = a;
    }
    setState(() {});
  }

  /// 停止按钮：归零回开头（暂停只是冻结位置，停止才是归零）。
  Future<void> _stopPlay() async {
    await _activePlayer.stop();
    if (mounted) setState(() {});
  }

  /// 打开链接备注（2026-11-03 走查三件套）：系统默认浏览器。
  /// 只放行 http/https 且 host 非空（dsh 复测：`https:foo`/`https://`
  /// 无主机也该拒）；launchUrl 失败除返回 false 外还可能抛
  /// PlatformException（dsh P2-3），一并兜底。
  Future<void> _openNoteUrl() async {
    final url = _row?.noteUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('链接无效：$url')));
      }
      return;
    }
    bool launched;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, st) {
      // 全捕获（不用 on Exception）：UnimplementedError 等 Error 子类
      // on Exception 接不住 → 用户实测"点击后没有反应"无任何提示。
      // 编程错误（StateError 等）同时上报 debug 日志（dsh 复测：不能
      // 只降级成 SnackBar 而在调试中消失）；用户看通用文案。
      FlutterError.reportError(FlutterErrorDetails(
          exception: e, stack: st, library: 'score_detail_page',
          context: ErrorDescription('launchUrl')));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法打开链接（系统未响应）')));
      }
      return;
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法打开链接：$url')));
    }
  }

  /// 编辑链接备注（顶部栏按钮 → 对话框输入，留空保存 = 清除）。
  Future<void> _editNoteUrl() async {
    final row = _row;
    final repo = _repo;
    if (row == null || repo == null || !mounted) return;
    final ctrl = TextEditingController(text: row.noteUrl ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('链接备注'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: '网址（教学/视频，留空清除）',
              hintText: 'https://…'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    var url = ctrl.text.trim();
    // 注：不在 pop 返回后 dispose（对话框退出动画仍引用它）——同
    // _renameScore 的权衡，正规修法局部 StatefulWidget，此处不引入。
    // 无 scheme 自动补 https://（dsh P2-4：用户输入 "bilibili.com/xxx"
    // 直接入库会打不开）；scheme 判断大小写不敏感（HTTP:// 不得被
    // 二次拼接成 https://HTTP:// 坏链接，dsh 复测 P3）。
    final lower = url.toLowerCase();
    if (url.isNotEmpty &&
        !lower.startsWith('http://') &&
        !lower.startsWith('https://')) {
      url = 'https://$url';
    }
    try {
      await repo.updateNoteUrl(row.id, url.isEmpty ? null : url);
    } catch (e) {
      // 写库失败（锁/盘）可见化，_row 保持旧值不误显新链接。
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
      return;
    }
    try {
      final fresh = await repo.getScore(row.id);
      if (mounted) setState(() => _row = fresh);
    } catch (_) {} // 回读失败不影响已写入的结果
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      // v2：透明 Scaffold + 统一光晕背景层（独立路由，自带外壳）。
      backgroundColor: Colors.transparent,
      // 曲谱文件名称居中（2026-11-08 用户反馈）。
      appBar: AppBar(
          centerTitle: true,
          title: Text(_row?.title ?? '曲谱'), actions: [
        // 链接备注（2026-11-03 走查三件套）：有链接先显"打开"，编辑钮
        // 常驻（无备注 = 添加图标，有备注 = 编辑图标）。行未加载时隐藏
        //（dsh P3：点了没反应像坏掉）。
        if (_row != null) ...[
          if ((_row?.noteUrl ?? '').isNotEmpty)
            IconButton(
                tooltip: '打开备注链接',
                icon: const Icon(Icons.open_in_new, size: 20),
                onPressed: _openNoteUrl),
          IconButton(
              tooltip: (_row?.noteUrl ?? '').isEmpty ? '添加链接备注' : '编辑链接备注',
              icon: Icon(
                  (_row?.noteUrl ?? '').isEmpty
                      ? Icons.note_add_outlined
                      : Icons.edit_note,
                  size: 22),
              onPressed: _editNoteUrl),
          const SizedBox(width: 8),
        ],
      ]),
      body: GbarBackground(
        child: (_pages == null)
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(builder: (ctx, box) {
              final wide = box.maxWidth >= 900; // 与 root.dart 宽窄阈值一致
              final isGtp = _row?.sourceType == 'gtp';
              final viewer = SourceViewer(pagePngs: _pages!);
              final tabArea = (_ir == null)
                  ? Center(
                      child: Text('谱面数据不可用', style: TextStyle(color: p.muted)))
                  // 调弦/变调夹信息条 + 谱面。宽窄两布局共用此 Column。
                  // 2026-11-08 用户反馈：调弦说明左对齐（原 Column 默认
                  // center 把信息条挤到中间）。
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(
                        // 左缩进 16 与谱面 TabLayout.leftPad 对齐。
                        padding: const EdgeInsets.only(left: 16, bottom: 8),
                        child: Text(
                            '${_tuningLabel(_ir!)}'
                            ' · ${_ir!.tempo.round()} BPM',
                            // Capo 标注已在谱面第 1 小节上方（capo:N，
                            // gp8 同位置）——信息条不再重复（2026-11-08）。
                            style: TextStyle(
                                fontSize: 12,
                                color: p.muted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                      ),
                      Expanded(
                        child: ListenableBuilder(
                          // 播放头 50ms 刷新（position notifier 驱动）。
                          listenable: _activePlayer.positionSeconds,
                          builder: (ctx, _) {
                            // 展开拍位（含反复跳回）→ 线性谱面拍位
                            //（2026-11-02 GP8 复刻：反复播放头指回段首）。
                            final playBeat =
                                _activePlayer.positionSeconds.value /
                                    (60.0 / _ir!.tempo);
                            final linear =
                                _activePlayer.linearBeatAt(playBeat);
                            // AB 循环段谱面标记（2026-11-19 用户需求：
                            // 秒 → 线性拍，与播放头同款换算）。
                            final secsPerBeat = 60.0 / _ir!.tempo;
                            final (loopA, loopB) = (
                              _activePlayer.loopA,
                              _activePlayer.loopB
                            );
                            return TabView(
                              ir: _ir!,
                              playheadBeat: _activePlayer.playing
                                  ? (linear ?? playBeat)
                                  : null,
                              loopABeats: (
                                loopA == null
                                    ? null
                                    : _activePlayer.linearBeatAt(
                                        loopA / secsPerBeat),
                                loopB == null
                                    ? null
                                    : _activePlayer.linearBeatAt(
                                        loopB / secsPerBeat),
                              ),
                              // 播放时谱面自动滚动跟随（走查反馈 ②）。
                              followPlayhead: true,
                              // 点击音符=从此起播（2026-11-01 走查）；
                              // 编辑移到长按。
                              onNoteTap: _playFromNote,
                              onNoteLongPress: _editNote,
                              onFailedTap: _clearMeasure,
                            );
                          },
                        ),
                      ),
                    ]);
              if (wide) {
                // 13.4：GTP 全屏谱面（右侧"没有页图"空态无意义，删除并排）。
                if (isGtp) return tabArea;
                // 图片/PDF 纯查看器；有历史 IR 数据则谱面 + 原图并排保留。
                if (_ir == null) return viewer;
                return Row(children: [
                  Expanded(child: tabArea),
                  SizedBox(width: 360, child: viewer),
                ]);
              }
              // 窄屏：GTP 无原图直接谱面；未识谱（图片谱）只出查看器；
              // 有 IR 的图片谱 Tab 切换（谱面/原图）。
              if (isGtp) return tabArea;
              if (_ir == null) return viewer;
              return DefaultTabController(
                length: 2,
                child: Column(children: [
                  TabBar(
                    tabs: const [Tab(text: '谱面'), Tab(text: '原图')],
                    labelColor: p.ink,
                    unselectedLabelColor: p.muted,
                    indicatorColor: p.dataHue,
                  ),
                  Expanded(
                    child: TabBarView(children: [tabArea, viewer]),
                  ),
                ]),
              );
            })), // LayoutBuilder + GbarBackground child 闭合
      // 播放控制条：有谱面数据才显示；进度由 position notifier 50ms 驱动，
      // playing/paused 态经 setState 切换（_togglePlay/_stopPlay）。
      bottomSheet: (_ir == null)
          ? null
          // 2026-11-12 四轮根治（用户三轮"背后色块"反馈）：**不加
          // Material 包裹**——Material(transparent) 在 bottomSheet 槽的
          // 约束下仍画出不透明 panel 底（浅色 (237,235,230) 全宽灰带，
          // golden A/B 实验：Material 换红→整带变红；去掉→干净透底）。
          // 11-10 加它本想盖"暗带"，实际它就是色块本体。裸放
          // ListenableBuilder+PlayBar（底板已透明，见 play_bar），真机上
          // bottomSheet 区透出 root 壳 ground（与谱面背景同色）。
          : ListenableBuilder(
              listenable: _activePlayer.positionSeconds,
              builder: (ctx, _) => PlayBar(
                playing: _activePlayer.playing,
                paused: _activePlayer.paused,
                positionSeconds: _activePlayer.positionSeconds.value,
                durationSeconds: _activePlayer.durationSeconds,
                busy: _rendering,
                onToggle: () => _togglePlay(),
                onStop: _stopPlay,
                onSeek: _onSeek,
                rate: _activePlayer.rate,
                onRateChanged: _onRateChanged,
                loopA: _activePlayer.loopA,
                loopB: _activePlayer.loopB,
                onLoopA: _onLoopA,
                onLoopB: _onLoopB,
                progressiveOn: _activePlayer.progressiveOn,
                onToggleProgressive: () {
                  final opening = !_activePlayer.progressiveOn;
                  setState(() => _activePlayer.progressiveOn = opening);
                  if (opening && mounted) {
                    // 开启反馈：原速开启时播放器自动降 0.75 起步。
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            '渐进提速已开：当前 ${_activePlayer.rate.toStringAsFixed(2)}x，'
                            '每 3 遍 +5% 到原速自动停'),
                        duration: const Duration(seconds: 2)));
                  }
                },
              ),
            ),
    );
  }
}