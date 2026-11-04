import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/data/database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

// 模拟 drift text 模式写入 local DateTime 的格式：ISO8601 + 时区偏移后缀
// （drift 读取时对带偏移的值按 parse(...).toLocal() 还原，见 drift mapping.dart）
String _isoLocal(DateTime d) {
  final off = d.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final h = off.inHours.abs().toString().padLeft(2, '0');
  final m = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
  return '${d.toIso8601String()}$sign$h:$m';
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('打卡增删改查', () async {
    final id = await db.into(db.practiceSessions).insert(PracticeSessionsCompanion.insert(
        startedAt: DateTime(2026, 10, 25, 9),
        endedAt: DateTime(2026, 10, 25, 9, 30),
        durationSeconds: 1800));
    final rows = await db.select(db.practiceSessions).get();
    expect(rows.single.id, id);
    expect(rows.single.durationSeconds, 1800);
    await (db.update(db.practiceSessions)..where((t) => t.id.equals(id)))
        .write(const PracticeSessionsCompanion(durationSeconds: Value(2400)));
    expect((await db.select(db.practiceSessions).get()).single.durationSeconds, 2400);
    await (db.delete(db.practiceSessions)..where((t) => t.id.equals(id))).go();
    expect(await db.select(db.practiceSessions).get(), isEmpty);
  });

  test('自定义调弦预设', () async {
    await db.into(db.tuningPresets).insert(
        TuningPresetsCompanion.insert(name: '我的调弦', notes: 'D2,A2,D3,G3,B3,E4'));
    final rows = await db.select(db.tuningPresets).get();
    expect(rows.single.name, '我的调弦');
    await (db.update(db.tuningPresets)..where((t) => t.id.equals(rows.single.id)))
        .write(TuningPresetsCompanion(name: const Value('改名')));
    expect((await db.select(db.tuningPresets).get()).single.name, '改名');
    await (db.delete(db.tuningPresets)..where((t) => t.id.equals(rows.single.id))).go();
    expect(await db.select(db.tuningPresets).get(), isEmpty);
  });

  test('设置 upsert', () async {
    await db.into(db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(key: 'a4', value: '440'));
    await db.into(db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(key: 'a4', value: '435'));
    final row = await (db.select(db.settings)..where((t) => t.key.equals('a4'))).getSingle();
    expect(row.value, '435');
  });

  // —— Scores 表（二期 M1）——
  test('scores 表：插入与默认值', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final id = await db.into(db.scores).insert(ScoresCompanion.insert(
        title: '测试曲', sourceType: 'image', sourcePath: 'scores/1/source.jpg'));
    final row = await (db.select(db.scores)..where((s) => s.id.equals(id)))
        .getSingle();
    expect(row.title, '测试曲');
    expect(row.sourceType, 'image');
    expect(row.sourcePath, 'scores/1/source.jpg');
    expect(row.irJson, isNull); // 未识谱
    expect(row.tuning, isNull);
    expect(row.createdAt, isNotNull);
    expect(row.updatedAt, isNotNull);
    await db.close();
  });

  // —— v1→v2 迁移（二期 M1 审查修复）——
  test('v1→v2 迁移：旧数据保留与新表创建', () async {
    // 手写 v1 fixture 库：datetime 列按项目 store_date_time_values_as_text: true
    // 以 TEXT（ISO8601 字符串）形态建列与写值
    final tempDir = await Directory.systemTemp.createTemp('guitarbar_mig_test');
    // tearDown 逆序执行：先关闭 drift 库（后注册），再删除临时目录（先注册）
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final fixturePath = p.join(tempDir.path, 'guitarbar.sqlite');
    final startedAt = DateTime(2026, 10, 25, 9);
    final endedAt = DateTime(2026, 10, 25, 9, 30);
    final presetCreatedAt = DateTime(2026, 1, 1);

    final raw = sqlite3.open(fixturePath);
    raw.execute('CREATE TABLE IF NOT EXISTS "practice_sessions" '
        '("id" INTEGER PRIMARY KEY AUTOINCREMENT, "started_at" TEXT NOT NULL, '
        '"ended_at" TEXT NOT NULL, "duration_seconds" INTEGER NOT NULL, "note" TEXT NULL)');
    raw.execute('CREATE TABLE IF NOT EXISTS "tuning_presets" '
        '("id" INTEGER PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL, '
        '"notes" TEXT NOT NULL, "created_at" TEXT NOT NULL)');
    raw.execute('CREATE TABLE IF NOT EXISTS "settings" '
        '("key" TEXT NOT NULL PRIMARY KEY, "value" TEXT NOT NULL)');
    raw.execute(
        'INSERT INTO practice_sessions (started_at, ended_at, duration_seconds, note) '
        'VALUES (?, ?, ?, ?)',
        [_isoLocal(startedAt), _isoLocal(endedAt), 1800, '第一次练习']);
    raw.execute('INSERT INTO tuning_presets (name, notes, created_at) VALUES (?, ?, ?)',
        ['标准调弦', 'E2,A2,D3,G3,B3,E4', _isoLocal(presetCreatedAt)]);
    raw.execute('INSERT INTO settings (key, value) VALUES (?, ?)', ['a4', '440']);
    raw.execute('PRAGMA user_version = 1');
    raw.close();

    final db = AppDatabase(NativeDatabase(File(fixturePath)));
    addTearDown(db.close);

    // ① 三张旧表数据完整可读
    final session = await db.select(db.practiceSessions).getSingle();
    expect(session.startedAt, startedAt);
    expect(session.endedAt, endedAt);
    expect(session.durationSeconds, 1800);
    expect(session.note, '第一次练习');
    final preset = await db.select(db.tuningPresets).getSingle();
    expect(preset.name, '标准调弦');
    expect(preset.notes, 'E2,A2,D3,G3,B3,E4');
    expect(preset.createdAt, presetCreatedAt);
    final setting = await db.select(db.settings).getSingle();
    expect(setting.key, 'a4');
    expect(setting.value, '440');

    // ② scores 表已由迁移创建
    expect(await db.select(db.scores).get(), isEmpty);

    // ③ 迁移后可写入 Score
    final scoreId = await db.into(db.scores).insert(ScoresCompanion.insert(
        title: '迁移后新曲', sourceType: 'image', sourcePath: 'scores/1/source.jpg'));
    final score =
        await (db.select(db.scores)..where((s) => s.id.equals(scoreId))).getSingle();
    expect(score.title, '迁移后新曲');
  });

  // —— v2→v3 迁移（2026-11-03 noteUrl 列；dsh 复测 P2-5：真实用户路径）——
  test('v2→v3 迁移：scores 行保留且 noteUrl 列可用', () async {
    final tempDir = await Directory.systemTemp.createTemp('guitarbar_mig_v3');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final fixturePath = p.join(tempDir.path, 'guitarbar.sqlite');
    // v2 形态 fixture：scores 表无 note_url 列（v2 用户库的真实结构）。
    final raw = sqlite3.open(fixturePath);
    raw.execute('CREATE TABLE "scores" '
        '("id" INTEGER PRIMARY KEY AUTOINCREMENT, "title" TEXT NOT NULL, '
        '"source_type" TEXT NOT NULL, "source_path" TEXT NOT NULL, '
        '"ir_json" TEXT NULL, "tuning" TEXT NULL, '
        '"created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL)');
    raw.execute(
        'INSERT INTO scores (title, source_type, source_path, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?)',
        ['旧曲', 'gtp', 'scores/1/source.gpx', _isoLocal(DateTime(2026, 11, 1)),
         _isoLocal(DateTime(2026, 11, 1))]);
    raw.execute('PRAGMA user_version = 2');
    raw.close();

    final db = AppDatabase(NativeDatabase(File(fixturePath)));
    addTearDown(db.close);

    // ① 旧行保留
    final row = await db.select(db.scores).getSingle();
    expect(row.title, '旧曲');
    expect(row.noteUrl, isNull); // 补列后默认 null
    // ② 新列可写（迁移目的）
    await (db.update(db.scores)..where((s) => s.id.equals(row.id)))
        .write(const ScoresCompanion(noteUrl: Value('https://example.com')));
    final after = await db.select(db.scores).getSingle();
    expect(after.noteUrl, 'https://example.com');
  });
}
