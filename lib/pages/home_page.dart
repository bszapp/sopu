/// 主页内容；导航栏和播放栏由全局 AppShell 统一布局。
library;

import 'package:flutter/material.dart';

import '../widgets/app_shell.dart';

import 'home_tab.dart';
import 'mine_page.dart';
import 'search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = PageController(initialPage: homeTabIndex.value);

  @override
  void initState() {
    super.initState();
    homeTabIndex.addListener(_switchPage);
  }

  void _switchPage() {
    if (_controller.hasClients) _controller.jumpToPage(homeTabIndex.value);
  }

  @override
  void dispose() {
    homeTabIndex.removeListener(_switchPage);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        physics: const NeverScrollableScrollPhysics(), // 顶部页面切换仅由导航触发
        controller: _controller,
        children: const [HomeTab(), SearchPage(), MinePage()],
      ),
    );
  }
}
