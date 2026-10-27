import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'data/database.dart';
import 'state/theme_settings.dart';
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
    ChangeNotifierProvider(create: (_) => ThemeSettingsState(db)..load()),
  ], child: const GuitarBarApp()));
}

class GuitarBarApp extends StatelessWidget {
  const GuitarBarApp({super.key});

  @override
  Widget build(BuildContext context) => Consumer<ThemeSettingsState>(
        builder: (_, theme, _) => MaterialApp(
              title: 'GuitarBar',
              theme: GuitarBarTheme.light(),
              darkTheme: GuitarBarTheme.dark(),
              // 主题模式由 ThemeSettingsState 持久化驱动（个人中心三选）。
              themeMode: theme.mode,
              debugShowCheckedModeBanner: false,
              home: const RootPage(),
            ),
      );
}
