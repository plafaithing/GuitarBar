# 13.1 鍜屽鸡搴撳垎绫绘祻瑙?瀹炵幇璁″垝

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 鍜屽鸡搴撳姞"娴忚"妯″紡鈥斺€斿垎绫绘爲锛堜笁鍜屽鸡/涓冨拰寮?鎸傜暀/鍔犻煶鎵╁睍 鈫?17 绉嶅瓙绫伙級脳 鏍归煶 12 閫夋灇涓剧偣閫夛紝鐩存帴鍑烘寚娉曪紙澶嶇敤涓€鏈熺敓鎴愬紩鎿庝笌璇曞惉锛夈€?
**Architecture:** 鏁版嵁灞?ChordCatalog锛堢函甯搁噺锛屼粠 chord_parser 鐨?`_qualities` 17 绉嶇粍缁囦负鍒嗙被鏍戯紝鏋氫妇鐩存帴浜?ParsedChord 涓嶇粡瀛楃涓茶В鏋愶級锛沀I 灞?chord_page 鍔犺緭鍏?娴忚鍙屾ā寮忥紙SegmentedButton 鍒囨崲锛夛紝娴忚閫夊畾鍗虫煡璇㈠鐢ㄦ棦鏈?`_search` 缁撴灉鍖恒€傝璁′緷鎹細璁捐鏂囨。 搂13.1锛?026-10-30 鐢ㄦ埛鎻愬嚭骞剁‘璁わ級銆?
**Tech Stack:** 绾?Flutter/Dart锛岄浂鏂颁緷璧栵紱澶嶇敤 `parseChord`/`chordToneClasses`/`FingeringGenerator`/`_ChordPainter`/鍥涜瘯鍚?璋冨鸡鑱斿姩銆?
**鍏抽敭澶嶇敤鎺ュ彛锛堝疄鐜拌€呭繀璇伙級:**

- `parseChord('Am7') 鈫?ParsedChord(rootPc, intervals)`锛坄lib/core/music/chord_parser.dart`鈥斺€擿_qualities` 琛ㄥ惈鍏ㄩ儴 17 绉嶏級
- `chordToneClasses(c) 鈫?Set<int>`銆乣FingeringGenerator(strings).generate(rootPc:, toneClasses:) 鈫?List<ChordVoicing>`锛坄lib/core/music/fingering.dart`锛?- `lib/ui/toolbox/chord_page.dart`锛歚_search()`锛堣В鏋愨啋鐢熸垚鈫抯etState锛夈€乣_voicings` 缁撴灉鍖猴紙鎸囨硶鍥惧崱鐗?鍥涜瘯鍚寜閽級銆乣_onTuningChanged` 璋冨鸡鑱斿姩鑷姩閲嶆煡銆乣_input` 鎺у埗鍣?- 璁捐璇█锛歝ontext.palette.*銆丆hoiceChip銆丼egmentedButton锛堝瑙備笁閫夊凡鏈夊厛渚?profile_page锛夈€乄rap

---

### Task A: ChordCatalog 鍒嗙被鐩綍鏁版嵁

**Files:**
- Create: `lib/core/music/chord_catalog.dart`
- Test: `test/chord_catalog_test.dart`

- [ ] **Step 1: 鍐欏け璐ユ祴璇?* `test/chord_catalog_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/music/chord_catalog.dart';
import 'package:guitarbar/core/music/chord_parser.dart';

void main() {
  test('鍥涘ぇ鍒嗙被瑕嗙洊鍏ㄩ儴 17 绉嶅瓙绫汇€佹棤閲嶅', () {
    final all = <String>{};
    for (final cat in chordCategories) {
      for (final sub in cat.subtypes) {
        expect(all.contains(sub.suffix), isFalse,
            reason: '${sub.suffix} 閲嶅鍑虹幇鍦?${cat.name}');
        all.add(sub.suffix);
      }
    }
    expect(all.length, 17);
    expect(chordCategories.length, 4);
    expect(chordCategories.map((c) => c.name),
        ['涓夊拰寮?, '涓冨拰寮?, '鎸傜暀鍜屽鸡', '鍔犻煶涓庢墿灞?]);
  });

  test('鐩綍涓庤В鏋愬櫒涓€鑷达細姣忎釜 (鏍归煶, 鍚庣紑) 鎷煎悕璧?parseChord 缁撴灉鐩稿悓', () {
    for (final root in rootNames.keys) {
      for (final cat in chordCategories) {
        for (final sub in cat.subtypes) {
          final p = parseChord(root + sub.suffix);
          expect(p.rootPc, rootNames[root],
              reason: '$root${sub.suffix} 鏍归煶');
          expect(p.intervals, sub.intervals,
              reason: '$root${sub.suffix} 闊崇▼');
        }
      }
    }
  });

  test('娴忚閫変腑鐩存帴鏋勯€?ParsedChord', () {
    final c = browseChord(9, 'm7'); // Am7
    expect(c.rootPc, 9);
    expect(c.intervals, [0, 3, 7, 10]);
  });

  test('browseChord 鏈煡鍚庣紑鎶?ArgumentError', () {
    expect(() => browseChord(0, 'zz'), throwsArgumentError);
  });

  test('鏍归煶琛?12 涓鐩栧叓搴︼紙0..11 鍞竴锛?, () {
    expect(rootNames.length, 12);
    expect(rootNames.values.toSet().length, 12);
    expect(rootNames['C'], 0);
    expect(rootNames['A'], 9);
  });
}
```

