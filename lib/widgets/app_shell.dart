// Navigation translation copied and adapted from PiliPlus lib/pages/main/view.dart.
// Layout copied in piliplus/main_layout.dart; see piliplus/SOURCE.md.
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/player_service.dart';
import 'piliplus/main_layout.dart';
import 'player_bar.dart';

final homeTabIndex = ValueNotifier<int>(0);
const shellTransitionDuration = Duration(milliseconds: 500);
const shellTransitionCurve = Curves.easeInOutCubicEmphasized;

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});
  final Widget child;
  Widget _navigationBar() => ValueListenableBuilder<int>(
    valueListenable: homeTabIndex,
    builder: (context, index, _) => NavigationBar(
      selectedIndex: index,
      height: 62,
      onDestinationSelected: (value) => homeTabIndex.value = value,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: '首页',
        ),
        NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: '我的',
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Overlay.wrap(
    child: ValueListenableBuilder<bool>(
      valueListenable: playerOnHome,
      builder: (context, onHome, _) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: onHome ? 1 : 0, end: onHome ? 1 : 0),
        duration: shellTransitionDuration,
        curve: shellTransitionCurve,
        child: child,
        builder: (context, progress, content) => Obx(() {
          final hasTrack = PlayerService.I.state.track.value != null;
          final media = MediaQuery.of(context);
          final bottomInset = media.padding.bottom;
          return Material(
            child: MainLayout(
              sideBar: null,
              body: MediaQuery.removePadding(
                context: context,
                removeBottom: true,
                child: content!,
              ),
              bottomNav: MediaQuery.removePadding(
                context: context,
                removeBottom: true,
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSize(
                        key: const ValueKey('shell.player.region'),
                        duration: shellTransitionDuration,
                        curve: shellTransitionCurve,
                        alignment: Alignment.bottomCenter,
                        child: const MiniPlayerBar(bottomSafeArea: false),
                      ),
                      IgnorePointer(
                        ignoring: !onHome,
                        child: ExcludeSemantics(
                          excluding: !onHome,
                          child: SizedBox(
                            key: const ValueKey('shell.navigation.viewport'),
                            height: 62 * progress,
                            child: ClipRect(
                              child: OverflowBox(
                                alignment: Alignment.bottomCenter,
                                minHeight: 62,
                                maxHeight: 62,
                                child: FractionalTranslation(
                                  translation: Offset(0.0, 1 - progress),
                                  child: MediaQuery.removePadding(
                                    context: context,
                                    removeTop: true,
                                    removeBottom: true,
                                    child: _navigationBar(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      _DockInset(
                        hasTrack: hasTrack,
                        navigationProgress: progress,
                        bottomInset: bottomInset,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    ),
  );
}

class _DockInset extends StatelessWidget {
  const _DockInset({
    required this.hasTrack,
    required this.navigationProgress,
    required this.bottomInset,
  });
  final bool hasTrack;
  final double navigationProgress, bottomInset;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: hasTrack ? 1.0 : 0.0, end: hasTrack ? 1.0 : 0.0),
    duration: shellTransitionDuration,
    curve: shellTransitionCurve,
    builder: (context, playbackProgress, _) => SizedBox(
      height: bottomInset * max(navigationProgress, playbackProgress),
    ),
  );
}
