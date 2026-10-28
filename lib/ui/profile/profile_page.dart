import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/stats.dart';
import '../../data/backup.dart';
import '../../data/database.dart';
import '../../state/practice_timer.dart';
import '../../state/theme_settings.dart';
import '../../ui/theme.dart';

/// 个人中心：练琴打卡（计时/统计/热力图/补卡）+ 外观与调试设置 + 数据导出/导入。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final PracticeTimer _timer;
  late final AppDatabase _db;
  final TextEditingController _minutesCtrl = TextEditingController();
  Future<List<PracticeSession>> _sessions = Future.value(const []);
  // 侦测 running true→false（stop 落库完成后）触发统计刷新。
  bool _wasRunning = false;

  @override
  void initState() {
    super.initState();
    _timer = context.read<PracticeTimer>();
    _db = context.read<AppDatabase>();
    _sessions = _loadSessions();
    _timer.addListener(_onTimerChanged);
  }

  @override
  void dispose() {
    _timer.removeListener(_onTimerChanged);
    _minutesCtrl.dispose();
    super.dispose();
  }

  void _onTimerChanged() {
    if (_wasRunning && !_timer.running) {
      // stop() 在打卡记录落库之后才 notifyListeners，此时重查即得最新统计。
      setState(() => _sessions = _loadSessions());
    }
    _wasRunning = _timer.running;
  }

  Future<List<PracticeSession>> _loadSessions() =>
      _db.select(_db.practiceSessions).get();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeSettingsState>();
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('个人中心', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _practicePanel(p),
            const SizedBox(height: 24),
            // 设置分组（surface 面板）。
            _panel(p, Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('外观',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: p.ink)),
                          const SizedBox(height: 2),
                          Text('跟随系统自动切换浅色/深色',
                              style:
                                  TextStyle(fontSize: 12, color: p.muted)),
                        ]),
                  ),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                          value: ThemeMode.system, label: Text('跟随系统')),
                      ButtonSegment(
                          value: ThemeMode.light, label: Text('浅色')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                    ],
                    selected: {theme.mode},
                    onSelectionChanged: (s) => theme.setMode(s.first),
                  ),
                ]),
                const Divider(),
                const SizedBox(height: 4),
                // 调试模式行（I2）：控制调音页诊断行显隐。
                Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('调试模式',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: p.ink)),
                          const SizedBox(height: 2),
                          Text('显示调音器性能诊断数据',
                              style:
                                  TextStyle(fontSize: 12, color: p.muted)),
                        ]),
                  ),
                  Switch(
                    value: theme.debugDiagnostics,
                    onChanged: (_) => theme.toggleDebugDiagnostics(),
                  ),
                ]),
              ],
            )),
            const SizedBox(height: 24),
            _dataPanel(p),
          ],
        ),
      ),
    );
  }

  // ---- 打卡区 ----

  Widget _practicePanel(GuitarBarPalette p) {
    return _panel(p, Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          // 主按钮：running 时展示实时计时（每秒随 Consumer 重建）。
          Consumer<PracticeTimer>(builder: (_, t, _) {
            return FilledButton.icon(
              onPressed: () => unawaited(t.running ? t.stop() : t.start()),
              icon: Icon(t.running ? Icons.stop : Icons.play_arrow),
              label: Text(t.running
                  ? '停止（${_mmss(t.elapsedSeconds)}）'
                  : '开始练习'),
            );
          }),
        ]),
        const SizedBox(height: 16),
        FutureBuilder<List<PracticeSession>>(
          future: _sessions,
          builder: (context, snap) {
            final rows = snap.data ?? const <PracticeSession>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _statBar(rows, p),
                const SizedBox(height: 16),
                Text('最近 12 周',
                    style: TextStyle(fontSize: 12, color: p.muted)),
                const SizedBox(height: 8),
                _heatmap(minutesPerDay(rows), p),
              ],
            );
          },
        ),
        const Divider(),
        const SizedBox(height: 4),
        Row(children: [
          SizedBox(
            width: 96,
            child: TextField(
              controller: _minutesCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: '分钟', isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _makeUpSession, child: const Text('手动补卡')),
        ]),
      ],
    ));
  }

  Widget _statBar(List<PracticeSession> rows, GuitarBarPalette p) {
    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    final monday = today0.subtract(Duration(days: today0.weekday - 1));
    final tomorrow = today0.add(const Duration(days: 1));
    final stats = [
      (
        '今日（分）',
        (totalSeconds(rows, today0, tomorrow) ~/ 60).toString()
      ),
      ('连续（天）', streakDays(practiceDays(rows), now).toString()),
      (
        '本周（分）',
        (totalSeconds(rows, monday, monday.add(const Duration(days: 7))) ~/ 60)
            .toString()
      ),
      (
        '30 天（时）',
        (totalSeconds(rows, today0.subtract(const Duration(days: 29)), tomorrow) /
                3600)
            .toStringAsFixed(1)
      ),
    ];
    return Row(
      children: [
        for (final (i, s) in stats.indexed) ...[
          if (i > 0) const Spacer(),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.$1, style: TextStyle(fontSize: 12, color: p.muted)),
            // KPI 数值：displaySmall = 30/400 + tabular figures（主题角色内置）。
            Text(s.$2, style: Theme.of(context).textTheme.displaySmall),
          ]),
        ],
      ],
    );
  }

  /// 热力图：最近 12 周（84 天），横向 GridView，7 行 = 周一…周日（列 = 周）。
  Widget _heatmap(Map<DateTime, int> minutes, GuitarBarPalette p) {
    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    final monday = today0.subtract(Duration(days: today0.weekday - 1));
    final start = monday.subtract(const Duration(days: 77)); // 12 周网格起点
    return SizedBox(
      height: 124, // 7 行 × 16px + 6 × 2px 间距
      child: GridView.count(
        scrollDirection: Axis.horizontal,
        crossAxisCount: 7,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        children: [
          for (var i = 0; i < 84; i++)
            Container(
              decoration: BoxDecoration(
                color: _heatColor(
                    minutes[start.add(Duration(days: i))] ?? 0,
                    p,
                    start.add(Duration(days: i)).isAfter(today0)),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }

  /// 色阶：0 → rule；<20 分 → dataHue@0.3；<45 分 → @0.6；≥45 分 → 全量。
  Color _heatColor(int min, GuitarBarPalette p, bool future) {
    if (future || min == 0) return p.rule;
    if (min < 20) return p.dataHue.withValues(alpha: 0.3);
    if (min < 45) return p.dataHue.withValues(alpha: 0.6);
    return p.dataHue;
  }

  /// 手动补卡：选日期（当日 20:00 起算）+ 面板内输入分钟数。
  Future<void> _makeUpSession() async {
    final minutes = int.tryParse(_minutesCtrl.text.trim());
    if (minutes == null || minutes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先输入有效的补卡分钟数')));
      return;
    }
    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    final date = await showDatePicker(
        context: context,
        initialDate: today0,
        firstDate: today0.subtract(const Duration(days: 365)),
        lastDate: today0);
    if (date == null || !mounted) return;
    final start = DateTime(date.year, date.month, date.day, 20);
    await _db.into(_db.practiceSessions).insert(
        PracticeSessionsCompanion.insert(
            startedAt: start,
            endedAt: start.add(Duration(minutes: minutes)),
            durationSeconds: minutes * 60));
    _minutesCtrl.clear();
    setState(() => _sessions = _loadSessions());
  }

  // ---- 数据分组 ----

  Widget _dataPanel(GuitarBarPalette p) {
    return _panel(p, Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('数据',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w500, color: p.ink)),
          const SizedBox(height: 2),
          Text('练习记录与调弦预设导出为 JSON 备份',
              style: TextStyle(fontSize: 12, color: p.muted)),
        ]),
      ),
      OutlinedButton(onPressed: _exportData, child: const Text('导出 JSON')),
      const SizedBox(width: 8),
      OutlinedButton(
          onPressed: () => unawaited(_importData()),
          child: const Text('导入 JSON')),
    ]));
  }

  Future<void> _exportData() async {
    final ok = await exportToFile(_db);
    if (mounted && ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已导出')));
    }
  }

  /// 导入 JSON 备份：backup.dart 契约——失败会抛异常（事务整体回滚，
  /// 数据库保持原状），此处 catch 并向用户提示失败原因；取消选择静默返回。
  Future<void> _importData() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await importFromFile(_db);
      if (ok) {
        messenger.showSnackBar(const SnackBar(content: Text('导入完成')));
        // 导入会替换练习记录，统计/热力图同步刷新。
        setState(() => _sessions = _loadSessions());
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  // ---- 公共 ----

  Widget _panel(GuitarBarPalette p, Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.border),
        ),
        child: child,
      );

  String _mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
