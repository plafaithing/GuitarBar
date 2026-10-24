# GuitarBar 第一期「练琴工具箱」实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一期练琴工具箱：调音器（20 组预设+自定义不限量+A4 校准）、和弦库（算法指法+琶音/扫弦试听）、指板音阶（随调弦联动）、节拍器（细分拍+Tap Tempo+音频时钟调度）、练琴打卡（全局计时+热力图），Windows 打样（iPad 4:3 比例窗口）。

**Architecture:** 四层——UI（3 tab）/ 业务逻辑（纯 Dart 乐理与算法，全部单测）/ 音频引擎（mic_stream 输入 + flutter_pcm_sound 输出，YIN 检测）/ 数据层（drift 三表 + JSON 导出导入）。

**Tech Stack:** Flutter (Windows) · provider/ChangeNotifier · drift + sqlite3_flutter_libs · mic_stream · flutter_pcm_sound · wakelock_plus · window_manager · file_selector

**Spec:** `docs/superpowers/specs/2026-10-23-practice-toolbox-design.md`（验收标准 13 条）

**平台备注:** 本计划只在 Windows 执行。iOS 侧 `flutter create --platforms ios .` 留到有 Mac/云 Mac 时（设计文档 3.1 节）；lib/ 不写任何平台专属 API，差异全走插件。

**依赖风险提示:** `mic_stream` 与 `flutter_pcm_sound` 的 API 以所装版本的 README 为准，若与计划中调用签名有出入，按 README 微调调用处（仅允许调整这两处接线，算法与纯逻辑代码不许改）。

---

## 文件结构

```
lib/
├── main.dart                        # 入口：window_manager、providers、RootPage
├── core/music/note.dart             # Note 解析 / midi / 频率 / centsOff
├── core/music/tuning.dart           # TuningGroup / TuningPreset
├── core/music/builtin_tunings.dart  # 内置 20 预设（5/4/7/4 分组）
├── core/music/scale.dart            # 音阶公式 + 指板网格
├── core/music/chord_parser.dart     # 和弦名 → 根音+音程
├── core/music/fingering.dart        # 指法搜索 + 评分
├── audio/pitch_detector.dart        # YIN
├── audio/mic_pitch_stream.dart      # 字节流 → 滑窗 → 音高流
├── audio/synth.dart                 # click / pluck / 和弦 PCM 混合
├── audio/pcm_player.dart            # flutter_pcm_sound 封装
├── audio/metronome_engine.dart      # 纯调度 + 引擎 + tap tempo
├── data/database.dart               # drift 三表 + AppDatabase（+database.g.dart 生成）
├── data/connection/open.dart        # 文件连接
├── data/backup.dart                 # JSON 导出/导入
├── state/tuning_state.dart          # 当前调弦 + A4 + 自定义预设管理
├── state/practice_timer.dart        # 全局练习计时 + wakelock
├── core/stats.dart                  # 打卡统计纯函数（streak/热力）
└── ui/
    ├── root.dart                    # 3 tab + 宽屏 NavigationRail + 顶栏计时
    ├── tuner/tuner_page.dart        # 双模式调音器 + 分组预设 + A4
    ├── toolbox/toolbox_page.dart    # 工具箱入口卡片
    ├── toolbox/chord_page.dart      # 和弦库
    ├── toolbox/fretboard_page.dart  # 指板音阶
    ├── toolbox/metronome_page.dart  # 节拍器
    └── profile/profile_page.dart    # 打卡 + 统计 + 导出导入
test/                                # 与 lib 同构的 _test.dart
```

---

### Task 1: 项目脚手架与依赖

**Files:**
- Create: Flutter 工程全部（`flutter create` 生成）
- Modify: `lib/main.dart`、`lib/ui/root.dart`
- Test: `flutter analyze`

- [ ] **Step 1: 生成 Flutter 工程**

在仓库根目录（已有 docs/、tasks/、.git）执行：

```bash
flutter --version
flutter create --project-name guitarbar --platforms windows --org com.guitarbar .
```

Expected: 生成 lib/ test/ windows/ pubspec.yaml 等；`flutter analyze` 通过（0 errors）。

- [ ] **Step 2: 添加依赖**

```bash
flutter pub add provider drift sqlite3_flutter_libs path_provider path mic_stream flutter_pcm_sound wakelock_plus window_manager file_selector intl
flutter pub add dev:drift_dev dev:build_runner
flutter pub get
```

Expected: pubspec.yaml 出现全部依赖；无版本冲突报错。

- [ ] **Step 3: 写入口 `lib/main.dart`（整文件替换）**

```dart
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'ui/root.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1024, 768), // iPad 4:3
    minimumSize: Size(768, 576),
    title: 'GuitarBar',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(const GuitarBarApp());
}

class GuitarBarApp extends StatelessWidget {
  const GuitarBarApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'GuitarBar',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: const RootPage(),
      );
}
```

- [ ] **Step 4: 写 `lib/ui/root.dart`（整文件）**

```dart
import 'package:flutter/material.dart';

class RootPage extends StatefulWidget {
  const RootPage({super.key});
  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _tab = 0;
  static const _titles = ['调音器', '工具箱', '个人中心'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final body = IndexedStack(index: _tab, children: [
        _Placeholder(_titles[0]), _Placeholder(_titles[1]), _Placeholder(_titles[2]),
      ]);
      return Scaffold(
        appBar: AppBar(title: Text(_titles[_tab])),
        body: wide
            ? Row(children: [
                NavigationRail(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(icon: Icon(Icons.tune), label: Text('调音器')),
                    NavigationRailDestination(icon: Icon(Icons.home_repair_service), label: Text('工具箱')),
                    NavigationRailDestination(icon: Icon(Icons.person), label: Text('个人中心')),
                  ],
                ),
                Expanded(child: body),
              ])
            : body,
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: '调音器'),
                  NavigationDestination(icon: Icon(Icons.home_repair_service_outlined), selectedIcon: Icon(Icons.home_repair_service), label: '工具箱'),
                  NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '个人中心'),
                ],
              ),
      );
    });
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(child: Text(text));
}
```

- [ ] **Step 5: 冒烟运行**

```bash
flutter analyze
flutter run -d windows
```

Expected: analyze 0 errors；窗口 1024×768，3 个 tab 可切换，宽窗口（拉伸 >900px）出现左侧导航栏。

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: Flutter 脚手架、依赖与三 tab 应用骨架"
```

---

### Task 2: 乐理核心 Note

**Files:**
- Create: `lib/core/music/note.dart`
- Test: `test/note_test.dart`

- [ ] **Step 1: 写失败测试 `test/note_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/music/note.dart';

