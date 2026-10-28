import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/ui/theme.dart';
import 'package:guitarbar/ui/tuner/guitar_headstock.dart';

/// 标准调弦 E2 A2 D3 G3 B3 E4（弦 0 = 低音 E）。
const _standard = ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'];

void main() {
  group('琴头几何', () {
    for (final h in const [330.0, 400.0, 520.0, 620.0]) {
      test('h=$h：方钮与琴头/弦钮互不重叠，且触控区达标', () {
        final m = HeadstockMetrics.forHeight(h);
        final canvas = Offset.zero & m.canvas;

        // 1) 方钮全部落在画布内。
        for (var i = 0; i < 6; i++) {
          expect(canvas.contains(m.buttonRects[i].topLeft), isTrue,
              reason: '弦 $i 方钮左上越界');
          expect(canvas.contains(m.buttonRects[i].bottomRight - const Offset(0.01, 0.01)),
              isTrue, reason: '弦 $i 方钮右下越界');
        }

        // 2) 方钮之间不重叠。
        for (var i = 0; i < 6; i++) {
          for (var j = i + 1; j < 6; j++) {
            expect(m.buttonRects[i].overlaps(m.buttonRects[j]), isFalse,
                reason: '方钮 $i 与 $j 重叠');
          }
        }

        // 3) 方钮不压琴头板。
        for (var i = 0; i < 6; i++) {
          expect(m.buttonRects[i].overlaps(m.plate), isFalse,
              reason: '方钮 $i 压在琴头板上');
        }

        // 4) 方钮不压外伸弦钮（旧版圆钮正好压在这里）。
        for (var i = 0; i < 6; i++) {
          for (var k = 0; k < 6; k++) {
            expect(m.buttonRects[i].overlaps(m.machineRects[k]), isFalse,
                reason: '方钮 $i 与弦钮 $k 重叠');
          }
        }

        // 5) 弦钮都在琴头板外侧（不埋进木头里）。
        for (final r in m.machineRects) {
          expect(m.plate.contains(r.center), isFalse,
              reason: '弦钮中心落在板内');
        }

        // 6) 压弦柱落在板内，且三排等距。
        for (var i = 0; i < 6; i++) {
          expect(m.plate.width / 2 - (m.postX(i) - m.plate.center.dx).abs(),
              greaterThan(0), reason: '弦 $i 压弦柱在板外');
        }
        final gaps = [
          m.rowYs[1] - m.rowYs[0],
          m.rowYs[2] - m.rowYs[1],
        ];
        expect((gaps[0] - gaps[1]).abs(), lessThan(0.001), reason: '三排弦钮不等距');

        // 7) 触控区 ≥ 44（h ≥ 330 时应满足）。
        expect(m.buttonSide, greaterThanOrEqualTo(44.0));
      });
    }

    test('极端小尺寸（h=200）只缩钮，不重叠也不出界', () {
      final m = HeadstockMetrics.forHeight(200);
      final canvas = Offset.zero & m.canvas;
      for (var i = 0; i < 6; i++) {
        expect(
            canvas.contains(
                m.buttonRects[i].bottomRight - const Offset(0.01, 0.01)),
            isTrue,
            reason: '弦 $i 方钮越界');
        expect(m.buttonRects[i].overlaps(m.plate), isFalse);
        for (var j = i + 1; j < 6; j++) {
          expect(m.buttonRects[i].overlaps(m.buttonRects[j]), isFalse,
              reason: '方钮 $i 与 $j 重叠');
        }
      }
      // fit() 也要在给定约束内收敛。
      final fitted = HeadstockMetrics.fit(const Size(320, 260));
      expect(fitted.canvas.width, lessThanOrEqualTo(320.5));
      expect(fitted.canvas.height, lessThanOrEqualTo(260.5));
    });

    test('弦序与左右列一致：左列 D A E，右列 G B E', () {
      expect(HeadstockMetrics.stringAt(0, true), 2); // D3
      expect(HeadstockMetrics.stringAt(1, true), 1); // A2
      expect(HeadstockMetrics.stringAt(2, true), 0); // E2
      expect(HeadstockMetrics.stringAt(0, false), 3); // G3
      expect(HeadstockMetrics.stringAt(1, false), 4); // B3
      expect(HeadstockMetrics.stringAt(2, false), 5); // E4
    });
  });

  testWidgets('渲染预览图（供人工比对参考图）', (tester) async {
    final dir = Directory('${Directory.systemTemp.path}/guitarbar-shots');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final cases = <String, (bool, int, int, bool)>{
      // 名字: (深色?, 命中弦, 音分, 有音高?)
      'idle-light': (false, -1, 0, false),
      'idle-dark': (true, -1, 0, false),
      'hit-light': (false, 1, 12, true),
      'intune-dark': (true, 2, 1, true),
    };

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final e in cases.entries) {
      final (dark, hit, cents, hasPitch) = e.value;
      final key = GlobalKey();
      final theme = dark ? GuitarBarTheme.dark() : GuitarBarTheme.light();
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              // 底色随主题，便于判断插画在真实页面底色上的对比度。
              child: Container(
                color: theme.scaffoldBackgroundColor,
                width: 700,
                height: 560,
                child: Center(
                  child: SizedBox(
                    width: 660,
                    height: 524,
                    child: GuitarHeadstock(
                      labels: _standard,
                      hitIndex: hit,
                      lockedIndex: null,
                      hasPitch: hasPitch,
                      cents: cents,
                      onTapString: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(
          () => boundary.toImage(pixelRatio: 2.0));
      final bytes = await tester.runAsync(
          () => image!.toByteData(format: ui.ImageByteFormat.png));
      File('${dir.path}/headstock-${e.key}.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image!.dispose();
    }
  });
}
