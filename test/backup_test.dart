import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/data/backup.dart';
import 'package:guitarbar/data/database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('导出 → 清空 → 导入，数据一致', () async {
    await db.into(db.practiceSessions).insert(PracticeSessionsCompanion.insert(
        startedAt: DateTime(2026, 10, 25, 9),
        endedAt: DateTime(2026, 10, 25, 9, 30),
        durationSeconds: 1800,
        note: const Value('爬格子')));
    await db.into(db.tuningPresets).insert(
        TuningPresetsCompanion.insert(name: '我的调弦', notes: 'D2,A2,D3,G3,B3,E4'));
    await db.into(db.settings)
        .insertOnConflictUpdate(SettingsCompanion.insert(key: 'a4', value: '435'));

    final json = await exportToJson(db);
    await db.delete(db.practiceSessions).go();
    await db.delete(db.tuningPresets).go();
    await db.delete(db.settings).go();
    await importFromJson(db, json);

    final row = (await db.select(db.practiceSessions).get()).single;
    expect(row.note, '爬格子');
    expect(row.durationSeconds, 1800);
    expect(row.startedAt, DateTime(2026, 10, 25, 9));
    expect(row.endedAt, DateTime(2026, 10, 25, 9, 30));
    expect((await db.select(db.tuningPresets).get()).single.notes, 'D2,A2,D3,G3,B3,E4');
    expect((await db.select(db.settings).get()).single.value, '435');
  });
}
