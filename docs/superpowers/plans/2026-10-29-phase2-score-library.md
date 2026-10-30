# GuitarBar 二期实现计划（M1-M4：曲谱库 → 识谱 → 谱面视图 → 自动演奏）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 图片/PDF 导入归档 → AI 识谱（模型无关）→ 六线谱视图（置信度+点选修正）→ 自动演奏可听。

**Architecture:** 三块边界——识谱管线（来源→IR）、曲谱库（存储/浏览/源文件仓库）、演奏端（只消费 IR 渲染 PCM）。IR 为全系统中心模型（设计文档 §4）。UI 全部从工具箱行进入，一期零改动。

**Tech Stack:** Flutter/Dart（既有栈 drift/flutter_soloud/file_selector）；新增 pdfrx ^2.5.0（PDF 查看与逐页转 PNG）、http（OpenAI 兼容 API）、image（图片规范化）。

**设计依据:** `docs/superpowers/specs/2026-10-29-phase2-score-library-design.md`（本文所有行为的唯一依据，冲突以设计文档为准）。

**既有代码关键接口（实现者必读）:**

- `SoundEngine.I`（`lib/audio/sound_engine.dart`）：`loadPcm(Int16List)→AudioSource`、`play(src,{loop})→SoundHandle`、`position(h)→Duration`、`stop(h)`、`disposeSource(src)`；采样率 44100 单声道。
- `pluck(freq,{sampleRate=44100,seconds=1.2})→Int16List`、`wrapWav`（`lib/audio/synth.dart`）。
- `Note.parse('E2')→Note`、`note.midi`、`note.frequency([a4])`（`lib/core/music/note.dart`）。
- drift：`lib/data/database.dart`，表类 + `@DriftDatabase`，行类自动生成（Scores 表 → 行类 `Score`）。
- 色板：`context.palette.*`（ground/panel/surface/border/ink/muted/dataHue/positive/negative 等），**禁止 Colors.\* 硬编码**；组件样式在主题层，页面零覆盖。
- 工具箱入口：`lib/ui/toolbox/toolbox_page.dart` 的 `tool(icon,title,subtitle,page)` 行式工厂。
- 全部代码注释用中文，风格对齐既有文件。

**运行环境注意:** Windows 构建前确认无僵尸进程（音频驱动级卡死需重启，见设计账本战役 1）；pdfrx 构建需要开发者模式（一期已开启）。

---

## 里程碑与任务总览

- **M1 曲谱库骨架**：Task 1-4（表/文件层/导入/列表页/纯查看器）
- **M2 识谱管线**：Task 5-11（IR/模型配置/API 客户端/校验/编排/接线）
- **M3 谱面视图**：Task 12-14（六线谱渲染/点选修正/详情页组装）
- **M4 自动演奏**：Task 15-16（PCM 渲染/播放接线——出口：播放可听）

---

### Task 1: Scores 表与 schema v2 迁移

**Files:**
- Modify: `lib/data/database.dart`
- Modify: `test/database_test.dart`

- [ ] **Step 1: 写失败测试**（在 `test/database_test.dart` 末尾追加，风格对齐文件内既有用例）

```dart
// —— Scores 表（二期 M1）——
test('scores 表：插入与默认值', () async {
  final db = AppDatabase(NativeDatabase.memory());
  final id = await db.into(db.scores).insert(ScoresCompanion.insert(
      title: '测试曲', sourceType: 'image', sourcePath: 'scores/1/source.jpg'));
  final row = await (db.select(db.scores)..where((s) => s.id.equals(id)))
      .getSingle();
  expect(row.title, '测试曲');
  expect(row.sourceType, 'image');
  expect(row.sourcePath, 'scores/1/source.jpg');
  expect(row.irJson, isNull); // 未识谱
  expect(row.tuning, isNull);
  await db.close();
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/database_test.dart`
Expected: FAIL（`scores` getter 不存在，编译错误）

- [ ] **Step 3: 实现表与迁移**（`lib/data/database.dart`：新增表类、注册、版本、迁移）

```dart
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
```

- [ ] **Step 4: 重新生成 drift 代码**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: 生成成功，无 error

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/database_test.dart`
Expected: PASS（含既有用例全绿）

- [ ] **Step 6: Commit**

```bash
git add lib/data/database.dart lib/data/database.g.dart test/database_test.dart
git commit -m "feat: scores 表与 schema v2 迁移（二期 M1）"
```

---

### Task 2: 文件层 ScoreFiles 与图片规范化

**Files:**
- Create: `lib/core/score/score_files.dart`
- Create: `lib/core/score/image_normalize.dart`
- Test: `test/score_files_test.dart`
- Modify: `pubspec.yaml`（加 `image: ^4.3.0`）

- [ ] **Step 1: 加依赖**

Run: `flutter pub add image:^4.3.0`
Expected: pubspec 更新、pub get 成功

- [ ] **Step 2: 写失败测试** `test/score_files_test.dart`

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_files.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('scorefiles'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('saveSourceImage 与 pagePngs 往返', () async {
    final files = ScoreFiles(tmp);
    final src = File('${tmp.path}/in.jpg')..writeAsBytesSync([1, 2, 3]);
    final saved = await files.saveSourceImage(5, src, 'jpg');
    expect(saved.path, endsWith('scores${Platform.pathSeparator}5${Platform.pathSeparator}source.jpg'));
    expect(saved.readAsBytesSync(), [1, 2, 3]);

    await files.savePagePngs(5, [
      Uint8List.fromList([9, 9]),
      Uint8List.fromList([8, 8]),
    ]);
    final pages = files.pagePngs(5);
    expect(pages.length, 2);
    expect(pages[0].path, contains('page-001.png'));
    expect(pages[1].path, contains('page-002.png'));

    await files.delete(5);
    expect(files.pagePngs(5), isEmpty);
    expect(File(saved.path).existsSync(), isFalse);
  });
}
```

注意文件顶部已含 `import 'dart:typed_data';`（Uint8List）。

- [ ] **Step 3: 跑测试确认失败**

Run: `flutter test test/score_files_test.dart`
Expected: FAIL（score_files.dart 不存在）

- [ ] **Step 4: 实现** `lib/core/score/score_files.dart`

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// 曲谱文件层：原谱文件 + 规范化页图都存在 <base>/<id>/ 下。
/// 原图 source.<ext> 永不改动；page-001.png 起为查看与识谱共用的页图。
class ScoreFiles {
  ScoreFiles(this.baseDir);
  final Directory baseDir;

  Directory dirFor(int id) => Directory(p.join(baseDir.path, '$id'));

  Future<File> saveSourceImage(int id, File src, String ext) async {
    final dir = dirFor(id);
    await dir.create(recursive: true);
    return src.copy(p.join(dir.path, 'source.$ext'));
  }

  Future<void> savePagePngs(int id, List<Uint8List> pngs) async {
    final dir = dirFor(id);
    await dir.create(recursive: true);
    for (var i = 0; i < pngs.length; i++) {
      await File(p.join(dir.path, 'page-${(i + 1).toString().padLeft(3, '0')}.png'))
          .writeAsBytes(pngs[i], flush: true);
    }
  }

  /// 页图列表（按页序）；无页图返回空。
  List<File> pagePngs(int id) {
    final dir = dirFor(id);
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('page-'))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  }

  File sourceFile(int id, String sourcePath) =>
      File(p.join(baseDir.path, sourcePath));

  Future<void> delete(int id) async {
    final dir = dirFor(id);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}
```

- [ ] **Step 5: 实现图片规范化** `lib/core/score/image_normalize.dart`

```dart
import 'dart:typed_data';

import 'package:image/image.dart' as imgpkg;

/// 图片规范化：长边 ≤ maxSide 等比缩到 PNG（识别输入与页图统一格式）。
/// 解码失败抛 FormatException。
Future<Uint8List> normalizeImage(Uint8List bytes, {int maxSide = 4096}) async {
  final decoded = imgpkg.decodeImage(bytes);
  if (decoded == null) throw const FormatException('无法解码图片');
  if (decoded.width <= maxSide && decoded.height <= maxSide) return bytes;
  final w = decoded.width >= decoded.height
      ? maxSide
      : (decoded.width * maxSide / decoded.height).round();
  final h = decoded.height > decoded.width
      ? maxSide
      : (decoded.height * maxSide / decoded.width).round();
  final resized = imgpkg.copyResize(decoded, width: w, height: h);
  return Uint8List.fromList(imgpkg.encodePng(resized));
}
```

- [ ] **Step 6: 规范化测试**（追加到 `test/score_files_test.dart`）

```dart
import 'package:guitarbar/core/score/image_normalize.dart';
import 'package:image/image.dart' as imgpkg;

test('normalizeImage：小图原样返回，大图缩到上限', () async {
  final small = Uint8List.fromList(
      imgpkg.encodePng(imgpkg.createImage(width: 100, height: 80)));
  expect((await normalizeImage(small)).length, small.length);

  final big = Uint8List.fromList(
      imgpkg.encodePng(imgpkg.createImage(width: 5000, height: 2500)));
  final out = await normalizeImage(big);
  final decoded = imgpkg.decodeImage(out)!;
  expect(decoded.width, 4096);
  expect(decoded.height, 2048);
});

test('normalizeImage：垃圾字节抛 FormatException', () async {
  expect(() => normalizeImage(Uint8List.fromList([1, 2, 3])),
      throwsFormatException);
});
```

- [ ] **Step 7: 跑测试确认通过**

Run: `flutter test test/score_files_test.dart`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add lib/core/score pubspec.yaml pubspec.lock test/score_files_test.dart
git commit -m "feat: 曲谱文件层与图片规范化（二期 M1）"
```

---

### Task 3: PDF 转图与 ScoreRepository 导入

**Files:**
- Create: `lib/core/score/pdf_raster.dart`
- Create: `lib/core/score/score_repository.dart`
- Modify: `pubspec.yaml`（加 `pdfrx: ^2.5.0`）
- Modify: `lib/main.dart`（pdfrx 引擎初始化）
- Test: `test/score_repository_test.dart`

- [ ] **Step 1: 加依赖与引擎初始化**

Run: `flutter pub add pdfrx:^2.5.0`

`lib/main.dart` 顶部加 `import 'package:pdfrx/pdfrx.dart';`，在 `WidgetsFlutterBinding.ensureInitialized();` 之后加：

```dart
  // pdfrx 引擎初始化：导入流程在无 pdfrx 组件参与时直接调引擎 API，需先初始化。
  pdfrxFlutterInitialize();
```

- [ ] **Step 2: 实现 PDF 转图** `lib/core/score/pdf_raster.dart`

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:pdfrx/pdfrx.dart';

/// PDF → 逐页 PNG（默认 200 DPI，白底）。
/// 注意：PdfPage.render 的参数以本机 pub cache 中 pdfrx_engine 实际签名为准
/// （%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\pdfrx_engine-*\lib\src\document.dart），
/// 版本差异只允许在此一处胶水调整。
class PdfRasterizer {
  const PdfRasterizer({this.dpi = 200});
  final double dpi;

  Future<List<Uint8List>> renderPages(File pdf) async {
    final doc = await PdfDocument.openFile(pdf.path);
    try {
      final scale = dpi / 72;
      final out = <Uint8List>[];
      for (final page in doc.pages) {
        final img = await page.render(
          x: 0,
          y: 0,
          width: page.width,
          height: page.height,
          fullWidth: page.width * scale,
          fullHeight: page.height * scale,
          format: PdfPageFormat.png,
          backgroundColor: const Color(0xFFFFFFFF), // 白底：扫描件透明区识别更稳
        );
        final bytes = img?.bytes;
        if (bytes == null || bytes.isEmpty) {
          throw StateError('PDF 第 ${page.pageNumber} 页渲染失败');
        }
        out.add(bytes);
      }
      return out;
    } finally {
      await doc.dispose();
    }
  }
}
```

- [ ] **Step 3: 写失败测试** `test/score_repository_test.dart`

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/pdf_raster.dart';
import 'package:guitarbar/core/score/score_files.dart';
import 'package:guitarbar/core/score/score_repository.dart';
import 'package:guitarbar/data/database.dart';

/// PdfRasterizer 的测试替身：固定返回两页假 PNG。
class FakeRasterizer implements PdfRasterizer {
  @override
  final double dpi = 200;
  @override
  Future<List<Uint8List>> renderPages(File pdf) async =>
      [Uint8List.fromList([1]), Uint8List.fromList([2])];
}

void main() {
  late Directory tmp;
  late AppDatabase db;
  late ScoreRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('scorerepo');
    db = AppDatabase(NativeDatabase.memory());
    repo = ScoreRepository(db, ScoreFiles(tmp), rasterizer: FakeRasterizer());
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('导入图片：落库 + 原图 + 单页图', () async {
    final img = File('${tmp.path}/a.png')
      ..writeAsBytesSync(Uint8List.fromList([7, 7, 7]));
    final row = await repo.importScore(title: '小星星', source: img);
    expect(row.sourceType, 'image');
    expect(row.irJson, isNull);
    expect(repo.files.pagePngs(row.id).length, 1);
    expect(repo.files.sourceFile(row.id, row.sourcePath).existsSync(), isTrue);
  });

  test('导入 PDF：两页页图', () async {
    final pdf = File('${tmp.path}/b.pdf')..writeAsBytesSync([1, 2, 3]);
    final row = await repo.importScore(title: '练习曲', source: pdf);
    expect(row.sourceType, 'pdf');
    expect(repo.files.pagePngs(row.id).length, 2);
  });

  test('listScores 按创建时间倒序、deleteScore 清库清文件', () async {
    final a = await repo.importScore(
        title: 'A', source: File('${tmp.path}/a.jpg')..writeAsBytesSync([1]));
    final b = await repo.importScore(
        title: 'B', source: File('${tmp.path}/b.jpg')..writeAsBytesSync([2]));
    final list = await repo.listScores();
    expect(list.map((e) => e.title), ['B', 'A']);
    await repo.deleteScore(a.id);
    expect(await repo.listScores().then((l) => l.map((e) => e.id)),
        isNot(contains(a.id)));
    expect(repo.files.pagePngs(a.id), isEmpty);
  });

  test('不支持的扩展名抛 ArgumentError', () async {
    final f = File('${tmp.path}/c.txt')..writeAsBytesSync([1]);
    expect(() => repo.importScore(title: 'x', source: f), throwsArgumentError);
  });
}
```

