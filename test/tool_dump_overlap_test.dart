// 一次性调试（2026-11-16 重叠探针残类定位）：忠实复刻探针判决，
// 对每个违例谱打印曲名 + 违例 y 带的捕获墨盒/flow 全列。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guitarbar/core/score/gp34_parser.dart';
import 'package:guitarbar/core/score/gp5_parser.dart';
import 'package:guitarbar/core/score/gtp12_parser.dart';
import 'package:guitarbar/core/score/gtp_parser.dart';
import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/ui/scores/tab_layout.dart';
import 'package:guitarbar/ui/scores/tab_view.dart';
import 'package:guitarbar/ui/theme.dart';

import 'font_setup.dart';

const _appDataScores =
    r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores';

String? _flavor(List<int> bytes) {
  if (bytes.length < 31) return null;
  final size = bytes[0];
  final raw = latin1.decode(bytes.sublist(1, 31));
  final version =
      (size < 1 ? '' : raw.substring(0, size < 30 ? size : 30)).trim();
  if (version.contains('GUITARE') ||
      version.contains('GUITAR PRO v1') ||
      version.contains('v2.20') ||
      version.contains('v2.21')) {
    return 'gtp12';
  }
  if (version.contains('v3.') ||
      version.contains('v4.') ||
      version.contains('L4.')) {
    return 'gp34';
  }
  if (version.contains('v5.')) return 'gp5';
  return null;
}

ScoreIr? _parse(Uint8List bytes, String name) {
  try {
    final head4 = latin1.decode(bytes.sublist(0, 4));
    if (head4 == 'BCFZ' || head4.startsWith('PK')) {
      return parseGpxBytes(bytes, sourceName: name);
    }
    final flavor = _flavor(bytes);
    if (flavor == null) return null;
    return switch (flavor) {
      'gtp12' => parseGtp12Bytes(bytes),
      'gp34' => parseGp34Bytes(bytes),
      'gp5' => parseGp5Bytes(bytes),
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

void main() {
  setUpAll(loadScoreFonts);
  testWidgets('dump 探针违例谱', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(786, 2400);
    addTearDown(tester.view.reset);
    final dir = Directory(_appDataScores);
    for (final d in dir.listSync()) {
      if (d is! Directory) continue;
      for (final x in d.listSync()) {
        if (x is! File) continue;
        final ext = x.path.toLowerCase().split('.').last;
        if (!['gpx', 'gp3', 'gp4', 'gp5', 'gtp'].contains(ext)) continue;
        final bytes = Uint8List.fromList(x.readAsBytesSync());
        final ir = _parse(bytes, d.uri.pathSegments.last);
        if (ir == null) continue;
        await tester.pumpWidget(MaterialApp(
          theme: GuitarBarTheme.light(),
          home: Scaffold(
              body:
                  SizedBox(width: 786, height: 2400, child: TabView(ir: ir))),
        ));
        await tester.pumpAndSettle();
        final caps = TabViewDebug.lastPaintedTexts;
        final violations = <String>[];
        for (var i = 0; i < caps.length; i++) {
          for (var j = i + 1; j < caps.length; j++) {
            final a = caps[i], b = caps[j];
            if ((a.centerX - b.centerX).abs() < a.halfW + b.halfW - 1 &&
                (a.centerY - b.centerY).abs() < a.halfH + b.halfH - 1) {
              violations.add('"${a.text}"@(${a.centerX.toStringAsFixed(0)},'
                  '${a.centerY.toStringAsFixed(0)}) x '
                  '"${b.text}"@(${b.centerX.toStringAsFixed(0)},'
                  '${b.centerY.toStringAsFixed(0)})');
            }
          }
        }
        if (violations.isEmpty) continue;
        debugPrint('### 违例谱: ${d.uri.pathSegments.last} '
            '($ext) 违例 ${violations.length} 处');
        for (final v in violations.take(8)) {
          debugPrint('  $v');
        }
        // 违例 y 带 → dump 该带墨盒 + flow 全列（±6px）
        final ys = violations
            .map((v) => double.tryParse(
                v.split('@').last.split(')').first.split(',')[1]))
            .whereType<double>()
            .toSet();
        for (final y0 in ys.take(3)) {
          debugPrint('--- y≈$y0 捕获墨盒 ---');
          final boxes = caps
              .where((c) => (c.centerY - y0).abs() < 8)
              .toList()
            ..sort((a, b) => a.centerX.compareTo(b.centerX));
          for (final c in boxes) {
            debugPrint('  box "${c.text}" @(${c.centerX.toStringAsFixed(1)},'
                '${c.centerY.toStringAsFixed(1)}) half(${c.halfW.toStringAsFixed(1)},'
                '${c.halfH.toStringAsFixed(1)})');
          }
          debugPrint('--- y≈$y0 flow 全列 ---');
          final band = TabViewDebug.lastFlow
              .where((f) => (f.y - y0).abs() < 8)
              .toList()
            ..sort((a, b) => a.x.compareTo(b.x));
          for (final f in band) {
            debugPrint('  flow m${f.mIdx + 1} '
                'b${f.note.beat.toStringAsFixed(3)} s${f.note.string} '
                'f${f.note.fret} "${TabLayout.tabLabel(f.note)}" '
                'x=${f.x.toStringAsFixed(1)} y=${f.y.toStringAsFixed(0)}');
          }
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
