import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as imgpkg;
import 'package:provider/provider.dart';

import '../../core/vision/vision_client.dart';
import '../../core/vision/vision_model.dart';
import '../../data/database.dart';
import '../theme.dart';

/// 识谱模型配置：卡片列表，可增删改、单选启用、测试连接。
/// key 本地存储不上传（设计文档 §8）。
class VisionModelsPage extends StatefulWidget {
  const VisionModelsPage({super.key});

  @override
  State<VisionModelsPage> createState() => _VisionModelsPageState();
}

class _VisionModelsPageState extends State<VisionModelsPage> {
  late final VisionModelStore _store;
  List<VisionModelConfig>? _configs;
  // 正在测试连接的配置 id 集合：多卡可并发测试，各自锁定/复位互不影响。
  final Set<String> _testing = {};

  @override
  void initState() {
    super.initState();
    _store = VisionModelStore(context.read<AppDatabase>());
    _reload();
  }

  Future<void> _reload() async {
    final list = await _store.load();
    if (mounted) setState(() => _configs = list);
  }

  Future<void> _persist(List<VisionModelConfig> list) async {
    await _store.saveAll(list);
    await _reload();
  }

  Future<void> _edit(VisionModelConfig? existing) async {
    final initial = existing ?? VisionModelStore.zhipuTemplate();
    final result = await showDialog<VisionModelConfig>(
      context: context,
      builder: (ctx) => _ConfigDialog(config: initial),
    );
    if (result == null || !mounted) return;
    final list = [...?_configs];
    if (existing == null) {
      // 新建即当前无任何启用配置时自动启用（2026-10-30 走查反馈：用户漏点
      // 卡片启用导致识谱报"未配置"）。
      final noneActive = list.every((c) => !c.active);
      list.add(noneActive ? result.copyWith(active: true) : result);
    } else {
      // 编辑保留原启用态。
      list[list.indexWhere((c) => c.id == existing.id)] =
          result.copyWith(active: existing.active);
    }
    await _persist(list);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final configs = _configs;
    return Scaffold(
      backgroundColor: p.ground,
      // 新建放右上角（零阴影）：FAB 自带 6dp 阴影，违反设计语言"静止零阴影"。
      appBar: AppBar(
        title: const Text('识谱模型'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
                onPressed: () => _edit(null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建')),
          ),
        ],
      ),
      body: configs == null
          ? const Center(child: CircularProgressIndicator())
          : configs.isEmpty
              ? Center(child: Text('还没有配置，点右上角新建（内置智谱模板）',
                  style: TextStyle(color: p.muted)))
              : ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: configs.length,
                  itemBuilder: (ctx, i) {
                    final c = configs[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: p.panel,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                                color: c.active ? p.dataHue : p.border)),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          title: Text('${c.name} · ${c.model}',
                              style:
                                  TextStyle(fontSize: 16, color: p.ink)),
                          subtitle: Text(c.baseUrl,
                              style:
                                  TextStyle(fontSize: 12, color: p.muted)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                                tooltip: '测试连接',
                                // in-flight：该卡测试中转圈且禁点（其余卡不受影响）。
                                icon: _testing.contains(c.id)
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : Icon(Icons.network_check,
                                        size: 20, color: p.muted),
                                onPressed: _testing.contains(c.id)
                                    ? null
                                    : () => _testConnection(c)),
                            IconButton(
                                tooltip: '编辑',
                                icon: Icon(Icons.edit_outlined,
                                    size: 20, color: p.muted),
                                onPressed: () => _edit(c)),
                            IconButton(
                                tooltip: '删除',
                                icon: Icon(Icons.delete_outline,
                                    size: 20, color: p.muted),
                                onPressed: () => _confirmDelete(c, i)),
                          ]),
                          onTap: () async {
                            // 点卡片 = 启用该套（saveAll 内收口 active 唯一）。
                            await _persist([
                              for (final x in configs)
                                x.copyWith(active: x.id == c.id)
                            ]);
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _testConnection(VisionModelConfig c) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _testing.add(c.id));
    // 8×8 小测试图：运行时生成。测试连接只需验证连通与返回格式，
    // 不花识别级 token。（2026-10-30 走查修复：原手写 PNG 字节常量实测
    // 是坏图——API 报 1210 图片解析错误；二进制常量不可手编。）
    final png = Uint8List.fromList(
        imgpkg.encodePng(imgpkg.Image(width: 8, height: 8)));
    // 短超时：测连接不该干等识别级 120s。超时由 VisionClient 转
    // VisionException，catch (e) 已覆盖，无需特判 TimeoutException。
    final client = VisionClient(timeout: const Duration(seconds: 15));
    try {
      await client.complete(
          baseUrl: c.baseUrl, apiKey: c.apiKey, model: c.model,
          prompt: 'ping', png: png);
      messenger.showSnackBar(const SnackBar(content: Text('连接成功')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('失败：$e')));
    } finally {
      client.close();
      if (mounted) setState(() => _testing.remove(c.id));
    }
  }

  /// 删除前确认（防误触丢 key），确认后才执行删除。
  Future<void> _confirmDelete(VisionModelConfig c, int i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除配置'),
        content: Text('确定删除「${c.name}」？'),
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
    final list = [...?_configs]..removeAt(i);
    await _persist(list);
  }
}

class _ConfigDialog extends StatefulWidget {
  const _ConfigDialog({required this.config});
  final VisionModelConfig config;

  @override
  State<_ConfigDialog> createState() => _ConfigDialogState();
}

class _ConfigDialogState extends State<_ConfigDialog> {
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.config.name);
    _baseUrl = TextEditingController(text: widget.config.baseUrl);
    _apiKey = TextEditingController(text: widget.config.apiKey);
    _model = TextEditingController(text: widget.config.model);
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('模型配置'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _name,
              decoration: const InputDecoration(labelText: '名称')),
          TextField(controller: _baseUrl,
              decoration: const InputDecoration(
                  labelText: 'API 地址（OpenAI 兼容，不含 /chat/completions）')),
          TextField(controller: _apiKey,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'API Key')),
          TextField(controller: _model,
              decoration:
                  const InputDecoration(labelText: '模型名（如 glm-4v-flash）')),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        ListenableBuilder(
          listenable:
              Listenable.merge([_name, _baseUrl, _apiKey, _model]),
          builder: (ctx, _) => FilledButton(
              onPressed: _baseUrl.text.trim().isEmpty ||
                      _model.text.trim().isEmpty ||
                      _apiKey.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      // 名称留空则用模型名兜底，列表不出现空标题。
                      widget.config.copyWith(
                          name: _name.text.trim().isEmpty
                              ? _model.text.trim()
                              : _name.text.trim(),
                          baseUrl: _baseUrl.text.trim(),
                          apiKey: _apiKey.text.trim(),
                          model: _model.text.trim())),
              child: const Text('保存')),
        ),
      ],
    );
  }
}
