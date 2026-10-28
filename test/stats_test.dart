import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/stats.dart';
import 'package:guitarbar/data/database.dart';

PracticeSession row(DateTime start, int seconds) => PracticeSession(
    id: 1,
    startedAt: start,
    endedAt: start.add(Duration(seconds: seconds)),
    durationSeconds: seconds,
    note: null);

void main() {
  final now = DateTime(2026, 10, 25, 12); // 周日
  test('连续天数：今天有练', () {
    final days = practiceDays([
      row(DateTime(2026, 10, 24, 9), 600),
      row(DateTime(2026, 10, 25, 9), 600),
    ]);
    expect(streakDays(days, now), 2);
  });

  test('连续天数：今天没练从昨天起算', () {
    final days = practiceDays([
      row(DateTime(2026, 10, 23, 9), 600),
      row(DateTime(2026, 10, 24, 9), 600),
    ]);
    expect(streakDays(days, now), 2);
  });

  test('连续天数：中断归零', () {
    final days = practiceDays([row(DateTime(2026, 10, 20, 9), 600)]);
    expect(streakDays(days, now), 0);
  });

  test('区间总时长', () {
    final rows = [
      row(DateTime(2026, 10, 24, 9), 600),
      row(DateTime(2026, 10, 25, 9), 1200),
      row(DateTime(2026, 9, 25, 9), 999),
    ];
    expect(totalSeconds(rows, DateTime(2026, 10, 19), DateTime(2026, 10, 26)),
        1800);
  });

  test('分钟按天聚合', () {
    final m = minutesPerDay([
      row(DateTime(2026, 10, 25, 9), 600),
      row(DateTime(2026, 10, 25, 20), 1200),
    ]);
    expect(m[DateTime(2026, 10, 25)], 30);
  });
}
