import '../data/database.dart';

/// 练习统计纯函数：打卡页与顶栏共用，无 UI 依赖（TDD，test/stats_test.dart）。

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// 有练习记录的自然日集合（按 startedAt 归到当天）。
Set<DateTime> practiceDays(List<PracticeSession> rows) =>
    {for (final r in rows) _day(r.startedAt)};

/// 连续练习天数：今天练了从今天倒数，今天没练从昨天倒数，断档即止。
int streakDays(Set<DateTime> days, DateTime today) {
  var d = _day(today);
  if (!days.contains(d)) d = d.subtract(const Duration(days: 1));
  var n = 0;
  while (days.contains(d)) {
    n++;
    d = d.subtract(const Duration(days: 1));
  }
  return n;
}

/// [from, to) 区间内总练习秒数。
int totalSeconds(List<PracticeSession> rows, DateTime from, DateTime to) =>
    rows
        .where((r) => !r.startedAt.isBefore(from) && r.startedAt.isBefore(to))
        .fold(0, (sum, r) => sum + r.durationSeconds);

/// 分钟按自然日聚合（不足一分钟截断）。
Map<DateTime, int> minutesPerDay(List<PracticeSession> rows) {
  final m = <DateTime, int>{};
  for (final r in rows) {
    final d = _day(r.startedAt);
    m[d] = (m[d] ?? 0) + r.durationSeconds ~/ 60;
  }
  return m;
}
