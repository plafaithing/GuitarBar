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
  // 'image' | 'pdf'
  TextColumn get sourceType => text()();
  // 相对应用支持目录：scores/<id>/source.<ext>（原谱文件，永不改动）
  TextColumn get sourcePath => text()();
  // 识谱结果 IR JSON；null = 未识谱
  TextColumn get irJson => text().nullable()();
  // "E2,A2,D3,G3,B3,E4"；null = 未识谱
  TextColumn get tuning => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [PracticeSessions, TuningPresets, Settings, Scores])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(scores);
        },
      );
}

LazyDatabase openConnection() => LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'guitarbar.sqlite'));
      return NativeDatabase(file);
    });