- [ ] **Step 2: 璺戞祴璇曠‘璁ゅけ璐?*

Run: `flutter test test/chord_catalog_test.dart`
Expected: FAIL锛坈hord_catalog.dart 涓嶅瓨鍦級

- [ ] **Step 3: 瀹炵幇** `lib/core/music/chord_catalog.dart`

```dart
import 'chord_parser.dart';

/// 鍜屽鸡鍒嗙被娴忚鐩綍锛堣璁℃枃妗?搂13.1锛夛細鏂版墜鏌ラ槄璺緞銆?/// 瀛愮被闊崇▼涓?chord_parser 鐨?_qualities 琛ㄥ悓婧愨€斺€斾竴鑷存€х敱
/// chord_catalog_test 鐨勪氦鍙夐獙璇侀拤浣忥紙鎷煎悕璧?parseChord 鏂█鐩稿悓锛夈€?class ChordSubtype {
  const ChordSubtype(this.suffix, this.name, this.intervals);
  final String suffix; // 鎷煎悕鍚庣紑锛?' 涓哄ぇ涓夛級
  final String name; // 涓枃鏄剧ず鍚?  final List<int> intervals; // 闊崇▼锛堜笌 _qualities 鍚屽€硷級
}

class ChordCategory {
  const ChordCategory(this.name, this.subtypes);
  final String name;
  final List<ChordSubtype> subtypes;
}

const _triads = ChordCategory('涓夊拰寮?, [
  ChordSubtype('', '澶т笁', [0, 4, 7]),
  ChordSubtype('m', '灏忎笁', [0, 3, 7]),
  ChordSubtype('aug', '澧炰笁', [0, 4, 8]),
  ChordSubtype('dim', '鍑忎笁', [0, 3, 6]),
  ChordSubtype('5', '浜斿害', [0, 7]),
]);

const _sevenths = ChordCategory('涓冨拰寮?, [
  ChordSubtype('7', '灞炰竷', [0, 4, 7, 10]),
  ChordSubtype('m7', '灏忎竷', [0, 3, 7, 10]),
  ChordSubtype('maj7', '澶т竷', [0, 4, 7, 11]),
  ChordSubtype('m7b5', '鍗婂噺涓?, [0, 3, 6, 10]),
]);

const _suspended = ChordCategory('鎸傜暀鍜屽鸡', [
  ChordSubtype('sus2', '鎸備簩', [0, 2, 7]),
  ChordSubtype('sus4', '鎸傚洓', [0, 5, 7]),
]);

const _extended = ChordCategory('鍔犻煶涓庢墿灞?, [
  ChordSubtype('add9', '鍔犱節', [0, 4, 7, 14]),
  ChordSubtype('6', '鍏拰寮?, [0, 4, 7, 9]),
  ChordSubtype('m6', '灏忓叚', [0, 3, 7, 9]),
  ChordSubtype('9', '灞炰節', [0, 4, 7, 10, 14]),
  ChordSubtype('m9', '灏忎節', [0, 3, 7, 10, 14]),
]);

const chordCategories = [_triads, _sevenths, _suspended, _extended];

/// 鏍归煶琛紙娴忚鐢紝闊冲悕 鈫?pitch class锛夈€?const rootNames = <String, int>{
  'C': 0, 'C#': 1, 'D': 2, 'D#': 3, 'E': 4, 'F': 5,
  'F#': 6, 'G': 7, 'G#': 8, 'A': 9, 'A#': 10, 'B': 11,
};

/// 娴忚閫変腑 鈫?ParsedChord锛堜笉缁忓瓧绗︿覆瑙ｆ瀽锛涚洰褰曚笌瑙ｆ瀽鍣ㄤ竴鑷存€х敱娴嬭瘯閽変綇锛夈€?ParsedChord browseChord(int rootPc, String suffix) {
  for (final cat in chordCategories) {
    for (final sub in cat.subtypes) {
      if (sub.suffix == suffix) return ParsedChord(rootPc, sub.intervals);
    }
  }
  throw ArgumentError('鏈煡鍜屽鸡绫诲瀷: $suffix');
}

/// 鎷煎拰寮︽樉绀哄悕锛堝 'Am7'锛涘ぇ涓夌┖鍚庣紑鍙樉鏍归煶锛夈€?String chordDisplayName(int rootPc, String suffix) {
  final root = rootNames.entries
      .firstWhere((e) => e.value == rootPc)
      .key;
  return root + suffix;
}
```

