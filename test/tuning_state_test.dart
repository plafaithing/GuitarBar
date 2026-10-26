import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/data/database.dart';
import 'package:guitarbar/state/tuning_state.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('A4 持久化往返', () async {
    final s = TuningState(db);
    await s.setA4(435);
    final s2 = TuningState(db);
    await s2.load();
    expect(s2.a4, 435);
  });

  test('自定义预设增删 + 选中持久化', () async {
    final s = TuningState(db);
    await s.load();
    final t = await s.addCustom('我的调弦', ['D2', 'A2', 'D3', 'G3', 'B3', 'E4']);
    expect(s.custom.length, 1);
    await s.select(t);
    final s2 = TuningState(db);
    await s2.load();
    expect(s2.current.id, t.id);
    await s2.deleteCustom(t);
    expect(s2.custom, isEmpty);
    expect(s2.current.isBuiltIn, isTrue);
  });

  test('重名自定义预设允许（设计决定：不去重）', () async {
    final s = TuningState(db);
    await s.load();
    await s.addCustom('我的调弦', ['D2', 'A2', 'D3', 'G3', 'B3', 'E4']);
    await s.addCustom('我的调弦', ['C2', 'G2', 'C3', 'F3', 'A3', 'D4']);
    expect(s.custom.length, 2);
  });

  test('load 跳过非法音名行，不影响其他预设', () async {
    final s = TuningState(db);
    await s.load();
    await s.addCustom('好预设', ['D2', 'A2', 'D3', 'G3', 'B3', 'E4']);
    // 直接向 tuningPresets 表插坏行（模拟外部脏数据；坏行是 DB 行不是 settings）。
    await db.into(db.tuningPresets).insert(
        TuningPresetsCompanion.insert(name: '坏行', notes: 'X2,坏,数据'));
    final s2 = TuningState(db);
    await s2.load(); // 不抛
    expect(s2.custom.length, 1);
    expect(s2.custom.single.name, '好预设');
  });
}
