import 'dart:async' show unawaited;
import 'dart:io' show Directory, File, FileMode, Platform;
import 'dart:isolate' show Isolate;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../core/hard_exit.dart';
import '../core/watchdog.dart';
import '../data/database.dart';
import '../state/practice_timer.dart';
import 'gbar_background.dart';
import 'profile/profile_page.dart';
import 'theme.dart';
import 'toolbox/toolbox_page.dart';
import 'tuner/tuner_page.dart';

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> with WindowListener {
  int _tab = 0;
  // 侧栏收起状态持久化到 settings 表（key: sidebarCollapsed，'1'/'0'）。
  bool _collapsed = false;
  static const _titles = ['调音器', '工具箱', '个人中心'];
  // 导航字形对：未选轮廓 / 选中填充。
  static const _icons = [
    Icons.music_note_outlined,
    Icons.home_repair_service_outlined,
    Icons.person_outline,
  ];
  static const _activeIcons = [
    Icons.music_note,
    Icons.home_repair_service,
    Icons.person,
  ];
  // 切页淡入：动效只做反馈（app 屏规则 150-200ms）。
  static const Duration _fadeDuration = Duration(milliseconds: 150);

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _loadCollapsed();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  /// 窗口关闭拦截（main 里 setPreventClose(true)）：1s 内强制关闭
  /// （2026-11-01 走查定案）。
  ///
  /// 时序：hide() 瞬间视觉关闭 → 打卡落库（唯一数据关键步，800ms 守卫）
  /// → exit(0) 强杀进程。此前 destroy() 方案窗口虽销毁但进程退出被
  /// native 线程（soloud 音频/录音）优雅收尾拖 5-10s——exit(0) 不等
  /// VM/native 收尾；打卡已完成（drift WAL 崩溃安全），mic/引擎资源
  /// 由 OS 回收，无数据风险。
  /// 关闭诊断日志（2026-11-04 用户实测：播放时/播放后关闭偶发卡死需
  /// 手动杀进程）。追加到 exe 旁 data\close-log.txt；写失败静默（日志
  /// 永不影响关闭本身）。
  void _closeLog(String msg) {
    try {
      final dir = Directory(p.join(
          File(Platform.resolvedExecutable).parent.path, 'data'));
      File(p.join(dir.path, 'close-log.txt')).writeAsStringSync(
          '${DateTime.now().toIso8601String()} $msg\n',
          mode: FileMode.append);
    } catch (_) {}
  }

  @override
  void onWindowClose() async {
    _closeLog('close: begin');
    Watchdog.armExit(); // 武装关闭守护：2s 内进程必须消失，否则补刀强杀
    unawaited(windowManager.hide()); // 即时视觉关闭（ms 级）
    _closeLog('close: hidden');
    // 独立 isolate 保险丝（2026-11-04 实锤升级）：主 isolate 的 event
    // loop 若被播放引擎的同步调用卡死，挂在其上的 Timer 一样不触发——
    // spawn 的 isolate 独立计时，无论主线程死活 1.5s 后 exit(0) 杀整个
    // 进程（dart:io exit 是进程级终止）。正常路径 stop 完成先行 exit，
    // 本 isolate 随进程消亡。
    unawaited(Isolate.spawn((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      hardExit(); // exit(0) 会挂在 native 终止序列（见 hard_exit.dart），必须强杀
    }, null));
    try {
      await PracticeTimer.I.stop(note: '应用关闭时自动保存')
          .timeout(const Duration(milliseconds: 800));
      _closeLog('close: practice-timer saved');
    } catch (_) {
      _closeLog('close: practice-timer failed/timeout');
    }
    _closeLog('close: hard-exiting');
    hardExit();
  }

  Future<void> _loadCollapsed() async {
    final db = context.read<AppDatabase>();
    final row = await (db.select(db.settings)
            ..where((t) => t.key.equals('sidebarCollapsed')))
        .getSingleOrNull();
    if (mounted && row != null) setState(() => _collapsed = row.value == '1');
  }

  Future<void> _toggleCollapsed() async {
    setState(() => _collapsed = !_collapsed);
    final db = context.read<AppDatabase>();
    await db.into(db.settings).insertOnConflictUpdate(SettingsCompanion.insert(
        key: 'sidebarCollapsed', value: _collapsed ? '1' : '0'));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      // 三页常驻保活（等价 IndexedStack）：非当前页 IgnorePointer + 透明，
      // 切页时新页 150ms 淡入；宽窄两种模式共用这一份 body。
      final body = Stack(children: [
        for (var i = 0; i < _titles.length; i++)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: i != _tab,
              child: AnimatedOpacity(
                opacity: i == _tab ? 1.0 : 0.0,
                duration: _fadeDuration,
                child: i == 0
                    ? const TunerPage()
                    : i == 2
                        ? const ProfilePage()
                        : const ToolboxPage(),
              ),
            ),
          ),
      ]);
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: wide
            ? null
            : AppBar(
                title: Text(_titles[_tab]),
                // 顶栏练习计时 chip：仅窄屏（有 AppBar）且计时中显示；
                // 宽屏无 AppBar，计时在个人中心页内可见。
                actions: [
                  Consumer<PracticeTimer>(builder: (_, t, _) {
                    if (!t.running) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Center(
                        child: Text(
                          '${t.elapsedSeconds ~/ 60}:${(t.elapsedSeconds % 60).toString().padLeft(2, '0')}',
                          style: TextStyle(
                              fontSize: 16,
                              fontFeatures: const [FontFeature.tabularFigures()],
                              color: context.palette.ink),
                        ),
                      ),
                    );
                  }),
                ],
              ),
        body: GbarBackground(
          // v2 统一背景（光晕）只在此画一次；子页 Scaffold 全透明。
          child: wide
              ? Row(children: [
                  _SideNav(
                    titles: _titles,
                    icons: _icons,
                    activeIcons: _activeIcons,
                    activeIndex: _tab,
                    collapsed: _collapsed,
                    onSelect: (i) => setState(() => _tab = i),
                    onToggleCollapse: _toggleCollapsed,
                  ),
                  Expanded(child: body),
                ])
              : body,
        ),
        bottomNavigationBar: wide
            ? null
            : Container(
                // 与宽屏侧栏同款分隔语言：地色底栏 + 顶部 1px 发丝线。
                decoration: BoxDecoration(
                  border: Border(
                      top: BorderSide(color: context.palette.border)),
                ),
                child: NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.music_note_outlined),
                      selectedIcon: Icon(Icons.music_note),
                      label: '调音器',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.home_repair_service_outlined),
                      selectedIcon: Icon(Icons.home_repair_service),
                      label: '工具箱',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.person_outline),
                      selectedIcon: Icon(Icons.person),
                      label: '个人中心',
                    ),
                  ],
                ),
              ),
      );
    });
  }
}

