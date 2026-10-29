import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/database.dart';

/// 一套识谱模型配置（OpenAI 兼容协议）。厂商只作为预置模板出现，
/// 架构不绑定任何厂商（设计文档 §5.2）。
class VisionModelConfig {
  const VisionModelConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.active,
  });

  final String id; // UUID 或时间戳字符串
  final String name; // 显示名
  final String baseUrl; // 如 https://open.bigmodel.cn/api/paas/v4
  final String apiKey;
  final String model; // 如 glm-4v-flash
  final bool active; // 单套启用

  VisionModelConfig copyWith({String? name, String? baseUrl, String? apiKey,
          String? model, bool? active}) =>
      VisionModelConfig(
          id: id,
          name: name ?? this.name,
          baseUrl: baseUrl ?? this.baseUrl,
          apiKey: apiKey ?? this.apiKey,
          model: model ?? this.model,
          active: active ?? this.active);

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'baseUrl': baseUrl,
        'apiKey': apiKey, 'model': model, 'active': active,
      };

  static VisionModelConfig fromJson(Map<String, dynamic> j) =>
      VisionModelConfig(
          id: j['id'] as String,
          name: j['name'] as String? ?? '',
          baseUrl: j['baseUrl'] as String? ?? '',
          apiKey: j['apiKey'] as String? ?? '',
          model: j['model'] as String? ?? '',
          active: j['active'] as bool? ?? false);
}

/// settings 表持久化（key = visionModels，JSON 数组）。active 唯一性在此收口。
class VisionModelStore {
  VisionModelStore(this._db);
  static const settingsKey = 'visionModels';

  final AppDatabase _db;

  /// 智谱预置模板（配置页新建时一键预填）。
  static VisionModelConfig zhipuTemplate() => VisionModelConfig(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: '智谱 GLM',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      apiKey: '',
      model: 'glm-4v-flash',
      active: false);

  Future<List<VisionModelConfig>> load() async {
    final row = await (_db.select(_db.settings)
            ..where((t) => t.key.equals(settingsKey)))
        .getSingleOrNull();
    if (row == null) return const [];
    try {
      final list = jsonDecode(row.value) as List;
      return [
        for (final e in list) VisionModelConfig.fromJson(e as Map<String, dynamic>)
      ];
    } catch (e) {
      debugPrint('识谱模型配置损坏，已按空处理：$e');
      return const []; // 坏数据按空处理，页面可重建
    }
  }

  Future<void> saveAll(List<VisionModelConfig> configs) async {
    // active 唯一：保留首个 active，其余强置 false。
    final normalized = <VisionModelConfig>[];
    var seenActive = false;
    for (final c in configs) {
      if (c.active && !seenActive) {
        normalized.add(c);
        seenActive = true;
      } else {
        normalized.add(c.active ? c.copyWith(active: false) : c);
      }
    }
    await _db.into(_db.settings).insertOnConflictUpdate(SettingsCompanion.insert(
        key: settingsKey,
        value: jsonEncode([for (final c in normalized) c.toJson()])));
  }

  Future<VisionModelConfig?> activeOf(List<VisionModelConfig> configs) async =>
      configs.where((c) => c.active).firstOrNull;
}