- [ ] **Step 4: 跑测试确认失败**

Run: `flutter test test/score_repository_test.dart`
Expected: FAIL（score_repository.dart 不存在）

- [ ] **Step 5: 实现** `lib/core/score/score_repository.dart`

```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../data/database.dart';
import 'image_normalize.dart';
import 'pdf_raster.dart';
import 'score_files.dart';

/// 曲谱库门面：DB 行 + 文件层的组合操作。UI 只经此访问曲谱。
class ScoreRepository {
  ScoreRepository(this._db, this.files, {PdfRasterizer? rasterizer})
      : rasterizer = rasterizer ?? const PdfRasterizer();

  final AppDatabase _db;
  final ScoreFiles files;
  final PdfRasterizer rasterizer;

  Future<List<Score>> listScores() =>
      (_db.select(_db.scores)
            ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
          .get();

  /// 导入：插行拿 id → 原图落盘 → 生成页图（PDF 逐页转 PNG / 图片规范化单页）。
  Future<Score> importScore({required String title, required File source}) async {
    final ext = p.extension(source.path).replaceFirst('.', '').toLowerCase();
    final isPdf = ext == 'pdf';
    const imageExts = ['png', 'jpg', 'jpeg', 'webp'];
    if (!isPdf && !imageExts.contains(ext)) {
      throw ArgumentError('不支持的曲谱文件类型: .$ext');
    }
    final id = await _db.into(_db.scores).insert(ScoresCompanion.insert(
        title: title, sourceType: isPdf ? 'pdf' : 'image', sourcePath: ''));
    try {
      final saved = await files.saveSourceImage(id, source, ext);
      final rel = 'scores/$id/${p.basename(saved.path)}';
      await (_db.update(_db.scores)..where((s) => s.id.equals(id)))
          .write(ScoresCompanion(sourcePath: Value(rel)));
      if (isPdf) {
        await files.savePagePngs(id, await rasterizer.renderPages(source));
      } else {
        await files.savePagePngs(
            id, [await normalizeImage(await source.readAsBytes())]);
      }
      return await (_db.select(_db.scores)..where((s) => s.id.equals(id)))
          .getSingle();
    } catch (_) {
      // 导入失败不留半成品行（文件层随 deleteScore 一并清）。
      await _db.delete(_db.scores).delete(id);
      rethrow;
    }
  }

  Future<void> deleteScore(int id) async {
    await (_db.delete(_db.scores)..where((s) => s.id.equals(id))).go();
    await files.delete(id);
  }

  /// 识谱结果回写（Task 11 用）。
  Future<void> updateRecognition(int id,
      {required String irJson, required String tuning}) async {
    await (_db.update(_db.scores)..where((s) => s.id.equals(id))).write(
        ScoresCompanion(
            irJson: Value(irJson),
            tuning: Value(tuning),
            updatedAt: Value(DateTime.now())));
  }

  /// 人工修正后回写 IR（Task 13 用）。
  Future<void> updateIrJson(int id, String irJson) async {
    await (_db.update(_db.scores)..where((s) => s.id.equals(id))).write(
        ScoresCompanion(
            irJson: Value(irJson), updatedAt: Value(DateTime.now())));
  }
}
```

注意：`select(_db.scores)` 在 drift 中即 `_db.select(...)`，实现时写成 `_db.select(...)` / `_db.update(...)` / `_db.delete(...)`（上面的 `select`/`update`/`delete` 裸调用若编译报错，统一改为 `_db.` 前缀）。

- [ ] **Step 6: 跑测试确认通过**

Run: `flutter test test/score_repository_test.dart test/score_files_test.dart test/database_test.dart`
Expected: PASS

- [ ] **Step 7: 真机导入走查（pdfrx 真渲染）**

Run: `flutter run -d windows`
手动：工具箱尚未有入口（Task 4 加）——临时验证方式：`flutter analyze` 通过即可，真渲染走查合并到 Task 4 的 Step（有入口后一起验）。

- [ ] **Step 8: Commit**

```bash
git add lib/core/score lib/main.dart pubspec.yaml pubspec.lock test/score_repository_test.dart
git commit -m "feat: PDF 转图与曲谱导入仓储（二期 M1）"
```

---

### Task 4: 曲谱库页 + 工具箱入口 + 纯查看器

> **执行修正备案（2026-10-29 质量审查实证）**：本任务 Step 1 的页面代码原稿缺
> Scaffold/Material 壳（MaterialPageRoute push 下列表态 ListTile 必崩、无返回键），
> 行结构 `Container(color) > ListTile` 触发 SDK 断言——实现时已按兄弟页同款
> Scaffold+AppBar+Material(color, shape) 行修复。后续任务勿照抄原稿壳结构。
> 另：SourceViewer 的 pageController 参数实现时省略（Task 14 确认不需要）；
> 详情页/列表页 `<support>/scores` 路径手写重复，Task 11 收口时抽共享构造。

**Files:**
- Create: `lib/ui/scores/scores_page.dart`
- Create: `lib/ui/scores/score_detail_page.dart`
- Create: `lib/ui/scores/source_viewer.dart`
- Modify: `lib/ui/toolbox/toolbox_page.dart`（加一行）
- Test: `test/scores_page_test.dart`

- [ ] **Step 1: 实现曲谱库列表页** `lib/ui/scores/scores_page.dart`

```dart
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../core/score/score_repository.dart';
import '../theme.dart';
import 'score_detail_page.dart';

/// 曲谱库：源文件仓库（导入即归档即查看），识谱/演奏是叠加增强。
class ScoresPage extends StatefulWidget {
  const ScoresPage({super.key, this.repoFactory});
  // widget 测试注入用；null = 走默认 path_provider 路径。
  final ScoreRepository Function()? repoFactory;

  @override
  State<ScoresPage> createState() => _ScoresPageState();
}

class _ScoresPageState extends State<ScoresPage> {
  ScoreRepository? _repo;
  List<Score>? _scores;

  @override
  void initState() {
    super.initState();
    _initRepo();
  }

  Future<void> _initRepo() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final repo = widget.repoFactory?.call() ??
          ScoreRepository(context.read<AppDatabase>(),
              ScoreFiles(Directory(p.join(dir.path, 'scores'))));
      if (!mounted) return;
      setState(() => _repo = repo);
      await _reload();
    } catch (_) {
      // 测试环境无 path_provider 插件：停在加载态。
    }
  }

  Future<void> _reload() async {
    final repo = _repo;
    if (repo == null) return;
    final list = await repo.listScores();
    if (mounted) setState(() => _scores = list);
  }

  Future<void> _import() async {
    final repo = _repo;
    if (repo == null) return;
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(
          label: '乐谱文件', extensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp']),
    ]);
    if (file == null || !mounted) return;
    final name = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final title = await _askTitle(name);
    if (title == null || title.trim().isEmpty || !mounted) return;
    try {
      await repo.importScore(title: title.trim(), source: File(file.path));
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入失败：$e')));
      }
    }
  }

  Future<String?> _askTitle(String initial) => showDialog<String>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController(text: initial);
          return AlertDialog(
            title: const Text('导入曲谱'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: '曲名'),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, ctrl.text),
                  child: const Text('导入')),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scores = _scores;
    final repo = _repo;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('曲谱库', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          FilledButton.icon(
              onPressed: repo == null ? null : _import,
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('导入')),
        ]),
        const SizedBox(height: 16),
        if (repo == null || scores == null)
          const Center(child: Padding(
              padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
        else if (scores.isEmpty)
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.library_music_outlined,
                    size: 48, color: p.muted),
                const SizedBox(height: 12),
                Text('还没有曲谱，点右上角导入图片或 PDF',
                    style: TextStyle(fontSize: 14, color: p.muted)),
              ]),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: scores.length,
              itemBuilder: (ctx, i) {
                final s = scores[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: p.panel,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: p.border),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    title: Text(s.title,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: p.ink)),
                    subtitle: Text(
                        '${s.sourceType == 'pdf' ? 'PDF' : '图片'} · ${repo.files.pagePngs(s.id).length} 页 · '
                        '${s.irJson == null ? '未识谱' : '已识谱'}',
                        style: TextStyle(fontSize: 12, color: p.muted)),
                    trailing: Icon(Icons.chevron_right,
                        size: 20, color: p.muted),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => ScoreDetailPage(scoreId: s.id))),
                  ),
                );
              },
            ),
          ),
      ]),
    );
  }
}
```

- [ ] **Step 2: ScoresPage 仓库初始化的最终形态**（path_provider 无同步接口——initState 里 fire-and-forget，与一期 root.dart `_loadCollapsed` 同款）

`_ScoresPageState` 字段与 initState：

```dart
  ScoreRepository? _repo;

  @override
  void initState() {
    super.initState();
    _initRepo();
  }

  Future<void> _initRepo() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final repo = ScoreRepository(
          context.read<AppDatabase>(),
          ScoreFiles(Directory(p.join(dir.path, 'scores'))));
      if (!mounted) return;
      setState(() => _repo = repo);
      await _reload();
    } catch (_) {
      // 测试环境无 path_provider 插件：停在加载态（widget 测试用可注入工厂绕开）。
    }
  }
```

需要 import：`package:path/path.dart' as p`、`package:path_provider/path_provider.dart`、`dart:io`。build 里 `_repo == null` 分支显示加载态；`_reload`/`_import` 前置判空 `_repo!`。**同时给 ScoresPage 加可注入工厂构造参数**（widget 测试用）：

```dart
class ScoresPage extends StatefulWidget {
  const ScoresPage({super.key, this.repoFactory});
  final ScoreRepository Function()? repoFactory;

// _initRepo 内：
      final repo = widget.repoFactory?.call() ??
          ScoreRepository(context.read<AppDatabase>(),
              ScoreFiles(Directory(p.join(dir.path, 'scores')))));
```

测试在 Step 6 传 `repoFactory: () => ScoreRepository(db, ScoreFiles(tempDir))`。

- [ ] **Step 3: 实现纯查看器** `lib/ui/scores/source_viewer.dart`

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';

/// 源文件纯查看器：逐页图片翻页 + 双指缩放。零编辑、零研究——就是查看器。
class SourceViewer extends StatefulWidget {
  const SourceViewer({super.key, required this.pagePngs, this.pageController});
  final List<File> pagePngs;
  final PageController? pageController;

  @override
  State<SourceViewer> createState() => _SourceViewerState();
}

class _SourceViewerState extends State<SourceViewer> {
  @override
  Widget build(BuildContext context) {
    if (widget.pagePngs.isEmpty) {
      return Center(
          child: Text('没有页图', style: TextStyle(color: context.palette.muted)));
    }
    return PageView.builder(
      controller: widget.pageController,
      itemCount: widget.pagePngs.length,
      itemBuilder: (ctx, i) => InteractiveViewer(
        maxScale: 6,
        child: Center(child: Image.file(widget.pagePngs[i], fit: BoxFit.contain)),
      ),
    );
  }
}
```

- [ ] **Step 4: 实现详情页骨架** `lib/ui/scores/score_detail_page.dart`

```dart
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../theme.dart';
import 'source_viewer.dart';

/// 曲谱详情：未识谱 = 纯查看器（一等使用方式）；谱面区后续任务填充。
/// 宽屏：谱面 + 原图并排；窄屏：原图（谱面 Tab 由 Task 14 加入）。
class ScoreDetailPage extends StatefulWidget {
  const ScoreDetailPage({super.key, required this.scoreId});
  final int scoreId;

  @override
  State<ScoreDetailPage> createState() => _ScoreDetailPageState();
}

class _ScoreDetailPageState extends State<ScoreDetailPage> {
  List<FileSystemEntity>? _pages;

  @override
  void initState() {
    super.initState();
    _loadPages();
  }

  Future<void> _loadPages() async {
    final dir = await getApplicationSupportDirectory();
    final files = Directory(p.join(dir.path, 'scores', '${widget.scoreId}'));
    if (!files.existsSync()) return;
    final pages = files.listSync().whereType<File>().toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    if (mounted) setState(() => _pages = pages);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pages = _pages
        ?.where((f) => p.basename(f.path).startsWith('page-'))
        .toList();
    return Scaffold(
      backgroundColor: p.ground,
      appBar: AppBar(title: const Text('曲谱')),
      body: pages == null
          ? const Center(child: CircularProgressIndicator())
          : SourceViewer(pagePngs: pages),
    );
  }
}
```

- [ ] **Step 5: 工具箱加行**（`lib/ui/toolbox/toolbox_page.dart`）

import 加：

```dart
import '../scores/scores_page.dart';
```

`Column` children 追加：

```dart
        tool(Icons.library_music_outlined, '曲谱库',
            '图片/PDF 归档 · AI 识谱 · 自动演奏', const ScoresPage()),
