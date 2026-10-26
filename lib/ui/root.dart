import 'package:flutter/material.dart';

import 'theme.dart';

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _tab = 0;
  // 侧栏收起为内存态；持久化到 settings 存储在 Task 12 接入时顺路做。
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
  static const _hints = [
    '拨响一根弦，这里会显示音高与偏差。',
    '音阶、和弦与指法工具会在这里出现。',
    '练习记录与偏好设置将在这里出现。',
  ];
  // 切页淡入：动效只做反馈（app 屏规则 150-200ms）。
  static const Duration _fadeDuration = Duration(milliseconds: 150);

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
                child: _Placeholder(_titles[i], _hints[i], pad: wide ? 24.0 : 16.0),
              ),
            ),
          ),
      ]);
      return Scaffold(
        appBar: wide ? null : AppBar(title: Text(_titles[_tab])),
        body: wide
            ? Row(children: [
                _SideNav(
                  titles: _titles,
                  icons: _icons,
                  activeIcons: _activeIcons,
                  activeIndex: _tab,
                  collapsed: _collapsed,
                  onSelect: (i) => setState(() => _tab = i),
                  onToggleCollapse: () => setState(() => _collapsed = !_collapsed),
                ),
                Expanded(child: body),
              ])
            : body,
        bottomNavigationBar: wide
            ? null
            : Container(
                // 与宽屏侧栏同款分隔语言：地色底栏 + 顶部 1px 发丝线。
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: GuitarBarColors.border)),
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
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: GuitarBarColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          collapsed ? _collapsedHeader() : _expandedHeader(),
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

  Widget _expandedHeader() {
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 24, right: 8, bottom: 12),
      child: Row(children: [
        const _PickMark(),
        const SizedBox(width: 8),
        const Text(
          'GuitarBar',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: GuitarBarColors.ink),
        ),
        const Spacer(),
        IconButton(
          tooltip: '收起侧栏',
          onPressed: onToggleCollapse,
          icon: const Icon(Icons.keyboard_double_arrow_left),
          color: GuitarBarColors.muted,
        ),
      ]),
    );
  }

  Widget _collapsedHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _PickMark(),
          IconButton(
            tooltip: '展开侧栏',
            onPressed: onToggleCollapse,
            icon: const Icon(Icons.keyboard_double_arrow_right),
            color: GuitarBarColors.muted,
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
    final labelColor = selected ? GuitarBarColors.ink : GuitarBarColors.muted;
    final glyph = selected ? activeIcon : icon;
    Widget child = Material(
      color: selected ? GuitarBarColors.activePill : Colors.transparent,
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
                ? Center(child: Icon(glyph, size: 20, color: GuitarBarColors.muted))
                : Row(children: [
                    const SizedBox(width: 8),
                    Icon(glyph, size: 20, color: GuitarBarColors.muted),
                    const SizedBox(width: 10),
                    Text(
                      title,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: labelColor),
                    ),
                  ]),
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
  Widget build(BuildContext context) => const CustomPaint(size: Size(20, 20), painter: _PickPainter());
}

class _PickPainter extends CustomPainter {
  const _PickPainter();

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
    canvas.drawPath(path, Paint()..color = GuitarBarColors.ink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 占位页：Task 12-17 用真实页面替换。
class _Placeholder extends StatelessWidget {
  const _Placeholder(this.title, this.hint, {required this.pad});

  final String title;
  final String hint;
  final double pad;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(hint, style: textTheme.bodyMedium?.copyWith(color: GuitarBarColors.muted)),
        ],
      ),
    );
  }
}
