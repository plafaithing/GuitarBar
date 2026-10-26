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
}
