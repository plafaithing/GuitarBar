import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/sample_bank.dart';
import '../../audio/sample_player.dart';
import '../../audio/score_player.dart';
import '../../audio/score_renderer.dart';
import '../../audio/sound_engine.dart';
import '../../core/music/builtin_tunings.dart';
import '../../core/score/score_ir.dart';
import '../../core/score/score_repository.dart';
import '../../data/database.dart';
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
    }
  }

  /// 音符点选编辑：弹层确认后回写 IR（confidence=1 人工确认）并刷新。
  Future<void> _editNote(int m, int i, NoteIr n) async {
    final ir = _ir;
    if (ir == null || _repo == null || _writing) return;
    _writing = true;
    try {
      final beatsPerBar = int.tryParse(ir.timeSignature.split('/').first) ?? 4;
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
  Future<void> _playFromNote(int m, int i, NoteIr n) async {
    final ir = _ir;
    if (ir == null || _rendering) return;
    final beatsPerBar = int.tryParse(ir.timeSignature.split('/').first) ?? 4;
    final seconds = (m * beatsPerBar + n.beat) * 60.0 / ir.tempo;
    final active = _activePlayer;
    if (active.playing || active.paused) {
      await active.seekToSecond(seconds);
      if (mounted) setState(() {});
      return;
    }
    await _togglePlay(startAt: seconds);
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

  /// 停止按钮：归零回开头（暂停只是冻结位置，停止才是归零）。
  Future<void> _stopPlay() async {
    await _activePlayer.stop();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.ground,
      appBar: AppBar(title: Text(_row?.title ?? '曲谱')),
      body: (_pages == null)
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (ctx, box) {
              final wide = box.maxWidth >= 900; // 与 root.dart 宽窄阈值一致
              final isGtp = _row?.sourceType == 'gtp';
              final viewer = SourceViewer(pagePngs: _pages!);
              final tabArea = (_ir == null)
                  ? Center(
                      child: Text('谱面数据不可用', style: TextStyle(color: p.muted)))
                  // 调弦/变调夹信息条 + 谱面。宽窄两布局共用此 Column。
                  : Column(children: [
                      Padding(
                        // 左缩进 16 与谱面 TabLayout.leftPad 对齐。
                        padding: const EdgeInsets.only(left: 16, bottom: 8),
                        child: Text(
                            '${_tuningLabel(_ir!)}'
                            '${_ir!.capo > 0 ? ' · Capo ${_ir!.capo}品' : ''}'
                            ' · ${_ir!.tempo.round()} BPM',
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
                          builder: (ctx, _) => TabView(
                              ir: _ir!,
                              // v1 播放头 tempo 来源：_ir.tempo（M5 变速后改用渲染时值）。
                              playheadBeat: _activePlayer.playing
                                  ? (_activePlayer.positionSeconds.value /
                                      (60.0 / _ir!.tempo))
                                  : null,
                              // 播放时谱面自动滚动跟随（走查反馈 ②）。
                              followPlayhead: true,
                              // 点击音符=从此起播（2026-11-01 走查）；
                              // 编辑移到长按。
                              onNoteTap: _playFromNote,
                              onNoteLongPress: _editNote,
                              onFailedTap: _clearMeasure,
                            ),
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
            }),
      // 播放控制条：有谱面数据才显示；进度由 position notifier 50ms 驱动，
      // playing/paused 态经 setState 切换（_togglePlay/_stopPlay）。
      bottomSheet: (_ir == null)
          ? null
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
                  onSeek: _onSeek),
            ),
    );
  }
}