```

- [ ] **Step 6: 列表页空态 widget 测试** `test/scores_page_test.dart`

```dart
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_files.dart';
import 'package:guitarbar/core/score/score_repository.dart';
import 'package:guitarbar/data/database.dart';
import 'package:guitarbar/ui/scores/scores_page.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('空态显示导入引导', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final tmp = Directory.systemTemp.createTempSync('scorespage');
    addTearDown(() {
      tmp.deleteSync(recursive: true);
      db.close();
    });
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<AppDatabase>.value(value: db),
    ], child: MaterialApp(home: Scaffold(body: ScoresPage(
        repoFactory: () => ScoreRepository(db, ScoreFiles(tmp)))))));
    await tester.pumpAndSettle();
    expect(find.text('还没有曲谱，点右上角导入图片或 PDF'), findsOneWidget);
  });
}
```

（注入 repoFactory 绕开 path_provider；列表在注入后正常加载空库。）

- [ ] **Step 7: 跑测试与真机走查**

Run: `flutter test test/scores_page_test.dart && flutter analyze`
Expected: PASS / No issues

Run: `flutter run -d windows`
手动走查（M1 出口）：工具箱 → 曲谱库 → 导入一份 PDF（多页）→ 列表显示页数 → 进详情翻页、缩放 → 返回再导入一张图片 → 查看。**M1 出口标准达成：一份 PDF 从导入到可见。**

- [ ] **Step 8: Commit**

```bash
git add lib/ui/scores lib/ui/toolbox/toolbox_page.dart test/scores_page_test.dart
git commit -m "feat: 曲谱库列表/导入/纯查看器与工具箱入口（M1 收口）"
```

---

### Task 5: 统一曲谱 IR 模型

**Files:**
- Create: `lib/core/score/score_ir.dart`
- Test: `test/score_ir_test.dart`

- [ ] **Step 1: 写失败测试** `test/score_ir_test.dart`

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_ir.dart';

ScoreIr sample() => ScoreIr(
      version: 1,
      title: '小星星',
      tempo: 90,
      timeSignature: '4/4',
      tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
      capo: 0,
      tracks: [
        TrackIr(name: '主旋律', measures: [
          MeasureIr(index: 0, confidence: 0.92, failed: false, notes: [
            NoteIr(beat: 0, duration: 1, string: 1, fret: 3,
                technique: null, confidence: 0.95),
          ]),
          MeasureIr(index: 1, confidence: 0, failed: true, notes: const []),
        ]),
      ],
      unrecognizedPages: const [2],
    );

void main() {
  test('IR JSON 往返无损', () {
    final a = sample();
    final b = ScoreIr.fromJson(jsonDecode(jsonEncode(a.toJson())));
    expect(b, a);
  });

  test('failed 小节序列化保留 failed 与空 notes', () {
    final m = sample().tracks[0].measures[1];
    final back = MeasureIr.fromJson(jsonDecode(jsonEncode(m.toJson())));
    expect(back.failed, isTrue);
    expect(back.notes, isEmpty);
    expect(back.confidence, 0);
  });

  test('unrecognizedPages 往返', () {
    expect(sample().toJson()['unrecognizedPages'], [2]);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/score_ir_test.dart`
Expected: FAIL（score_ir.dart 不存在）

- [ ] **Step 3: 实现** `lib/core/score/score_ir.dart`

```dart
/// 统一曲谱 IR（设计文档 §4）：所有来源（AI 识谱/确定性导入/人工修正）归一于此。
/// JSON 形态与存储、视觉模型输出同构。
class ScoreIr {
  const ScoreIr({
    required this.version,
    required this.title,
    required this.tempo,
    required this.timeSignature,
    required this.tuning,
    required this.capo,
    required this.tracks,
    this.unrecognizedPages = const [],
  });

  final int version;
  final String title;
  final double tempo;
  final String timeSignature; // "4/4"
  // 低→高：index 0 = 6弦（E2）……index 5 = 1弦（E4）；与 Note.parse 对齐
  final List<String> tuning;
  final int capo;
  final List<TrackIr> tracks;
  // 识别失败的页号（0 起），可见化不静默丢
  final List<int> unrecognizedPages;

  Map<String, dynamic> toJson() => {
        'version': version,
        'title': title,
        'tempo': tempo,
        'timeSignature': timeSignature,
        'tuning': tuning,
        'capo': capo,
        'tracks': [for (final t in tracks) t.toJson()],
        'unrecognizedPages': unrecognizedPages,
      };

  static ScoreIr fromJson(Map<String, dynamic> j) => ScoreIr(
        version: (j['version'] as num?)?.toInt() ?? 1,
        title: j['title'] as String? ?? '未命名',
        tempo: (j['tempo'] as num?)?.toDouble() ?? 90,
        timeSignature: j['timeSignature'] as String? ?? '4/4',
        tuning: [
          if (j['tuning'] case final List l)
            for (final s in l) s as String
        ],
        capo: (j['capo'] as num?)?.toInt() ?? 0,
        tracks: [
          if (j['tracks'] case final List l)
            for (final t in l) TrackIr.fromJson(t as Map<String, dynamic>)
        ],
        unrecognizedPages: [
          if (j['unrecognizedPages'] case final List l)
            for (final n in l) (n as num).toInt()
        ],
      );

  @override
  bool operator ==(Object other) =>
      other is ScoreIr &&
      jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

class TrackIr {
  const TrackIr({required this.name, required this.measures});
  final String name;
  final List<MeasureIr> measures;

  Map<String, dynamic> toJson() =>
      {'name': name, 'measures': [for (final m in measures) m.toJson()]};

  static TrackIr fromJson(Map<String, dynamic> j) => TrackIr(
        name: j['name'] as String? ?? '主旋律',
        measures: [
          if (j['measures'] case final List l)
            for (final m in l) MeasureIr.fromJson(m as Map<String, dynamic>)
        ],
      );
}

class MeasureIr {
  const MeasureIr({
    required this.index,
    required this.confidence,
    required this.failed,
    required this.notes,
  });

  final int index; // 全曲连续小节号（0 起）
  final double confidence; // 0-1；0 表示不可用
  final bool failed; // true = 识别失败占位，notes 恒空
  final List<NoteIr> notes;

  Map<String, dynamic> toJson() => {
        'index': index,
        'confidence': confidence,
        'failed': failed,
        'notes': [for (final n in notes) n.toJson()],
      };

  static MeasureIr fromJson(Map<String, dynamic> j) => MeasureIr(
        index: (j['index'] as num?)?.toInt() ?? 0,
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
        failed: j['failed'] as bool? ?? false,
        notes: [
          if (j['notes'] case final List l)
            for (final n in l) NoteIr.fromJson(n as Map<String, dynamic>)
        ],
      );

  @override
  bool operator ==(Object other) =>
      other is MeasureIr &&
      jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

class NoteIr {
  const NoteIr({
    required this.beat,
    required this.duration,
    required this.string,
    required this.fret,
    required this.technique,
    this.confidence,
  });

  final double beat; // 小节内拍位置，0 起
  final double duration; // 单位拍
  final int string; // 1-6，1 = 最细高音弦
  final int fret; // 0-24，0 = 空弦
  final String? technique; // null | h | p | s | b | x
  final double? confidence; // null = 非 AI 来源

  Map<String, dynamic> toJson() => {
        'beat': beat,
        'duration': duration,
        'string': string,
        'fret': fret,
        'technique': technique,
        'confidence': confidence,
      };

  static NoteIr fromJson(Map<String, dynamic> j) => NoteIr(
        beat: (j['beat'] as num?)?.toDouble() ?? 0,
        duration: (j['duration'] as num?)?.toDouble() ?? 1,
        string: (j['string'] as num?)?.toInt() ?? 1,
        fret: (j['fret'] as num?)?.toInt() ?? 0,
        technique: j['technique'] as String?,
        confidence: (j['confidence'] as num?)?.toDouble(),
      );

  NoteIr copyWith({double? beat, double? duration, int? string, int? fret,
      String? technique, double? confidence}) =>
      NoteIr(
          beat: beat ?? this.beat,
          duration: duration ?? this.duration,
          string: string ?? this.string,
          fret: fret ?? this.fret,
          technique: technique ?? this.technique,
          confidence: confidence ?? this.confidence);

  @override
  bool operator ==(Object other) =>
      other is NoteIr &&
      jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/score_ir_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/score/score_ir.dart test/score_ir_test.dart
git commit -m "feat: 统一曲谱 IR 模型与 JSON 往返（二期 M2）"
```

---

### Task 6: 识谱模型配置存储 VisionModelStore

**Files:**
- Create: `lib/core/vision/vision_model.dart`
- Test: `test/vision_model_test.dart`

- [ ] **Step 1: 写失败测试** `test/vision_model_test.dart`

```dart
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/vision/vision_model.dart';
import 'package:guitarbar/data/database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('保存与读取往返', () async {
    final store = VisionModelStore(db);
    await store.saveAll([
      VisionModelConfig(
          id: 'a', name: '智谱', baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
          apiKey: 'k1', model: 'glm-4v-flash', active: true),
      VisionModelConfig(
          id: 'b', name: '自定义', baseUrl: 'https://x/v1',
          apiKey: 'k2', model: 'm2', active: false),
    ]);
    final loaded = await store.load();
    expect(loaded.length, 2);
    expect(loaded[0].name, '智谱');
    expect(loaded[0].active, isTrue);
  });

  test('多套 active 时保留首个', () async {
    final store = VisionModelStore(db);
    await store.saveAll([
      VisionModelConfig(id: 'a', name: 'A', baseUrl: 'u', apiKey: 'k',
          model: 'm', active: true),
      VisionModelConfig(id: 'b', name: 'B', baseUrl: 'u', apiKey: 'k',
          model: 'm', active: true),
    ]);
    final loaded = await store.load();
    expect(loaded.where((e) => e.active).map((e) => e.id), ['a']);
  });

  test('activeOf 取启用配置；空库存返回 null', () async {
    final store = VisionModelStore(db);
    expect(await store.activeOf(await store.load()), isNull);
  });

  test('JSON 行格式稳定（settings 表单 key）', () async {
    final store = VisionModelStore(db);
    await store.saveAll([VisionModelConfig(
        id: 'a', name: 'N', baseUrl: 'u', apiKey: 'k', model: 'm',
        active: true)]);
    final raw = await (db.select(db.settings)
            ..where((t) => t.key.equals(VisionModelStore.settingsKey)))
        .getSingle();
    final decoded = jsonDecode(raw.value) as List;
    expect(decoded.first['model'], 'm');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/vision_model_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现** `lib/core/vision/vision_model.dart`

```dart
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../data/database.dart';

/// 一套识谱模型配置（OpenAI 兼容协议）。厂商只作为预置模板出现，
/// 架构不绑定任何厂商（设计文档 §5.2）。
class VisionModelConfig {
  const VisionModelConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.active,
  });

  final String id; // UUID 或时间戳字符串
  final String name; // 显示名
  final String baseUrl; // 如 https://open.bigmodel.cn/api/paas/v4
  final String apiKey;
  final String model; // 如 glm-4v-flash
  final bool active; // 单套启用

  VisionModelConfig copyWith({String? name, String? baseUrl, String? apiKey,
          String? model, bool? active}) =>
      VisionModelConfig(
          id: id,
          name: name ?? this.name,
          baseUrl: baseUrl ?? this.baseUrl,
          apiKey: apiKey ?? this.apiKey,
          model: model ?? this.model,
          active: active ?? this.active);

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'baseUrl': baseUrl,
        'apiKey': apiKey, 'model': model, 'active': active,
      };

  static VisionModelConfig fromJson(Map<String, dynamic> j) =>
      VisionModelConfig(
          id: j['id'] as String,
          name: j['name'] as String? ?? '',
          baseUrl: j['baseUrl'] as String? ?? '',
          apiKey: j['apiKey'] as String? ?? '',
          model: j['model'] as String? ?? '',
          active: j['active'] as bool? ?? false);
}

/// settings 表持久化（key = visionModels，JSON 数组）。active 唯一性在此收口。
class VisionModelStore {
  VisionModelStore(this._db);
  static const settingsKey = 'visionModels';

  final AppDatabase _db;

  /// 智谱预置模板（新配置页一键预填）。
  static VisionModelConfig zhipuTemplate() => VisionModelConfig(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: '智谱 GLM',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      apiKey: '',
      model: 'glm-4v-flash',
      active: false);

  Future<List<VisionModelConfig>> load() async {
    final row = await (_db.select(_db.settings)
            ..where((t) => t.key.equals(settingsKey)))
        .getSingleOrNull();
    if (row == null) return const [];
    try {
      final list = jsonDecode(row.value) as List;
      return [
        for (final e in list) VisionModelConfig.fromJson(e as Map<String, dynamic>)
      ];
    } catch (_) {
      return const []; // 坏数据按空处理，页面可重建
    }
  }

  Future<void> saveAll(List<VisionModelConfig> configs) async {
    // active 唯一：保留首个 active，其余强置 false。
    var seenActive = false;
    final normalized = [
      for (final c in configs)
        c.active && !seenActive
            ? (seenActive = true, c).$2
            : (c.active ? c.copyWith(active: false) : c)
    ];
    await _db.into(_db.settings).insertOnConflictUpdate(SettingsCompanion.insert(
        key: settingsKey,
        value: jsonEncode([for (final c in normalized) c.toJson()])));
  }

  Future<VisionModelConfig?> activeOf(List<VisionModelConfig> configs) async =>
      configs.where((c) => c.active).firstOrNull;
}
```

注意：`(seenActive = true, c).$2` 写法可读性差，改为普通循环构建 normalized 列表。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/vision_model_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/vision/vision_model.dart test/vision_model_test.dart
git commit -m "feat: 识谱模型配置存储（多套配置单套启用，二期 M2）"
```

---

### Task 7: VisionClient（OpenAI 兼容 vision 请求）

> **执行修正备案（2026-10-29 质量审查）**：本任务原稿缺请求超时（挂起即死锁，实现已加
> 可注入 timeout 默认 120s）、`res.body` latin1 乱码（已改 utf8.decode(bodyBytes)）、
> HTTP 错误体未截断（已截 200 字符）。后续引用本任务代码时以实现终态为准。

**Files:**
- Create: `lib/core/vision/vision_client.dart`
- Modify: `pubspec.yaml`（加 `http: ^1.2.0`）
- Test: `test/vision_client_test.dart`

- [ ] **Step 1: 加依赖**

Run: `flutter pub add http:^1.2.0`

