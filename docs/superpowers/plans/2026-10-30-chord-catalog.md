# 13.1 和弦库分类浏览 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 和弦库加"浏览"模式——分类树（三和弦/七和弦/挂留/加音扩展 → 17 种子类）× 根音 12 选枚举点选，直接出指法（复用一期生成引擎与试听）。

**Architecture:** 数据层 ChordCatalog（纯常量，从 chord_parser 的 `_qualities` 17 种组织为分类树，枚举直接产 ParsedChord 不经字符串解析）；UI 层 chord_page 加输入/浏览双模式（SegmentedButton 切换），浏览选定即查询复用既有 `_search` 结果区。设计依据：设计文档 §13.1（2026-10-30 用户提出并确认）。

**Tech Stack:** 纯 Flutter/Dart，零新依赖；复用 `parseChord`/`chordToneClasses`/`FingeringGenerator`/`_ChordPainter`/四试听/调弦联动。

**关键复用接口（实现者必读）:**

- `parseChord('Am7') → ParsedChord(rootPc, intervals)`（`lib/core/music/chord_parser.dart`——`_qualities` 表含全部 17 种）
- `chordToneClasses(c) → Set<int>`、`FingeringGenerator(strings).generate(rootPc:, toneClasses:) → List<ChordVoicing>`（`lib/core/music/fingering.dart`）
- `lib/ui/toolbox/chord_page.dart`：`_search()`（解析→生成→setState）、`_voicings` 结果区（指法图卡片+四试听按钮）、`_onTuningChanged` 调弦联动自动重查、`_input` 控制器
- 设计语言：context.palette.*、ChoiceChip、SegmentedButton（外观三选已有先例 profile_page）、Wrap

---

### Task A: ChordCatalog 分类目录数据

**Files:**
- Create: `lib/core/music/chord_catalog.dart`
- Test: `test/chord_catalog_test.dart`

- [ ] **Step 1: 写失败测试** `test/chord_catalog_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/music/chord_catalog.dart';
import 'package:guitarbar/core/music/chord_parser.dart';

void main() {
  test('四大分类覆盖全部 17 种子类、无重复', () {
    final all = <String>{};
    for (final cat in chordCategories) {
      for (final sub in cat.subtypes) {
        expect(all.contains(sub.suffix), isFalse,
            reason: '${sub.suffix} 重复出现在 ${cat.name}');
        all.add(sub.suffix);
      }
    }
    expect(all.length, 17);
    expect(chordCategories.length, 4);
    expect(chordCategories.map((c) => c.name),
        ['三和弦', '七和弦', '挂留和弦', '加音与扩展']);
  });

  test('目录与解析器一致：每个 (根音, 后缀) 拼名走 parseChord 结果相同', () {
    for (final root in rootNames.keys) {
      for (final cat in chordCategories) {
        for (final sub in cat.subtypes) {
          final p = parseChord(root + sub.suffix);
          expect(p.rootPc, rootNames[root],
              reason: '$root${sub.suffix} 根音');
          expect(p.intervals, sub.intervals,
              reason: '$root${sub.suffix} 音程');
        }
      }
    }
  });

  test('浏览选中直接构造 ParsedChord', () {
    final c = browseChord(9, 'm7'); // Am7
    expect(c.rootPc, 9);
    expect(c.intervals, [0, 3, 7, 10]);
  });

  test('browseChord 未知后缀抛 ArgumentError', () {
    expect(() => browseChord(0, 'zz'), throwsArgumentError);
  });

  test('根音表 12 个覆盖八度（0..11 唯一）', () {
    expect(rootNames.length, 12);
    expect(rootNames.values.toSet().length, 12);
    expect(rootNames['C'], 0);
    expect(rootNames['A'], 9);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/chord_catalog_test.dart`
Expected: FAIL（chord_catalog.dart 不存在）

- [ ] **Step 3: 实现** `lib/core/music/chord_catalog.dart`

