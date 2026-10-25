import 'package:flutter/material.dart';

class RootPage extends StatefulWidget {
  const RootPage({super.key});
  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _tab = 0;
  static const _titles = ['调音器', '工具箱', '个人中心'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final body = IndexedStack(index: _tab, children: [
        _Placeholder(_titles[0]), _Placeholder(_titles[1]), _Placeholder(_titles[2]),
      ]);
      return Scaffold(
        appBar: AppBar(title: Text(_titles[_tab])),
        body: wide
            ? Row(children: [
                NavigationRail(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(icon: Icon(Icons.tune), label: Text('调音器')),
                    NavigationRailDestination(icon: Icon(Icons.home_repair_service), label: Text('工具箱')),
                    NavigationRailDestination(icon: Icon(Icons.person), label: Text('个人中心')),
                  ],
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
                  NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: '调音器'),
                  NavigationDestination(icon: Icon(Icons.home_repair_service_outlined), selectedIcon: Icon(Icons.home_repair_service), label: '工具箱'),
                  NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '个人中心'),
                ],
              ),
      );
    });
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(child: Text(text));
}