- [ ] **Step 2: 写失败测试** `test/vision_client_test.dart`

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/vision/vision_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const cfg = (
    baseUrl: 'https://api.example.com/v4/',
    apiKey: 'sk-test',
    model: 'glm-4v-flash',
  );

  test('成功：取 choices[0].message.content；请求体含 data URI 图', () async {
    http.Request? captured;
    final client = MockClient((req) async {
      captured = req as http.Request;
      return http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': '{"measures": []}'}}
            ]
          }),
          200);
    });
    final c = VisionClient(client: client);
    final out = await c.complete(
        baseUrl: cfg.baseUrl, apiKey: cfg.apiKey, model: cfg.model,
        prompt: 'p', png: Uint8List.fromList([1, 2, 3]));
    expect(out, '{"measures": []}');
    final body = jsonDecode(captured!.body);
    expect(captured!.url.toString(), 'https://api.example.com/v4/chat/completions');
    expect(captured!.headers['Authorization'], 'Bearer sk-test');
    final content = body['messages'][0]['content'] as List;
    expect(content[1]['image_url']['url'], startsWith('data:image/png;base64,'));
  });

  test('HTTP 401 → VisionException', () async {
    final c = VisionClient(
        client: MockClient((req) async => http.Response('denied', 401)));
    expect(
        () => c.complete(baseUrl: cfg.baseUrl, apiKey: cfg.apiKey,
            model: cfg.model, prompt: 'p',
            png: Uint8List.fromList([1])),
        throwsA(isA<VisionException>()));
  });

  test('响应缺 content → VisionException', () async {
    final c = VisionClient(
        client: MockClient((req) async =>
            http.Response(jsonEncode({'choices': []}), 200)));
    expect(
        () => c.complete(baseUrl: cfg.baseUrl, apiKey: cfg.apiKey,
            model: cfg.model, prompt: 'p',
            png: Uint8List.fromList([1])),
        throwsA(isA<VisionException>()));
  });
}
```

- [ ] **Step 3: 跑测试确认失败**

Run: `flutter test test/vision_client_test.dart`
Expected: FAIL

- [ ] **Step 4: 实现** `lib/core/vision/vision_client.dart`

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// OpenAI 兼容 chat-completions 视觉请求（设计文档 §5.2）。
/// 一个协议覆盖智谱/OpenAI/DeepSeek/硅基流动/Ollama 等，不绑定厂商。
class VisionException implements Exception {
  const VisionException(this.message);
  final String message;
  @override
  String toString() => message;
}

class VisionClient {
  VisionClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<String> complete({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    required Uint8List png,
    String mime = 'image/png',
  }) async {
    final b = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final uri = Uri.parse('$b/chat/completions');
    final body = jsonEncode({
      'model': model,
      'temperature': 0.1,
      'max_tokens': 8192,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:$mime;base64,${base64Encode(png)}'}
            },
          ],
        },
      ],
    });
    final http.Response res;
    try {
      res = await _client.post(uri,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: body);
    } catch (e) {
      throw VisionException('网络请求失败：$e');
    }
    if (res.statusCode != 200) {
      throw VisionException('HTTP ${res.statusCode}：${res.body}');
    }
    final data = jsonDecode(res.body);
    final content =
        (data['choices'] as List?)?.firstOrNull?['message']?['content'];
    if (content is! String || content.isEmpty) {
      throw const VisionException('响应缺少 content');
    }
    return content;
  }
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/vision_client_test.dart && flutter analyze`
Expected: PASS / No issues

- [ ] **Step 6: Commit**

```bash
git add lib/core/vision/vision_client.dart pubspec.yaml pubspec.lock test/vision_client_test.dart
git commit -m "feat: OpenAI 兼容视觉 API 客户端（二期 M2）"
```

---

### Task 8: 模型配置页 UI

**Files:**
- Create: `lib/ui/profile/vision_models_page.dart`
- Modify: `lib/ui/profile/profile_page.dart`（设置面板加一行入口）
- Test: `test/vision_models_page_test.dart`

- [ ] **Step 1: 实现配置页** `lib/ui/profile/vision_models_page.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/vision/vision_client.dart';
import '../../core/vision/vision_model.dart';
import '../../data/database.dart';
import '../theme.dart';

/// 识谱模型配置：卡片列表，可增删改、单选启用、测试连接。
/// key 本地存储不上传（设计文档 §8）。
class VisionModelsPage extends StatefulWidget {
  const VisionModelsPage({super.key});

  @override
  State<VisionModelsPage> createState() => _VisionModelsPageState();
}

class _VisionModelsPageState extends State<VisionModelsPage> {
  late final VisionModelStore _store;
  List<VisionModelConfig>? _configs;

  @override
  void initState() {
    super.initState();
    _store = VisionModelStore(context.read<AppDatabase>());
    _reload();
  }

  Future<void> _reload() async {
    final list = await _store.load();
    if (mounted) setState(() => _configs = list);
  }

  Future<void> _persist(List<VisionModelConfig> list) async {
    await _store.saveAll(list);
    await _reload();
  }

  Future<void> _edit(VisionModelConfig? existing) async {
    final initial =
        existing ?? VisionModelStore.zhipuTemplate().copyWith(name: existing?.name ?? '智谱 GLM');
    final result = await showDialog<VisionModelConfig>(
      context: context,
      builder: (ctx) => _ConfigDialog(config: initial),
    );
    if (result == null || !mounted) return;
    final list = [...?_configs];
    if (existing == null) {
      list.add(result);
    } else {
      list[list.indexWhere((c) => c.id == existing.id)] = result;
    }
    await _persist(list);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final configs = _configs;
    return Scaffold(
      backgroundColor: p.ground,
      appBar: AppBar(title: const Text('识谱模型')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(null),
        child: const Icon(Icons.add),
      ),
      body: configs == null
          ? const Center(child: CircularProgressIndicator())
          : configs.isEmpty
              ? Center(child: Text('还没有配置，点 + 新建（内置智谱模板）',
                  style: TextStyle(color: p.muted)))
              : ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: configs.length,
                  itemBuilder: (ctx, i) {
                    final c = configs[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: p.panel,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: c.active ? p.dataHue : p.border),
                      ),
                      child: ListTile(
                        title: Text('${c.name} · ${c.model}',
                            style: TextStyle(fontSize: 16, color: p.ink)),
                        subtitle: Text(c.baseUrl,
                            style: TextStyle(fontSize: 12, color: p.muted)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              tooltip: '测试连接',
                              icon: Icon(Icons.network_check,
                                  size: 20, color: p.muted),
                              onPressed: () => _testConnection(c)),
                          IconButton(
                              tooltip: '编辑',
                              icon: Icon(Icons.edit_outlined,
                                  size: 20, color: p.muted),
                              onPressed: () => _edit(c)),
                          IconButton(
                              tooltip: '删除',
                              icon: Icon(Icons.delete_outline,
                                  size: 20, color: p.muted),
                              onPressed: () async {
                                final list = [...configs]..removeAt(i);
                                await _persist(list);
                              }),
                        ]),
                        onTap: () async {
                          // 点卡片 = 启用该套。
                          await _persist([
                            for (final x in configs)
                              x.copyWith(active: x.id == c.id)
                          ]);
                        },
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _testConnection(VisionModelConfig c) async {
    final messenger = ScaffoldMessenger.of(context);
    // 1×1 白 PNG，验证连通与返回格式，不花识别级 token。
    const png = [
      137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1,
      0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84,
      120, 156, 99, 250, 207, 192, 80, 15, 0, 4, 133, 2, 89, 137, 77, 217, 0,
      0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
    ];
    try {
      await VisionClient().complete(
          baseUrl: c.baseUrl, apiKey: c.apiKey, model: c.model,
          prompt: 'ping', png: Uint8List.fromList(png));
      messenger.showSnackBar(const SnackBar(content: Text('连接成功')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('失败：$e')));
    }
  }
}

class _ConfigDialog extends StatefulWidget {
  const _ConfigDialog({required this.config});
  final VisionModelConfig config;

  @override
  State<_ConfigDialog> createState() => _ConfigDialogState();
}

class _ConfigDialogState extends State<_ConfigDialog> {
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.config.name);
    _baseUrl = TextEditingController(text: widget.config.baseUrl);
    _apiKey = TextEditingController(text: widget.config.apiKey);
    _model = TextEditingController(text: widget.config.model);
  }

  @override
  void dispose() {
    _name.dispose(); _baseUrl.dispose(); _apiKey.dispose(); _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('模型配置'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _name,
              decoration: const InputDecoration(labelText: '名称')),
          TextField(controller: _baseUrl,
              decoration: const InputDecoration(
                  labelText: 'API 地址（OpenAI 兼容，不含 /chat/completions）')),
          TextField(controller: _apiKey,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'API Key')),
          TextField(controller: _model,
              decoration: const InputDecoration(labelText: '模型名（如 glm-4v-flash）')),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        ListenableBuilder(
          listenable: Listenable.merge(
              [_name, _baseUrl, _apiKey, _model]),
          builder: (ctx, _) => FilledButton(
              onPressed: _baseUrl.text.trim().isEmpty ||
                      _model.text.trim().isEmpty ||
                      _apiKey.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      widget.config.copyWith(
                          name: _name.text.trim(),
                          baseUrl: _baseUrl.text.trim(),
                          apiKey: _apiKey.text.trim(),
                          model: _model.text.trim())),
              child: const Text('保存')),
        ),
      ],
    );
  }
}
```

实现纪律：① `_edit` 里模板一行写成 `existing ?? VisionModelStore.zhipuTemplate()`；② 保存按钮要求 baseUrl/key/model 三项非空（ListenableBuilder 监听四个控制器动态禁用），不给默认值兜底——空配置宁可禁用保存。

- [ ] **Step 2: 个人中心加入口**（`lib/ui/profile/profile_page.dart` 设置面板"调试模式"行后追加）

```dart
                const Divider(),
                const SizedBox(height: 4),
                // 识谱模型配置入口（二期 M2）。
                InkWell(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const VisionModelsPage())),
                  child: SizedBox(
                    height: 48,
                    child: Row(children: [
                      Expanded(child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('识谱模型',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: p.ink)),
                            Text('AI 识谱 API 配置（OpenAI 兼容）',
                                style: TextStyle(fontSize: 12, color: p.muted)),
                          ])),
                      Icon(Icons.chevron_right, size: 20, color: p.muted),
                    ]),
                  ),
                ),
```

顶部 import 加 `import 'vision_models_page.dart';`。

- [ ] **Step 3: 页面冒烟 widget 测试** `test/vision_models_page_test.dart`

```dart
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/vision/vision_model.dart';
import 'package:guitarbar/data/database.dart';
import 'package:guitarbar/ui/profile/vision_models_page.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('空态提示新建', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<AppDatabase>.value(value: db),
    ], child: const MaterialApp(home: VisionModelsPage())));
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有配置'), findsOneWidget);
    await db.close();
  });

  testWidgets('已有配置显示卡片并可点选启用', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final store = VisionModelStore(db);
    await store.saveAll([VisionModelConfig(
        id: 'a', name: '智谱', baseUrl: 'https://u', apiKey: 'k',
        model: 'glm-4v-flash', active: false)]);
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<AppDatabase>.value(value: db),
    ], child: const MaterialApp(home: VisionModelsPage())));
    await tester.pumpAndSettle();
    expect(find.textContaining('智谱'), findsWidgets);
    await tester.tap(find.textContaining('智谱').first);
    await tester.pumpAndSettle();
    final raw = await (db.select(db.settings)
            ..where((t) => t.key.equals(VisionModelStore.settingsKey)))
        .getSingle();
    expect((jsonDecode(raw.value) as List).first['active'], isTrue);
    await db.close();
  });
}
```

- [ ] **Step 4: 跑测试**

Run: `flutter test test/vision_models_page_test.dart && flutter analyze`
Expected: PASS / No issues

- [ ] **Step 5: Commit**

```bash
git add lib/ui/profile pubspec.lock test/vision_models_page_test.dart
git commit -m "feat: 识谱模型配置页（增删改/启用/测试连接，二期 M2）"
```

---

### Task 9: 识谱 Prompt 与响应机器校验

**Files:**
- Create: `lib/core/vision/tab_prompt.dart`
- Create: `lib/core/vision/score_validator.dart`
- Test: `test/score_validator_test.dart`

- [ ] **Step 1: 实现 Prompt** `lib/core/vision/tab_prompt.dart`

```dart
/// 识谱系统提示（设计文档 §5.2/§5.4）：v1 硬指标 = 音符+节奏；技法 best-effort。
const tabSystemPrompt =
    '你是乐谱数字化引擎。输入是一页吉他谱图片（六线谱、标准五线谱或两者对照）。'
    '把本页全部音乐内容转为 JSON，严格遵守：'
    '1.只输出 JSON，不要解释、不要 Markdown 代码围栏。'
    '2.结构 {"measures":[{"index":<本页内序号,从0起>,"confidence":<0到1小数>,'
    '"notes":[{"beat":<小节内拍位置,从0起>,"duration":<时值,单位拍>,'
    '"string":<1到6,1=最细高音弦>,"fret":<0到24,0=空弦>,'
    '"technique":null或"h","p","s","b","x"之一}]}]}。'
    '3.六线谱直接读弦与品；五线谱按给定调弦就近映射到弦与品。'
    '4.无法确定的音宁可整小节给低 confidence，也不要猜测编造。'
    '5.拍弦、密集和弦、复杂连音区 confidence 给低于 0.6。'
    '6.反复记号只记一遍内容；歌词、和弦名、指法标注一律忽略。';

String tabUserPrompt({
  required List<String> tuning,
  required String timeSignature,
  required int page,
  required int total,
}) =>
    '调弦（从6弦到1弦，低到高）：${tuning.reversed.join(', ')}。'
    '拍号：$timeSignature（每小节 ${timeSignature.split('/')[0]} 拍）。'
    '本页为第 ${page + 1}/$total 页。';
```

