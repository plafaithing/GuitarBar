import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/data/database.dart';
import 'package:guitarbar/state/theme_settings.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('load 默认 system', () async {
    final s = ThemeSettingsState(db);
    await s.load();
    expect(s.mode, ThemeMode.system);
  });

  test('setMode(dark) → 新实例 load 得 dark', () async {
    final s = ThemeSettingsState(db);
    await s.load();
    await s.setMode(ThemeMode.dark);
    final s2 = ThemeSettingsState(db);
    await s2.load();
    expect(s2.mode, ThemeMode.dark);
  });

  test('setMode(system) 往返', () async {
    final s = ThemeSettingsState(db);
    await s.load();
    await s.setMode(ThemeMode.dark);
    await s.setMode(ThemeMode.system);
    final s2 = ThemeSettingsState(db);
    await s2.load();
    expect(s2.mode, ThemeMode.system);
  });
}
