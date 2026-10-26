import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'data/database.dart';
import 'state/tuning_state.dart';
import 'ui/root.dart';
import 'ui/theme.dart';

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
  final db = AppDatabase(openConnection());
  runApp(MultiProvider(providers: [
    Provider<AppDatabase>.value(value: db),
    ChangeNotifierProvider(create: (_) => TuningState(db)..load()),
  ], child: const GuitarBarApp()));
}

class GuitarBarApp extends StatelessWidget {
  const GuitarBarApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'GuitarBar',
        // debug 构建演示截图不带右上角 DEBUG 丝带（release 本就没有）。
        debugShowCheckedModeBanner: false,
        theme: GuitarBarTheme.light(),
        home: const RootPage(),
      );
}