void main() {
  test('解析科学记谱', () {
    expect(Note.parse('E2').midi, 40);
    expect(Note.parse('Eb2').midi, 39);
    expect(Note.parse('C#4').midi, 61);
    expect(Note.parse('B1').midi, 35);
    expect(Note.parse('A1').midi, 33);
    expect(() => Note.parse('H2'), throwsArgumentError);
  });

  test('名称往返', () {
    expect(Note.parse('E2').name, 'E2');
    expect(Note.parse('Eb2').name, 'D#2');
    expect(Note.parse('Eb2').label(flats: true), 'Eb2');
  });

  test('频率（A4=440）', () {
    expect(Note.parse('A4').frequency(), closeTo(440, 0.001));
    expect(Note.parse('E2').frequency(), closeTo(82.407, 0.01));
    expect(Note.parse('E4').frequency(), closeTo(329.628, 0.01));
  });

  test('频率随 A4 校准', () {
    expect(Note.parse('A4').frequency(435), closeTo(435, 0.001));
  });

  test('centsOff', () {
    expect(centsOff(440.0, 440.0), 0);
    expect(centsOff(466.16, 440.0), closeTo(100, 0.5));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/note_test.dart`
Expected: FAIL（note.dart 不存在）

- [ ] **Step 3: 实现 `lib/core/music/note.dart`**

```dart
import 'dart:math' as math;

class Note {
  final int midi;
  const Note(this.midi);

  static const _sharp = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  static const _flat = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];
  static const _base = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};

  int get pitchClass => midi % 12;
  int get octave => (midi ~/ 12) - 1;
  String get name => '${_sharp[pitchClass]}$octave';
  String label({bool flats = false}) =>
      '${(flats ? _flat : _sharp)[pitchClass]}$octave';

  static Note parse(String s) {
    final m = RegExp(r'^([A-Ga-g])([#b]?)(-?\d+)$').firstMatch(s.trim());
    if (m == null) throw ArgumentError('无效音名: $s');
    var pc = _base[m.group(1)!.toUpperCase()]!;
    if (m.group(2) == '#') pc += 1;
    if (m.group(2) == 'b') pc -= 1;
    return Note(pc + (int.parse(m.group(3)!) + 1) * 12);
  }

  double frequency([double a4 = 440.0]) =>
      a4 * math.pow(2, (midi - 69) / 12).toDouble();
}

int centsOff(double measured, double target) =>
    (1200 * (math.log(measured / target) / math.ln2)).round();
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/note_test.dart`
Expected: 全部 PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/music/note.dart test/note_test.dart
git commit -m "feat: Note 科学记谱解析与频率计算"
```

---

### Task 3: 调弦预设模型 + 内置 20 组

**Files:**
- Create: `lib/core/music/tuning.dart`、`lib/core/music/builtin_tunings.dart`
- Test: `test/tuning_test.dart`

- [ ] **Step 1: 写失败测试 `test/tuning_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/music/builtin_tunings.dart';
import 'package:guitarbar/core/music/tuning.dart';

void main() {
  test('内置 20 组，分组 5/4/7/4', () {
    expect(builtinTunings.length, 20);
    int count(TuningGroup g) => builtinTunings.where((t) => t.group == g).length;
    expect(count(TuningGroup.standardDown), 5);
    expect(count(TuningGroup.drop), 4);
    expect(count(TuningGroup.open), 7);
    expect(count(TuningGroup.special), 4);
  });

  test('Standard = E2 A2 D3 G3 B3 E4', () {
    final std = builtinTunings.firstWhere((t) => t.name == 'Standard');
    expect(std.strings.map((n) => n.name).toList(),
        ['E2', 'A2', 'D3', 'G3', 'B3', 'E4']);
    expect(std.isBuiltIn, isTrue);
  });

  test('Drop D 六弦为 D2，其余同 Standard', () {
    final d = builtinTunings.firstWhere((t) => t.name == 'Drop D');
    expect(d.strings[0].name, 'D2');
    expect(d.strings[1].name, 'A2');
  });

  test('名称无重复、每弦数 6', () {
    expect(builtinTunings.map((t) => t.name).toSet().length, 20);
    for (final t in builtinTunings) {
      expect(t.strings.length, 6, reason: t.name);
    }
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/tuning_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现 `lib/core/music/tuning.dart`**

```dart
import 'note.dart';

enum TuningGroup { standardDown, drop, open, special, custom }

extension TuningGroupLabel on TuningGroup {
  String get label => switch (this) {
        TuningGroup.standardDown => '标准/降调',
        TuningGroup.drop => 'Drop',
        TuningGroup.open => 'Open',
        TuningGroup.special => '特殊',
        TuningGroup.custom => '自定义',
      };
}

class TuningPreset {
  final String id;
  final String name;
  final List<Note> strings; // 低音弦 → 高音弦
  final TuningGroup group;
  final bool isBuiltIn;

  const TuningPreset({
    required this.id,
    required this.name,
    required this.strings,
    required this.group,
    this.isBuiltIn = false,
  });

  TuningPreset copyWith({String? name, List<Note>? strings, TuningGroup? group}) =>
      TuningPreset(
        id: id,
        name: name ?? this.name,
        strings: strings ?? this.strings,
        group: group ?? this.group,
        isBuiltIn: isBuiltIn,
      );
}
```

- [ ] **Step 4: 实现 `lib/core/music/builtin_tunings.dart`（音高严格按设计文档 5.1 表）**

```dart
import 'note.dart';
import 'tuning.dart';

TuningPreset _t(String name, TuningGroup g, List<String> notes) => TuningPreset(
      id: 'builtin-$name',
      name: name,
      strings: notes.map(Note.parse).toList(),
      group: g,
      isBuiltIn: true,
    );

final List<TuningPreset> builtinTunings = [
  // 标准/降调
  _t('Standard', TuningGroup.standardDown, ['E2', 'A2', 'D3', 'G3', 'B3', 'E4']),
  _t('Half Step Down', TuningGroup.standardDown, ['Eb2', 'Ab2', 'Db3', 'Gb3', 'Bb3', 'Eb4']),
  _t('Full Step Down', TuningGroup.standardDown, ['D2', 'G2', 'C3', 'F3', 'A3', 'D4']),
  _t('1.5 Steps Down', TuningGroup.standardDown, ['C#2', 'F#2', 'B2', 'E3', 'G#3', 'C#4']),
  _t('Two Steps Down', TuningGroup.standardDown, ['C2', 'F2', 'Bb2', 'Eb3', 'G3', 'C4']),
  // Drop
  _t('Drop D', TuningGroup.drop, ['D2', 'A2', 'D3', 'G3', 'B3', 'E4']),
  _t('Drop C', TuningGroup.drop, ['C2', 'G2', 'C3', 'F3', 'A3', 'D4']),
  _t('Drop B', TuningGroup.drop, ['B1', 'F#2', 'B2', 'E3', 'G#3', 'C#4']),
  _t('Drop A', TuningGroup.drop, ['A1', 'E2', 'A2', 'D3', 'F#3', 'B3']),
  // Open
  _t('Open D', TuningGroup.open, ['D2', 'A2', 'D3', 'F#3', 'A3', 'D4']),
  _t('Open E', TuningGroup.open, ['E2', 'B2', 'E3', 'G#3', 'B3', 'E4']),
  _t('Open G', TuningGroup.open, ['D2', 'G2', 'D3', 'G3', 'B3', 'D4']),
  _t('Open A', TuningGroup.open, ['E2', 'A2', 'E3', 'A3', 'C#4', 'E4']),
  _t('Open C', TuningGroup.open, ['C2', 'G2', 'C3', 'G3', 'C4', 'E4']),
  _t('Open F', TuningGroup.open, ['F2', 'A2', 'C3', 'F3', 'A3', 'F4']),
  _t('Open D Minor', TuningGroup.open, ['D2', 'A2', 'D3', 'F3', 'A3', 'D4']),
  // 特殊
  _t('DADGAD', TuningGroup.special, ['D2', 'A2', 'D3', 'G3', 'A3', 'D4']),
  _t('Modal D', TuningGroup.special, ['D2', 'A2', 'D3', 'E3', 'A3', 'D4']),
  _t('Nashville (High Strung)', TuningGroup.special, ['E3', 'A3', 'D4', 'G4', 'B4', 'E5']),
  _t('All Fourths', TuningGroup.special, ['E2', 'A2', 'D3', 'G3', 'C4', 'F4']),
];
```

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/tuning_test.dart`
Expected: 全部 PASS

- [ ] **Step 6: Commit**

```bash
git add lib/core/music/tuning.dart lib/core/music/builtin_tunings.dart test/tuning_test.dart
git commit -m "feat: 调弦模型与内置 20 组分组预设"
```

---

### Task 4: 音阶引擎

**Files:**
- Create: `lib/core/music/scale.dart`
- Test: `test/scale_test.dart`

- [ ] **Step 1: 写失败测试 `test/scale_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/music/note.dart';
import 'package:guitarbar/core/music/scale.dart';
import 'package:guitarbar/core/music/builtin_tunings.dart';

void main() {
  test('大调音程', () {
    final pcs = scalePitchClasses(0, ScaleType.major); // C 大调
    expect(pcs, [0, 2, 4, 5, 7, 9, 11]);
  });

  test('五声与布鲁斯', () {
    expect(scalePitchClasses(9, ScaleType.minorPentatonic), [9, 0, 2, 5, 7]); // Am 五声
    expect(scalePitchClasses(4, ScaleType.blues).length, 6);
  });

  test('指板网格：Standard C 大调', () {
    final std = builtinTunings.firstWhere((t) => t.name == 'Standard');
    final grid = fretboardGrid(std.strings, 0, ScaleType.major, frets: 12);
    expect(grid[0][8], 48); // 6 弦 8 品 = C3
    expect(grid[1][3], 48); // 5 弦 3 品 = C3
    expect(grid[0][0], null); // E 空弦不是 C
  });

  test('Drop D 下 6 弦空弦是 D', () {
    final dropD = builtinTunings.firstWhere((t) => t.name == 'Drop D');
    final grid = fretboardGrid(dropD.strings, 2, ScaleType.major, frets: 12); // D 大调
    expect(grid[0][0], Note.parse('D2').midi);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/scale_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现 `lib/core/music/scale.dart`**

```dart
import 'note.dart';
import 'tuning.dart';

enum ScaleType {
  major('大调', [0, 2, 4, 5, 7, 9, 11]),
  naturalMinor('自然小调', [0, 2, 3, 5, 7, 8, 10]),
  majorPentatonic('大调五声', [0, 2, 4, 7, 9]),
  minorPentatonic('小调五声', [0, 3, 5, 7, 10]),
  blues('布鲁斯', [0, 3, 5, 6, 7, 10]);

  final String label;
  final List<int> intervals;
  const ScaleType(this.label, this.intervals);
}

List<int> scalePitchClasses(int rootPc, ScaleType type) =>
    type.intervals.map((i) => (rootPc + i) % 12).toList();

/// grid[弦索引][品] = 该品 midi（在音阶内）或 null
List<List<int?>> fretboardGrid(
    List<Note> tuning, int rootPc, ScaleType type,
    {int frets = 12}) {
  final pcs = scalePitchClasses(rootPc, type).toSet();
  return [
    for (final s in tuning)
      [
        for (var f = 0; f <= frets; f++)
          pcs.contains((s.midi + f) % 12) ? s.midi + f : null
      ]
  ];
}

const solfege = ['Do', 'Re', 'Mi', 'Fa', 'Sol', 'La', 'Si'];

/// 唱名下标（大调体系内按根音起算），不在音阶内返回 -1
int solfegeIndex(int rootPc, int pitchClass) {
  final idx = scalePitchClasses(rootPc, ScaleType.major)
      .toList()
      .indexOf(pitchClass);
  return idx;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/scale_test.dart`
Expected: 全部 PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/music/scale.dart test/scale_test.dart
git commit -m "feat: 音阶公式与指板网格引擎"
```

---

### Task 5: 和弦解析 + 指法生成

**Files:**
- Create: `lib/core/music/chord_parser.dart`、`lib/core/music/fingering.dart`
- Test: `test/chord_test.dart`

- [ ] **Step 1: 写失败测试 `test/chord_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/music/builtin_tunings.dart';
import 'package:guitarbar/core/music/chord_parser.dart';
import 'package:guitarbar/core/music/fingering.dart';

void main() {
  test('解析和弦名', () {
    expect(parseChord('C').intervals, [0, 4, 7]);
    expect(parseChord('Am7').rootPc, 9);
    expect(parseChord('Am7').intervals, [0, 3, 7, 10]);
    expect(parseChord('F#m7b5').rootPc, 6);
    expect(parseChord('F#m7b5').intervals, [0, 3, 6, 10]);
    expect(parseChord('Dsus4').rootPc, 2);
    expect(() => parseChord('X13'), throwsArgumentError);
  });

  TuningPreset get std =>
      builtinTunings.firstWhere((t) => t.name == 'Standard');

  test('C 大三和弦含 x32010', () {
    final gen = FingeringGenerator(std.strings);
    final c = parseChord('C');
    final v = gen.generate(rootPc: c.rootPc, toneClasses: chordToneClasses(c));
    expect(v.map((x) => x.frets.join(',')), contains(',3,2,0,1,0'));
  });

  test('Am 含 x02210，Am7 含 x02010，E 含 022100', () {
    final gen = FingeringGenerator(std.strings);
    final am = parseChord('Am');
    expect(gen.generate(rootPc: am.rootPc, toneClasses: chordToneClasses(am))
        .map((x) => x.frets.join(',')), contains(',0,2,2,1,0'));
    final am7 = parseChord('Am7');
    expect(gen.generate(rootPc: am7.rootPc, toneClasses: chordToneClasses(am7))
        .map((x) => x.frets.join(',')), contains(',0,2,0,1,0'));
    final e = parseChord('E');
    expect(gen.generate(rootPc: e.rootPc, toneClasses: chordToneClasses(e))
        .map((x) => x.frets.join(',')), contains('0,2,2,1,0,0'));
  });

  test('所有返回指法不含和弦外音且非空（F#m7b5）', () {
    final gen = FingeringGenerator(std.strings);
    final f = parseChord('F#m7b5');
    final tones = chordToneClasses(f);
    final v = gen.generate(rootPc: f.rootPc, toneClasses: tones);
    expect(v, isNotEmpty);
    for (final vo in v) {
      final sounded = {
        for (var i = 0; i < 6; i++)
          if (vo.frets[i] != null) (std.strings[i].midi + vo.frets[i]!) % 12
      };
      expect(sounded.difference(tones), isEmpty, reason: vo.frets.join(','));
    }
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/chord_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现 `lib/core/music/chord_parser.dart`**

```dart
class ParsedChord {
  final int rootPc;
  final List<int> intervals;
  const ParsedChord(this.rootPc, this.intervals);
}

const _qualities = <String, List<int>>{
  '': [0, 4, 7], 'm': [0, 3, 7], '7': [0, 4, 7, 10], 'm7': [0, 3, 7, 10],
  'maj7': [0, 4, 7, 11], 'dim': [0, 3, 6], 'aug': [0, 4, 8],
  'sus2': [0, 2, 7], 'sus4': [0, 5, 7], 'm7b5': [0, 3, 6, 10],
  '6': [0, 4, 7, 9], 'm6': [0, 3, 7, 9], 'add9': [0, 4, 7, 14],
  '9': [0, 4, 7, 10, 14], 'm9': [0, 3, 7, 10, 14], '5': [0, 7],
};

const _basePc = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};

ParsedChord parseChord(String input) {
  final m = RegExp(r'^\s*([A-G][#b]?)(.*)$').firstMatch(input);
  if (m == null) throw ArgumentError('无法解析和弦: $input');
  final rootToken = m.group(1)!;
  var rootPc = _basePc[rootToken[0]]!;
  if (rootToken.endsWith('#')) rootPc += 1;
  if (rootToken.endsWith('b')) rootPc -= 1;
  rootPc = (rootPc % 12 + 12) % 12;
  final intervals = _qualities[m.group(2)!];
  if (intervals == null) throw ArgumentError('不支持和弦类型 "${m.group(2)}" ($input)');
  return ParsedChord(rootPc, intervals);
}
```

- [ ] **Step 4: 实现 `lib/core/music/fingering.dart`**

```dart
import 'chord_parser.dart';
import 'note.dart';
import 'tuning.dart';

Set<int> chordToneClasses(ParsedChord c) =>
    c.intervals.map((i) => (c.rootPc + i) % 12).toSet();

/// frets[0] = 6 弦（低音），null = 不弹
class ChordVoicing {
  final List<int?> frets;
  final int score; // 越小越易
  const ChordVoicing(this.frets, this.score);
}

class FingeringGenerator {
  final List<Note> tuning; // 低 → 高
  FingeringGenerator(this.tuning);

  /// 在所有 4 品宽窗口搜索，返回按易到难排序的前 top 个
  List<ChordVoicing> generate(
      {required int rootPc, required Set<int> toneClasses,
      int maxFret = 15, int top = 6}) {
    final found = <String, ChordVoicing>{};
    for (var w = 0; w + 3 <= maxFret; w++) {
      _search(w, rootPc, toneClasses, found);
    }
    final list = found.values.toList()
      ..sort((a, b) => a.score.compareTo(b.score));
    return list.take(top).toList();
  }

  void _search(int w, int rootPc, Set<int> tones, Map<String, ChordVoicing> out) {
    void dfs(int idx, List<int?> acc) {
      if (idx == 6) {
        final sounded = <int>{};
        for (var i = 0; i < 6; i++) {
          final f = acc[i];
          if (f != null) sounded.add((tuning[i].midi + f) % 12);
        }
        if (!sounded.containsAll(tones)) return;
        if (!sounded.every(tones.contains)) return;
        final fretted = acc.whereType<int>().where((f) => f > 0).toList();
        if (fretted.isEmpty) return;
        if (fretted.toSet().length > 4) return; // 横按同品算 1 指
        final hi = fretted.reduce((a, b) => a > b ? a : b);
        final lo = fretted.reduce((a, b) => a < b ? a : b);
        final span = hi - lo;
        if (span > 3) return;
        final key = acc.join(',');
        if (out.containsKey(key)) return;
        var score = w + 2 * acc.where((f) => f == null).length + span;
        var rootInBass = false;
        for (var i = 0; i < 3; i++) {
          final f = acc[i];
          if (f != null && (tuning[i].midi + f) % 12 == rootPc) {
            rootInBass = true;
            break;
          }
        }
        if (!rootInBass) score += 4;
        out[key] = ChordVoicing(List.of(acc), score);
        return;
      }
      for (final f in <int?>[null, 0, w, w + 1, w + 2, w + 3]) {
        acc.add(f);
        dfs(idx + 1, acc);
        acc.removeLast();
      }
    }

    dfs(0, <int?>[]);
  }
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/chord_test.dart`
Expected: 全部 PASS（指法搜索总量约 60 万节点，整体应在数秒内）

- [ ] **Step 6: Commit**

```bash
git add lib/core/music/chord_parser.dart lib/core/music/fingering.dart test/chord_test.dart
git commit -m "feat: 和弦名解析与调弦联动指法生成"
```

---

### Task 6: 数据层 drift 三表

**Files:**
- Create: `lib/data/database.dart`、`lib/data/connection/open.dart`
- Generate: `lib/data/database.g.dart`
- Test: `test/database_test.dart`

- [ ] **Step 1: 写失败测试 `test/database_test.dart`**

```dart
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/data/database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('打卡增删改查', () async {
    final id = await db.into(db.practiceSessions).insert(PracticeSessionsCompanion.insert(
        startedAt: DateTime(2026, 10, 25, 9),
        endedAt: DateTime(2026, 10, 25, 9, 30),
        durationSeconds: 1800));
    final rows = await db.select(db.practiceSessions).get();
    expect(rows.single.id, id);
    expect(rows.single.durationSeconds, 1800);
  });

  test('自定义调弦预设', () async {
    await db.into(db.tuningPresets).insert(
        TuningPresetsCompanion.insert(name: '我的调弦', notes: 'D2,A2,D3,G3,B3,E4'));
    final rows = await db.select(db.tuningPresets).get();
    expect(rows.single.name, '我的调弦');
    await (db.update(db.tuningPresets)..where((t) => t.id.equals(rows.single.id)))
        .write(TuningPresetsCompanion(name: const drift.Value('改名')));
    expect((await db.select(db.tuningPresets).get()).single.name, '改名');
    await (db.delete(db.tuningPresets)..where((t) => t.id.equals(rows.single.id))).go();
    expect(await db.select(db.tuningPresets).get(), isEmpty);
  });

  test('设置 upsert', () async {
    await db.into(db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(key: 'a4', value: '440'));
    await db.into(db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(key: 'a4', value: '435'));
    final row = await (db.select(db.settings)..where((t) => t.key.equals('a4'))).getSingle();
    expect(row.value, '435');
  });
}
```

- [ ] **Step 2: 实现 `lib/data/database.dart`**

```dart
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

@DriftDatabase(tables: [PracticeSessions, TuningPresets, Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;
}

LazyDatabase openConnection() => LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'guitarbar.sqlite'));
      return NativeDatabase(file);
    });
