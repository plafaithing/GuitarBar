import 'dart:ffi' as ffi;

/// 强制终止进程（2026-11-04 关闭卡死实锤修复）。
///
/// 背景：close-log 证实 onWindowClose 全部走完、`exit(0)` 已调用但进程
/// 仍存活——**exit() 的 C 终止序列本身挂死**（播放过 soloud 引擎后，
/// native atexit/DLL_PROCESS_DETACH 清理钩子死锁；冷启动关闭 124ms
/// 正常，播放过必卡）。dart:io exit 与任何"优雅退出"都不可用。
///
/// [hardExit] 直调 kernel32.TerminateProcess(GetCurrentProcess(), 0)：
/// 无条件立即终止本进程，不走 CRT/atexit/Detach 清理——资源由 OS 回收
/// （与既有定案一致：drift WAL 崩溃安全，音频/录音线程交给 OS）。
ffi.DynamicLibrary? _k32cache;
int Function(int, int)? _terminate;
int Function()? _getCurrentProcess;

void _init() {
  final k32 = _k32cache ??= ffi.DynamicLibrary.open('kernel32.dll');
  _getCurrentProcess ??= k32
      .lookupFunction<ffi.IntPtr Function(), int Function()>(
          'GetCurrentProcess');
  _terminate ??= k32.lookupFunction<
      ffi.Int32 Function(ffi.IntPtr, ffi.Uint32),
      int Function(int, int)>('TerminateProcess');
}

/// 无条件立即终止当前进程（exit code 0）。不返回。
void hardExit() {
  _init();
  _terminate!(_getCurrentProcess!(), 0);
}