- [ ] **Step 4: 璺戞祴璇曠‘璁ら€氳繃**

Run: `flutter test test/chord_catalog_test.dart`
Expected: PASS锛涘叏閲?+ analyze銆?
- [ ] **Step 5: Commit**

```
git add lib/core/music/chord_catalog.dart test/chord_catalog_test.dart
git commit -m "feat: 鍜屽鸡鍒嗙被娴忚鐩綍锛?7 绉嶅洓鍒嗙被浜ゅ弶楠岃瘉锛?3.1锛?
```

---

### Task B: 鍜屽鸡搴撴祻瑙堟ā寮?UI

**Files:**
- Modify: `lib/ui/toolbox/chord_page.dart`
- Test: `test/chord_browse_test.dart`

- [ ] **Step 1: 瀹炵幇娴忚妯″紡**锛坄chord_page.dart`锛?
鏂板鐘舵€佸瓧娈碉細

```dart
  bool _browseMode = false;
  String _categoryName = '涓夊拰寮?;
  String _suffix = ''; // 褰撳墠瀛愮被鍚庣紑锛堥粯璁ゅぇ涓夛級
  int? _rootPc; // 閫夊畾鏍归煶锛沶ull = 鏈€?```

`_search` 鎶藉叕鍏辨煡璇紙杈撳叆/娴忚鍏辩敤锛夛細

```dart
  /// 鍏叡鏌ヨ锛歅arsedChord 鈫?鎸囨硶锛堣緭鍏ヨВ鏋愪笌娴忚鏋氫妇涓ゆ潯璺眹浜庢锛夈€?  void _query(ParsedChord c) {
    final state = context.read<TuningState>();
    _voicings = FingeringGenerator(state.current.strings)
        .generate(rootPc: c.rootPc, toneClasses: chordToneClasses(c));
    _error = null;
    setState(() {});
  }
```

鍘?`_search` 鏀逛负 `_search()` 鍐?`parseChord` + try/catch 鈫?`_query(c)`锛堥敊璇鐞嗕繚鐣欒緭鍏ユā寮忥級锛涙柊澧烇細

```dart
  void _browseSelect(int rootPc) {
    setState(() => _rootPc = rootPc);
    // 閫夊畾鏍归煶鍗虫煡璇紙绫诲瀷宸插繀鏈夐粯璁わ級锛涘悕瀛楀啓鍥炶緭鍏ユ锛屽垏鍥炶緭鍏ユā寮忔部鐢ㄣ€?    _input.text = chordDisplayName(rootPc, _suffix);
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
      // 鎹㈠ぇ绫婚粯璁ら€夊叾绗竴涓瓙绫汇€?      _suffix = chordCategories
          .firstWhere((c) => c.name == name)
          .subtypes
          .first
          .suffix;
    });
    if (_rootPc != null) _selectSubtype(_suffix);
  }
```

`_onTuningChanged` 鐨勯噸鏌ラ渶鍏煎娴忚妯″紡锛氭娊 `_research()`鈥斺€旀祻瑙堟ā寮忔寜 `_rootPc/_suffix` 閲嶆煡銆佽緭鍏ユā寮忔寜 `_search()`锛堣嫢鏃?voicings 涓旀湭鏌ヨ杩囧垯璺宠繃锛夈€傛渶绠€瀹炵幇锛?
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

