/// 主壳: 底部导航(首页/搜索/我的) + 全局迷你播放条。
library;

import 'package:flutter/material.dart';

import '../widgets/player_bar.dart';

import 'home_tab.dart';
import 'mine_page.dart';
import 'search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  final _controller = PageController(initialPage: 0);

  void _switchPage(int i) {
    setState(() {
      _index = i;
      _controller.jumpToPage(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        physics: const NeverScrollableScrollPhysics(), // 顶部页面切换仅由导航触发
        controller: _controller,
        children: const [HomeTab(), SearchPage(), MinePage()],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayerBar(bottomSafeArea: false),
          NavigationBar(
            selectedIndex: _index,
            height: 62,
            onDestinationSelected: _switchPage,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: '首页',
              ),
              NavigationDestination(
                icon: Icon(Icons.search),
                selectedIcon: Icon(Icons.search),
                label: '搜索',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: '我的',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
