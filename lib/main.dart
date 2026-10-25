import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'ui/root.dart';

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
  runApp(const GuitarBarApp());
}

class GuitarBarApp extends StatelessWidget {
  const GuitarBarApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'GuitarBar',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: const RootPage(),
      );
}
