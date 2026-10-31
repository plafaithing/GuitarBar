import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/ui/scores/source_viewer.dart';
import 'package:guitarbar/ui/theme.dart';

// 1x1 合法 PNG（同 score_detail_page_test 用法，真实可解码）。
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

/// 临时目录造 n 张页图。
Directory _makePages(int n) {
  final tmp = Directory.systemTemp.createTempSync('sourceviewer');
  addTearDown(() => tmp.deleteSync(recursive: true));
  for (var i = 1; i <= n; i++) {
    File('${tmp.path}${Platform.pathSeparator}'
            'page-${i.toString().padLeft(3, '0')}.png')
        .writeAsBytesSync(base64Decode(_pngBase64));
  }
  return tmp;
}

List<File> _files(Directory dir, int n) => [
      for (var i = 1; i <= n; i++)
        File('${dir.path}${Platform.pathSeparator}'
            'page-${i.toString().padLeft(3, '0')}.png')
    ];

Future<void> _pumpViewer(WidgetTester tester, SourceViewer viewer) async {
  await tester.pumpWidget(
      MaterialApp(theme: GuitarBarTheme.light(), home: Scaffold(body: viewer)));
  await tester.pumpAndSettle();
}

Future<void> _wheel(WidgetTester tester, Offset delta,
    {bool ctrl = false}) async {
  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendEventToBinding(PointerScrollEvent(
      position: tester.getCenter(find.byType(SourceViewer)),
      scrollDelta: delta));
  await tester.pump();
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

Matrix4 _matrix(WidgetTester tester) => tester
    .widget<Transform>(find.byKey(SourceViewer.transformKey))
    .transform;

/// 双击（两次 tap 间隔 kDoubleTapMinTime）。
Future<void> _doubleTap(WidgetTester tester) async {
  await tester.tap(find.byType(SourceViewer));
  await tester.pump(kDoubleTapMinTime);
  await tester.tap(find.byType(SourceViewer));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('空页图显示占位文案', (tester) async {
    await _pumpViewer(tester, const SourceViewer(pagePngs: []));
    expect(find.text('没有页图'), findsOneWidget);
  });

  testWidgets('滚轮翻页：下滚下一页、上滚上一页', (tester) async {
    final dir = _makePages(2);
    await _pumpViewer(tester, SourceViewer(pagePngs: _files(dir, 2)));
    expect(find.text('1 / 2'), findsOneWidget);
    await _wheel(tester, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await _wheel(tester, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('Ctrl+滚轮缩放；缩放态滚轮翻页锁定（平移不翻页）', (tester) async {
    final dir = _makePages(2);
    await _pumpViewer(tester, SourceViewer(pagePngs: _files(dir, 2)));
    // Ctrl+上滚 → 放大一格（1.0 + 0.1）
    await _wheel(tester, const Offset(0, -120), ctrl: true);
    expect(_matrix(tester).getMaxScaleOnAxis(), closeTo(1.1, 0.001));
    // 缩放态普通滚轮 → 垂直平移：页码不变、translate.y 减小（内容上移）
    final tyBefore = _matrix(tester).getTranslation().y;
    await _wheel(tester, const Offset(0, 120));
    expect(find.text('1 / 2'), findsOneWidget);
    expect(_matrix(tester).getTranslation().y, lessThan(tyBefore));
    // 双击复位后滚轮恢复翻页
    await _doubleTap(tester);
    expect(_matrix(tester).getMaxScaleOnAxis(), closeTo(1.0, 0.001));
    await _wheel(tester, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('双击放大到 2.5 倍居中；再双击复位', (tester) async {
    final dir = _makePages(1);
    await _pumpViewer(tester, SourceViewer(pagePngs: _files(dir, 1)));
    await _doubleTap(tester);
    expect(_matrix(tester).getMaxScaleOnAxis(), closeTo(2.5, 0.001));
    // 居中锚定：t = -c·(s-1)，c = 视口中心 (400, 300)
    final t = _matrix(tester).getTranslation();
    expect(t.x, closeTo(-400 * 1.5, 0.5));
    expect(t.y, closeTo(-300 * 1.5, 0.5));
    await _doubleTap(tester);
    expect(_matrix(tester).getMaxScaleOnAxis(), closeTo(1.0, 0.001));
  });

  testWidgets('双指捏合放大（锚点指间）', (tester) async {
    final dir = _makePages(1);
    await _pumpViewer(tester, SourceViewer(pagePngs: _files(dir, 1)));
    final g1 = await tester.startGesture(const Offset(300, 300));
    final g2 = await tester.startGesture(const Offset(500, 300));
    await tester.pump();
    // 张开 200 → 300：比例 1.5
    await g1.moveBy(const Offset(-50, 0));
    await g2.moveBy(const Offset(50, 0));
    await tester.pump();
    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();
    expect(_matrix(tester).getMaxScaleOnAxis(), closeTo(1.5, 0.01));
  });

  testWidgets('触摸横拉翻页（拖过半屏松手进下一页）', (tester) async {
    final dir = _makePages(2);
    await _pumpViewer(tester, SourceViewer(pagePngs: _files(dir, 2)));
    final g = await tester
        .startGesture(tester.getCenter(find.byType(SourceViewer)));
    await tester.pump();
    // 拖 500/800 过半屏：松手按 round(0.625) 对齐下一页。甩动速度路径
    // 不在此测——widget 测试 fake clock 不推进 pointer 事件时间戳（恒 0），
    // dt=0 时速度恒 0，settle 走 round 分支。
    await g.moveBy(const Offset(-250, 0));
    await tester.pump();
    await g.moveBy(const Offset(-250, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('文本模式：全文展示、无翻页、复制按钮写剪贴板', (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = call.arguments['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    const text = '<GPIF><Score>hello</Score></GPIF>';
    await _pumpViewer(
        tester, const SourceViewer(pagePngs: [], gpxSourceText: text));
    expect(find.textContaining('<GPIF>'), findsOneWidget);
    expect(find.byType(PageView), findsNothing); // 文本模式无翻页
    await tester.tap(find.text('复制'));
    await tester.pump();
    expect(clipboard, text);
  });

  testWidgets('文本模式：滚轮滚动（内容上移）、Ctrl+滚轮缩放', (tester) async {
    // 长文本（50 行 ≈ 840px > 视口 600px）才有滚动余量。
    final long = [for (var i = 0; i < 50; i++) 'line $i'].join('\n');
    await _pumpViewer(
        tester, SourceViewer(pagePngs: const [], gpxSourceText: long));
    await _wheel(tester, const Offset(0, 120));
    expect(_matrix(tester).getTranslation().y, lessThan(0));
    await _wheel(tester, const Offset(0, -120), ctrl: true);
    expect(_matrix(tester).getMaxScaleOnAxis(), closeTo(1.1, 0.001));
  });
}