```dart
import 'chord_parser.dart';

/// 和弦分类浏览目录（设计文档 §13.1）：新手查阅路径。
/// 子类音程与 chord_parser 的 _qualities 表同源——一致性由
/// chord_catalog_test 的交叉验证钉住（拼名走 parseChord 断言相同）。
class ChordSubtype {
  const ChordSubtype(this.suffix, this.name, this.intervals);
  final String suffix; // 拼名后缀（'' 为大三）
  final String name; // 中文显示名
  final List<int> intervals; // 音程（与 _qualities 同值）
}

class ChordCategory {
  const ChordCategory(this.name, this.subtypes);
  final String name;
  final List<ChordSubtype> subtypes;
}

const _triads = ChordCategory('三和弦', [
  ChordSubtype('', '大三', [0, 4, 7]),
  ChordSubtype('m', '小三', [0, 3, 7]),
  ChordSubtype('aug', '增三', [0, 4, 8]),
  ChordSubtype('dim', '减三', [0, 3, 6]),
  ChordSubtype('5', '五度', [0, 7]),
]);

const _sevenths = ChordCategory('七和弦', [
  ChordSubtype('7', '属七', [0, 4, 7, 10]),
  ChordSubtype('m7', '小七', [0, 3, 7, 10]),
  ChordSubtype('maj7', '大七', [0, 4, 7, 11]),
  ChordSubtype('m7b5', '半减七', [0, 3, 6, 10]),
]);

const _suspended = ChordCategory('挂留和弦', [
  ChordSubtype('sus2', '挂二', [0, 2, 7]),
  ChordSubtype('sus4', '挂四', [0, 5, 7]),
]);

const _extended = ChordCategory('加音与扩展', [
  ChordSubtype('add9', '加九', [0, 4, 7, 14]),
  ChordSubtype('6', '六和弦', [0, 4, 7, 9]),
  ChordSubtype('m6', '小六', [0, 3, 7, 9]),
  ChordSubtype('9', '属九', [0, 4, 7, 10, 14]),
  ChordSubtype('m9', '小九', [0, 3, 7, 10, 14]),
]);

const chordCategories = [_triads, _sevenths, _suspended, _extended];

/// 根音表（浏览用，音名 → pitch class）。
const rootNames = <String, int>{
  'C': 0, 'C#': 1, 'D': 2, 'D#': 3, 'E': 4, 'F': 5,
  'F#': 6, 'G': 7, 'G#': 8, 'A': 9, 'A#': 10, 'B': 11,
};

/// 浏览选中 → ParsedChord（不经字符串解析；目录与解析器一致性由测试钉住）。
ParsedChord browseChord(int rootPc, String suffix) {
  for (final cat in chordCategories) {
    for (final sub in cat.subtypes) {
      if (sub.suffix == suffix) return ParsedChord(rootPc, sub.intervals);
    }
  }
  throw ArgumentError('未知和弦类型: $suffix');
}

/// 拼和弦显示名（如 'Am7'；大三空后缀只显根音）。
String chordDisplayName(int rootPc, String suffix) {
  final root = rootNames.entries
      .firstWhere((e) => e.value == rootPc)
      .key;
  return root + suffix;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/chord_catalog_test.dart`
Expected: PASS；全量 + analyze。

- [ ] **Step 5: Commit**

```
git add lib/core/music/chord_catalog.dart test/chord_catalog_test.dart
git commit -m "feat: 和弦分类浏览目录（17 种四分类交叉验证，13.1）"
```

---

### Task B: 和弦库浏览模式 UI

**Files:**
- Modify: `lib/ui/toolbox/chord_page.dart`
- Test: `test/chord_browse_test.dart`

- [ ] **Step 1: 实现浏览模式**（`chord_page.dart`）

新增状态字段：

```dart
  bool _browseMode = false;
  String _categoryName = '三和弦';
  String _suffix = ''; // 当前子类后缀（默认大三）
  int? _rootPc; // 选定根音；null = 未选
```

`_search` 抽公共查询（输入/浏览共用）：

```dart
  /// 公共查询：ParsedChord → 指法（输入解析与浏览枚举两条路汇于此）。
  void _query(ParsedChord c) {
    final state = context.read<TuningState>();
    _voicings = FingeringGenerator(state.current.strings)
        .generate(rootPc: c.rootPc, toneClasses: chordToneClasses(c));
    _error = null;
    setState(() {});
  }
```

原 `_search` 改为 `_search()` 内 `parseChord` + try/catch → `_query(c)`（错误处理保留输入模式）；新增：

```dart
  void _browseSelect(int rootPc) {
    setState(() => _rootPc = rootPc);
    // 选定根音即查询（类型已必有默认）；名字写回输入框，切回输入模式沿用。
    _input.text = chordDisplayName(rootPc, _suffix);
    _query(browseChord(rootPc, _suffix));
  }

  void _selectSubtype(String suffix) {
    setState(() => _suffix = suffix);
    final root = _rootPc;
    if (root != null) {
      _input.text = chordDisplayName(root, suffix);
      _query(browseChord(root, suffix));
    }
  }

  void _selectCategory(String name) {
    setState(() {
      _categoryName = name;
      // 换大类默认选其第一个子类。
      _suffix = chordCategories
          .firstWhere((c) => c.name == name)
          .subtypes
          .first
          .suffix;
    });
    if (_rootPc != null) _selectSubtype(_suffix);
  }
```