```

注意：`openConnection` 里的 `open.dart` 不再单独建文件，直接放 database.dart 底部（上面已含），删除计划中的 `lib/data/connection/open.dart`。

- [ ] **Step 3: 生成代码**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: 生成 `lib/data/database.g.dart`，无错误

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/database_test.dart`
Expected: 全部 PASS

- [ ] **Step 5: Commit**

```bash
git add lib/data test/database_test.dart
git commit -m "feat: drift 数据层三表（打卡/自定义调弦/设置）"
```

---

### Task 7: JSON 导出/导入

**Files:**
- Create: `lib/data/backup.dart`
- Test: `test/backup_test.dart`

- [ ] **Step 1: 写失败测试 `test/backup_test.dart`**

```dart
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/data/backup.dart';
import 'package:guitarbar/data/database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('导出 → 清空 → 导入，数据一致', () async {
    await db.into(db.practiceSessions).insert(PracticeSessionsCompanion.insert(
        startedAt: DateTime(2026, 10, 25, 9),
        endedAt: DateTime(2026, 10, 25, 9, 30),
        durationSeconds: 1800,
        note: const drift.Value('爬格子')));
    await db.into(db.tuningPresets).insert(
        TuningPresetsCompanion.insert(name: '我的调弦', notes: 'D2,A2,D3,G3,B3,E4'));
    await db.into(db.settings)
        .insertOnConflictUpdate(SettingsCompanion.insert(key: 'a4', value: '435'));

    final json = await exportToJson(db);
    await db.delete(db.practiceSessions).go();
    await db.delete(db.tuningPresets).go();
    await db.delete(db.settings).go();
    await importFromJson(db, json);

    expect((await db.select(db.practiceSessions).get()).single.note, '爬格子');
    expect((await db.select(db.tuningPresets).get()).single.notes, 'D2,A2,D3,G3,B3,E4');
    expect((await db.select(db.settings).get()).single.value, '435');
  });
}
```

- [ ] **Step 2: 实现 `lib/data/backup.dart`**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:file_selector/file_selector.dart';
import 'package:guitarbar/data/database.dart';

Future<Map<String, dynamic>> exportToJson(AppDatabase db) async {
  final sessions = await db.select(db.practiceSessions).get();
  final presets = await db.select(db.tuningPresets).get();
  final settings = await db.select(db.settings).get();
  return {
    'version': 1,
    'sessions': [
      for (final s in sessions)
        {
          'startedAt': s.startedAt.millisecondsSinceEpoch,
          'endedAt': s.endedAt.millisecondsSinceEpoch,
          'durationSeconds': s.durationSeconds,
          'note': s.note,
        }
    ],
    'presets': [
      for (final p in presets) {'name': p.name, 'notes': p.notes}
    ],
    'settings': {for (final s in settings) s.key: s.value},
  };
}

Future<void> importFromJson(AppDatabase db, Map<String, dynamic> json) async {
  await db.transaction(() async {
    await db.delete(db.practiceSessions).go();
    await db.delete(db.tuningPresets).go();
    await db.delete(db.settings).go();
    for (final s in (json['sessions'] as List).cast<Map>()) {
      await db.into(db.practiceSessions).insert(PracticeSessionsCompanion.insert(
          startedAt: DateTime.fromMillisecondsSinceEpoch(s['startedAt'] as int),
          endedAt: DateTime.fromMillisecondsSinceEpoch(s['endedAt'] as int),
          durationSeconds: s['durationSeconds'] as int,
          note: drift.Value(s['note'] as String?)));
    }
    for (final p in (json['presets'] as List).cast<Map>()) {
      await db.into(db.tuningPresets).insert(
          TuningPresetsCompanion.insert(name: p['name'] as String, notes: p['notes'] as String));
    }
    for (final e in (json['settings'] as Map).entries) {
      await db.into(db.settings)
          .insertOnConflictUpdate(SettingsCompanion.insert(key: e.key as String, value: e.value as String));
    }
  });
}

/// UI 用：导出到用户选择的文件
Future<void> exportToFile(AppDatabase db) async {
  final json = await exportToJson(db);
  final location = await getSaveLocation(
      suggestedName: 'guitarbar-backup-${DateTime.now().millisecondsSinceEpoch}.json');
  if (location == null) return;
  final f = XFile.fromData(utf8.encode(jsonEncode(json)),
      mimeType: 'application/json');
  await f.saveTo(location.path);
}

/// UI 用：从用户选择的文件导入
Future<void> importFromFile(AppDatabase db) async {
  final f = await openFile(acceptedTypeGroups: const [
    XTypeGroup(label: 'JSON', extensions: ['json'])
  ]);
  if (f == null) return;
  await importFromJson(db, jsonDecode(await f.readAsString()) as Map<String, dynamic>);
}
```

- [ ] **Step 3: 跑测试确认通过**

Run: `flutter test test/backup_test.dart`
Expected: PASS（`exportToFile/importFromFile` 涉及对话框，仅手动验证，测试覆盖纯转换）

- [ ] **Step 4: Commit**

```bash
git add lib/data/backup.dart test/backup_test.dart
git commit -m "feat: JSON 导出导入（数据迁移通道）"
```

---

### Task 8: YIN 音高检测

**Files:**
- Create: `lib/audio/pitch_detector.dart`
- Test: `test/pitch_detector_test.dart`

- [ ] **Step 1: 写失败测试 `test/pitch_detector_test.dart`**

```dart
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/pitch_detector.dart';

List<double> sine(double freq, int sampleRate, int n, {double amp = 0.8}) =>
    [for (var i = 0; i < n; i++) amp * math.sin(2 * math.pi * freq * i / sampleRate)];

void main() {
  const sr = 44100;
  test('检测低音 E2 ≈ 82.41 Hz', () {
    final f = detectPitch(sine(82.41, sr, 4096), sr);
    expect(f, isNotNull);
    expect(f!, closeTo(82.41, 1.0));
  });
  test('检测 E4 ≈ 329.63 Hz', () {
    final f = detectPitch(sine(329.63, sr, 4096), sr);
    expect(f!, closeTo(329.63, 1.0));
  });
  test('静音返回 null', () {
    expect(detectPitch(List.filled(4096, 0.0), sr), isNull);
  });
}
```

- [ ] **Step 2: 实现 `lib/audio/pitch_detector.dart`**

```dart
import 'dart:typed_data';