- [ ] **Step 2: 写失败测试** `test/score_validator_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/core/vision/score_validator.dart';

void main() {
  test('干净 JSON 直接解析', () {
    final r = parsePage(
        '{"measures":[{"index":0,"confidence":0.9,"notes":'
        '[{"beat":0,"duration":1,"string":1,"fret":3,"technique":null}]}]}',
        indexOffset: 5);
    expect(r.measures.single.index, 5);
    expect(r.measures.single.notes.single.fret, 3);
    expect(r.failedCount, 0);
  });

  test('剥 Markdown 围栏', () {
    final r = parsePage('```json\n{"measures":[{"index":0,"confidence":0.8,'
        '"notes":[]}]}\n```', indexOffset: 0);
    expect(r.measures.length, 1);
  });

  test('越界音符 → 整小节 failed（不静默丢）', () {
    final r = parsePage(
        '{"measures":[{"index":0,"confidence":0.9,"notes":'
        '[{"beat":0,"duration":1,"string":9,"fret":3,"technique":null}]}]}',
        indexOffset: 0);
    expect(r.measures.single.failed, isTrue);
    expect(r.measures.single.notes, isEmpty);
    expect(r.failedCount, 1);
  });

  test('technique 白名单外的值 → failed', () {
    final r = parsePage(
        '{"measures":[{"index":0,"confidence":0.9,"notes":'
        '[{"beat":0,"duration":1,"string":1,"fret":0,"technique":"zz"}]}]}',
        indexOffset: 0);
    expect(r.measures.single.failed, isTrue);
  });

  test('bad duration（<=0）→ failed', () {
    final r = parsePage(
        '{"measures":[{"index":0,"confidence":0.9,"notes":'
        '[{"beat":0,"duration":0,"string":1,"fret":0,"technique":null}]}]}',
        indexOffset: 0);
    expect(r.measures.single.failed, isTrue);
  });

  test('confidence 缺省 0.5，越界夹到 [0,1]', () {
    final r = parsePage(
        '{"measures":[{"notes":[{"beat":0,"duration":1,"string":1,'
        '"fret":0,"technique":null,"confidence":3}]}]}',
        indexOffset: 0);
    expect(r.measures.single.confidence, 1.0);
    expect(r.measures.single.notes.single.confidence, 1.0);
  });

  test('index 按数组位置重编（不信 AI 的编号）', () {
    final r = parsePage(
        '{"measures":[{"index":99,"confidence":0.9,"notes":[]},'
        '{"index":42,"confidence":0.9,"notes":[]}]}',
        indexOffset: 10);
    expect(r.measures.map((m) => m.index), [10, 11]);
  });

  test('完全没有 JSON → FormatException（页级失败）', () {
    expect(() => parsePage('我不知道', indexOffset: 0), throwsFormatException);
  });
}
```

- [ ] **Step 3: 跑测试确认失败**

Run: `flutter test test/score_validator_test.dart`
Expected: FAIL

- [ ] **Step 4: 实现** `lib/core/vision/score_validator.dart`

```dart
import 'dart:convert';

import '../score/score_ir.dart';

const _techniques = {'h', 'p', 's', 'b', 'x'};

class PageParseResult {
  const PageParseResult({required this.measures, required this.failedCount});
  final List<MeasureIr> measures;
  final int failedCount; // 本页被判 failed 的小节数
}

/// 视觉模型响应 → IR 小节（零成本机器防线，设计文档 §5.2）。
/// 规则：剥围栏 → 解析 → 逐音校验；任一音不合法 = 整小节 failed（不静默丢）；
/// index 一律按数组位置重编，不信任模型编号。
PageParseResult parsePage(String raw, {required int indexOffset}) {
  final json = _extractJson(raw);
  final data = jsonDecode(json);
  if (data is! Map<String, dynamic> || data['measures'] is! List) {
    throw const FormatException('响应缺少 measures 数组');
  }
  final measures = <MeasureIr>[];
  var failed = 0;
  final rawMeasures = data['measures'] as List;
  for (var i = 0; i < rawMeasures.length; i++) {
    final m = _measure(rawMeasures[i], i + indexOffset);
    if (m.failed) failed++;
    measures.add(m);
  }
  return PageParseResult(measures: measures, failedCount: failed);
}

String _extractJson(String raw) {
  final s = raw.indexOf('{');
  final e = raw.lastIndexOf('}');
  if (s < 0 || e <= s) throw const FormatException('响应中没有 JSON 对象');
  return raw.substring(s, e + 1);
}

MeasureIr _measure(dynamic raw, int index) {
  double confidenceOf(dynamic v, double fallback) {
    if (v is! num) return fallback;
    return v.toDouble().clamp(0.0, 1.0).toDouble();
  }

  if (raw is! Map<String, dynamic>) {
    return MeasureIr(index: index, confidence: 0, failed: true, notes: const []);
  }
  final conf = confidenceOf(raw['confidence'], 0.5);
  final notes = <NoteIr>[];
  var ok = true;
  if (raw['notes'] is List) {
    for (final n in raw['notes'] as List) {
      final note = _note(n);
      if (note == null) {
        ok = false;
        break;
      }
      notes.add(note);
    }
  } else {
    ok = false;
  }
  return ok
      ? MeasureIr(index: index, confidence: conf, failed: false, notes: notes)
      : MeasureIr(index: index, confidence: 0, failed: true, notes: const []);
}

