import 'package:flutter/material.dart';

import 'theme.dart';

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _tab = 0;
  static const _titles = ['调音器', '工具箱', '个人中心'];
  static const _icons = [
    Icons.tune_outlined,
    Icons.home_repair_service_outlined,
    Icons.person_outline,
  ];
  static const _hints = [
    '拨响一根弦，这里会显示音高与偏差。',
    '音阶、和弦与指法工具会在这里出现。',
    '练习记录与偏好设置将在这里出现。',
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final body = IndexedStack(
        index: _tab,
        children: [
          for (var i = 0; i < _titles.length; i++)
            _Placeholder(_titles[i], _hints[i], pad: wide ? 24.0 : 16.0),
        ],
      );
      return Scaffold(
        appBar: wide ? null : AppBar(title: Text(_titles[_tab])),
        body: wide
            ? Row(children: [
                _SideNav(
                  titles: _titles,
                  icons: _icons,
                  activeIndex: _tab,
                  onSelect: (i) => setState(() => _tab = i),
                ),
                Expanded(child: body),
              ])
            : body,
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.tune_outlined), label: '调音器'),
                  NavigationDestination(icon: Icon(Icons.home_repair_service_outlined), label: '工具箱'),
                  NavigationDestination(icon: Icon(Icons.person_outline), label: '个人中心'),
                ],
              ),
      );
    });
  }
}

/// 宽屏左侧导航（Open 平面）：置于画布底色之上，右缘 1px 发丝线；
/// 导航块在剩余空间垂直居中，底部预留练习计时器位。
class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.titles,
    required this.icons,
    required this.activeIndex,
    required this.onSelect,
  });

  final List<String> titles;
  final List<IconData> icons;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 256,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: GuitarBarColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 20, top: 24, bottom: 12),
            child: Row(children: [
              _PickMark(),
              SizedBox(width: 8),
              Text(
                'GuitarBar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: GuitarBarColors.ink),
              ),
            ]),
          ),
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < titles.length; i++)
                  _NavItem(
                    title: titles[i],
                    icon: icons[i],
                    selected: i == activeIndex,
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
}

/// 导航行：32px 高、34px 节距；选中以灰药丸 + 标签提亮标记，图标恒为 muted
/// （药丸独自承担选中信号）。
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final labelColor = selected ? GuitarBarColors.ink : GuitarBarColors.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Material(
        color: selected ? GuitarBarColors.activePill : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: Semantics(
          selected: selected,
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: SizedBox(
              height: 32,
              child: Row(children: [
                const SizedBox(width: 8),
                Icon(icon, size: 16, color: GuitarBarColors.muted),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: labelColor),
                ),
              ]),
            ),
          ),
        ),
      ),
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
