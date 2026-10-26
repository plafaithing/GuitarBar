import 'package:flutter/foundation.dart';

import '../core/music/builtin_tunings.dart';
import '../core/music/note.dart';
import '../core/music/tuning.dart';
// drift 为 TuningPresets 表生成的数据类与 core/music/tuning.dart 的
// TuningPreset 重名，此处只需要领域模型，hide 掉生成类。
import '../data/database.dart' hide TuningPreset;

/// 调音器页状态：当前调弦、A4 参考音高、自定义预设，全部持久化到 settings 表。
class TuningState extends ChangeNotifier {
  TuningState(this._db);
  final AppDatabase _db;

  TuningPreset current = builtinTunings.first;
  double a4 = 440;
  List<TuningPreset> custom = [];

  Future<void> load() async {
    final a4Row = await (_db.select(_db.settings)..where((t) => t.key.equals('a4')))
        .getSingleOrNull();
    a4 = double.tryParse(a4Row?.value ?? '') ?? 440;
    final rows = await _db.select(_db.tuningPresets).get();
    // 逐行容错：单个脏行（非法音名）只跳过该行，不打断整个 load
    // （a4 有 tryParse 兜底，预设行同样不能让启动后预设区永久不可用）。
    final presets = <TuningPreset>[];
    for (final r in rows) {
      try {
        presets.add(TuningPreset(
            id: 'custom-${r.id}',
            name: r.name,
            strings: r.notes.split(',').map(Note.parse).toList(),
            group: TuningGroup.custom));
      } on ArgumentError {
        // 非法音名行：跳过。
      }
    }
    custom = presets;
    final cur = await (_db.select(_db.settings)
            ..where((t) => t.key.equals('currentTuning')))
        .getSingleOrNull();
    if (cur != null) {
      current = [...builtinTunings, ...custom]
          .firstWhere((t) => t.id == cur.value, orElse: () => current);
    }
    notifyListeners();
  }

  Future<void> select(TuningPreset t) async {
    current = t;
    await _save('currentTuning', t.id);
    notifyListeners();
  }

  Future<void> setA4(double v) async {
    a4 = v;
    await _save('a4', v.toString());
    notifyListeners();
  }

  Future<TuningPreset> addCustom(String name, List<String> notes) async {
    final id = await _db.into(_db.tuningPresets).insert(
        TuningPresetsCompanion.insert(name: name, notes: notes.join(',')));
    final t = TuningPreset(
        id: 'custom-$id',
        name: name,
        strings: notes.map(Note.parse).toList(),
        group: TuningGroup.custom);
    custom = [...custom, t];
    notifyListeners();
    return t;
  }

  Future<void> deleteCustom(TuningPreset t) async {
    final dbId = int.parse(t.id.substring('custom-'.length));
    await (_db.delete(_db.tuningPresets)..where((x) => x.id.equals(dbId))).go();
    custom = custom.where((x) => x.id != t.id).toList();
    if (current.id == t.id) current = builtinTunings.first;
    notifyListeners();
  }

  Future<void> _save(String k, String v) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: k, value: v));
}
