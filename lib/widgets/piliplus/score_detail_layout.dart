// Copied and adapted from PiliPlus lib/pages/video/view.dart; GPL-3.0-or-later.
// Source methods: childWhenDisabled, _childWhenDisabledLandscapeInner,
// buildTabBar, videoIntro. See SOURCE.md and LICENSE.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';

import 'video_header.dart';
import 'scroll_behavior.dart';
import 'keep_alive_wrapper.dart';

class ScoreDetailLayout extends StatefulWidget {
  const ScoreDetailLayout({
    super.key,
    required this.scoreView,
    required this.introBuilder,
    required this.commentsBuilder,
    required this.relatedSliver,
    required this.onComment,
    required this.title,
    this.commentCount = '',
    this.aspectRatio,
    this.onOpenScore,
  });
  final Widget scoreView;
  final WidgetBuilder introBuilder, commentsBuilder;
  final Widget relatedSliver;
  final VoidCallback onComment;
  final String title;
  final String commentCount;
  final double? aspectRatio;
  final VoidCallback? onOpenScore;
  @override
  State<ScoreDetailLayout> createState() => _ScoreDetailLayoutState();
}

class _ScoreDetailLayoutState extends State<ScoreDetailLayout>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );
  final _outerController = ScrollController(),
      _introController = ScrollController();
  final _scrollKey = GlobalKey<ExtendedNestedScrollViewState>(),
      _childKey = GlobalKey();
  late double maxWidth, maxHeight, _videoHeight;
  final EdgeInsets padding = EdgeInsets.zero;
  late ThemeData theme;
  ColorScheme get colorScheme => theme.colorScheme;
  bool get isPortrait => maxHeight >= maxWidth;
  double _scrollRatio = 0;
  void _scrollRatioChanged(double ratio) {
    if (mounted && ratio != _scrollRatio) setState(() => _scrollRatio = ratio);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _outerController.dispose();
    _introController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    theme = Theme.of(context);
    final darkIcons =
        _scrollRatio >= .5 && colorScheme.brightness == Brightness.light;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: darkIcons ? Brightness.dark : Brightness.light,
        statusBarBrightness: darkIcons ? Brightness.light : Brightness.dark,
      ),
      child: Column(
        children: [
          SizedBox(
            height: MediaQuery.viewPaddingOf(context).top,
            child: ColoredBox(
              color: Color.lerp(
                Colors.black,
                colorScheme.surface,
                _scrollRatio,
              )!,
              child: const SizedBox.expand(),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                maxWidth = constraints.maxWidth;
                maxHeight = constraints.maxHeight;
                final ratio = (widget.aspectRatio ?? 16 / 9).clamp(.35, 3.2);
                final shortest = maxWidth < maxHeight ? maxWidth : maxHeight;
                final longest = maxWidth > maxHeight ? maxWidth : maxHeight;
                final natural = maxWidth / ratio;
                _videoHeight = natural.clamp(
                  kToolbarHeight + 1,
                  maxHeight >= maxWidth
                      ? (longest * .65).clamp(shortest, maxHeight)
                      : maxHeight,
                );
                return isPortrait
                    ? childWhenDisabled
                    : _childWhenDisabledLandscapeInner();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget videoPlayer({required double width, required double height}) =>
      widget.scoreView;
  // _buildHeaderOverlay/_buildOverlayToolBar copied from video/view.dart.
  // The score viewer replaces the video action; opacity covers the entire header.
  Widget _buildHeaderOverlay() => Positioned.fill(
    bottom: -1,
    child: IgnorePointer(
      ignoring: _scrollRatio == 0,
      child: Opacity(
        opacity: _scrollRatio,
        child: Container(
          color: colorScheme.surface,
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: kToolbarHeight,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 42,
                        height: 34,
                        child: IconButton(
                          tooltip: '返回',
                          icon: Icon(
                            Icons.arrow_back,
                            size: 17,
                            color: colorScheme.onSurface,
                          ),
                          onPressed: () => Navigator.maybePop(context),
                        ),
                      ),
                      SizedBox(
                        width: 42,
                        height: 34,
                        child: IconButton(
                          tooltip: '返回主页',
                          icon: Icon(
                            Icons.home_outlined,
                            size: 18,
                            color: colorScheme.onSurface,
                          ),
                          onPressed: () =>
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst),
                        ),
                      ),
                    ],
                  ),
                ),
                Center(
                  child: TextButton.icon(
                    onPressed: widget.onOpenScore,
                    icon: const Icon(Icons.image_outlined, size: 19),
                    label: const Text('查看谱面'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _viewerBackButton() => Positioned(
    top: 4,
    left: 4,
    child: IconButton.filledTonal(
      tooltip: '返回',
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: .35),
        foregroundColor: Colors.white,
      ),
      icon: const Icon(Icons.arrow_back, size: 20),
      onPressed: () => Navigator.maybePop(context),
    ),
  );

  Widget get childWhenDisabled => ExtendedNestedScrollView(
    onlyOneScrollInBody: true,
    physics: const ClampingScrollPhysics(),
    key: _scrollKey,
    controller: _outerController,
    scrollBehavior: const NoOverscrollIndicator(),
    pinnedHeaderSliverHeightBuilder: () => kToolbarHeight,
    headerSliverBuilder: (context, innerBoxIsScrolled) {
      final height = _videoHeight;
      return [
        VideoHeader(
          minExtent: kToolbarHeight,
          maxExtent: height,
          minVideoHeight: _videoHeight,
          onScrollRatioChanged: _scrollRatioChanged,
          child: Stack(
            clipBehavior: .none,
            children: [
              SizedBox(
                width: maxWidth,
                height: height,
                child: videoPlayer(width: maxWidth, height: height),
              ),
              _viewerBackButton(),
              _buildHeaderOverlay(),
            ],
          ),
        ),
      ];
    },
    body: Material(
      key: _childKey,
      child: Column(
        children: [
          buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                videoIntro(needCtr: false),
                widget.commentsBuilder(context),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget _childWhenDisabledLandscapeInner() {
    double width =
        clampDouble(maxHeight / maxWidth * 1.08, 0.5, 0.7) * maxWidth;
    if (maxWidth >= 560) {
      width = maxWidth - clampDouble(maxWidth - width, 280, 425);
    }
    final videoWidth = width;
    final double height =
        width / (widget.aspectRatio ?? 16 / 9).clamp(.35, 3.2);
    final videoHeight = height;
    if (height > maxHeight) {
      return childSplit((widget.aspectRatio ?? 16 / 9).clamp(.35, 3.2));
    }
    final introHeight = maxHeight - height - padding.top;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: videoWidth,
              height: videoHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: videoPlayer(width: videoWidth, height: videoHeight),
                  ),
                  _viewerBackButton(),
                  _buildHeaderOverlay(),
                ],
              ),
            ),
            Offstage(
              offstage: false,
              child: SizedBox(
                width: width,
                height: introHeight,
                child: videoIntro(needRelated: false, needCtr: true),
              ),
            ),
          ],
        ),
        Offstage(
          offstage: false,
          child: SizedBox(
            width: maxWidth - width - padding.horizontal,
            height: maxHeight - padding.top,
            child: Material(
              key: _childKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildTabBar(introText: '相关推荐'),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        KeepAliveWrapper(
                          child: CustomScrollView(
                            key: const PageStorageKey('related'),
                            slivers: [widget.relatedSliver],
                          ),
                        ),
                        widget.commentsBuilder(context),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // childSplit copied from video/view.dart; actual score aspect ratio replaces
  // the video ratio, with the same full-height player and right-hand tab panel.
  Widget childSplit(double ratio) {
    final videoHeight = maxHeight - padding.vertical;
    final width = videoHeight * ratio;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: width,
          height: videoHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: videoPlayer(width: width, height: videoHeight),
              ),
              _viewerBackButton(),
            ],
          ),
        ),
        SizedBox(
          width: maxWidth - width - padding.horizontal,
          height: maxHeight - padding.top,
          child: Material(
            key: _childKey,
            child: Column(
              children: [
                buildTabBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [videoIntro(), widget.commentsBuilder(context)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget buildTabBar({
    bool needIndicator = true,
    String? introText,
    bool showIntro = true,
    VoidCallback? onTap,
  }) {
    final tabs = [
      introText ?? '简介',
      widget.commentCount.isEmpty ? '评论' : '评论 ${widget.commentCount}',
    ];
    Widget tabBar() {
      final flag = !needIndicator || tabs.length == 1;
      return TabBar(
        padding: .zero,
        dividerHeight: 0,
        labelPadding: .zero,
        dividerColor: Colors.transparent,
        controller: _tabController,
        indicator: flag ? const BoxDecoration() : null,
        labelColor: flag ? colorScheme.onSurface : null,
        labelStyle:
            TabBarTheme.of(context).labelStyle?.copyWith(fontSize: 13) ??
            const TextStyle(fontSize: 13),
        onTap: (value) {
          if (!_tabController.indexIsChanging && _outerController.hasClients) {
            _outerController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        },
        tabs: tabs.map((text) {
          return Tab(child: Text(text, softWrap: false, overflow: .visible));
        }).toList(),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
      ),
      child: SizedBox(
        height: 45,
        child: Row(
          children: [
            if (tabs.isEmpty)
              const Spacer()
            else
              Expanded(
                child: Align(
                  alignment: .centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 96.0 * tabs.length),
                    child: tabBar(),
                  ),
                ),
              ),
            SizedBox(
              height: 32,
              child: TextButton(
                style: const ButtonStyle(
                  padding: WidgetStatePropertyAll(.zero),
                ),
                onPressed: widget.onComment,
                child: Text(
                  '发表评论',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }

  Widget videoIntro({bool needRelated = true, bool needCtr = true}) {
    Widget child = CustomScrollView(
      key: const PageStorageKey('intro'),
      controller: needCtr ? _introController : null,
      physics: !needCtr
          ? const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics())
          : null,
      slivers: [
        widget.introBuilder(context),
        if (needRelated) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Divider(
                height: 1,
                indent: 12,
                endIndent: 12,
                color: colorScheme.outline.withValues(alpha: .08),
              ),
            ),
          ),
          widget.relatedSliver,
        ],
      ],
    );

    return KeepAliveWrapper(child: child);
  }
}
