import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/vision/vision_model.dart';
import 'package:guitarbar/data/database.dart';
import 'package:guitarbar/ui/profile/vision_models_page.dart';
import 'package:guitarbar/ui/theme.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('空态提示新建', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<AppDatabase>.value(value: db),
    ], child: MaterialApp(
        theme: GuitarBarTheme.light(), home: const VisionModelsPage())));
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有配置'), findsOneWidget);
  });

  testWidgets('已有配置显示卡片并可点选启用', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = VisionModelStore(db);
    await store.saveAll([VisionModelConfig(
        id: 'a', name: '智谱', baseUrl: 'https://u', apiKey: 'k',
        model: 'glm-4v-flash', active: false)]);
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<AppDatabase>.value(value: db),
    ], child: MaterialApp(
        theme: GuitarBarTheme.light(), home: const VisionModelsPage())));
    await tester.pumpAndSettle();
    expect(find.textContaining('智谱'), findsWidgets);
    await tester.tap(find.textContaining('智谱').first);
    await tester.pumpAndSettle();
    final raw = await (db.select(db.settings)
            ..where((t) => t.key.equals(VisionModelStore.settingsKey)))
        .getSingle();
    expect((jsonDecode(raw.value) as List).first['active'], isTrue);
  });
}
