import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'core/watchdog.dart';
import 'data/database.dart';
import 'state/practice_timer.dart';
import 'state/theme_settings.dart';
import 'state/tuning_state.dart';
import 'ui/root.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 心跳守护（2026-11-04 关闭卡死兜底）：主线程 event loop 一旦被播放
  // 引擎等同步调用卡死，守护 isolate 6.5s 后自动 exit(0)——窗口关闭
  // 回调排不上队也有最后一道防线。必须在最早期启动。
  Watchdog.start();
  // pdfrx 引擎初始化：导入流程在无 pdfrx 组件参与时直接调引擎 API，需先初始化。
  await pdfrxFlutterInitialize();
  await windowManager.ensureInitialized();
  // 窗口比例（2026-11-23 用户定案改**横向**）：Windows 横屏设计比例
  // ——1150×780（竖屏比例弃用）；最小 900×620；打开居中。
  const options = WindowOptions(
    size: Size(920, 820), // 920 > 侧栏断点 900：避开 5px 边界（2026-11-23 用户定）
    minimumSize: Size(900, 620),
    center: true,
    title: 'GuitarBar',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  // 拦截 X 关闭：由 root.dart 的 onWindowClose 优雅停机后再 destroy。
  await windowManager.setPreventClose(true);
  final db = AppDatabase(openConnection());
  PracticeTimer.init(db);
  runApp(MultiProvider(providers: [
    Provider<AppDatabase>.value(value: db),
    ChangeNotifierProvider(create: (_) => TuningState(db)..load()),
    ChangeNotifierProvider(create: (_) => ThemeSettingsState(db)..load()),
    ChangeNotifierProvider<PracticeTimer>.value(value: PracticeTimer.I),
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