/// YIN 音高检测。输入 [-1,1] 归一化采样，返回 Hz 或 null（未检测到周期性）。
double? detectPitch(List<double> buf, int sampleRate, {double threshold = 0.15}) {
  final n = buf.length;
  if (n < 512) return null;
  final half = n ~/ 2;
  final diff = Float64List(half);
  for (var tau = 1; tau < half; tau++) {
    var sum = 0.0;
    for (var i = 0; i < half; i++) {
      final d = buf[i] - buf[i + tau];
      sum += d * d;
    }
    diff[tau] = sum;
  }
  final cmnd = Float64List(half);
  var running = 0.0;
  for (var tau = 1; tau < half; tau++) {
    running += diff[tau];
    cmnd[tau] = running == 0 ? double.nan : diff[tau] * tau / running;
  }
  var tauEst = -1;
  for (var tau = 2; tau < half - 1; tau++) {
    if (cmnd[tau] < threshold) {
      while (tau + 1 < half - 1 && cmnd[tau + 1] < cmnd[tau]) {
        tau++;
      }
      tauEst = tau;
      break;
    }
  }
  if (tauEst < 0) return null;
  final x0 = tauEst > 1 ? cmnd[tauEst - 1] : cmnd[tauEst];
  final x1 = cmnd[tauEst];
  final x2 = cmnd[tauEst + 1];
  final denom = 2 * (2 * x1 - x2 - x0);
  final better = denom == 0 ? tauEst.toDouble() : tauEst + (x2 - x0) / denom;
  if (better <= 0) return null;
  return sampleRate / better;
}
```

- [ ] **Step 3: 跑测试确认通过**

Run: `flutter test test/pitch_detector_test.dart`
Expected: 全部 PASS

- [ ] **Step 4: Commit**

```bash
git add lib/audio/pitch_detector.dart test/pitch_detector_test.dart
git commit -m "feat: YIN 音高检测算法"
```

---

### Task 9: 麦克风管线（滑窗 → 音高流）

**Files:**
- Create: `lib/audio/mic_pitch_stream.dart`
- Test: `test/window_accumulator_test.dart`

- [ ] **Step 1: 写失败测试 `test/window_accumulator_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/mic_pitch_stream.dart';

void main() {
  test('累计到 hop 出窗，窗口大小正确', () {
    final acc = PitchWindower(windowSamples: 10, hopSamples: 5);
    final windows = acc.add(List.generate(12, (i) => i.toDouble()));
    expect(windows.length, 1);
    expect(windows.single.length, 10);
    expect(windows.single.first, 0); // 最早样本在窗口头
    expect(acc.add(List.generate(5, (i) => 100 + i)).length, 1);
  });

  test('样本不足不出窗', () {
    final acc = PitchWindower(windowSamples: 10, hopSamples: 5);
    expect(acc.add(List.generate(4, (i) => i.toDouble())), isEmpty);
  });
}
```

- [ ] **Step 2: 实现 `lib/audio/mic_pitch_stream.dart`**

```dart
import 'dart:typed_data';

import 'package:mic_stream/mic_stream.dart';

import 'pitch_detector.dart';

/// 滑窗累积器：每新增 hopSamples 个样本，吐出一个末尾 windowSamples 大小的窗口
class PitchWindower {
  PitchWindower({required this.windowSamples, required this.hopSamples})
      : assert(hopSamples > 0 && windowSamples >= hopSamples);
  final int windowSamples;
  final int hopSamples;

  final List<double> _buf = [];
  int _sinceLast = 0;

  List<List<double>> add(Iterable<double> samples) {
    final out = <List<double>>[];
    for (final s in samples) {
      _buf.add(s);
      _sinceLast++;
      if (_sinceLast == hopSamples && _buf.length >= windowSamples) {
        out.add(List.of(_buf.sublist(_buf.length - windowSamples)));
        _sinceLast = 0;
      }
    }
    if (_buf.length > windowSamples * 4) {
      _buf.removeRange(0, _buf.length - windowSamples);
    }
    return out;
  }
}

/// 订阅麦克风，产出最新音高（Hz 或 null）
class MicPitchStream {
  Stream<double?>? _sub;

  Stream<double?> start({int sampleRate = 44100}) {
    _sub ??= MicStream.microphone(sampleRate: sampleRate)
        .map((chunk) {
          final i16 = Int16List.view(chunk.buffer, 0, chunk.length ~/ 2);
          return [for (final v in i16) v / 32768.0];
        })
        .transform(_WindowTransform(sampleRate));
    return _sub!;
  }

  void stop() => _sub = null;
}

class _WindowTransform
    extends StreamTransformerBase<List<double>, double?> {
  final int _sr;
  _WindowTransform(this._sr);

  @override
  Stream<double?> bind(Stream<List<double>> stream) {
    final acc = PitchWindower(windowSamples: 4096, hopSamples: 2048);
    late StreamController<double?> ctrl;
    ctrl = StreamController<double?>(
      onListen: () {
        stream.listen((chunk) {
          for (final w in acc.add(chunk)) {
            ctrl.add(detectPitch(w, _sr));
          }
        }, onDone: ctrl.close, onError: ctrl.addError);
      },
    );
    return ctrl.stream;
  }
}
```

- [ ] **Step 3: 跑测试确认通过**

Run: `flutter test test/window_accumulator_test.dart`
Expected: PASS

- [ ] **Step 4: Windows 真机冒烟**

写临时驱动（可放 `tool/mic_smoke.dart` 或直接在调音器页接入后验证，Task 12 会真实接 UI）：对麦克风弹一根空弦，日志能看到稳定频率（±2 Hz 抖动内）。

- [ ] **Step 5: Commit**

```bash
git add lib/audio/mic_pitch_stream.dart test/window_accumulator_test.dart
git commit -m "feat: 麦克风采样滑窗与音高流管线"
```

---

### Task 10: 声音合成（click / pluck / 和弦 PCM）+ PCM 播放器

**Files:**
- Create: `lib/audio/synth.dart`、`lib/audio/pcm_player.dart`
- Test: `test/synth_test.dart`

- [ ] **Step 1: 写失败测试 `test/synth_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/synth.dart';
import 'package:guitarbar/core/music/builtin_tunings.dart';
import 'package:guitarbar/core/music/fingering.dart';
import 'package:guitarbar/core/music/chord_parser.dart';

void main() {
  test('click 长度与衰减', () {
    final c = click(0);
    expect(c.length, 2646); // 0.06s * 44100
    expect(c.first, greaterThan(8000));
    expect(c.last.abs(), lessThan(1000)); // 已衰减
  });

  test('pluck 长度且非静音', () {
    final p = pluck(110.0);
    expect(p.length, 52920); // 1.2s * 44100
    expect(p.take(100).any((v) => v != 0), isTrue);
  });

  test('和弦 PCM：同时发声长度 = 单音长度', () {
    final std = builtinTunings.firstWhere((t) => t.name == 'Standard');
    final c = parseChord('C');
    final v = FingeringGenerator(std.strings)
        .generate(rootPc: c.rootPc, toneClasses: chordToneClasses(c))
        .first;
    final pcm = voicingPcm(std.strings, v.frets, PlayMode.pluckAll);
    expect(pcm.length, 52920);
    expect(pcm.any((x) => x != 0), isTrue);
  });

  test('琶音长度 = 单音 + 间隔*(音数-1)', () {
    final std = builtinTunings.firstWhere((t) => t.name == 'Standard');
    final c = parseChord('C');
    final v = FingeringGenerator(std.strings)
        .generate(rootPc: c.rootPc, toneClasses: chordToneClasses(c))
        .first;
    final count = v.frets.whereType<int>().length;
    final pcm = voicingPcm(std.strings, v.frets, PlayMode.arpeggio);
    expect(pcm.length, 52920 + 9702 * (count - 1)); // 0.22s * 44100 = 9702
  });
}
```

- [ ] **Step 2: 实现 `lib/audio/synth.dart`**

```dart
import 'dart:math' as math;
import 'dart:typed_data';

import '../core/music/fingering.dart';
import '../core/music/note.dart';

const _clickFreqs = [1000.0, 820.0, 620.0]; // 0 重音 / 1 强拍 / 2 弱拍

Int16List click(int kind, {int sampleRate = 44100}) {
  final n = (sampleRate * 0.06).round();
  final out = Int16List(n);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    out[i] = (0.9 * math.exp(-t * 60) * math.sin(2 * math.pi * _clickFreqs[kind] * t) * 32767)
        .round();
  }
  return out;
}

/// Karplus-Strong 拨弦合成
Int16List pluck(double freq, {int sampleRate = 44100, double seconds = 1.2}) {
  final n = (sampleRate * seconds).round();
  final delayLen = math.max(2, (sampleRate / freq).round());
  final ring = Float64List(delayLen);
  final rand = math.Random(42); // 固定种子，结果可复现
  for (var i = 0; i < delayLen; i++) {
    ring[i] = rand.nextDouble() * 2 - 1;
  }
  final out = Int16List(n);
  var idx = 0;
  for (var i = 0; i < n; i++) {
    final cur = ring[idx];
    ring[idx] = (cur + ring[(idx + 1) % delayLen]) * 0.5 * 0.996;
    out[i] = (cur * 32767 * 0.8).round().clamp(-32768, 32767).toInt();
    idx = (idx + 1) % delayLen;
  }
  return out;
}

enum PlayMode { pluckAll, arpeggio, strumDown, strumUp }

/// 按指法发声：同时 / 琶音 / 下扫 / 上扫
Int16List voicingPcm(List<Note> tuning, List<int?> frets, PlayMode mode,
    {int sampleRate = 44100, double a4 = 440}) {
  final freqs = <double>[
    for (var i = 0; i < 6; i++)
      if (frets[i] != null) Note(tuning[i].midi + frets[i]!).frequency(a4)
  ];
  if (freqs.isEmpty) return Int16List(0);
  const arpStagger = 0.22, strumStagger = 0.025;
  final staggerSamples = switch (mode) {
    PlayMode.pluckAll => 0,
    PlayMode.arpeggio => (sampleRate * arpStagger).round(),
    PlayMode.strumDown => (sampleRate * strumStagger).round(),
    PlayMode.strumUp => (sampleRate * strumStagger).round(),
  };
  final total = 52920 + staggerSamples * (freqs.length - 1);
  final mix = Float64List(total);
  for (var k = 0; k < freqs.length; k++) {
    final pcm = pluck(freqs[k], sampleRate: sampleRate);
    final rev = mode == PlayMode.strumUp;
    final off = staggerSamples * (rev ? freqs.length - 1 - k : k);
    for (var i = 0; i < pcm.length; i++) {
      mix[off + i] += pcm[i] / 32768.0;
    }
  }
  return Int16List.fromList(
      [for (final v in mix) (v.clamp(-1.0, 1.0) * 32767).round()]);
}
```

- [ ] **Step 3: 实现 `lib/audio/pcm_player.dart`**

```dart
import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

/// flutter_pcm_sound 封装：维护已喂入样本计数，暴露帧渲染回调
class PcmPlayer {
  int _fed = 0;
  int sampleRate = 44100;
  void Function(int playedSamples)? onFrame;

  Future<void> setup({int sampleRate = 44100}) async {
    this.sampleRate = sampleRate;
    _fed = 0;
    await FlutterPcmSound.setup(sampleRate: sampleRate, channelCount: 1);
    await FlutterPcmSound.setFeedThreshold(4096);
    FlutterPcmSound.setFrameRenderedCallback((event) => onFrame?.call(event.frame));
  }

  Future<void> feed(Int16List pcm) async {
    _fed += pcm.length;
    await FlutterPcmSound.feed(pcm);
  }

  int get fedSamples => _fed;

  Future<void> start() => FlutterPcmSound.start();

