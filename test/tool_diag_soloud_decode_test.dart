// 一次性诊断：真 soloud 引擎逐个 loadMem 全部 114 个采样 ogg——解码
// 失败清单（多谱共因的降级源实锤）。
@Tags(['heavy'])
library;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/audio/sound_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('真引擎解码全采样', () async {
    final engine = SoundEngine.I;
    await engine.init();
    final dir = Directory(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\flutter_assets\assets\sounds\steel');
    final files = dir.listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
    debugPrint('files=${files.length}');
    var ok = 0;
    final failed = <String, String>{};
    for (final f in files) {
      final bytes = await rootBundle.load(f.path.replaceFirst(
          r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\flutter_assets\', ''));
      try {
        final src = await engine.loadOgg(
            f.path.split(r'\').last, bytes.buffer.asUint8List());
        ok++;
        unawaited2(engine.disposeSource(src));
      } catch (e) {
        failed[f.path.split(r'\').last] = '$e';
      }
    }
    debugPrint('ok=$ok failed=${failed.length}');
    for (final e in failed.entries.take(20)) {
      debugPrint('  [FAIL] ${e.key}: ${e.value}');
    }
    await engine.shutdown();
  }, timeout: const Timeout(Duration(minutes: 5)));
}

void unawaited2(Future f) {}