NoteIr? _note(dynamic raw) {
  if (raw is! Map<String, dynamic>) return null;
  final beat = (raw['beat'] as num?)?.toDouble();
  final duration = (raw['duration'] as num?)?.toDouble();
  final string = (raw['string'] as num?)?.toInt();
  final fret = (raw['fret'] as num?)?.toInt();
  final technique = raw['technique'];
  if (beat == null || beat < 0) return null;
  if (duration == null || duration <= 0) return null;
  if (string == null || string < 1 || string > 6) return null;
  if (fret == null || fret < 0 || fret > 24) return null;
  if (technique != null &&
      (technique is! String || !_techniques.contains(technique))) {
    return null;
  }
  final conf = raw['confidence'];
  return NoteIr(
      beat: beat,
      duration: duration,
      string: string,
      fret: fret,
      technique: technique as String?,
      confidence: conf is num ? conf.toDouble().clamp(0.0, 1.0).toDouble() : null);
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/score_validator_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/core/vision/tab_prompt.dart lib/core/vision/score_validator.dart test/score_validator_test.dart
git commit -m "feat: 识谱 Prompt 与响应机器校验（二期 M2）"
```

---

### Task 10: ScoreRecognizer 编排

**Files:**
- Create: `lib/core/vision/score_recognizer.dart`
- Test: `test/score_recognizer_test.dart`

- [ ] **Step 1: 写失败测试** `test/score_recognizer_test.dart`

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/vision/score_recognizer.dart';
import 'package:guitarbar/core/vision/vision_client.dart';
import 'package:guitarbar/core/vision/vision_model.dart';

class ScriptedClient implements VisionClient {
  ScriptedClient(this.responses);
  final List<Object> responses; // String 成功 / VisionException 失败
  int callCount = 0;

  @override
  Future<String> complete({required String baseUrl, required String apiKey,
      required String model, required String prompt, required Uint8List png,
      String mime = 'image/png'}) async {
    final r = responses[callCount++];
    if (r is VisionException) throw r;
    return r as String;
  }
}

File tmpPage(Directory d, String name) =>
    File('${d.path}/$name')..writeAsBytesSync([1, 2, 3]);

const cfg = VisionModelConfig(
    id: 'a', name: 'x', baseUrl: 'https://u', apiKey: 'k',
    model: 'm', active: true);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('recognizer'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('两页成功：合并小节、index 连续', () async {
    final client = ScriptedClient([
      '{"measures":[{"index":0,"confidence":0.9,"notes":[]},{"index":1,"confidence":0.8,"notes":[]}]}',
      '{"measures":[{"index":0,"confidence":0.7,"notes":[]}]}',
    ]);
    final ir = await ScoreRecognizer(client).recognize(
        title: 'T',
        pagePngs: [tmpPage(tmp, 'a.png'), tmpPage(tmp, 'b.png')],
        cfg: cfg, tempo: 90,
        tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
        timeSignature: '4/4');
    expect(ir.tracks.single.measures.map((m) => m.index), [0, 1, 2]);
    expect(ir.unrecognizedPages, isEmpty);
  });

  test('单页失败重试 1 次后成功', () async {
    final client = ScriptedClient([
      const VisionException('boom'),
      '{"measures":[{"index":0,"confidence":0.9,"notes":[]}]}',
    ]);
    final ir = await ScoreRecognizer(client).recognize(
        title: 'T', pagePngs: [tmpPage(tmp, 'a.png')],
        cfg: cfg, tempo: 90,
        tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
        timeSignature: '4/4');
    expect(ir.unrecognizedPages, isEmpty);
    expect(ir.tracks.single.measures.length, 1);
  });

  test('重试仍失败：failed 占位小节 + unrecognizedPages 记录', () async {
    final client = ScriptedClient([
      const VisionException('boom'),
      const VisionException('boom'),
      '{"measures":[{"index":0,"confidence":0.9,"notes":[]}]}',
    ]);
    final ir = await ScoreRecognizer(client).recognize(
        title: 'T',
        pagePngs: [tmpPage(tmp, 'a.png'), tmpPage(tmp, 'b.png')],
        cfg: cfg, tempo: 90,
        tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
        timeSignature: '4/4');
    expect(ir.unrecognizedPages, [0]);
    final failed = ir.tracks.single.measures
        .where((m) => m.failed)
        .toList();
    expect(failed.length, 1);
    expect(failed.single.index, 0);
    // 第二页正常编入
    expect(ir.tracks.single.measures.length, 2);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/score_recognizer_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现** `lib/core/vision/score_recognizer.dart`

> **空 measures 页契约（2026-10-29 Task 9 质量审查裁决）**：`parsePage` 对
> `{"measures":[]}` 返回空列表且无失败信号（合法——用户谱库有视奏顺序图页）。
> Task 10 编排侧处理：某页（含重试后）结果 `r.measures.isEmpty` 时，把该页记入
> `unrecognizedPages` 但**不插 failed 占位小节**（页级可见、不污染小节编号）。
> 与"重试仍失败"路径（插占位小节+记页）区分开。

```dart
import 'dart:io';

import '../score/score_ir.dart';
import 'score_validator.dart';
import 'tab_prompt.dart';
import 'vision_client.dart';
import 'vision_model.dart';

/// 识谱编排（设计文档 §5）：逐页调视觉模型 → 机器校验 → 合并 IR。
/// 页失败重试 1 次，仍失败 = failed 占位小节 + unrecognizedPages 记录。
class ScoreRecognizer {
  ScoreRecognizer(this._client);
  final VisionClient _client;

  Future<ScoreIr> recognize({
    required String title,
    required List<File> pagePngs,
    required VisionModelConfig cfg,
    required double tempo,
    required List<String> tuning,
    required String timeSignature,
    void Function(int done, int total)? onPage,
  }) async {
    final measures = <MeasureIr>[];
    final failedPages = <int>[];
    var offset = 0;

    for (var i = 0; i < pagePngs.length; i++) {
      onPage?.call(i, pagePngs.length);
      final png = await pagePngs[i].readAsBytes();
      final prompt = '$tabSystemPrompt\n\n'
          '${tabUserPrompt(tuning: tuning, timeSignature: timeSignature, page: i, total: pagePngs.length)}';

      Future<String> once() =>
          _client.complete(baseUrl: cfg.baseUrl, apiKey: cfg.apiKey,
              model: cfg.model, prompt: prompt, png: png);

      try {
        final r = parsePage(await once(), indexOffset: offset);
        measures.addAll(r.measures);
        offset += r.measures.length;
      } catch (_) {
        try {
          final r = parsePage(await once(), indexOffset: offset); // 重试 1 次
          measures.addAll(r.measures);
          offset += r.measures.length;
        } catch (_) {
          failedPages.add(i);
          measures.add(MeasureIr(
              index: offset, confidence: 0, failed: true, notes: const []));
          offset += 1;
        }
      }
    }

    return ScoreIr(
      version: 1,
      title: title,
      tempo: tempo,
      timeSignature: timeSignature,
      tuning: tuning,
      capo: 0,
      tracks: [TrackIr(name: '主旋律', measures: measures)],
      unrecognizedPages: failedPages,
    );
  }
}
```

注意：ScriptedClient 测试实现 `implements VisionClient` 时需补齐完整接口（Task 7 审查修复后接口含三成员）：`complete`、`@override Duration get timeout => Duration.zero;`、`@override void close() {}`。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/score_recognizer_test.dart && flutter analyze`
Expected: PASS / No issues

- [ ] **Step 5: Commit**

```bash
git add lib/core/vision/score_recognizer.dart test/score_recognizer_test.dart
git commit -m "feat: 识谱编排（逐页/重试/失败占位，二期 M2）"
```

---

### Task 11: 识谱 UI 接线

> **执行修正备案（2026-10-29 Task 10 质量审查）**：本任务代码与 Task 10 终态签名
> 有三处漂移，实现时按下述修正：① `recognize` 调用**必须传 capo**（参数对话框
> 的返回改为四元组 `(tempo, tuning, timeSignature, capo)`，对话框加变调夹输入，
> v1 可固定 0 但参数位留齐）② client 构造必须 `VisionClient(timeout:
> const Duration(minutes: 10))`（GLM thinking 分钟级，默认 120s 会掐断长页）③
> recognize 支持 `cancelled` 回调与 `RecognizeCancelled` 异常——进度对话框加
> 取消按钮，取消时捕获 RecognizeCancelled 提示"已取消"（不覆盖库内已有 IR）。
> 进度文案按 onPage 契约（0 起、处理前回调）显示"第 done+1/N 页"。

**Files:**
- Modify: `lib/ui/scores/score_detail_page.dart`（识谱按钮 + 参数 + 进度）
- Modify: `lib/ui/scores/scores_page.dart`（已识谱徽标已有，无需改——确认即可）

- [ ] **Step 1: 详情页加识谱流程**（`score_detail_page.dart` 内新增）

字段与加载（追加到 `_ScoreDetailPageState`）：

```dart
  // 识谱参数与流程状态。
  bool _recognizing = false;

  Future<void> _recognize() async {
    final params = await _askRecognizeParams();
    if (params == null || !mounted) return;
    setState(() => _recognizing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final store = VisionModelStore(context.read<AppDatabase>());
      final cfg = await store.activeOf(await store.load());
      if (cfg == null) {
        messenger.showSnackBar(const SnackBar(
            content: Text('未配置识谱模型，请到 个人中心 → 识谱模型 配置')));
        return;
      }
      final ir = await ScoreRecognizer(VisionClient()).recognize(
          title: _row!.title,
          pagePngs: _pages!.whereType<File>().toList(),
          cfg: cfg,
          tempo: params.$1,
          tuning: params.$2,
          timeSignature: params.$3,
          onPage: (done, total) {
            if (mounted) setState(() => _progress = '$done/$total 页');
          });
      await _repo!.updateRecognition(
          widget.scoreId, irJson: jsonEncode(ir.toJson()), tuning: ir.tuning.join(','));
      await _reload();
      if (mounted) {
        setState(() {
          _recognizing = false;
          _progress = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ir.unrecognizedPages.isEmpty
                ? '识谱完成'
                : '识谱完成，第 ${ir.unrecognizedPages.map((p) => p + 1).join(',')} 页未识别')));
      }
    } catch (e) {
      if (mounted) {
        setState(() { _recognizing = false; _progress = null; });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('识谱失败：$e')));
      }
    }
  }

  Future<(double, List<String>, String)?> _askRecognizeParams() =>
      showDialog<(double, List<String>, String)>(
        context: context,
        builder: (ctx) {
          double tempo = 90;
          var tuning = const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'];
          return StatefulBuilder(
            builder: (ctx, setLocal) => AlertDialog(
              title: const Text('识谱参数'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const Text('曲速'),
                  Expanded(
                    child: Slider(
                      min: 40, max: 200, divisions: 160,
                      label: tempo.round().toString(),
                      value: tempo,
                      onChanged: (v) => setLocal(() => tempo = v),
                    ),
                  ),
                  Text('${tempo.round()}',
                      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                ]),
                // 调弦 v1 固定标准调弦；自定义调弦联动留 M5+。
                Text('调弦：标准 E-A-D-G-B-E（v1 固定）',
                    style: TextStyle(fontSize: 12, color: Theme.of(ctx).hintColor)),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(
                        ctx, (tempo, tuning, '4/4')),
                    child: const Text('开始识谱')),
              ],
            ),
          );
        },
      );
```

需要 import：`dart:convert`（jsonEncode）、`dart:io`（File，已有）、`package:flutter/services.dart`（FontFeature 在 material 内也可用，若报错补 services）、`package:provider/provider.dart`、`../../core/vision/score_recognizer.dart`、`../../core/vision/vision_client.dart`、`../../core/vision/vision_model.dart`。

新增字段 `String? _progress;`；`_row`（当前 Score 行，`_loadPages` 时一并从 DB 查出：`_row = await (db.select(db.scores)..where((s) => s.id.equals(widget.scoreId))).getSingle()`，需 import drift）。

AppBar actions 加识谱按钮（识别中显示进度文字）：

```dart
      appBar: AppBar(
        title: const Text('曲谱'),
        actions: [
          if (_recognizing)
            Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: Text('识谱中 $_progress',
                    style: TextStyle(fontSize: 14, color: p.muted))))
          else
            IconButton(
                tooltip: 'AI 识谱',
                onPressed: (_pages == null) ? null : _recognize,
                icon: const Icon(Icons.document_scanner_outlined)),
        ],
      ),
```

body 分支：`_row?.irJson != null` 时显示"已识谱，谱面视图见后续任务"占位文本（Task 12 换成 TabView）。

- [ ] **Step 2: 分析与手动走查**

Run: `flutter analyze`
Expected: No issues

Run: `flutter run -d windows`
手动走查：个人中心 → 识谱模型 → 新建智谱配置（粘贴 key）→ 测试连接成功 → 打开一份已导入曲谱 → 识谱 → 观察逐页进度与完成提示 → 列表徽标变"已识谱"。**M2 出口标准达成：一份图片谱识出 IR 入库。**（若识别质量差，记录模型名与现象到 `tasks/todo.md`，默认模型决策点在 M2 收口时定。）

- [ ] **Step 3: Commit**

```bash
git add lib/ui/scores/score_detail_page.dart
git commit -m "feat: 识谱接线（参数/进度/失败提示，M2 收口）"
```

---

### Task 12: TabLayout 几何与 TabView 渲染

**Files:**
- Create: `lib/ui/scores/tab_layout.dart`
- Create: `lib/ui/scores/tab_view.dart`
- Test: `test/tab_layout_test.dart`

- [ ] **Step 1: 写失败测试** `test/tab_layout_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';

ScoreIr ir(int measureCount) => ScoreIr(
      version: 1, title: 'T', tempo: 90, timeSignature: '4/4',
      tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], capo: 0,
      tracks: [
        TrackIr(name: '主旋律', measures: [
          for (var i = 0; i < measureCount)
            MeasureIr(index: i, confidence: 0.9, failed: false, notes: const []),
        ]),
      ],
    );

void main() {
  test('beatsPerBar 从拍号解析', () {
    expect(TabLayout(ir(1)).beatsPerBar, 4);
  });

  test('measureWidth = 拍数 × pxPerBeat', () {
    final l = TabLayout(ir(1));
    expect(l.measureWidth, 4 * TabLayout.pxPerBeat);
  });

  test('rowsFor：宽度放得下 3 行 1 行，放不下换行', () {
    final l = TabLayout(ir(5));
    final wide = l.measureWidth * 3 + TabLayout.measureGap * 2 + TabLayout.leftPad * 2 + 100;
    final rows = l.rowsFor(wide);
    expect(rows.map((r) => r.length), [3, 2]);

    final rows2 = l.rowsFor(l.measureWidth + TabLayout.leftPad * 2);
    expect(rows2.map((r) => r.length), [1, 1, 1, 1, 1]);
  });

  test('noteX 随 beat 线性', () {
    final l = TabLayout(ir(1));
    final wide = l.measureWidth + TabLayout.leftPad * 2;
    final x0 = l.noteX(0, 0.0, wide);
    final x1 = l.noteX(0, 1.0, wide);
    expect(x1 - x0, TabLayout.pxPerBeat);
  });

  test('stringY：1 弦在最上（y 最小）', () {
    final l = TabLayout(ir(1));
    final wide = l.measureWidth + TabLayout.leftPad * 2;
    expect(l.stringY(1, 0), lessThan(l.stringY(6, 0)));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/tab_layout_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现 TabLayout** `lib/ui/scores/tab_layout.dart`

```dart
import 'package:flutter/material.dart';

import '../../core/score/score_ir.dart';

/// 六线谱布局几何（纯函数，可测）：自动换行、小节/音符定位。
/// 1 弦在最上（六线谱惯例），弦号 1→6 自上而下。
class TabLayout {
  TabLayout(this.ir);
  final ScoreIr ir;

  static const stringGap = 18.0;
  static const topPad = 28.0;
  static const bottomPad = 20.0;
  static const leftPad = 16.0;
  static const pxPerBeat = 48.0;
  static const measureGap = 14.0;
  static const rowGap = 26.0;

  int get beatsPerBar =>
      int.tryParse(ir.timeSignature.split('/')[0]) ?? 4;
  double get measureWidth => beatsPerBar * pxPerBeat;
  double get rowHeight => topPad + 5 * stringGap + bottomPad;

  /// 自动换行：每行小节 index 列表。
  List<List<int>> rowsFor(double maxWidth) {
    final perRow =
        (((maxWidth - leftPad * 2 + measureGap) / (measureWidth + measureGap))
                .floor())
            .clamp(1, 1 << 31);
    final total = ir.tracks.isEmpty
        ? 0
        : ir.tracks.first.measures.length;
    final rows = <List<int>>[];
    for (var i = 0; i < total; i += perRow) {
      rows.add([
        for (var k = i; k < (i + perRow).clamp(0, total); k++) k
      ]);
    }
    return rows;
  }

  Size sizeFor(double maxWidth) {
    final rows = rowsFor(maxWidth);
    final h = rows.isEmpty
        ? rowHeight
        : rows.length * rowHeight + (rows.length - 1) * rowGap;
    return Size(maxWidth, h);
  }

  /// 小节所在行与小节列。
  (int row, int col) locate(int measureIndex, double maxWidth) {
    final rows = rowsFor(maxWidth);
    for (var r = 0; r < rows.length; r++) {
      final c = rows[r].indexOf(measureIndex);
      if (c >= 0) return (r, c);
    }
    return (0, 0);
  }

  double measureX(int measureIndex, double maxWidth) {
    final (r, c) = locate(measureIndex, maxWidth);
    return leftPad + c * (measureWidth + measureGap) + (r == 0 ? 0 : 0);
  }

  double noteX(int measureIndex, double beat, double maxWidth) =>
      measureX(measureIndex, maxWidth) + beat * pxPerBeat;

  double stringY(int string, int row) =>
      row * (rowHeight + rowGap) + topPad + (string - 1) * stringGap;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/tab_layout_test.dart`
Expected: PASS

- [ ] **Step 5: 实现 TabView 绘制** `lib/ui/scores/tab_view.dart`

```dart
import 'package:flutter/material.dart';

import '../../core/score/score_ir.dart';
import '../theme.dart';
import 'tab_layout.dart';

/// 六线谱视图：弦线/品数字/小节线 + 置信度标记 + failed 小节可见化 + 播放头。
/// 1 弦在最上（六线谱惯例）。dataHue 上数据（音符/置信度底），播放头 positive。
class TabView extends StatelessWidget {
  const TabView({super.key, required this.ir, this.playheadBeat, this.onNoteTap,
      this.onFailedTap});
  final ScoreIr ir;
  /// 播放头位置（全曲拍位，Task 16 接线）；null = 不显示。
  final double? playheadBeat;
  final void Function(int measureIndex, int noteIndex, NoteIr note)? onNoteTap;
  final void Function(int measureIndex)? onFailedTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(builder: (ctx, box) {
      final layout = TabLayout(ir);
      final w = box.maxWidth;
      return GestureDetector(
        onTapUp: (d) => _hitTest(d.localPosition, w),
        child: SingleChildScrollView(
          child: SizedBox(
            width: w,
            height: layout.sizeFor(w).height,
            child: CustomPaint(
              painter: _TabPainter(
                  layout: layout,
                  ir: ir,
                  playheadBeat: playheadBeat,
                  stringLine: p.border,
                  fretText: p.ink,
                  barLine: p.border,
                  confBg: p.dataHue.withOpacity(0.12),
                  failedText: p.negative,
                  playhead: p.positive,
                  pageNum: p.muted),
            ),
          ),
        ),
      );
    });
  }

  /// 点击命中：找最近的弦线（|dy| < stringGap/2），再找该弦上最近的音符
  /// （|dx| < pxPerBeat/2）。failed 小节整块可点。
  void _hitTest(Offset local, double maxWidth) {
    final layout = TabLayout(ir);
    final tracks = ir.tracks;
    if (tracks.isEmpty || onNoteTap == null && onFailedTap == null) return;
    for (final m in tracks.first.measures) {
      final mx = layout.measureX(m.index, maxWidth);
      if (local.dx < mx - TabLayout.measureGap / 2 ||
          local.dx > mx + layout.measureWidth) {
        continue;
      }
      final row = layout.locate(m.index, maxWidth).$1;
      if (m.failed) {
        onFailedTap?.call(m.index);
        return;
      }
      for (var i = 0; i < m.notes.length; i++) {
        final n = m.notes[i];
        final nx = layout.noteX(m.index, n.beat, maxWidth);
        final ny = layout.stringY(n.string, row);
        if ((local.dx - nx).abs() < TabLayout.pxPerBeat / 2 &&
            (local.dy - ny).abs() < TabLayout.stringGap / 2) {
          onNoteTap?.call(m.index, i, n);
          return;
        }
      }
    }
  }
}

class _TabPainter extends CustomPainter {
  _TabPainter({
    required this.layout,
    required this.ir,
    required this.playheadBeat,
    required this.stringLine,
    required this.fretText,
    required this.barLine,
    required this.confBg,
    required this.failedText,
    required this.playhead,
    required this.pageNum,
  });

  final TabLayout layout;
  final ScoreIr ir;
  final double? playheadBeat;
  final Color stringLine, fretText, barLine, confBg, failedText, playhead, pageNum;

  @override
  void paint(Canvas canvas, Size size) {
    final rows = layout.rowsFor(size.width);
    final measures =
        ir.tracks.isEmpty ? const <MeasureIr>[] : ir.tracks.first.measures;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var r = 0; r < rows.length; r++) {
      final rowTop = layout.stringY(1, r);
      final rowBottom = layout.stringY(6, r);
      // 1. 弦线（1 弦最上）。
      for (var s = 1; s <= 6; s++) {
        final y = layout.stringY(s, r);
        canvas.drawLine(Offset(layout.leftPad, y),
            Offset(size.width - layout.leftPad, y), Paint()..color = stringLine);
      }
      // 2-6. 小节：底色/编号/竖线/音符/failed 标记。
      for (final m in rows[r].map((idx) => measures[idx])) {
        final mx = layout.measureX(m.index, size.width);
        final mw = layout.measureWidth;
        // 低置信度底（failed 不画底，画标记）。
        if (!m.failed && m.confidence < 0.6) {
          canvas.drawRect(
              Rect.fromLTWH(mx, rowTop - 8, mw, rowBottom - rowTop + 16),
              Paint()..color = confBg);
        }
        // 小节号。
        _text(canvas, '${m.index + 1}', Offset(mx, rowTop - 16),
            TextStyle(fontSize: 10, color: pageNum));
        // 左右小节竖线。
        canvas.drawLine(Offset(mx, rowTop), Offset(mx, rowBottom),
            Paint()..color = barLine);
        canvas.drawLine(Offset(mx + mw, rowTop), Offset(mx + mw, rowBottom),
            Paint()..color = barLine);
        if (m.failed) {
          _text(canvas, '未识别', Offset(mx + mw / 2, (rowTop + rowBottom) / 2),
              TextStyle(fontSize: 12, color: failedText));
          continue;
        }
        for (final n in m.notes) {
          _text(canvas, '${n.fret}',
              Offset(layout.noteX(m.index, n.beat, size.width),
                  layout.stringY(n.string, r)),
              TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fretText));
        }
      }
    }
    // 7. 播放头（全曲拍 → 小节/行内位置）。
    if (playhead != null && playheadBeat != null) {
      final beatPerBar = layout.beatsPerBar;
      final measure = (playheadBeat! / beatPerBar).floor();
      final inMeasure = playheadBeat! - measure * beatPerBar;
      var row = 0, col = 0, found = false;
      for (var r = 0; r < rows.length && !found; r++) {
        final c = rows[r].indexOf(measure);
        if (c >= 0) {
          row = r;
          col = c;
          found = true;
        }
      }
      if (found) {
        final x = layout.leftPad +
            col * (layout.measureWidth + TabLayout.measureGap) +
            inMeasure * TabLayout.pxPerBeat;
        final y0 = layout.stringY(1, row) - 10;
        final y1 = layout.stringY(6, row) + 10;
        canvas.drawLine(Offset(x, y0), Offset(x, y1),
            Paint()..color = playhead..strokeWidth = 2);
      }
    }
    // 8. 图例（低置信度底色示意）。
    canvas.drawRect(const Rect.fromLTWH(0, 0, 10, 10), Paint()..color = confBg);
    _text(canvas, '低置信度', Offset(14, 5),
        TextStyle(fontSize: 10, color: pageNum));
  }

  void _text(Canvas canvas, String s, Offset at, TextStyle style) {
    final tp = TextPainter(
        text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _TabPainter old) =>
      old.playheadBeat != playheadBeat || old.ir != ir;
}
```

实现纪律：`withOpacity` 调用为 package:flutter material 侧合法 API（`Color.withOpacity`）；若工程 lint 提示弃用则改 `withValues(alpha:)`。播放头跨行定位用 rows 反查（不假设小节宽恒定）。`shouldRepaint` 的 `old.ir != ir` 依赖 Task 5 的 `==` identical 短路（播放中 `_ir` 实例不变；编辑后是新实例，一次性 O(树) 比较可接受）——Task 5 审查修复已落地该短路，两者需同批生效。

- [ ] **Step 6: 分析与静态验证**

Run: `flutter analyze && flutter test test/tab_layout_test.dart`
Expected: No issues / PASS

- [ ] **Step 7: Commit**

```bash
git add lib/ui/scores/tab_layout.dart lib/ui/scores/tab_view.dart test/tab_layout_test.dart
git commit -m "feat: 六线谱几何与渲染（置信度/failed/播放头，二期 M3）"
```

---

### Task 13: 小节点选编辑

**Files:**
- Create: `lib/ui/scores/note_edit_sheet.dart`
- Modify: `lib/ui/scores/tab_view.dart`（音符命中检测 + 点击回调）
- Modify: `lib/ui/scores/score_detail_page.dart`（接 sheet + 保存回写）
- Test: `test/note_edit_test.dart`（回写逻辑纯函数）

- [ ] **Step 1: 回写纯函数失败测试** `test/note_edit_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/ui/scores/note_edit_sheet.dart';

