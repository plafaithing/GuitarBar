import 'package:flutter/material.dart';

import '../data/database.dart';

/// 主题模式状态：从 settings 表加载/持久化，驱动 MaterialApp.themeMode。
class ThemeSettingsState extends ChangeNotifier {
  ThemeSettingsState(this._db);
  final AppDatabase _db;

  ThemeMode mode = ThemeMode.system;

  /// 调试诊断显示开关（调音页诊断行默认隐藏，开关打开才显示）。
  bool debugDiagnostics = false;

  Future<void> load() async {
    final row = await (_db.select(_db.settings)
            ..where((t) => t.key.equals('themeMode')))
        .getSingleOrNull();
    mode = switch (row?.value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final dbg = await (_db.select(_db.settings)
            ..where((t) => t.key.equals('debugDiagnostics')))
        .getSingleOrNull();
    debugDiagnostics = dbg?.value == '1';
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    mode = m;
    await _db.into(_db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(key: 'themeMode', value: m.name));
    notifyListeners();
  }

  Future<void> toggleDebugDiagnostics() async {
    debugDiagnostics = !debugDiagnostics;
    await _db.into(_db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(
            key: 'debugDiagnostics', value: debugDiagnostics ? '1' : '0'));
    notifyListeners();
  }
}
