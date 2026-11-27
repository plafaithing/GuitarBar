// 一次性调试：dump 某 gpx 在 w=786 下 y≈914 附近的所有捕获墨盒
// （定位 mf × 2 同 y 相撞的真实元素）。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guitarbar/core/score/gtp_parser.dart';
import 'package:guitarbar/ui/scores/tab_view.dart';
import 'package:guitarbar/ui/theme.dart';

import 'font_setup.dart';

void main() {
  setUpAll(loadScoreFonts);
  testWidgets('dump 墨盒', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(786, 2400);
    addTearDown(tester.view.reset);
    final dir = Directory(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores');
    // 找第一个 gpx
    File? gpx;
    for (final d in dir.listSync()) {
      if (d is Directory) {
        for (final f in d.listSync()) {
          if (f is File && f.path.toLowerCase().endsWith('.gpx')) {
            gpx = f;
            break;
          }
        }
      }
      if (gpx != null) break;
    }
    expect(gpx, isNotNull);
    final ir = parseGpxBytes(
        Uint8List.fromList(gpx!.readAsBytesSync()),
        sourceName: gpx.uri.pathSegments.last);
    await tester.pumpWidget(MaterialApp(
      theme: GuitarBarTheme.light(),
      home: Scaffold(
          body: SizedBox(
              width: 786, height: 2400, child: TabView(ir: ir))),
    ));
    await tester.pumpAndSettle();
    final caps = TabViewDebug.lastPaintedTexts.toList()
      ..sort((a, b) => a.centerY.compareTo(b.centerY));
    // dump y 850~980 的全部墨盒
    for (final c in caps) {
      if (c.centerY >= 850 && c.centerY <= 980) {
        debugPrint('y=${c.centerY.toStringAsFixed(0)} x=${c.centerX.toStringAsFixed(0)} '
            'w=${(c.halfW * 2).toStringAsFixed(0)} "${c.text}"');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