void main() {
  test('applyNoteEdit：按 (measure, noteIdx) 替换音符并置 confidence=1', () {
    final ir = ScoreIr(
        version: 1, title: 'T', tempo: 90, timeSignature: '4/4',
        tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], capo: 0,
        tracks: [
          TrackIr(name: '主旋律', measures: [
            MeasureIr(index: 0, confidence: 0.9, failed: false, notes: [
              const NoteIr(beat: 0, duration: 1, string: 1, fret: 3,
                  technique: null, confidence: 0.5),
            ]),
          ]),
        ]);
    final out = applyNoteEdit(ir, 0, 0,
        const NoteIr(beat: 0, duration: 0.5, string: 2, fret: 5,
            technique: 'h', confidence: 1));
    final n = out.tracks[0].measures[0].notes[0];
    expect(n.string, 2);
    expect(n.fret, 5);
    expect(n.duration, 0.5);
    expect(n.technique, 'h');
    expect(n.confidence, 1); // 人工确认标记
    expect(out.tracks[0].measures[0].confidence, 1); // 小节级同步人工确认
  });

  test('applyMeasureClear：failed 小节重建为空小节', () {
    final ir = ScoreIr(
        version: 1, title: 'T', tempo: 90, timeSignature: '4/4',
        tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], capo: 0,
        tracks: [
          TrackIr(name: '主旋律', measures: [
            const MeasureIr(index: 0, confidence: 0, failed: true, notes: []),
          ]),
        ]);
    final out = applyMeasureClear(ir, 0);
    expect(out.tracks[0].measures[0].failed, isFalse);
    expect(out.tracks[0].measures[0].notes, isEmpty);
    expect(out.tracks[0].measures[0].confidence, 1);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/note_edit_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现** `lib/ui/scores/note_edit_sheet.dart`（回写函数 + 编辑弹层）

```dart
import 'package:flutter/material.dart';

import '../../core/score/score_ir.dart';
import '../theme.dart';

/// 人工修正（设计文档 §5.3）：保存回写 IR，confidence 置 1 = 人工确认。
ScoreIr applyNoteEdit(ScoreIr ir, int measureIndex, int noteIndex, NoteIr note) {
  final tracks = [
    for (final t in ir.tracks)
      if (t.measures.any((m) => m.index == measureIndex))
        TrackIr(
            name: t.name,
            measures: [
              for (final m in t.measures)
                m.index == measureIndex
                    ? MeasureIr(
                        index: m.index,
                        confidence: 1,
                        failed: false,
                        notes: [
                          for (var i = 0; i < m.notes.length; i++)
                            i == noteIndex ? note : m.notes[i],
                        ])
                    : m,
            ])
      else
        t,
  ];
  return ScoreIr(
      version: ir.version,
      title: ir.title,
      tempo: ir.tempo,
      timeSignature: ir.timeSignature,
      tuning: ir.tuning,
      capo: ir.capo,
      tracks: tracks,
      unrecognizedPages: ir.unrecognizedPages);
}

/// failed 小节 → 重建为空小节（从"未识别"进入可编辑状态）。
ScoreIr applyMeasureClear(ScoreIr ir, int measureIndex) {
  final tracks = [
    for (final t in ir.tracks)
      TrackIr(
          name: t.name,
          measures: [
            for (final m in t.measures)
              m.index == measureIndex
                  ? MeasureIr(index: m.index, confidence: 1, failed: false, notes: const [])
                  : m,
          ]),
  ];
  return ScoreIr(
      version: ir.version,
      title: ir.title,
      tempo: ir.tempo,
      timeSignature: ir.timeSignature,
      tuning: ir.tuning,
      capo: ir.capo,
      tracks: tracks,
      unrecognizedPages: ir.unrecognizedPages);
}

/// 音符编辑弹层：弦/品/时值/技法快捷编辑。
Future<NoteIr?> showNoteEditSheet(BuildContext ctx, NoteIr note) {
  var string = note.string;
  var fret = note.fret;
  var duration = note.duration;
  var technique = note.technique;
  return showModalBottomSheet<NoteIr>(
    context: ctx,
    builder: (ctx) {
      final p = ctx.palette;
      return StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('编辑音符', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.ink)),
                const SizedBox(height: 16),
                Row(children: [
                  Text('弦', style: TextStyle(fontSize: 14, color: p.ink)),
                  const SizedBox(width: 8),
                  for (var s = 1; s <= 6; s++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                          label: Text('$s'),
                          selected: string == s,
                          onSelected: (_) => setLocal(() => string = s)),
                    ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Text('品', style: TextStyle(fontSize: 14, color: p.ink)),
                  const SizedBox(width: 8),
                  IconButton(onPressed: () => setLocal(() => fret = (fret - 1).clamp(0, 24)),
                      icon: const Icon(Icons.remove_circle_outline)),
                  Text('$fret', style: const TextStyle(fontSize: 18, fontFeatures: [FontFeature.tabularFigures()])),
                  IconButton(onPressed: () => setLocal(() => fret = (fret + 1).clamp(0, 24)),
                      icon: const Icon(Icons.add_circle_outline)),
                  const SizedBox(width: 16),
                  Text('时值(拍)', style: TextStyle(fontSize: 14, color: p.ink)),
                  const SizedBox(width: 8),
                  for (final d in const [4.0, 2.0, 1.0, 0.5, 0.25])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                          label: Text(d >= 1 ? '${d.toInt()}' : '${(d * 100).toInt()}%'),
                          selected: duration == d,
                          onSelected: (_) => setLocal(() => duration = d)),
                    ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Text('技法', style: TextStyle(fontSize: 14, color: p.ink)),
                  const SizedBox(width: 8),
                  for (final t in const [
                    (null, '无'), ('h', '击'), ('p', '勾'), ('s', '滑'), ('b', '弯'), ('x', '闷'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                          label: Text(t.$2),
                          selected: technique == t.$1,
                          onSelected: (_) => setLocal(() => technique = t.$1)),
                    ),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    // 直接构造新 NoteIr（不走 copyWith——technique 需要能置回 null）。
                    onPressed: () => Navigator.pop(
                        ctx,
                        NoteIr(
                            beat: note.beat,
                            duration: duration,
                            string: string,
                            fret: fret,
                            technique: technique,
                            confidence: 1)),
                    child: const Text('保存'),
                  ),
                ),
              ]),
        ),
      );
    },
  );
}
```

注意：`technique` 变量声明为 `String?`；保存按钮直接构造新 NoteIr（Task 5 的 `copyWith` 语义无法把 technique 置回 null，不修改它）。

- [ ] **Step 4: 确认点击命中**（已在 Task 12 的 TabView 最终代码中实现：`onNoteTap`/`onFailedTap` 回调字段与 `_hitTest`——本步骤无新代码，跑 `flutter analyze` 确认无未用警告即可）

- [ ] **Step 5: 详情页接线**（`score_detail_page.dart`）

- `_reload()` 后若 `_row!.irJson != null` 解析 `_ir = ScoreIr.fromJson(jsonDecode(_row!.irJson!))`（字段 `ScoreIr? _ir`）。
- body 宽屏：`Row(children: [Expanded(child: _tabArea()), SizedBox(width: 360, child: SourceViewer(...))])`；窄屏：`_tabArea()`（Task 14 再加 Tab 切换，本任务先直接显示 TabView）。
- `_tabArea()`：`_ir == null` → 居中提示"尚未识谱"（muted）；有 → `TabView(ir: _ir!, onNoteTap: _editNote, onFailedTap: _clearMeasure)`。
- `_editNote(m, i, n)`：`showNoteEditSheet` → 结果非空 → `_ir = applyNoteEdit(_ir!, m, i, 结果)` → `await _repo!.updateIrJson(widget.scoreId, jsonEncode(_ir!.toJson()))` → setState 刷新。
- `_clearMeasure(m)`：同样经 `applyMeasureClear` 回写。

- [ ] **Step 6: 跑测试与走查**

Run: `flutter test test/note_edit_test.dart && flutter analyze`
Expected: PASS / No issues

Run: `flutter run -d windows`
手动：识谱后的谱面 → 点一个音符改弦/品/时值 → 保存 → 谱面即时更新 → 重进页面数据仍在。

- [ ] **Step 7: Commit**

```bash
git add lib/ui/scores test/note_edit_test.dart
git commit -m "feat: 音符点选编辑与 failed 小节重建（人工确认 confidence=1，二期 M3）"
```

---

### Task 14: 详情页组装（宽屏并排 / 窄屏切换 + 图例）

**Files:**
- Modify: `lib/ui/scores/score_detail_page.dart`

- [ ] **Step 1: 组装双模式**

`build` 里的 body 改为（LayoutBuilder 区分宽窄，阈值 900 与 root.dart 一致）：

```dart
      body: LayoutBuilder(builder: (ctx, box) {
        final wide = box.maxWidth >= 900;
        final viewer = SourceViewer(pagePngs: pages ?? const []);
        final tabArea = _tabArea();
        if (wide) {
          return Row(children: [
            Expanded(child: tabArea),
            SizedBox(width: 360, child: viewer),
          ]);
        }
        // 窄屏：谱面/原图 Tab 切换（未识谱只有原图）。
        return DefaultTabController(
          length: _ir == null ? 1 : 2,
          child: Column(children: [
            if (_ir != null)
              TabBar(tabs: const [
                Tab(text: '谱面'),
                Tab(text: '原图'),
              ], labelColor: p.ink, unselectedLabelColor: p.muted,
                  indicatorColor: p.dataHue),
            Expanded(
              child: _ir == null
                  ? viewer
                  : TabBarView(children: [tabArea, viewer]),
            ),
          ]),
        );
      }),
```

谱面区顶部加图例行（低置信度色块示意 + "未识别"说明，10-12px muted）。

- [ ] **Step 2: 分析与 M3 出口走查**

Run: `flutter analyze && flutter test`
Expected: No issues / 全绿

Run: `flutter run -d windows`
手动（**M3 出口标准**）：识谱后的曲谱宽屏谱面+原图并排可对照；窄屏 Tab 切换正常；低置信度小节有轻标记；failed 小节显示"未识别"且点击可重建为空小节。

- [ ] **Step 3: Commit**

```bash
git add lib/ui/scores/score_detail_page.dart
git commit -m "feat: 详情页宽窄双模式组装与图例（M3 收口）"
```

---

### Task 15: ScoreRenderer（IR → PCM）

**Files:**
- Create: `lib/audio/score_renderer.dart`
- Test: `test/score_renderer_test.dart`

- [ ] **Step 1: 写失败测试** `test/score_renderer_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/score_renderer.dart';
import 'package:guitarbar/core/score/score_ir.dart';

ScoreIr irWith(List<NoteIr> notes, {double tempo = 60}) => ScoreIr(
      version: 1, title: 'T', tempo: tempo, timeSignature: '4/4',
      tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], capo: 0,
      tracks: [
        TrackIr(name: '主旋律', measures: [
          MeasureIr(index: 0, confidence: 1, failed: false, notes: notes),
        ]),
      ],
    );

const sr = 44100;

void main() {
  test('单音：beat 前无声、起始处有能量、总长含尾音', () {
    final r = renderScore(irWith([
      const NoteIr(beat: 1.0, duration: 1.0, string: 6, fret: 0,
          technique: null, confidence: null),
    ]));
    // tempo 60 → 1 拍 = 1s = 44100 样本
    for (var i = 0; i < 44000; i++) {
      expect(r.pcm[i], 0, reason: 'beat=1 前应静音');
    }
    // 拨弦有 3ms 淡入（首样本为 0），检查起始窗内出现能量。
    expect(r.pcm.sublist(44100, 44600).any((v) => v.abs() > 1000), isTrue);
    // 总长 ≥ 音符结束(2s) + 尾音(1.2s) = 3.2s
    expect(r.seconds, closeTo(3.2, 0.01));
  });

  test('failed 小节跳过渲染', () {
    final ir = irWith(const []);
    final irFailed = ScoreIr(
        version: 1, title: 'T', tempo: 60, timeSignature: '4/4',
        tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'], capo: 0,
        tracks: [
          TrackIr(name: '主旋律', measures: [
            const MeasureIr(index: 0, confidence: 0, failed: true, notes: []),
          ]),
        ]);
    final r = renderScore(irFailed);
    expect(r.pcm.every((v) => v == 0), isTrue);
    expect(ir, isNotNull); // 保持 irWith 引用
  });

  test('闷音 x 衰减快：0.3s 后能量远小于正常拨弦', () {
    final normal = renderScore(irWith([
      const NoteIr(beat: 0, duration: 1, string: 6, fret: 0,
          technique: null, confidence: null),
    ]));
    final muted = renderScore(irWith([
      const NoteIr(beat: 0, duration: 1, string: 6, fret: 0,
          technique: 'x', confidence: null),
    ]));
    final tail = (sr * 0.8).round();
    var sumN = 0, sumM = 0;
    for (var i = tail; i < tail + 1000; i++) {
      sumN += normal.pcm[i].abs();
      sumM += muted.pcm[i].abs();
    }
    expect(sumM * 3, lessThan(sumN));
  });

  test('混音：双音叠加非零且不削波（有限值即可）', () {
    final r = renderScore(irWith([
      const NoteIr(beat: 0, duration: 1, string: 6, fret: 0, technique: null, confidence: null),
      const NoteIr(beat: 0, duration: 1, string: 5, fret: 0, technique: null, confidence: null),
    ]));
    expect(r.pcm.any((v) => v != 0), isTrue);
    expect(r.pcm.any((v) => v < -32768 || v > 32767), isFalse);
  });

  test('弦号映射：string 1（最细）比 string 6（最粗）频率高一个量级', () {
    // 过零率近似频率：E4≈330Hz（0.1s 内约 66 次过零），E2≈82Hz（约 16 次）。
    // 锁住 2026-10-29 修正的 tunings[6 - n.string] 映射（镜像颠倒会此断言失败）。
    int zc(Int16List pcm) {
      var n = 0;
      for (var i = 1; i < 4410 && i < pcm.length; i++) {
        if ((pcm[i - 1] < 0) != (pcm[i] < 0)) n++;
      }
      return n;
    }

    final hi = renderScore(irWith([
      const NoteIr(beat: 0, duration: 1, string: 1, fret: 0, technique: null, confidence: null),
    ]));
    final lo = renderScore(irWith([
      const NoteIr(beat: 0, duration: 1, string: 6, fret: 0, technique: null, confidence: null),
    ]));
    expect(zc(hi.pcm), greaterThan(zc(lo.pcm) * 2));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/score_renderer_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现** `lib/audio/score_renderer.dart`

```dart
import 'dart:typed_data';

import '../core/music/note.dart';
import '../core/score/score_ir.dart';
import 'synth.dart';

class RenderedScore {
  const RenderedScore(
      {required this.pcm, required this.sampleRate, required this.seconds});
  final Int16List pcm;
  final int sampleRate;
  final double seconds;
}

/// 渲染式自动演奏（设计文档 §7.1）：整曲 IR → 离线 PCM。
/// beat→sample 按 tempo 换算；音符 = KS pluck 叠加进时间线；
/// 闷音 x 短衰减；failed 小节跳过；变速=改 tempo 重渲染（M5）。
RenderedScore renderScore(ScoreIr ir,
    {int sampleRate = 44100, double a4 = 440}) {
  final beatSamples = 60.0 / ir.tempo * sampleRate;
  const tailSeconds = 1.2;

  // 总长：最后音符结束 + 尾音。
  var endBeat = 0.0;
  for (final t in ir.tracks) {
    for (final m in t.measures) {
      for (final n in m.notes) {
        final e = n.beat + n.duration + tailSeconds * ir.tempo / 60;
        if (e > endBeat) endBeat = e;
      }
    }
  }
  final total = (endBeat * beatSamples).ceil() + 1;
  final mix = Float64List(total);
  final tunings = [for (final s in ir.tuning) Note.parse(s)];

  for (final t in ir.tracks) {
    for (final m in t.measures) {
      if (m.failed) continue;
      for (final n in m.notes) {
        // 弦号映射：NoteIr.string 1=最细高音弦，tuning 低→高 index 0=6弦，
        // 故 string 1 → tunings[5]（2026-10-29 质量审查修正，原稿写反）。
        final freq = Note(tunings[6 - n.string].midi + n.fret).frequency(a4);
        final pcm = pluck(freq,
            sampleRate: sampleRate,
            seconds: n.technique == 'x' ? 0.3 : tailSeconds);
        final off = (n.beat * beatSamples).round();
        for (var i = 0; i < pcm.length && off + i < total; i++) {
          mix[off + i] += pcm[i] / 32768.0;
        }
      }
    }
  }
  return RenderedScore(
      pcm: Int16List.fromList(
          [for (final v in mix) (v.clamp(-1.0, 1.0) * 32767).round()]),
      sampleRate: sampleRate,
      seconds: total / sampleRate);
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/score_renderer_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/audio/score_renderer.dart test/score_renderer_test.dart
git commit -m "feat: IR→PCM 渲染器（采样精确时间线/闷音/混音限幅，二期 M4）"
```

---

### Task 16: ScorePlayer 与播放控制条（M4 收口）

> **执行备忘（2026-10-30 Task 12 质量审查）**：接线播放头时一并做两项渲染性能
> 优化并实测帧耗时——① paint 内用行循环列号直算 x（消掉 measureX/locate 链路
> 每小节每音符重复重算 rowsFor，约 3 行）② TextPainter 按字符串缓存跨帧复用
> （约 15 行，identical(ir) 已是失效开关）。M3 静态场景两项均可接受，播放 50ms
> 刷新时叠加才成问题。另：Task 14 图例行与 TabView 内置图例二选一。

**Files:**
- Create: `lib/audio/score_player.dart`
- Create: `lib/ui/scores/play_bar.dart`
- Modify: `lib/ui/scores/score_detail_page.dart`（底部播放条 + 谱面播放头）

- [ ] **Step 1: 实现 ScorePlayer** `lib/audio/score_player.dart`

> **执行修正备案（2026-10-30 Task 15 质量审查）**：计划原稿的 `stop()` 有置序 bug——
> `_handle = null` 先于 `final h = _handle`，h 恒 null → stop/disposeSource 永不执行
> （点停止声音不停）。实现时先取 `final h = _handle;` 再置空。另：真实谱渲染
> 实测 ~0.3-1s（60 小节 JIT 953ms）非"毫秒级"——M4 播放时用 _progress 式忙碌
> 反馈，M5 变速重渲染时 `Isolate.run(() => renderScore(ir))`（约 10 行改造）。
> renderScore 侧多小节偏移/capo/秒哨兵三处 Critical 已由 Task 15 修复提交处理。

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'score_renderer.dart';
import 'sound_engine.dart';

/// 自动演奏播放：渲染 PCM → loadPcm → play。
/// 位置轮询仅供 UI 播放头（与节拍器同思路，不影响音频精度）。
class ScorePlayer {
  ScorePlayer(this._sound);
  final SoundEngine _sound;

  AudioSource? _src;
  SoundHandle? _handle;
  Timer? _timer;
  double durationSeconds = 0;

  final ValueNotifier<double> positionSeconds = ValueNotifier(0);
  bool get playing => _handle != null;
  bool get loaded => _src != null;

  Future<void> load(RenderedScore r) async {
    await stop();
    _src = await _sound.loadPcm(r.pcm);
    durationSeconds = r.seconds;
  }

  Future<void> start() async {
    final src = _src;
    if (src == null || _handle != null) return;
    _handle = _sound.play(src);
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final h = _handle;
      if (h == null) return;
      final pos = _sound.position(h).inMicroseconds / 1e6;
      positionSeconds.value = pos.clamp(0.0, durationSeconds).toDouble();
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _handle = null;
    positionSeconds.value = 0;
    final s = _src;
    _src = null;
    final h = _handle;
    if (h != null) await _sound.stop(h);
    if (s != null) await _sound.disposeSource(s);
  }
}
```

- [ ] **Step 2: 实现 PlayBar** `lib/ui/scores/play_bar.dart`

```dart
import 'package:flutter/material.dart';

import '../theme.dart';

/// 播放控制条（v1：播放/停止 + 进度；变速/AB/多轨为 M5）。
class PlayBar extends StatelessWidget {
  const PlayBar(
      {super.key,
      required this.playing,
      required this.positionSeconds,
      required this.durationSeconds,
      required this.onToggle});
  final bool playing;
  final double positionSeconds;
  final double durationSeconds;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.panel,
        border: Border(top: BorderSide(color: p.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        IconButton(
            onPressed: onToggle,
            icon: Icon(playing ? Icons.stop : Icons.play_arrow, color: p.ink)),
        Expanded(
          child: Slider(
            value: durationSeconds == 0
                ? 0
                : (positionSeconds / durationSeconds).clamp(0.0, 1.0),
            onChanged: null, // v1 不可拖动定位（AB 循环在 M5）
            activeColor: p.dataHue,
          ),
        ),
        Text(
          '${positionSeconds.toStringAsFixed(1)}/${durationSeconds.toStringAsFixed(1)}s',
          style: TextStyle(
              fontSize: 12,
              color: p.muted,
              fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 3: 详情页接线**

`_ScoreDetailPageState` 加：

```dart
  ScorePlayer? _player;
  bool _playing = false;
  double _pos = 0;

  Future<void> _togglePlay() async {
    if (_ir == null) return;
    _player ??= ScorePlayer(SoundEngine.I);
    if (_playing) {
      await _player!.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    // 渲染在 isolate 外直接做（整曲 < 10s 音频，毫秒级可接受；卡了 M5 再拆）。
    final rendered = renderScore(_ir!);
    await _player!.load(rendered);
    await _player!.start();
    if (mounted) setState(() => _playing = true);
  }
```

`dispose` 加 `unawaited(_player?.stop())`。需新增 import：`dart:async`（unawaited）、`../../audio/score_renderer.dart`（renderScore）、`../../audio/score_player.dart`、`../../audio/sound_engine.dart`。

body 底部：`bottomSheet: _ir == null ? null : PlayBar(...)`——用 ListenableBuilder 监听 `_player?.positionSeconds` 刷新进度；停止时把 `_playing` 复位（监听 positionSeconds 归零不可靠——onToggle 里自己置位，stop 分支已置 false）。

谱面播放头：`_tabArea()` 中把 `_player?.positionSeconds` → 全曲拍：`beat = pos / (60 / tempo)`，传给 `TabView(playheadBeat: beat)`（ListenableBuilder 包裹）。

- [ ] **Step 4: 分析与 M4 出口走查**

Run: `flutter analyze && flutter test`
Expected: No issues / 全绿

Run: `flutter run -d windows`
手动（**M4 出口标准**）：打开已识谱曲谱 → 点播放 → 听到按谱演奏的合成音 → 谱面播放头随进度移动 → 停止干净。**听觉校对闭环成立。**

- [ ] **Step 5: Commit**

```bash
git add lib/audio/score_player.dart lib/ui/scores/play_bar.dart lib/ui/scores/score_detail_page.dart
git commit -m "feat: 自动演奏播放与控制条（M4 收口，听觉校对闭环）"
```

---

## 收尾

- [ ] 全量测试：`flutter test`（全绿）+ `flutter analyze`（No issues）
- [ ] M1-M4 对照设计文档验收：M1 导入到可见 ✓ / M2 图片谱识出 IR 入库 ✓ / M3 谱面对照可读可改 ✓ / M4 播放可听 ✓
- [ ] 更新 `tasks/todo.md`（M1-M4 完成勾选 + M5-M7 待办）与设计账本（若有新决策）
- [ ] 人工确认走查记录补入 `tasks/acceptance.md` 二期节
- [ ] git log 审一遍提交序列，确认每 Task 一个提交
- [ ] 推送 GitHub：`git push origin master`
