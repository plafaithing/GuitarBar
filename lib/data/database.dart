import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

class PracticeSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime()();
  IntColumn get durationSeconds => integer()();
  TextColumn get note => text().nullable()();
}

class TuningPresets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get notes => text()(); // "E2,A2,D3,G3,B3,E4"
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

class Scores extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  // 'image' | 'pdf' | 'gtp'（gpx/gp5）
  TextColumn get sourceType => text()();
  // 相对应用支持目录：scores/<id>/source.<ext>（原谱文件，永不改动）
  TextColumn get sourcePath => text()();
  // 识谱结果 IR JSON；null = 未识谱
  TextColumn get irJson => text().nullable()();
  // "E2,A2,D3,G3,B3,E4"；null = 未识谱
  TextColumn get tuning => text().nullable()();
  // 链接备注（2026-11-03 走查三件套）：教学/视频网址，详情页顶部栏可
  // 编辑、点击跳浏览器；null = 无备注。
  TextColumn get noteUrl => text().nullable()();
  // 回收站（2026-11-05 用户定案：删除先进回收站 30 天后自动清）：
  // 软删时间戳；null = 正常，非 null = 已进回收站。
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [PracticeSessions, TuningPresets, Settings, Scores])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          // v2 建表分支用当前（v4）schema 定义——已含全部新列，不能再
          // addColumn（duplicate column）；只有 v2+ 的旧库才逐级补列。
          if (from < 2) {
            await m.createTable(scores);
          } else {
            if (from < 3) await m.addColumn(scores, scores.noteUrl);
            if (from < 4) await m.addColumn(scores, scores.deletedAt);
          }
        },
      );
}

LazyDatabase openConnection() => LazyDatabase(() async {
      // 数据库位置（2026-11-03 AppData/Documents 不可写事故）：候选链
      // exe 旁 data（第一顺位）→ Documents\GuitarBar 兜底。旧 AppData 库
      // 存在则一次性迁入（保打卡+曲谱），旧文件保留作备份。
      final root = await resolveDataRoot();
      final file = File(p.join(root.path, 'guitarbar.sqlite'));
      return NativeDatabase(file, setup: (raw) {
        // 锁等待 5s：外部进程瞬锁先等待再失败。
        raw.execute('PRAGMA busy_timeout = 5000');
      });
    });

/// 数据根目录（2026-11-03 迁移）：候选 **exe 旁 data（第一顺位）** →
/// Documents\GuitarBar 兜底，写验证通过才采用；附一次性迁移旧 AppData
/// 数据库。曲谱文件根（scores/）也基于此（ScoreRepository 共用，保证
/// 同盘可写）。
Future<Directory> resolveDataRoot() async {
  // 历史位置（AppData\Roaming\com.guitarbar\guitarbar）。
  final legacyDir = await getApplicationSupportDirectory();
  final legacyFile = File(p.join(legacyDir.path, 'guitarbar.sqlite'));

  // 候选链（2026-11-03 用户定案：数据放应用自身目录，对齐 iOS 沙盒
  // 惯例——exe 旁 data 第一顺位，Documents 仅兜底）。
  final docs = await getApplicationDocumentsDirectory();
  final candidates = <Directory>[
    Directory(p.join(File(Platform.resolvedExecutable).parent.path, 'data')),
    Directory(p.join(docs.path, 'GuitarBar')),
  ];

  for (final dir in candidates) {
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File(p.join(dir.path, 'guitarbar.sqlite'));
      // 一次性迁移：候选位置无库而历史库存在（含打卡/曲谱）→ 复制。
      if (!file.existsSync() && legacyFile.existsSync()) {
        legacyFile.copySync(file.path);
      }
      // 写验证：该位置真的可写才采用。
      final probe = File(p.join(dir.path, '.write-probe'));
      probe.writeAsStringSync('x');
      probe.deleteSync();
      return dir;
    } catch (_) {
      continue; // 该位置不可写 → 下一候选
    }
  }
  // 兜底：全候选不可写——回历史位置（读至少可用，错误可见化会提示）。
  return legacyDir;
}
