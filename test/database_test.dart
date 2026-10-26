import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/data/database.dart';

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
}
