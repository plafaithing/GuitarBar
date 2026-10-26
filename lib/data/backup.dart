import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:file_selector/file_selector.dart';
import 'package:guitarbar/data/database.dart';

Future<Map<String, dynamic>> exportToJson(AppDatabase db) async {
  final sessions = await db.select(db.practiceSessions).get();
  final presets = await db.select(db.tuningPresets).get();
  final settings = await db.select(db.settings).get();
  return {
    'version': 1,
    'sessions': [
      for (final s in sessions)
        {
          'startedAt': s.startedAt.millisecondsSinceEpoch,
          'endedAt': s.endedAt.millisecondsSinceEpoch,
          'durationSeconds': s.durationSeconds,
          'note': s.note,
        }
    ],
    'presets': [
      for (final p in presets) {'name': p.name, 'notes': p.notes}
    ],
    'settings': {for (final s in settings) s.key: s.value},
  };
}

Future<void> importFromJson(AppDatabase db, Map<String, dynamic> json) async {
  await db.transaction(() async {
    await db.delete(db.practiceSessions).go();
    await db.delete(db.tuningPresets).go();
    await db.delete(db.settings).go();
    for (final s in (json['sessions'] as List).cast<Map>()) {
      await db.into(db.practiceSessions).insert(PracticeSessionsCompanion.insert(
          startedAt: DateTime.fromMillisecondsSinceEpoch(s['startedAt'] as int),
          endedAt: DateTime.fromMillisecondsSinceEpoch(s['endedAt'] as int),
          durationSeconds: s['durationSeconds'] as int,
          note: Value(s['note'] as String?)));
    }
    for (final p in (json['presets'] as List).cast<Map>()) {
      await db.into(db.tuningPresets).insert(
          TuningPresetsCompanion.insert(name: p['name'] as String, notes: p['notes'] as String));
    }
    for (final e in (json['settings'] as Map).entries) {
      await db.into(db.settings)
          .insertOnConflictUpdate(SettingsCompanion.insert(key: e.key as String, value: e.value as String));
    }
  });
}

/// UI 用：导出到用户选择的文件
Future<void> exportToFile(AppDatabase db) async {
  final json = await exportToJson(db);
  final location = await getSaveLocation(
      suggestedName: 'guitarbar-backup-${DateTime.now().millisecondsSinceEpoch}.json');
  if (location == null) return;
  final f = XFile.fromData(utf8.encode(jsonEncode(json)),
      mimeType: 'application/json');
  await f.saveTo(location.path);
}

/// UI 用：从用户选择的文件导入
Future<void> importFromFile(AppDatabase db) async {
  final f = await openFile(acceptedTypeGroups: const [
    XTypeGroup(label: 'JSON', extensions: ['json'])
  ]);
  if (f == null) return;
  await importFromJson(db, jsonDecode(await f.readAsString()) as Map<String, dynamic>);
}
