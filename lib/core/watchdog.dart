import 'dart:async';
import 'dart:isolate';

import 'hard_exit.dart';

/// 关闭守护（2026-11-04 v2：关闭监视模式）。
///
/// 背景链：播放过 soloud 引擎后，`exit(0)` 的 C 终止序列挂死（close-log
/// 实锤：onWindowClose 四步全走完、进程不死；taskkill /F 都杀不动的
/// 僵尸现场）。hardExit（TerminateProcess）是终点修复。
///
/// v1 心跳误杀教训：启动的 5s 同步段内主 isolate 不回 pong，守护在
/// ~6.5s 时把刚启动的应用杀了。v2 改为**关闭监视**——平时零干预，
/// 收到 [armExit]（onWindowClose 开头）后才武装：2s 内进程必须消失
/// （正常路径 hardExit 先行；若主 isolate 卡在打卡 await，守护补刀）。
class Watchdog {
  Watchdog._();

  static SendPort? _guardPort;

  /// app 启动即调用（main.dart）：spawn 守护 isolate 待命。
  static void start() {
    final port = ReceivePort();
    unawaited(Isolate.spawn(_guard, port.sendPort));
    unawaited(port.first.then((sp) => _guardPort = sp as SendPort));
  }

  /// onWindowClose 开头调用：武装守护，2s 后无论主线程死活强杀。
  static void armExit() => _guardPort?.send(0);

  static Future<void> _guard(SendPort toMain) async {
    final toGuard = ReceivePort();
    toMain.send(toGuard.sendPort); // 把回信道交给主 isolate
    await toGuard.first; // 阻塞等武装信号（isolate 间消息，不走主线程）
    await Future<void>.delayed(const Duration(milliseconds: 2000));
    hardExit();
  }
}
