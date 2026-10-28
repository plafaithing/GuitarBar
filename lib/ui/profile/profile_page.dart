import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/backup.dart';
import '../../data/database.dart';
import '../../state/theme_settings.dart';
import '../../ui/theme.dart';

/// 个人中心：主题外观设置 + 数据导出/导入；打卡统计为 Task 17 占位分区。
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeSettingsState>();
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('个人中心', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          // 设置分组（surface 面板）。
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: p.border),
            ),
            child: Column(
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
                const Divider(),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('数据',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: p.ink)),
                          const SizedBox(height: 2),
                          Text('练习记录与调弦预设导出为 JSON 备份',
                              style:
                                  TextStyle(fontSize: 12, color: p.muted)),
                        ]),
                  ),
                  OutlinedButton(
                      onPressed: () async {
                        final ok =
                            await exportToFile(context.read<AppDatabase>());
                        if (context.mounted && ok) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已导出')));
                        }
                      },
                      child: const Text('导出 JSON')),
                  const SizedBox(width: 8),
                  OutlinedButton(
                      onPressed: () => unawaited(_importData(context)),
                      child: const Text('导入 JSON')),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 打卡占位分区：Task 17 落地，不放假 UI。
          Text('练琴打卡',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w500, color: p.ink)),
          const SizedBox(height: 4),
          Text('练习计时与统计将在下个版本落地',
              style: TextStyle(fontSize: 12, color: p.muted)),
        ],
      ),
    );
  }

  /// 导入 JSON 备份：backup.dart 契约——失败会抛异常（事务整体回滚，
  /// 数据库保持原状），此处 catch 并向用户提示失败原因；取消选择静默返回。
  Future<void> _importData(BuildContext context) async {
    final db = context.read<AppDatabase>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await importFromFile(db);
      if (ok) {
        messenger.showSnackBar(const SnackBar(content: Text('导入完成')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }
}
