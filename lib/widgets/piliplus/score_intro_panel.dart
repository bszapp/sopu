// Copied and adapted from PiliPlus lib/pages/video/introduction/ugc/view.dart.
// GPL-3.0-or-later; see SOURCE.md and LICENSE.
import 'package:flutter/material.dart';

import 'animated_height.dart';
import 'expandable.dart';
import 'translucent_column.dart';
import '../common.dart' show UserAvatar;

class ScoreIntroPanel extends StatefulWidget {
  const ScoreIntroPanel({
    super.key,
    required this.title,
    required this.author,
    required this.authorPhoto,
    required this.authorSubtitle,
    this.onAuthor,
    required this.stats,
    required this.description,
    required this.scoreId,
    required this.badges,
    required this.actions,
    this.following,
    this.followBusy = false,
    this.onFollow,
  });
  final String title,
      author,
      authorPhoto,
      authorSubtitle,
      stats,
      description,
      scoreId;
  final VoidCallback? onAuthor;
  final bool? following;
  final bool followBusy;
  final VoidCallback? onFollow;
  final Widget badges;
  final List<Widget> actions;
  @override
  State<ScoreIntroPanel> createState() => _ScoreIntroPanelState();
}

class _ScoreIntroPanelState extends State<ScoreIntroPanel> {
  bool _expand = false;
  ColorScheme get colorScheme => Theme.of(context).colorScheme;
  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const .only(left: 12.0, right: 12.0, top: 10),
      sliver: SliverToBoxAdapter(
        child: GestureDetector(
          onTap: () => setState(() => _expand = !_expand),
          child: TranslucentColumn(
            crossAxisAlignment: .start,
            children: [
              NoTranslucentArea(child: _buildOwnerInfo()),
              const SizedBox(height: 8),
              _buildTitle(),
              const SizedBox(height: 8),
              Row(
                spacing: 3,
                children: [
                  Icon(
                    Icons.play_arrow_outlined,
                    size: 16,
                    color: colorScheme.outline,
                  ),
                  Text(
                    widget.stats,
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                ],
              ),
              NoTranslucentArea(child: widget.badges),
              AnimatedHeightWidgetExt(
                expand: _expand,
                duration: const Duration(milliseconds: 300),
                child: TranslucentColumn(
                  mainAxisSize: .min,
                  crossAxisAlignment: .start,
                  children: _infos(),
                ),
              ),
              const SizedBox(height: 8),
              NoTranslucentArea(child: actionGrid(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOwnerInfo() {
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: .centerLeft,
            child: GestureDetector(
              behavior: .opaque,
              onTap: widget.onAuthor,
              child: Row(
                spacing: 10,
                mainAxisSize: .min,
                children: [
                  UserAvatar(
                    url: widget.authorPhoto,
                    name: widget.author,
                    radius: 17.5,
                    previewOnTap: false,
                  ),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        Text(
                          widget.author.isEmpty ? '作者信息未提供' : widget.author,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        Text(
                          widget.authorSubtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.onFollow != null)
          FilledButton.tonal(
            onPressed: widget.followBusy ? null : widget.onFollow,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              visualDensity: const VisualDensity(vertical: -1.8),
              tapTargetSize: MaterialTapTargetSize.padded,
              backgroundColor: widget.following == true
                  ? colorScheme.surfaceContainerHighest
                  : null,
            ),
            child: Text(
              widget.followBusy
                  ? '处理中'
                  : widget.following == true
                  ? '已关注'
                  : '关注',
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
    );
  }

  Widget _buildTitle() => ExpandablePanel(
    collapsed: _buildVideoTitle(),
    expanded: _buildVideoTitle(isExpand: true),
    expand: _expand,
  );
  Widget _buildVideoTitle({bool isExpand = false}) => Text.rich(
    TextSpan(text: widget.title),
    maxLines: isExpand ? null : 2,
    overflow: isExpand ? null : .ellipsis,
    style: const TextStyle(fontSize: 16),
  );
  List<Widget> _infos() => [
    const SizedBox(height: 8, width: .infinity),
    Text(
      widget.scoreId,
      style: TextStyle(fontSize: 14, color: colorScheme.secondary),
    ),
    if (widget.description.isNotEmpty) ...[
      const SizedBox(height: 8),
      SelectableText(widget.description, style: const TextStyle(height: 1.4)),
    ],
    const SizedBox(height: 8),
    NoTranslucentArea(child: widget.badges),
  ];
  Widget actionGrid(BuildContext context) => SizedBox(
    height: 48,
    child: Row(crossAxisAlignment: .start, children: widget.actions),
  );
}
