// 测试共享：加载生产字体（谱面文字显式请求 kUiFontFamily='Microsoft
// YaHei'，见 tab_view._text / tab_layout._measureInk）。测试环境不加载
// 时 family 缺失走 fallback 链 → 度量与生产不一致，布局断言会漂移
// （2026-11-16 重叠探针实证）。字体文件缺失（非本机/CI）时静默跳过，
// 度量退回测试默认——探针口径偏保守不偏松。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;

Future<void> loadScoreFonts() async {
  final loader = FontLoader('Microsoft YaHei');
  for (final p in [
    r'C:\Windows\Fonts\msyh.ttc',
    r'C:\Windows\Fonts\msyhbd.ttc',
  ]) {
    final f = File(p);
    if (!f.existsSync()) continue;
    final bytes = f.readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}