/// 宽屏左侧导航（Open 平面）：展开 205px / 收起 56px 图标栏，右缘 1px 发丝线；
/// 导航块在剩余空间垂直居中，底部预留练习计时器位。
class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.titles,
    required this.icons,
    required this.activeIcons,
    required this.activeIndex,
    required this.collapsed,
    required this.onSelect,
    required this.onToggleCollapse,
  });

  final List<String> titles;
  final List<IconData> icons;
  final List<IconData> activeIcons;
  final int activeIndex;
  final bool collapsed;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: collapsed ? 56 : 205,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: context.palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          collapsed ? _collapsedHeader(context) : _expandedHeader(context),
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < titles.length; i++)
                  _NavItem(
                    title: titles[i],
                    icon: icons[i],
                    activeIcon: activeIcons[i],
                    selected: i == activeIndex,
                    collapsed: collapsed,
                    onTap: () => onSelect(i),
                  ),
              ]),
            ),
          ),
          // 底部为练习计时器预留位（Task 17 填充）。
        ],
      ),
    );
  }

  Widget _expandedHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 24, right: 8, bottom: 12),
      child: Row(children: [
        const _PickMark(),
        const SizedBox(width: 8),
        Text(
          'GuitarBar',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.palette.ink),
        ),
        const Spacer(),
        IconButton(
          tooltip: '收起侧栏',
          onPressed: onToggleCollapse,
          icon: const Icon(Icons.keyboard_double_arrow_left),
          color: context.palette.muted,
        ),
      ]),
    );
  }

  Widget _collapsedHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _PickMark(),
          IconButton(
            tooltip: '展开侧栏',
            onPressed: onToggleCollapse,
            icon: const Icon(Icons.keyboard_double_arrow_right),
            color: context.palette.muted,
          ),
        ]),
      ),
    );
  }
}

/// 导航行：36px 高、38px 节距；选中项灰药丸（activePill），未选中项无底色坐在
/// 地色上。展开态图标 20 + 标签 18/400，收起态 36×36 药丸仅 20px 图标（Tooltip
/// 供悬停提示、Semantics 保留名称）；选中另加填充字形与标签提亮，图标色恒为
/// muted（形状变化不加色彩信号）。
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.title,
    required this.icon,
    required this.activeIcon,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final labelColor = selected ? p.ink : p.muted;
    final glyph = selected ? activeIcon : icon;
    Widget child = Container(
      // v2 选中态：dataHue 微光药丸（透明底 + 光晕装饰语言），替代原灰药丸。
      decoration: BoxDecoration(
        color: selected ? p.dataHue.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: selected
            ? Border.all(color: p.dataHue.withValues(alpha: 0.28))
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: Semantics(
          label: collapsed ? title : null,
          selected: selected,
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: SizedBox(
              height: 36,
              child: collapsed
                  ? Center(child: Icon(glyph, size: 20, color: labelColor))
                  : Row(children: [
                      const SizedBox(width: 8),
                      Icon(glyph, size: 20, color: labelColor),
                      const SizedBox(width: 10),
                      Text(
                        title,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: labelColor),
                      ),
                    ]),
            ),
          ),
        ),
      ),
    );
    if (collapsed) {
      child = Tooltip(message: title, child: child);
    }
    return Padding(
      // 收起态内缩 10 → 36×36 药丸；展开态内缩 12。
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 10.0 : 12.0, vertical: 1),
      child: child,
    );
  }
}

/// 品牌标记：拨片剪影（宽顶、底尖，微收腰）。
class _PickMark extends StatelessWidget {
  const _PickMark();

  @override
  Widget build(BuildContext context) => CustomPaint(
      size: const Size(20, 20),
      painter: _PickPainter(ink: context.palette.ink));
}

class _PickPainter extends CustomPainter {
  const _PickPainter({required this.ink});

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.50, h * 0.96) // 底部尖端
      ..cubicTo(w * 0.18, h * 0.66, 0, h * 0.46, 0, h * 0.28) // 左侧收腰
      ..cubicTo(0, h * 0.08, w * 0.20, 0, w * 0.50, 0) // 左上圆角
      ..cubicTo(w * 0.80, 0, w, h * 0.08, w, h * 0.28) // 右上圆角
      ..cubicTo(w, h * 0.46, w * 0.82, h * 0.66, w * 0.50, h * 0.96) // 右侧收腰
      ..close();
    canvas.drawPath(path, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
