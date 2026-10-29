import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/vision/vision_model.dart';
import 'package:guitarbar/data/database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('保存与读取往返', () async {
    final store = VisionModelStore(db);
    await store.saveAll([
      VisionModelConfig(
          id: 'a', name: '智谱', baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
          apiKey: 'k1', model: 'glm-4v-flash', active: true),
      VisionModelConfig(
          id: 'b', name: '自定义', baseUrl: 'https://x/v1',
          apiKey: 'k2', model: 'm2', active: false),
    ]);
    final loaded = await store.load();
    expect(loaded.length, 2);
    expect(loaded[0].name, '智谱');
    expect(loaded[0].active, isTrue);
  });

  test('多套 active 时保留首个', () async {
    final store = VisionModelStore(db);
    await store.saveAll([
      VisionModelConfig(id: 'a', name: 'A', baseUrl: 'u', apiKey: 'k',
          model: 'm', active: true),
      VisionModelConfig(id: 'b', name: 'B', baseUrl: 'u', apiKey: 'k',
          model: 'm', active: true),
    ]);
    final loaded = await store.load();
    expect(loaded.where((e) => e.active).map((e) => e.id), ['a']);
  });

  test('activeOf 取启用配置；空库存返回 null', () async {
    final store = VisionModelStore(db);
    expect(await store.activeOf(await store.load()), isNull);
  });

  test('load 坏数据按空处理', () async {
    final store = VisionModelStore(db);
    await db.into(db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(
            key: VisionModelStore.settingsKey, value: 'not json'));
    expect(await store.load(), isEmpty);
  });

  test('JSON 行格式稳定（settings 表单 key）', () async {
    final store = VisionModelStore(db);
    await store.saveAll([VisionModelConfig(
        id: 'a', name: 'N', baseUrl: 'u', apiKey: 'k', model: 'm',
        active: true)]);
    final raw = await (db.select(db.settings)
            ..where((t) => t.key.equals(VisionModelStore.settingsKey)))
        .getSingle();
    final decoded = jsonDecode(raw.value) as List;
    expect(decoded.first['model'], 'm');
  });
}
