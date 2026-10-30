import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/score/score_files.dart';
import '../../core/score/score_ir.dart';
import '../../core/score/score_repository.dart';
import '../../core/vision/score_recognizer.dart';
import '../../core/vision/vision_client.dart';
import '../../core/vision/vision_model.dart';
import '../../data/database.dart';
import '../theme.dart';
import 'source_viewer.dart';

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
        // 与 ScoresPage 同一路径约定：<support>/scores/<id>/ 的页图。
        // 经 ScoreFiles 读（不用手写目录遍历）。
        final dir = await getApplicationSupportDirectory();
        if (!mounted) return;
        repo = ScoreRepository(context.read<AppDatabase>(),
            ScoreFiles(Directory(p.join(dir.path, 'scores'))));
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
      setState(() {
        _row = row;
        _ir = ir;
        _pages = pages;
      });
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
      // 延迟校准：模型 thinking 分钟级，识谱专用 10 分钟超时（区别于测试连接 15s）。
      final client = VisionClient(timeout: const Duration(minutes: 10));
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
            cancelled: () => _cancelRequested);
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
                  const Text('变调夹'),
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
                onPressed: () => _cancelRequested = true,
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
          : (_ir != null)
              ? Center(
                  child: Text('已识谱 · 谱面视图建设中（下一里程碑）',
                      style: TextStyle(color: p.muted)))
              : SourceViewer(pagePngs: _pages!),
    );
  }
}