UI锛坆uild 鍐呰緭鍏ヨ涔嬪墠鍔犳ā寮忓垏鎹紝鍒囨崲鍚庤緭鍏ヨ鎹㈡垚娴忚闈㈡澘锛夛細

```dart
        // 妯″紡鍒囨崲锛氳緭鍏ワ紙涔愭墜锛? 娴忚锛堟柊鎵嬫煡闃咃紝13.1锛夈€?        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('杈撳叆')),
            ButtonSegment(value: true, label: Text('娴忚')),
          ],
          selected: {_browseMode},
          onSelectionChanged: (s) =>
              setState(() => _browseMode = s.first),
        ),
        const SizedBox(height: 12),
        if (!_browseMode)
          Row(children: [ /* 鍘熻緭鍏ヨ鏁翠綋涓嶅姩 */ ]),
        if (_browseMode) ..._browsePanel(palette),
```

`_browsePanel`锛堜笁琛?Wrap锛岄€夋嫨鍗虫煡锛夛細

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
        Text('閫夊畾鏍归煶鍚庢樉绀烘寚娉?,
            style: TextStyle(fontSize: 12, color: p.muted)),
      const SizedBox(height: 8),
    ];
  }
```

import 琛?`import '../../core/music/chord_catalog.dart';`銆?
- [ ] **Step 2: widget 娴嬭瘯** `test/chord_browse_test.dart`

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
  // TuningState 渚濊禆 AppDatabase锛堣嚜瀹氫箟棰勮琛級锛涘唴缃爣鍑嗚皟寮﹀嵆棣栭璁俱€?  testWidgets('娴忚妯″紡锛氬垏鍒版祻瑙?鈫?閫夋牴闊?C 鍑烘寚娉曞崱', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final tuning = TuningState(db)..load();
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<TuningState>.value(value: tuning),
    ], child: MaterialApp(
        theme: GuitarBarTheme.light(), home: const ChordPage())));
    await tester.pumpAndSettle();
    // 鍒囨祻瑙堛€?    await tester.tap(find.text('娴忚'));
    await tester.pumpAndSettle();
    // 榛樿涓夊拰寮?澶т笁 + 閫夋牴闊?C 鈫?鏌ヨ鍑烘寚娉曪紙C 澶т笁鑷冲皯 1 涓寚娉曪級銆?    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle();
    expect(find.byType(Card), isNotEmpty);
    // 杈撳叆妗嗗悓姝ユ樉绀?C銆?    expect(find.widgetWithText(TextField, 'C'), findsOneWidget);
  });

  testWidgets('娴忚妯″紡锛氭崲瀛愮被鍒板皬涓?鈫?杈撳叆妗嗗悓姝?Cm', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final tuning = TuningState(db)..load();
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<TuningState>.value(value: tuning),
    ], child: MaterialApp(
        theme: GuitarBarTheme.light(), home: const ChordPage())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('娴忚'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('灏忎笁'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Cm'), findsOneWidget);
  });
}
```

锛堣嫢 TuningState 鏋勯€?鍔犺浇涓庢祴璇曠幆澧冩湁鍑哄叆鈥斺€斿弬鑰?`test/tuning_state_test.dart` 鏃㈡湁鍐欐硶瀵归綈锛汼oundEngine init 澶辫触涓嶅奖鍝嶆寚娉曟覆鏌撳彧绂佽瘯鍚€傦級

- [ ] **Step 3: 鍏ㄩ噺楠岃瘉**

Run: `flutter test`锛堝叏閲忥級+ `flutter analyze`
Expected: 鍏ㄧ豢 / No issues

- [ ] **Step 4: Commit**

```
git add lib/ui/toolbox/chord_page.dart test/chord_browse_test.dart
git commit -m "feat: 鍜屽鸡搴撴祻瑙堟ā寮忥紙鍒嗙被鏍懨楁牴闊崇偣閫夊嚭鎸囨硶锛?3.1锛?
```

---

## 鏀跺熬

- [ ] 鍏ㄩ噺娴嬭瘯 + analyze
- [ ] 璧版煡娓呭崟琛?acceptance.md锛氭祻瑙堟ā寮忛€夌被鍨?鏍归煶鍑烘寚娉?鍚嶅瓧鍐欏洖杈撳叆妗嗭紙鍒囧洖杈撳叆妯″紡娌跨敤锛?璋冨鸡鑱斿姩鍦ㄦ祻瑙堟ā寮忛噸鏌?鍥涜瘯鍚彲鐢?- [ ] todo.md 鍕鹃€?13.1
