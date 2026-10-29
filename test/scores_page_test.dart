import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_files.dart';
import 'package:guitarbar/core/score/score_repository.dart';
import 'package:guitarbar/data/database.dart';
import 'package:guitarbar/ui/theme.dart';
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
    ], child: MaterialApp(theme: GuitarBarTheme.light(), home: Scaffold(body: ScoresPage(
        repoFactory: () => ScoreRepository(db, ScoreFiles(tmp)))))));
    await tester.pumpAndSettle();
    expect(find.text('还没有曲谱，点右上角导入图片或 PDF'), findsOneWidget);
  });
}