  Future<void> stop() async {
    await FlutterPcmSound.release();
    _fed = 0;
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/synth_test.dart`
Expected: 全部 PASS

- [ ] **Step 5: Commit**

```bash
git add lib/audio/synth.dart lib/audio/pcm_player.dart test/synth_test.dart
git commit -m "feat: click/pluck/和弦 PCM 合成与播放器封装"
```

---

### Task 11: 节拍器调度（纯逻辑 TDD）+ 引擎接线

**Files:**
- Create: `lib/audio/metronome_engine.dart`
- Test: `test/metronome_test.dart`

- [ ] **Step 1: 写失败测试 `test/metronome_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/metronome_engine.dart';

void main() {
  const sr = 44100;
  test('120bpm 4/4 二细分：tick 间隔与重音', () {
    final cfg = const MetronomeConfig(bpm: 120, beatsPerBar: 4, subdivision: 2);
    final ticks = scheduleTicks(cfg: cfg, startSample: 0, tickCount: 9, sampleRate: sr);
    expect(ticks[0].kind, 0); // 小节头重音
    expect(ticks[0].sample, 0);
    expect(ticks[1].kind, 2); // 弱拍（细分）
    expect(ticks[1].sample, 11025); // 0.25s
    expect(ticks[2].kind, 1); // 强拍（非小节头正拍）
    expect(ticks[2].sample, 22050);
    expect(ticks[8].kind, 0); // 下一个小节头
  });

  test('6/8 单细分：第 6 拍回到重音', () {
    final cfg = const MetronomeConfig(bpm: 120, beatsPerBar: 6, subdivision: 1);
    final ticks = scheduleTicks(cfg: cfg, startSample: 0, tickCount: 7, sampleRate: sr);
    expect(ticks[6].kind, 0);
  });

  test('bpmFromTaps', () {
    final base = DateTime(2026, 10, 25);
    final taps = [base, base.add(const Duration(milliseconds: 500)),
        base.add(const Duration(seconds: 1)),
        base.add(const Duration(milliseconds: 1500))];
    expect(bpmFromTaps(taps), closeTo(120, 0.1));
    expect(bpmFromTaps(taps.sublist(0, 1)), 0);
  });

  test('tap 间隔超 2 秒被忽略', () {
    final base = DateTime(2026, 10, 25);
    final taps = [base, base.add(const Duration(milliseconds: 500)),
        base.add(const Duration(seconds: 5)),
        base.add(const Duration(seconds: 5, milliseconds: 500))];
    expect(bpmFromTaps(taps), closeTo(120, 0.1)); // 只用最后两个
  });
}
```

- [ ] **Step 2: 实现纯逻辑 + 引擎 `lib/audio/metronome_engine.dart`**

```dart
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'pcm_player.dart';
import 'synth.dart';

class MetronomeConfig {
  final double bpm;
  final int beatsPerBar;
  final int subdivision; // 每拍细分：1 四分 / 2 八分 / 3 三连 / 4 十六分
  const MetronomeConfig(
      {required this.bpm, required this.beatsPerBar, required this.subdivision});
  double get beatSeconds => 60.0 / bpm;
  double get tickSeconds => beatSeconds / subdivision;
}

class TickEvent {
  final int sample;
  final int kind; // 0 重音 / 1 强拍 / 2 弱拍
  const TickEvent(this.sample, this.kind);
}

int tickKind(int tickIndex, MetronomeConfig cfg) {
  final beatInBar = (tickIndex ~/ cfg.subdivision) % cfg.beatsPerBar;
  final sub = tickIndex % cfg.subdivision;
  if (sub != 0) return 2;
  return beatInBar == 0 ? 0 : 1;
}

List<TickEvent> scheduleTicks(
    {required MetronomeConfig cfg,
    required int startSample,
    required int tickCount,
    required int sampleRate}) {
  return [
    for (var i = 0; i < tickCount; i++)
      TickEvent(
          startSample + (i * cfg.tickSeconds * sampleRate).round(),
          tickKind(i, cfg))
  ];
}

double bpmFromTaps(List<DateTime> taps) {
  if (taps.length < 2) return 0;
  final gaps = <double>[];
  for (var i = 1; i < taps.length; i++) {
    final g = taps[i].difference(taps[i - 1]).inMilliseconds / 1000.0;
    if (g <= 2.0) gaps.add(g);
  }
  if (gaps.isEmpty) return 0;
  gaps.sort();
  return 60.0 / gaps[gaps.length ~/ 2];
}

/// 引擎：向 PcmPlayer 前瞻填充静音 + click，靠帧回调驱动进度
class MetronomeEngine {
  MetronomeEngine(this._player);
  final PcmPlayer _player;

  MetronomeConfig cfg =
      const MetronomeConfig(bpm: 100, beatsPerBar: 4, subdivision: 1);
  bool running = false;
  final ValueNotifier<int> currentTick = ValueNotifier(-1);

  int _startSample = 0;
  int _nextSampleAbs = 0;

  Future<void> start() async {
    _player.onFrame = _onFrame;
    _startSample = _player.fedSamples;
    _nextSampleAbs = _startSample;
    currentTick.value = -1;
    running = true;
    await _fill();
    await _player.start();
  }

  Future<void> stop() async {
    running = false;
    currentTick.value = -1;
    await _player.stop();
  }

  void _onFrame(int played) {
    if (!running) return;
    final rel = played - _startSample;
    if (rel >= 0) {
      currentTick.value = (rel / (cfg.tickSeconds * _player.sampleRate)).floor();
    }
    _fill();
  }

  Future<void> _fill() async {
    const lookahead = 16384;
    final horizon = _player.fedSamples + lookahead;
    while (_nextSampleAbs < horizon) {
      final rel = _nextSampleAbs - _startSample;
      final tickSamples = cfg.tickSeconds * _player.sampleRate;
      final idx = (rel / tickSamples).round();
      final tickAbs = _startSample + (idx * tickSamples).round();
      if (tickAbs > _nextSampleAbs) {
        await _player.feed(Int16List(tickAbs - _nextSampleAbs)); // 静音填充
        _nextSampleAbs = tickAbs;
      }
      final kind = tickKind(idx, cfg);
      final c = click(kind, sampleRate: _player.sampleRate);
      await _player.feed(c);
      _nextSampleAbs += c.length;
    }
  }
}
```

- [ ] **Step 3: 跑测试确认通过**

Run: `flutter test test/metronome_test.dart`
Expected: 全部 PASS

- [ ] **Step 4: Commit**

```bash
git add lib/audio/metronome_engine.dart test/metronome_test.dart
git commit -m "feat: 节拍器音频时钟调度与 Tap Tempo"
```

---

### Task 12: TuningState + 调音器页（页面暂不接线）

**Files:**
- Create: `lib/state/tuning_state.dart`、`lib/ui/tuner/tuner_page.dart`
- Test: `test/tuning_state_test.dart`

- [ ] **Step 1: 写失败测试 `test/tuning_state_test.dart`**

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/data/database.dart';
import 'package:guitarbar/state/tuning_state.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('A4 持久化往返', () async {
    final s = TuningState(db);
    await s.setA4(435);
    final s2 = TuningState(db);
    await s2.load();
    expect(s2.a4, 435);
  });

  test('自定义预设增删 + 选中持久化', () async {
    final s = TuningState(db);
    await s.load();
    final t = await s.addCustom('我的调弦', ['D2', 'A2', 'D3', 'G3', 'B3', 'E4']);
    expect(s.custom.length, 1);
    await s.select(t);
    final s2 = TuningState(db);
    await s2.load();
    expect(s2.current.id, t.id);
    await s2.deleteCustom(t);
    expect(s2.custom, isEmpty);
    expect(s2.current.isBuiltIn, isTrue);
  });
}
```

- [ ] **Step 2: 实现 `lib/state/tuning_state.dart`**

```dart
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../core/music/builtin_tunings.dart';
import '../core/music/note.dart';
import '../core/music/tuning.dart';
import '../data/database.dart';

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
    custom = [
      for (final r in rows)
        TuningPreset(
            id: 'custom-${r.id}',
            name: r.name,
            strings: r.notes.split(',').map(Note.parse).toList(),
            group: TuningGroup.custom)
    ];
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
```

- [ ] **Step 3: 实现 `lib/ui/tuner/tuner_page.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/music/note.dart';
import '../../core/music/tuning.dart';
import '../../audio/mic_pitch_stream.dart';
import '../../state/tuning_state.dart';

enum _TunerMode { guitar, chromatic }

class TunerPage extends StatefulWidget {
  const TunerPage({super.key});
  @override
  State<TunerPage> createState() => _TunerPageState();
}

class _TunerPageState extends State<TunerPage> {
  _TunerMode _mode = _TunerMode.guitar;
  int? _lockedString;
  bool _micOn = false;
  double? _freq;
  StreamSubscription<double?>? _sub;

  static final _allNotes = [for (var m = 28; m <= 88; m++) Note(m)];

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _toggleMic() {
    if (_micOn) {
      _sub?.cancel();
      _sub = null;
      _micOn = false;
      _freq = null;
    } else {
      _sub = MicPitchStream()
          .start()
          .listen((f) => mounted ? setState(() => _freq = f) : null);
      _micOn = true;
    }
    setState(() {});
  }

  (int, int)? _nearestString() {
    if (_freq == null) return null;
    final strings = context.read<TuningState>().current.strings;
    final a4 = context.read<TuningState>().a4;
    int best = -1, bestCents = 1 << 30;
    for (var i = 0; i < strings.length; i++) {
      final c = centsOff(_freq!, strings[i].frequency(a4));
      if (c.abs() < bestCents.abs()) {
        bestCents = c;
        best = i;
      }
    }
    return (best, bestCents);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TuningState>();
    int cents = 0;
    Note? targetNote;
    if (_freq != null) {
      if (_mode == _TunerMode.chromatic) {
        targetNote =
            Note(69 + (12 * math.log(_freq! / state.a4) / math.ln2).round());
        cents = centsOff(_freq!, targetNote!.frequency(state.a4));
      } else {
        final idx = _lockedString ?? (_nearestString()?.$1 ?? -1);
        if (idx >= 0) {
          targetNote = state.current.strings[idx];
          cents = centsOff(_freq!, targetNote.frequency(state.a4));
        }
      }
    }
    final inTune = _freq != null && cents.abs() <= 3;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          SegmentedButton<_TunerMode>(
            segments: const [
              ButtonSegment(value: _TunerMode.guitar, label: Text('吉他模式')),
              ButtonSegment(value: _TunerMode.chromatic, label: Text('半音调音器')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const Spacer(),
          IconButton(
              onPressed: () => _showA4Dialog(context, state),
              tooltip: 'A4 参考音高',
              icon: Text('A4=${state.a4.toStringAsFixed(0)}')),
          IconButton(
              onPressed: () => _showPresetSheet(context, state),
              tooltip: '调弦预设',
              icon: const Icon(Icons.list)),
          FilledButton.tonal(
              onPressed: _toggleMic,
              child: Text(_micOn ? '停止' : '开始调音')),
        ]),
        const Spacer(),
        Text(targetNote?.label(flats: _preferFlats(targetNote!)) ?? '--',
            style: Theme.of(context).textTheme.displayLarge),
        Text(_freq == null ? '未检测到声音' : '${_freq!.toStringAsFixed(1)} Hz',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SizedBox(
            width: 280, height: 120,
            child: CustomPaint(painter: _NeedlePainter(cents.toDouble(), inTune))),
        Text('${cents.abs()} 音分 ${cents > 0 ? '偏高 ↑' : cents < 0 ? '偏低 ↓' : ''}',
            style: TextStyle(
                fontSize: 18,
                color: inTune ? Colors.green : Theme.of(context).colorScheme.onSurface)),
        const Spacer(),
        if (_mode == _TunerMode.guitar)
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < 6; i++)
                ChoiceChip(
                  label: Text('${6 - i}弦 ${state.current.strings[i].name}'),
                  selected: _lockedString == i,
                  onSelected: (sel) =>
                      setState(() => _lockedString = sel ? i : null),
                ),
            ],
          ),
      ]),
    );
  }

  bool _preferFlats(Note n) =>
      ['A#', 'C#', 'D#', 'F#', 'G#'].contains(n.name.substring(0, n.name.length - 1));

  void _showA4Dialog(BuildContext context, TuningState state) {
    double v = state.a4;
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('A4 参考音高'),
      content: StatefulBuilder(builder: (context, setD) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${v.toStringAsFixed(1)} Hz'),
          Slider(value: v, min: 430, max: 450, divisions: 40,
              label: v.toStringAsFixed(1),
              onChanged: (x) => setD(() => v = x)),
        ],
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () { state.setA4(v); Navigator.pop(context); },
            child: const Text('确定')),
      ],
    ));
  }

  void _showPresetSheet(BuildContext context, TuningState state) {
    showModalBottomSheet(context: context, builder: (_) => _PresetSheet(state: state));
  }
}
```

注意：文件顶部需要 `import 'dart:math' as math;`（指针与半音计算）和 `import 'dart:async';`（StreamSubscription）。

- [ ] **Step 4: 追加 `_NeedlePainter` 与 `_PresetSheet`（同一文件末尾）**

```dart
class _NeedlePainter extends CustomPainter {
  _NeedlePainter(this.cents, this.inTune);
  final double cents;
  final bool inTune;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - 8;
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = Colors.grey.shade400;
    final clamped = cents.clamp(-50.0, 50.0);
    final angle = clamped / 50 * (math.pi / 3); // ±60°
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        math.pi + math.pi / 6, 2 * math.pi / 3, false, arcPaint);
    final needlePaint = Paint()
      ..strokeWidth = 3
      ..color = inTune ? Colors.green : Colors.redAccent;
    final tip = Offset(center.dx + radius * math.sin(angle),
        center.dy - radius * math.cos(angle));
    canvas.drawLine(center, tip, needlePaint);
    for (final c in const [-50, -25, 0, 25, 50]) {
      final a = c / 50 * (math.pi / 3);
      final p1 = Offset(center.dx + (radius - 10) * math.sin(a),
          center.dy - (radius - 10) * math.cos(a));
      final p2 = Offset(center.dx + radius * math.sin(a),
          center.dy - radius * math.cos(a));
      canvas.drawLine(p1, p2, Paint()..color = Colors.grey);
    }
  }

  @override
  bool shouldRepaint(_NeedlePainter old) =>
      old.cents != cents || old.inTune != inTune;
}

class _PresetSheet extends StatelessWidget {
  const _PresetSheet({required this.state});
  final TuningState state;

  @override
  Widget build(BuildContext context) {
    final groups = TuningGroup.values;
    return SafeArea(
      child: SizedBox(
        height: 480,
        child: ListView(
          children: [
            for (final g in groups)
              if (g != TuningGroup.custom || state.custom.isNotEmpty)
                ExpansionTile(
                  initiallyExpanded: state.current.group == g,
                  title: Text(g.label),
                  children: [
                    for (final t in [
                      ...builtinTunings.where((x) => x.group == g),
                      if (g == TuningGroup.custom) ...state.custom
                    ])
                      ListTile(
                        title: Text(t.name),
                        subtitle: Text(t.strings.map((n) => n.name).join(' ')),
                        selected: state.current.id == t.id,
                        onTap: () {
                          state.select(t);
                          Navigator.pop(context);
                        },
                        trailing: g == TuningGroup.custom
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () {
                                  state.deleteCustom(t);
                                  Navigator.pop(context);
                                })
                            : IconButton(
                                icon: const Icon(Icons.copy),
                                tooltip: '复制为新预设',
                                onPressed: () => _showEditor(context, state,
                                    base: t)),
                      ),
                    if (g == TuningGroup.custom)
                      ListTile(
                        leading: const Icon(Icons.add),
                        title: const Text('新建自定义调弦'),
                        onTap: () => _showEditor(context, state),
                      ),
                  ],
                ),
          ],
        ),
      ),
    );
  }

  void _showEditor(BuildContext context, TuningState state,
      {TuningPreset? base}) {
    var name = base != null ? '${base.name} 副本' : '新调弦';
    var picked = List<Note>.from(base?.strings ??
        [Note.parse('E2'), Note.parse('A2'), Note.parse('D3'),
         Note.parse('G3'), Note.parse('B3'), Note.parse('E4')]);
    final allNotes = [for (var m = 28; m <= 88; m++) Note(m)];
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: TextFormField(
                  initialValue: name,
                  onChanged: (v) => name = v,
                  decoration: const InputDecoration(labelText: '预设名称')),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 6; i++)
                      DropdownButtonFormField<Note>(
                        initialValue: picked[i],
                        decoration: InputDecoration(labelText: '${6 - i} 弦'),
                        items: [
                          for (final n in allNotes)
                            DropdownMenuItem(value: n, child: Text(n.name))
                        ],
                        onChanged: (n) => picked[i] = n!,
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () {
                      state.addCustom(name, picked.map((n) => n.name).toList());
                      Navigator.pop(context);
                    },
                    child: const Text('保存')),
              ],
            ));
  }
}
```

注意：`_NeedlePainter` 需要 `import 'dart:math' as math;`（与 Step 3 修正合并）。`StreamSubscription` 需要 `import 'dart:async';`。

- [ ] **Step 5: 跑测试确认通过 + analyze**

Run: `flutter test test/tuning_state_test.dart && flutter analyze`
Expected: PASS / 0 errors（页面尚未接线，`unused_element` 警告可暂忽略或加 `// ignore: unused_element`）

- [ ] **Step 6: Commit**

```bash
git add lib/state lib/ui/tuner test/tuning_state_test.dart
git commit -m "feat: 调音器页（双模式/分组预设/A4校准/指针）"
```

---

### Task 13: 节拍器页

**Files:**
- Create: `lib/ui/toolbox/metronome_page.dart`

- [ ] **Step 1: 实现 `lib/ui/toolbox/metronome_page.dart`（整文件）**

```dart
import 'package:flutter/material.dart';

import '../../audio/metronome_engine.dart';
import '../../audio/pcm_player.dart';

class MetronomePage extends StatefulWidget {
  const MetronomePage({super.key});
  @override
  State<MetronomePage> createState() => _MetronomePageState();
}

class _MetronomePageState extends State<MetronomePage> {
  final _player = PcmPlayer();
  late final MetronomeEngine _engine = MetronomeEngine(_player);
  bool _ready = false;
  final _taps = <DateTime>[];

  static const _timeSigs = [(2, '2/4'), (3, '3/4'), (4, '4/4'), (6, '6/8')];
  static const _subs = [(1, '四分'), (2, '八分'), (3, '三连音'), (4, '十六分')];

  @override
  void initState() {
    super.initState();
    _player.setup().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _engine.stop();
    super.dispose();
  }

  Future<void> _toggle() async {
    _engine.running ? await _engine.stop() : await _engine.start();
    setState(() {});
  }

  void _tap() {
    _taps.add(DateTime.now());
    if (_taps.length > 8) _taps.removeAt(0);
    final bpm = bpmFromTaps(_taps);
    if (bpm > 0) {
      setState(() => _engine.cfg = MetronomeConfig(
          bpm: bpm.clamp(30, 300).toDouble(),
          beatsPerBar: _engine.cfg.beatsPerBar,
          subdivision: _engine.cfg.subdivision));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _engine.cfg;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        ValueListenableBuilder<int>(
          valueListenable: _engine.currentTick,
          builder: (_, tick, __) {
            final beatInBar =
                tick < 0 ? -1 : (tick ~/ cfg.subdivision) % cfg.beatsPerBar;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < cfg.beatsPerBar; i++)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: i == beatInBar
                          ? (i == 0 ? Colors.red : Colors.teal)
                          : Colors.grey.shade300,
                    ),
                  ),
              ],
            );
          },
        ),
        Text('${cfg.bpm.toStringAsFixed(0)} BPM',
            style: Theme.of(context).textTheme.displayMedium),
        Slider(
          value: cfg.bpm,
          min: 30,
          max: 300,
          onChanged: _engine.running
              ? null
              : (v) => setState(() => _engine.cfg = MetronomeConfig(
                  bpm: v,
                  beatsPerBar: cfg.beatsPerBar,
                  subdivision: cfg.subdivision)),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          FilledButton.tonal(onPressed: _tap, child: const Text('Tap 点速')),
          const SizedBox(width: 12),
          FilledButton(
              onPressed: _ready ? _toggle : null,
              child: Text(_engine.running ? '停止' : '开始')),
        ]),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          DropdownButton<int>(
            value: cfg.beatsPerBar,
            items: [
              for (final (b, l) in _timeSigs)
                DropdownMenuItem(value: b, child: Text(l))
            ],
            onChanged: (b) => setState(() => _engine.cfg = MetronomeConfig(
                bpm: cfg.bpm, beatsPerBar: b!, subdivision: cfg.subdivision)),
          ),
          const SizedBox(width: 24),
          DropdownButton<int>(
            value: cfg.subdivision,
            items: [
              for (final (s, l) in _subs)
                DropdownMenuItem(value: s, child: Text(l))
            ],
            onChanged: (s) => setState(() => _engine.cfg = MetronomeConfig(
                bpm: cfg.bpm, beatsPerBar: cfg.beatsPerBar, subdivision: s!)),
          ),
        ]),
      ]),
    );
  }
}
```

- [ ] **Step 2: 手动冒烟（临时挂到 RootPage tab1 或后续 Task 16 统一接线后验证）**

运行后：4/4 100 BPM 播放 30 秒，拍点间隔无可感知漂移；点 Tap 数下节奏，BPM 显示贴合。

- [ ] **Step 3: Commit**

```bash
git add lib/ui/toolbox/metronome_page.dart
git commit -m "feat: 节拍器页（细分拍/Tap Tempo/拍点指示灯）"
```

---

### Task 14: 和弦库页

**Files:**
- Create: `lib/ui/toolbox/chord_page.dart`

- [ ] **Step 1: 实现 `lib/ui/toolbox/chord_page.dart`（整文件）**

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/pcm_player.dart';
import '../../audio/synth.dart';
import '../../core/music/chord_parser.dart';
import '../../core/music/fingering.dart';
import '../../state/tuning_state.dart';

class ChordPage extends StatefulWidget {
  const ChordPage({super.key});
  @override
  State<ChordPage> createState() => _ChordPageState();
}

class _ChordPageState extends State<ChordPage> {
  final _input = TextEditingController(text: 'Am7');
  List<ChordVoicing> _voicings = [];
  String? _error;
  final _player = PcmPlayer();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _player.setup().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _search() {
    final state = context.read<TuningState>();
    try {
      final c = parseChord(_input.text);
      _voicings = FingeringGenerator(state.current.strings)
          .generate(rootPc: c.rootPc, toneClasses: chordToneClasses(c));
      _error = null;
    } on ArgumentError catch (e) {
      _voicings = [];
      _error = e.message?.toString() ?? '解析失败';
    }
    setState(() {});
  }

  Future<void> _play(ChordVoicing v, PlayMode mode) async {
    final state = context.read<TuningState>();
    await _player.feed(
        voicingPcm(state.current.strings, v.frets, mode, a4: state.a4));
    await _player.start();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              decoration: const InputDecoration(
                  labelText: '输入和弦名（如 Am7、F#m7b5）'),
              onSubmitted: (_) => _search(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _search, child: const Text('查询')),
        ]),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_error!, style: const TextStyle(color: Colors.red))),
        Expanded(
          child: ListView.builder(
            itemCount: _voicings.length,
            itemBuilder: (_, i) {
              final v = _voicings[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    SizedBox(
                        width: 220,
                        height: 180,
                        child: CustomPaint(
                            painter: _ChordPainter(
                                frets: v.frets,
                                preferLowFret: i == 0))),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      FilledButton.tonal(
                          onPressed:
                              _ready ? () => _play(v, PlayMode.pluckAll) : null,
                          child: const Text('同时')),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                          onPressed:
                              _ready ? () => _play(v, PlayMode.arpeggio) : null,
                          child: const Text('琶音')),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                          onPressed:
                              _ready ? () => _play(v, PlayMode.strumDown) : null,
                          child: const Text('下扫')),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                          onPressed:
                              _ready ? () => _play(v, PlayMode.strumUp) : null,
                          child: const Text('上扫')),
                    ]),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _ChordPainter extends CustomPainter {
  _ChordPainter({required this.frets, required this.preferLowFret});
  final List<int?> frets;
  final bool preferLowFret;

  @override
  void paint(Canvas canvas, Size size) {
    final fretted = frets.whereType<int>().where((f) => f > 0).toList();
    final minFret = preferLowFret || fretted.isEmpty
        ? 1
        : math.max(1, fretted.reduce((a, b) => a < b ? a : b));
    final visibleFrets = 5;
    final line = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1.5;
    final left = 30.0, right = size.width - 10;
    final top = 40.0, gap = (size.height - top - 10) / visibleFrets;
    // 弦（竖线 6 根）
    final stringGap = (right - left) / 5;
    for (var s = 0; s < 6; s++) {
      final x = left + stringGap * s;
      canvas.drawLine(Offset(x, top), Offset(x, top + gap * visibleFrets), line);
    }
    // 品（横线，第一格加粗表示琴枕）
    for (var f = 0; f <= visibleFrets; f++) {
      final y = top + gap * f;
      canvas.drawLine(Offset(left, y), Offset(right, y),
          f == 0 ? (Paint()..color = Colors.black..strokeWidth = 4) : line);
    }
    if (!preferLowFret && fretted.isNotEmpty) {
      // 起始品标注
      final tp = TextPainter(
          text: TextSpan(text: '${minFret}品',
              style: const TextStyle(fontSize: 12)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(2, top + gap * 0.5));
    }
    // 品位点与 X/O
    final dot = Paint()..color = Colors.teal;
    for (var s = 0; s < 6; s++) {
      final f = frets[s];
      final x = left + stringGap * s;
      if (f == null) {
        canvas.drawLine(Offset(x - 5, 22), Offset(x + 5, 32),
            Paint()..color = Colors.red..strokeWidth = 2);
        canvas.drawLine(Offset(x - 5, 32), Offset(x + 5, 22),
            Paint()..color = Colors.red..strokeWidth = 2);
      } else if (f == 0) {
        canvas.drawCircle(Offset(x, 27), 5, Paint()..color = Colors.green);
      } else {
        final row = f - minFret;
        if (row >= 0 && row < visibleFrets) {
          canvas.drawCircle(
              Offset(x, top + gap * (row + 0.5)), 9, dot);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ChordPainter old) => old.frets != frets;
}
```

- [ ] **Step 2: 手动验证（Task 16 接线后）**

查询 Am7 出多个指法且最易的为 x02010 类指法；四种发声模式均可听；切换 Drop D 后查询 D5 和弦指法随调弦变化。

- [ ] **Step 3: Commit**

```bash
git add lib/ui/toolbox/chord_page.dart
git commit -m "feat: 和弦库页（算法指法图与四种试听）"
```

---

### Task 15: 指板音阶页

**Files:**
- Create: `lib/ui/toolbox/fretboard_page.dart`

- [ ] **Step 1: 实现 `lib/ui/toolbox/fretboard_page.dart`（整文件）**

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/pcm_player.dart';
import '../../audio/synth.dart';
import '../../core/music/note.dart';
import '../../core/music/scale.dart';
import '../../state/tuning_state.dart';

class FretboardPage extends StatefulWidget {
  const FretboardPage({super.key});
  @override
  State<FretboardPage> createState() => _FretboardPageState();
}

class _FretboardPageState extends State<FretboardPage> {
  int _rootPc = 9; // A
  ScaleType _scale = ScaleType.minorPentatonic;
  bool _showSolfege = false;
  final _player = PcmPlayer();
  bool _ready = false;

  static const _frets = 12;
  static const _pcNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

  @override
  void initState() {
    super.initState();
    _player.setup().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _tapCell(TuningState state, int stringIdx, int fret) {
    final midi = state.current.strings[stringIdx].midi + fret;
    if (_ready) {
      _player.feed(pluck(Note(midi).frequency(state.a4)));
      _player.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TuningState>();
    final grid = fretboardGrid(state.current.strings, _rootPc, _scale, frets: _frets);
    final majorPcs = scalePitchClasses(_rootPc, ScaleType.major);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          DropdownButton<int>(
            value: _rootPc,
            items: [
              for (var pc = 0; pc < 12; pc++)
                DropdownMenuItem(value: pc, child: Text(_pcNames[pc]))
            ],
            onChanged: (v) => setState(() => _rootPc = v!),
          ),
          const SizedBox(width: 16),
          DropdownButton<ScaleType>(
            value: _scale,
            items: [
              for (final s in ScaleType.values)
                DropdownMenuItem(value: s, child: Text(s.label))
            ],
            onChanged: (s) => setState(() => _scale = s!),
          ),
          const SizedBox(width: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('音名')),
              ButtonSegment(value: true, label: Text('唱名')),
            ],
            selected: {_showSolfege},
            onSelectionChanged: (s) => setState(() => _showSolfege = s.first),
          ),
        ]),
        Text('调弦：${state.current.name}',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final cellW = c.maxWidth / (_frets + 1);
            final cellH = (c.maxHeight - 20) / 6;
            return GestureDetector(
              onTapUp: (d) {
                final fret = ((d.localPosition.dx) ~/ cellW) - 1;
                final str = (d.localPosition.dy ~/ cellH).clamp(0, 5);
                if (fret >= 0 && fret <= _frets) _tapCell(state, str, fret);
              },
              child: CustomPaint(
                size: Size(c.maxWidth, c.maxHeight),
                painter: _FretboardPainter(
                    grid: grid,
                    cellW: cellW,
                    cellH: cellH,
                    showSolfege: _showSolfege,
                    rootPc: _rootPc,
                    majorPcs: majorPcs),
              ),
            );
          }),
        ),
      ]),
    );
  }
}

class _FretboardPainter extends CustomPainter {
  _FretboardPainter(
      {required this.grid,
      required this.cellW,
      required this.cellH,
      required this.showSolfege,
      required this.rootPc,
      required this.majorPcs});
  final List<List<int?>> grid;
  final double cellW, cellH;
  final bool showSolfege;
  final int rootPc;
  final List<int> majorPcs;

  static const _pcNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

  @override
  void paint(Canvas canvas, Size size) {
    final inScalePaint = Paint()..color = Colors.teal.withOpacity(0.85);
    final rootPaint = Paint()..color = Colors.orange;
    final linePaint = Paint()
      ..color = Colors.black26
      ..strokeWidth = 1;
    // 品线
    for (var f = 0; f <= 12; f++) {
      final x = cellW * (f + 1);
      canvas.drawLine(Offset(x, 0), Offset(x, cellH * 6), linePaint);
    }
    // 弦线
    for (var s = 0; s < 6; s++) {
      canvas.drawLine(Offset(0, cellH * (s + 0.5)),
          Offset(size.width, cellH * (s + 0.5)), linePaint);
    }
    // 音格
    for (var s = 0; s < 6; s++) {
      for (var f = 0; f <= 12; f++) {
        final midi = grid[s][f];
        if (midi == null) continue;
        final isRoot = midi % 12 == rootPc;
        final cx = cellW * (f + 0.5) + cellW / 2;
        final cy = cellH * (s + 0.5);
        canvas.drawCircle(Offset(cx, cy), math.min(cellW, cellH) * 0.36,
            isRoot ? rootPaint : inScalePaint);
        final label = showSolfege
            ? (majorPcs.indexOf(midi % 12) >= 0
                ? solfege[majorPcs.indexOf(midi % 12)]
                : _pcNames[midi % 12])
            : _pcNames[midi % 12];
        final tp = TextPainter(
            text: TextSpan(
                text: label,
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
            textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
      }
    }
    // 品号
    for (var f = 0; f <= 12; f++) {
      if ([3, 5, 7, 9, 12].contains(f)) {
        final tp = TextPainter(
            text: TextSpan(text: '$f', style: const TextStyle(fontSize: 10)),
            textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset(cellW * (f + 1) - tp.width / 2, size.height - 14));
      }
    }
  }

  @override
  bool shouldRepaint(_FretboardPainter old) => true;
}
```

- [ ] **Step 2: 手动验证（Task 16 接线后）**

切到 Drop D：6 弦空弦音随调弦变化；点任意品位发声；音名/唱名切换正常；根音橙色高亮。

- [ ] **Step 3: Commit**

```bash
git add lib/ui/toolbox/fretboard_page.dart
git commit -m "feat: 指板音阶页（随调弦联动/点按发声/唱名切换）"
```

---

### Task 16: 全局接线（providers + RootPage + 工具箱入口）

**Files:**
- Create: `lib/ui/toolbox/toolbox_page.dart`
- Modify: `lib/main.dart`（整文件替换）、`lib/ui/root.dart`（替换 IndexedStack 子项与 imports）

- [ ] **Step 1: 实现 `lib/ui/toolbox/toolbox_page.dart`（整文件）**

```dart
import 'package:flutter/material.dart';

import 'chord_page.dart';
import 'fretboard_page.dart';
import 'metronome_page.dart';

class ToolboxPage extends StatelessWidget {
  const ToolboxPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: 3,
      children: [
        _Card(
            icon: Icons.music_note,
            title: '和弦库',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ChordPage()))),
        _Card(
            icon: Icons.piano,
            title: '指板音阶',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const FretboardPage()))),
        _Card(
            icon: Icons.av_timer,
            title: '节拍器',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MetronomePage()))),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.title, required this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 48),
              const SizedBox(height: 8),
              Text(title),
            ]),
          ),
        ),
      );
}
```

- [ ] **Step 2: 替换 `lib/main.dart`（整文件）**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'data/database.dart';
import 'state/practice_timer.dart';
import 'state/tuning_state.dart';
import 'ui/root.dart';
import 'ui/tuner/tuner_page.dart';
import 'ui/toolbox/toolbox_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1024, 768),
    minimumSize: Size(768, 576),
    title: 'GuitarBar',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  final db = AppDatabase(openConnection());
  runApp(MultiProvider(providers: [
    Provider<AppDatabase>.value(value: db),
    ChangeNotifierProvider(create: (_) => TuningState(db)..load()),
    ChangeNotifierProvider(create: (_) => PracticeTimer(db)),
  ], child: const GuitarBarApp()));
}

class GuitarBarApp extends StatelessWidget {
  const GuitarBarApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'GuitarBar',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: const RootPage(),
      );
}
```

- [ ] **Step 3: 修改 `lib/ui/root.dart`**

把 IndexedStack 子项与 imports 改为（`_Placeholder` 类与个人中心占位保留，Task 17 替换）：

```dart
import 'package:flutter/material.dart';

import 'tuner/tuner_page.dart';
import 'toolbox/toolbox_page.dart';

// IndexedStack 行改为：
      final body = IndexedStack(index: _tab, children: [
        const TunerPage(),
        const ToolboxPage(),
        _Placeholder(_titles[2]),
      ]);
```

- [ ] **Step 4: 冒烟 + 手动验证**

```bash
flutter analyze && flutter run -d windows
```

对照验收标准走查（记录结果到 `tasks/todo.md`）：
- #2 麦克风弹弦显示弦名与音分，到位变绿
- #3 半音模式识别任意单音
- #4 预设分组展示；自定义增删改查重启保留
- #5 Am7/F#m7b5 返回指法图并试听
- #6 Drop D 下指板/和弦联动
- #10 A4 调整后重启仍生效
- #11 细分拍与 Tap Tempo
- #13 琶音/扫弦试听

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: 全局接线（调音器一级入口+工具箱卡片）"
```

---

### Task 17: 打卡（统计纯函数 TDD + 全局计时 + 个人中心页）

**Files:**
- Create: `lib/core/stats.dart`、`lib/state/practice_timer.dart`、`lib/ui/profile/profile_page.dart`
- Modify: `lib/ui/root.dart`
- Test: `test/stats_test.dart`

- [ ] **Step 1: 写失败测试 `test/stats_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/stats.dart';
import 'package:guitarbar/data/database.dart';

PracticeSessionData row(DateTime start, int seconds) => PracticeSessionData(
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
    expect(totalSeconds(rows, DateTime(2026, 10, 19), DateTime(2026, 10, 26)), 1800);
  });

  test('分钟按天聚合', () {
    final m = minutesPerDay([
      row(DateTime(2026, 10, 25, 9), 600),
      row(DateTime(2026, 10, 25, 20), 1200),
    ]);
    expect(m[DateTime(2026, 10, 25)], 30);
  });
}
```

- [ ] **Step 2: 实现 `lib/core/stats.dart`**

```dart
import '../data/database.dart';

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

Set<DateTime> practiceDays(List<PracticeSessionData> rows) =>
    {for (final r in rows) _day(r.startedAt)};

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

int totalSeconds(List<PracticeSessionData> rows, DateTime from, DateTime to) =>
    rows
        .where((r) => !r.startedAt.isBefore(from) && r.startedAt.isBefore(to))
        .fold(0, (sum, r) => sum + r.durationSeconds);

Map<DateTime, int> minutesPerDay(List<PracticeSessionData> rows) {
  final m = <DateTime, int>{};
  for (final r in rows) {
    final d = _day(r.startedAt);
    m[d] = (m[d] ?? 0) + r.durationSeconds ~/ 60;
  }
  return m;
}
```

- [ ] **Step 3: 跑测试确认通过**

Run: `flutter test test/stats_test.dart`
Expected: 全部 PASS

- [ ] **Step 4: 实现 `lib/state/practice_timer.dart`（含 wakelock）**

```dart
import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/database.dart';

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
    await WakelockPlus.enable(); // 练习中屏幕常亮（验收 #12）
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
      await _db.into(_db.practiceSessions).insert(PracticeSessionsCompanion.insert(
          startedAt: start,
          endedAt: end,
          durationSeconds: end.difference(start).inSeconds,
          note: drift.Value(note)));
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 5: 实现 `lib/ui/profile/profile_page.dart`（整文件）**

```dart
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/stats.dart';
import '../../data/backup.dart';
import '../../data/database.dart';
import '../../state/practice_timer.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  String _fmt(int seconds) {
    final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
    return h > 0 ? '$h 时 $m 分' : '$m 分钟';
  }

  Future<void> _manualEntry(BuildContext context, AppDatabase db) async {
    final date = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now());
    if (date == null || !context.mounted) return;
    final minutesCtrl = TextEditingController(text: '30');
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: Text('${date.month}月${date.day}日 补卡'),
              content: TextField(
                  controller: minutesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '练习分钟数')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('保存')),
              ],
            ));
    if (ok != true) return;
    final minutes = int.tryParse(minutesCtrl.text) ?? 0;
    if (minutes <= 0) return;
    final start = DateTime(date.year, date.month, date.day, 20);
    await db.into(db.practiceSessions).insert(PracticeSessionsCompanion.insert(
        startedAt: start,
        endedAt: start.add(Duration(minutes: minutes)),
        durationSeconds: minutes * 60));
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final timer = context.watch<PracticeTimer>();
    return FutureBuilder<List<PracticeSessionData>>(
      future: db.select(db.practiceSessions).get(),
      builder: (context, snap) {
        final rows = snap.data ?? const <PracticeSessionData>[];
        final now = DateTime.now();
        final today = totalSeconds(rows, DateTime(now.year, now.month, now.day),
            DateTime(now.year, now.month, now.day + 1));
        final week = totalSeconds(rows, now.subtract(const Duration(days: 7)), now);
        final month = totalSeconds(rows, now.subtract(const Duration(days: 30)), now);
        final streak = streakDays(practiceDays(rows), now);
        final perDay = minutesPerDay(rows);
        return Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(children: [
            Center(
              child: FilledButton.icon(
                icon: Icon(timer.running ? Icons.stop : Icons.play_arrow),
                label: Text(timer.running
                    ? '停止（${timer.elapsedSeconds ~/ 60}:${(timer.elapsedSeconds % 60).toString().padLeft(2, '0')}）'
                    : '开始练习'),
                onPressed: () async =>
                    timer.running ? await timer.stop() : await timer.start(),
              ),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _Stat('今日', _fmt(today)),
              _Stat('连续', '$streak 天'),
              _Stat('本周', _fmt(week)),
              _Stat('30 天', _fmt(month)),
            ]),
            const SizedBox(height: 12),
            Text('最近 12 周', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            _Heatmap(perDay: perDay),
            const SizedBox(height: 12),
            Row(children: [
              OutlinedButton(
                  onPressed: () => _manualEntry(context, db),
                  child: const Text('手动补卡')),
              const SizedBox(width: 8),
              OutlinedButton(
                  onPressed: () => exportToFile(db), child: const Text('导出 JSON')),
              const SizedBox(width: 8),
              OutlinedButton(
                  onPressed: () => importFromFile(db), child: const Text('导入 JSON')),
            ]),
          ]),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.perDay});
  final Map<DateTime, int> perDay;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 83));
    final first = start.subtract(Duration(days: start.weekday - 1)); // 对齐周一
    final total = 84 + (start.weekday - 1);
    return SizedBox(
      height: 7 * 17.0,
      child: GridView.count(
        scrollDirection: Axis.horizontal,
        crossAxisCount: 7, // 每列一周（列内为周一→周日）
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
        children: [
          for (var i = 0; i < total; i++)
            Builder(builder: (_) {
              final d = first.add(Duration(days: i));
              if (d.isAfter(today)) return const SizedBox();
              final mins = perDay[d] ?? 0;
              final color = mins == 0
                  ? Colors.grey.shade200
                  : mins < 20
                      ? Colors.teal.shade200
                      : mins < 45
                          ? Colors.teal.shade400
                          : Colors.teal.shade700;
              return Container(
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(3)));
            }),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: 修改 `lib/ui/root.dart`（个人中心 + 顶栏常驻计时）**

整文件替换：

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/practice_timer.dart';
import 'profile/profile_page.dart';
import 'tuner/tuner_page.dart';
import 'toolbox/toolbox_page.dart';

class RootPage extends StatefulWidget {
  const RootPage({super.key});
  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _tab = 0;
  static const _titles = ['调音器', '工具箱', '个人中心'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final body = IndexedStack(index: _tab, children: const [
        TunerPage(),
        ToolboxPage(),
        ProfilePage(),
      ]);
      return Scaffold(
        appBar: AppBar(
          title: Text(_titles[_tab]),
          actions: [
            Consumer<PracticeTimer>(builder: (_, t, __) {
              if (!t.running) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    '${t.elapsedSeconds ~/ 60}:${(t.elapsedSeconds % 60).toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              );
            }),
          ],
        ),
        body: wide
            ? Row(children: [
                NavigationRail(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(icon: Icon(Icons.tune), label: Text('调音器')),
                    NavigationRailDestination(icon: Icon(Icons.home_repair_service), label: Text('工具箱')),
                    NavigationRailDestination(icon: Icon(Icons.person), label: Text('个人中心')),
                  ],
                ),
                Expanded(child: body),
              ])
            : body,
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: '调音器'),
                  NavigationDestination(icon: Icon(Icons.home_repair_service_outlined), selectedIcon: Icon(Icons.home_repair_service), label: '工具箱'),
                  NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '个人中心'),
                ],
              ),
      );
    });
  }
}
```

- [ ] **Step 7: 全量测试 + 手动验证**

```bash
flutter analyze && flutter test && flutter run -d windows
```

- #8 开始练习 → 切到工具箱开节拍器 → 顶栏计时走动 → 回个人中心停止，打卡记录出现
- #12 计时中屏幕不熄屏（Windows 验证：停止后 wakelock 关闭无异常即可）
- 补卡后热力图/连续天数变化正确
- #9 导出 JSON → 删除 App 数据目录下 guitarbar.sqlite → 重启 → 导入，数据恢复

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: 个人中心打卡（全局计时/热力图/补卡/导出导入）"
```

