// Temp probe (not committed): reproduce bottomSheet fill-screen bug.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/ui/scores/play_bar.dart';
import 'package:guitarbar/ui/theme.dart';

void main() {
  testWidgets('PROBE1: plain body', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: GuitarBarTheme.light(),
        home: Scaffold(
          appBar: AppBar(title: const Text('T')),
          body: Container(color: const Color(0xFFEDEBE6)),
          bottomSheet: const PlayBar(
              playing: true, positionSeconds: 1.0, durationSeconds: 100.0,
              onToggle: _noop),
        )));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(PlayBar));
    // ignore: avoid_print
    print('PROBE1 size=$size');
    expect(size.height, lessThan(100), reason: 'one-row bar expected');
  });

  testWidgets('PROBE2: wide Row body (detail-page shape)', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: GuitarBarTheme.light(),
        home: Scaffold(
          appBar: AppBar(title: const Text('T')),
          body: LayoutBuilder(builder: (ctx, box) {
            return Row(children: [
              const Expanded(child: SizedBox()),
              SizedBox(
                  width: 360,
                  child: Container(color: const Color(0xFFEDEBE6))),
            ]);
          }),
          bottomSheet: const PlayBar(
              playing: true, positionSeconds: 1.0, durationSeconds: 100.0,
              onToggle: _noop),
        )));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(PlayBar));
    // ignore: avoid_print
    print('PROBE2 size=$size');
    expect(size.height, lessThan(100));
  });

  testWidgets('PROBE3: DefaultTabController Column body (narrow shape)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: GuitarBarTheme.light(),
        home: Scaffold(
          appBar: AppBar(title: const Text('T')),
          body: DefaultTabController(
            length: 2,
            child: Column(children: const [
              TabBar(tabs: [Tab(text: 'A'), Tab(text: 'B')]),
              Expanded(child: SizedBox()),
            ]),
          ),
          bottomSheet: const PlayBar(
              playing: true, positionSeconds: 1.0, durationSeconds: 100.0,
              onToggle: _noop),
        )));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(PlayBar));
    // ignore: avoid_print
    print('PROBE3 size=$size');
    expect(size.height, lessThan(100));
  });
}

void _noop() {}
