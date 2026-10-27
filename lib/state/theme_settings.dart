import 'package:flutter/material.dart';

import '../data/database.dart';

/// 主题模式状态：从 settings 表加载/持久化，驱动 MaterialApp.themeMode。
class ThemeSettingsState extends ChangeNotifier {
  ThemeSettingsState(this._db);
  final AppDatabase _db;

  ThemeMode mode = ThemeMode.system;

  Future<void> load() async {
    final row = await (_db.select(_db.settings)
            ..where((t) => t.key.equals('themeMode')))
        .getSingleOrNull();
    mode = switch (row?.value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    mode = m;
    await _db.into(_db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(key: 'themeMode', value: m.name));
    notifyListeners();
  }
}