---

### Task 18: 第一期验收走查

**Files:**
- Modify: `tasks/todo.md`（记录验收结果）

- [ ] **Step 1: 全量自动化检查**

```bash
flutter analyze
flutter test
```

Expected: analyze 0 errors；全部测试 PASS（note/tuning/scale/chord/database/backup/pitch_detector/window_accumulator/synth/metronome/tuning_state/stats 共 12 个测试文件）。

- [ ] **Step 2: 按 13 条验收标准走查**

| # | 标准 | 验证方式 |
|---|---|---|
| 1 | iPad 比例窗口 + 宽窗口侧边栏 | 启动看 1024×768；拉伸 >900px 出 NavigationRail |
| 2 | 吉他模式识弦+音分+变绿 | 弹 6→1 弦逐根验证 |
| 3 | 半音模式识别任意音 | 哼唱/按品任意音显示音名 |
| 4 | 20 预设分组 + 自定义不限量 | 预设面板核对 5/4/7/4 分组；建 2 个自定义重启仍在 |
| 5 | 和弦查询+试听 | Am7、F#m7b5 |
| 6 | 调弦联动 | 切 Drop D 看指板与和弦 |
| 7 | 节拍器 5 分钟无漂移 | 4/4 100BPM 跑 5 分钟对拍 |
| 8 | 打卡流程 | 开始→切页→停止 |
| 9 | JSON 导出导入 | 导出→删库→导入 |
| 10 | A4 校准持久化 | 设 435 重启 |
| 11 | 细分拍+Tap | 三连音模式 + Tap 120 |
| 12 | 练习中常亮 | 计时中观察 |
| 13 | 琶音/扫弦 | 和弦页四按钮 |

发现的问题当场修复并提交（fix: ...）。

- [ ] **Step 3: 记录结果并收尾**

把走查结果写入 `tasks/todo.md` 的 Review 节；最后提交：

```bash
git add -A
git commit -m "chore: 第一期验收走查完成"
```

**后续提醒（不在本计划内）**：二期启动前需先写二期设计文档；iOS 侧在有 Mac/云 Mac 时执行 `flutter create --platforms ios .` 并按设计文档 3.1 节选交付路线。