`_onTuningChanged` 的重查需兼容浏览模式：抽 `_research()`——浏览模式按 `_rootPc/_suffix` 重查、输入模式按 `_search()`（若无 voicings 且未查询过则跳过）。最简实现：

```dart
  void _onTuningChanged() {
    if (_tuning.current.id == _lastTuningId) return;
    _lastTuningId = _tuning.current.id;
    if (_browseMode && _rootPc != null) {
      _query(browseChord(_rootPc!, _suffix));
    } else if (_voicings.isNotEmpty || _error != null) {
      _search();
    }
  }
```

UI（build 内输入行之前加模式切换，切换后输入行换成浏览面板）：

```dart
        // 模式切换：输入（乐手）/ 浏览（新手查阅，13.1）。
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('输入')),
            ButtonSegment(value: true, label: Text('浏览')),
          ],
          selected: {_browseMode},
          onSelectionChanged: (s) =>
              setState(() => _browseMode = s.first),
        ),
        const SizedBox(height: 12),
        if (!_browseMode)
          Row(children: [ /* 原输入行整体不动 */ ]),
        if (_browseMode) ..._browsePanel(palette),
```

`_browsePanel`（三行 Wrap，选择即查）：

```dart
  List<Widget> _browsePanel(GuitarBarPalette p) {
    final category = chordCategories
        .firstWhere((c) => c.name == _categoryName);
    return [
      Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final cat in chordCategories)
              ChoiceChip(
                  label: Text(cat.name),
                  selected: cat.name == _categoryName,
                  onSelected: (_) => _selectCategory(cat.name)),
          ]),
      const SizedBox(height: 8),
      Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final sub in category.subtypes)
              ChoiceChip(
                  label: Text(sub.name),
                  selected: sub.suffix == _suffix,
                  onSelected: (_) => _selectSubtype(sub.suffix)),
          ]),
      const SizedBox(height: 8),
      Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final e in rootNames.entries)
              ChoiceChip(
                  label: Text(e.key),
                  selected: _rootPc == e.value,
                  onSelected: (_) => _browseSelect(e.value)),
          ]),
      const SizedBox(height: 4),
      if (_rootPc == null)
        Text('选定根音后显示指法',
            style: TextStyle(fontSize: 12, color: p.muted)),
      const SizedBox(height: 8),
    ];
  }
```

import 补 `import '../../core/music/chord_catalog.dart';`。

- [ ] **Step 2: widget 测试** `test/chord_browse_test.dart`

```dart
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/data/database.dart';
import 'package:guitarbar/state/tuning_state.dart';
import 'package:guitarbar/ui/theme.dart';
import 'package:guitarbar/ui/toolbox/chord_page.dart';
import 'package:provider/provider.dart';

void main() {
  // TuningState 依赖 AppDatabase（自定义预设表）；内置标准调弦即首预设。
  testWidgets('浏览模式：切到浏览 → 选根音 C 出指法卡', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final tuning = TuningState(db)..load();
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<TuningState>.value(value: tuning),
    ], child: MaterialApp(
        theme: GuitarBarTheme.light(), home: const ChordPage())));
    await tester.pumpAndSettle();
    // 切浏览。
    await tester.tap(find.text('浏览'));
    await tester.pumpAndSettle();
    // 默认三和弦/大三 + 选根音 C → 查询出指法（C 大三至少 1 个指法）。
    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle();
    expect(find.byType(Card), isNotEmpty);
    // 输入框同步显示 C。
    expect(find.widgetWithText(TextField, 'C'), findsOneWidget);
  });

  testWidgets('浏览模式：换子类到小三 → 输入框同步 Cm', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final tuning = TuningState(db)..load();
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<TuningState>.value(value: tuning),
    ], child: MaterialApp(
        theme: GuitarBarTheme.light(), home: const ChordPage())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('浏览'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('小三'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Cm'), findsOneWidget);
  });
}
```

（若 TuningState 构造/加载与测试环境有出入——参考 `test/tuning_state_test.dart` 既有写法对齐；SoundEngine init 失败不影响指法渲染只禁试听。）

- [ ] **Step 3: 全量验证**

Run: `flutter test`（全量）+ `flutter analyze`
Expected: 全绿 / No issues

- [ ] **Step 4: Commit**

```
git add lib/ui/toolbox/chord_page.dart test/chord_browse_test.dart
git commit -m "feat: 和弦库浏览模式（分类树×根音点选出指法，13.1）"
```

---

## 收尾

- [ ] 全量测试 + analyze
- [ ] 走查清单补 acceptance.md：浏览模式选类型+根音出指法/名字写回输入框（切回输入模式沿用）/调弦联动在浏览模式重查/四试听可用
- [ ] todo.md 勾选 13.1
