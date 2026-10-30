import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/score_player.dart';
import '../../audio/score_renderer.dart';
import '../../audio/sound_engine.dart';
import '../../core/score/score_ir.dart';
import '../../core/score/score_repository.dart';
import '../../core/vision/score_recognizer.dart';
import '../../core/vision/vision_client.dart';
import '../../core/vision/vision_model.dart';
import '../../data/database.dart';
import '../theme.dart';
import 'note_edit_sheet.dart';
import 'play_bar.dart';
import 'source_viewer.dart';
import 'tab_view.dart';

/// 曲谱详情：未识谱 = 纯查看器（一等使用方式）；谱面区由 Task 12-14 填充。
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
  ScoreIr? _ir; // 识谱结果（null=未识谱）
  List<File>? _pages;
  bool _recognizing = false;
  String? _progress; // '第 X/N 页'
  bool _cancelRequested = false;
  bool _writing = false; // 回写串行守卫：防连点两次，第二次基于旧 _ir 覆盖第一次编辑
  late final ScorePlayer _player;
  bool _rendering = false; // 渲染忙碌（0.3-1s 真实谱）

  @override
  void initState() {
    super.initState();
    // 构造不触引擎（loadPcm/play 才会），initState 初始化安全。
    _player = ScorePlayer(SoundEngine.I, onEnded: _onPlayEnded);
    _initRepo();
  }

  /// 曲终自动停止：tick 已同步清理播放态，这里只刷新按钮/进度。
  void _onPlayEnded() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_player.stop());
    super.dispose();
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

  /// 页图 + 行 + IR 一并加载（识谱回写后复用）。
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
        ir = null; // 坏 IR 按未识谱处理，可在详情重识
      }
    }
    final pages = repo.files.pagePngs(widget.scoreId);
    if (mounted) {
      // 播放中 _ir 被替换（编辑/重识谱回写）：立即停播——旧 PCM 对不上
      // 新 IR 的拍位（tempo 可能变）。stop 同步段先清句柄，下方 setState
      // 时按钮已回到播放态。
      if (_player.playing && !identical(_ir, ir)) {
        unawaited(_player.stop());
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
      // 弹层期间识谱完成 _reload 换了新 IR：按旧坐标写入会覆盖识别结果，拒写。
      if (!identical(_ir, ir)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('识别结果已更新，请重新点选要修正的音符')));
        return;
      }
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
              content: Text('小节已清空；音符补录将在后续版本提供，可重新识谱')));
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

  Future<void> _recognize() async {
    final row = _row;
    final pages = _pages;
    if (row == null || pages == null || pages.isEmpty || _recognizing) return;
    final params = await _askRecognizeParams();
    if (params == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _recognizing = true;
      _cancelRequested = false;
      _progress = null;
    });
    try {
      final store = VisionModelStore(context.read<AppDatabase>());
      final cfg = await store.activeOf(await store.load());
      if (cfg == null) {
        messenger.showSnackBar(const SnackBar(
            content: Text('未配置识谱模型，请到 个人中心 → 识谱模型 配置')));
        return;
      }
      // 延迟校准：模型分钟级，识谱专用 10 分钟超时 + 8192 输出上限 + 关思考
      // （区别于测试连接 15s/1024；thinking 模型不关会把预算烧在 reasoning，
      // content 为空——2026-10-30 探针实证。OpenAI 严格端点用户自配时不传
      // 此参数，故只在识谱场景绑定智谱系模型约定）。
      final client = VisionClient(
          timeout: const Duration(minutes: 10),
          maxTokens: 8192,
          disableThinking: true);
      try {
        final ir = await ScoreRecognizer(client).recognize(
            title: row.title,
            pagePngs: pages,
            cfg: cfg,
            tempo: params.$1,
            tuning: params.$2,
            timeSignature: params.$3,
            capo: params.$4,
            onPage: (done, total) {
              if (mounted) setState(() => _progress = '第 ${done + 1}/$total 页');
            },
            cancelled: () => _cancelRequested,
            // 谱面标注的 capo 覆盖手动兜底值（2026-10-30 用户反馈：
            // 指弹谱的变调夹品数谱面印着，应由模型识别而非用户手填）。
            onCapoRecognized: (sheetCapo) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('已按谱面标注设置变调夹：第 $sheetCapo 品')));
              }
            });
        await _repo!.updateRecognition(widget.scoreId,
            irJson: jsonEncode(ir.toJson()), tuning: ir.tuning.join(','));
        await _reload();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(ir.unrecognizedPages.isEmpty
                  ? '识谱完成'
                  : '识谱完成，第 ${ir.unrecognizedPages.map((e) => e + 1).join(',')} 页未识别')));
        }
      } finally {
        client.close();
      }
    } on RecognizeCancelled {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('识谱已取消')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('识谱失败：$e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _recognizing = false;
          _progress = null;
        });
      }
    }
  }

  /// 播放/停止切换：播 = 渲染整曲 PCM → loadPcm → play。
  Future<void> _togglePlay() async {
    final ir = _ir;
    if (ir == null || _rendering) return;
    if (_player.playing) {
      await _player.stop();
      if (mounted) setState(() {});
      return;
    }
    setState(() => _rendering = true);
    // 同步渲染会阻塞主 isolate（0.3-1s）：先让 busy 帧（spinner）上屏
    // 再渲染，否则 spinner 与播放态同帧出现、忙碌反馈形同虚设。
    await WidgetsBinding.instance.endOfFrame;
    try {
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
      await _player.start();
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

  /// 四元组（曲速/调弦/拍号/变调夹）。调弦 v1 固定标准调弦，
  /// 自定义调弦联动留 M5+（谱面调弦以导入源为准的方案届时评估）。
  Future<(double, List<String>, String, int)?> _askRecognizeParams() =>
      showDialog<(double, List<String>, String, int)>(
        context: context,
        builder: (ctx) {
          double tempo = 90;
          int capo = 0;
          const tuning = ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'];
          return StatefulBuilder(
            builder: (ctx, setLocal) => AlertDialog(
              title: const Text('识谱参数'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const Text('曲速'),
                  Expanded(
                    child: Slider(
                        min: 40,
                        max: 200,
                        divisions: 160,
                        label: '${tempo.round()}',
                        value: tempo,
                        onChanged: (v) => setLocal(() => tempo = v)),
                  ),
                  Text('${tempo.round()}',
                      style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()])),
                ]),
                Row(children: [
                  const Text('变调夹兜底'),
                  IconButton(
                      onPressed: () =>
                          setLocal(() => capo = (capo - 1).clamp(0, 7)),
                      icon: const Icon(Icons.remove_circle_outline)),
                  Text('$capo',
                      style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()])),
                  IconButton(
                      onPressed: () =>
                          setLocal(() => capo = (capo + 1).clamp(0, 7)),
                      icon: const Icon(Icons.add_circle_outline)),
                ]),
                Text('调弦：标准 E-A-D-G-B-E（v1 固定）',
                    style: TextStyle(
                        fontSize: 12, color: ctx.palette.muted)),
                const SizedBox(height: 4),
                Text('变调夹优先按谱面标注自动识别，此处仅兜底',
                    style: TextStyle(
                        fontSize: 12, color: ctx.palette.muted)),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () =>
                        Navigator.pop(ctx, (tempo, tuning, '4/4', capo)),
                    child: const Text('开始识谱')),
              ],
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.ground,
      appBar: AppBar(
        title: Text(_row?.title ?? '曲谱'),
        actions: [
          if (_recognizing) ...[
            Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Center(
                    child: Text(_progress ?? '',
                        style: TextStyle(fontSize: 14, color: p.muted)))),
            IconButton(
                tooltip: '取消识谱',
                onPressed: () => setState(() {
                      _cancelRequested = true;
                      _progress = '取消中…当前页结束后生效';
                    }),
                icon: const Icon(Icons.cancel_outlined)),
          ] else
            IconButton(
                tooltip: 'AI 识谱',
                onPressed:
                    (_pages == null || _pages!.isEmpty) ? null : _recognize,
                icon: const Icon(Icons.document_scanner_outlined)),
        ],
      ),
      body: (_pages == null)
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (ctx, box) {
              final wide = box.maxWidth >= 900; // 与 root.dart 宽窄阈值一致
              final viewer = SourceViewer(pagePngs: _pages!);
              final tabArea = (_ir == null)
                  ? Center(
                      child: Text('尚未识谱——点右上角 AI 识谱',
                          style: TextStyle(color: p.muted)))
                  : ListenableBuilder(
                      // 播放头 50ms 刷新（position notifier 驱动）。
                      listenable: _player.positionSeconds,
                      builder: (ctx, _) => TabView(
                          ir: _ir!,
                          // v1 播放头 tempo 来源：_ir.tempo（M5 变速后改用渲染时值）。
                          playheadBeat: _player.playing
                              ? (_player.positionSeconds.value /
                                  (60.0 / _ir!.tempo))
                              : null,
                          // 识别中禁编辑：回调置空，避免编辑写入被识谱回写覆盖。
                          onNoteTap: _recognizing ? null : _editNote,
                          onFailedTap: _recognizing ? null : _clearMeasure,
                        ),
                    );
              if (wide) {
                // 宽屏：谱面 + 原图并排（识谱对照的原位工作流，设计 §8）。
                return Row(children: [
                  Expanded(child: tabArea),
                  SizedBox(width: 360, child: viewer),
                ]);
              }
              // 窄屏：未识谱只出查看器；已识谱 Tab 切换（谱面/原图）。
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
      // 播放控制条：已识谱才显示；进度由 position notifier 50ms 驱动，
      // playing 态经 setState 切换（_togglePlay）。
      bottomSheet: (_ir == null)
          ? null
          : ListenableBuilder(
              listenable: _player.positionSeconds,
              builder: (ctx, _) => PlayBar(
                  playing: _player.playing,
                  positionSeconds: _player.positionSeconds.value,
                  durationSeconds: _player.durationSeconds,
                  busy: _rendering,
                  onToggle: _togglePlay),
            ),
    );
  }
}
