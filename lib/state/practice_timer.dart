import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/database.dart';

/// 全局练习计时：start 后顶栏常驻计时，stop 自动写打卡记录；
/// 练习期间屏幕常亮（wakelock）。notifyListeners 在记录落库之后触发，
/// 监听方（个人中心）此时重查即可拿到最新统计。
class PracticeTimer extends ChangeNotifier {
  PracticeTimer(this._db);
  final AppDatabase _db;

  bool running = false;
  DateTime? startedAt;
  int elapsedSeconds = 0;
  Timer? _ticker;

  Future<void> start() async {
    running = true;
    startedAt = DateTime.now();
    elapsedSeconds = 0;
    await WakelockPlus.enable(); // 练习中屏幕常亮
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsedSeconds++;
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> stop({String? note}) async {
    _ticker?.cancel();
    _ticker = null;
    final start = startedAt;
    running = false;
    startedAt = null;
    await WakelockPlus.disable();
    if (start != null) {
      final end = DateTime.now();
      await _db.into(_db.practiceSessions).insert(
          PracticeSessionsCompanion.insert(
              startedAt: start,
              endedAt: end,
              durationSeconds: end.difference(start).inSeconds,
              note: Value(note)));
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
