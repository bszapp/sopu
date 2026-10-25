// Adapted from PiliPlus pages/member/widget/user_info_card.dart:
// _buildV, _buildH, _buildAvatar, _buildName, _buildSign and _buildRight.
// GPL-3.0-or-later; Bilibili entities/actions replaced by profile data/callbacks.
import 'package:flutter/material.dart';

import 'num_utils.dart';

import '../common.dart';
import 'member_header_layout.dart';

class MemberInfoCard extends StatelessWidget {
  const MemberInfoCard({
    super.key,
    required this.name,
    required this.avatar,
    required this.header,
    required this.description,
    required this.uid,
    required this.platform,
    required this.stats,
    required this.badges,
    required this.isOwner,
    required this.following,
    required this.followBusy,
    required this.onFollow,
    this.error = '',
    this.onRetry,
  });
  final String name, avatar, header, description, uid, platform, error;
  final Map<String, String> stats;
  final List<String> badges;
  final bool isOwner, followBusy;
  final bool? following;
  final VoidCallback onFollow;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    Widget buildHeader() => SizedBox(
      width: double.infinity,
      height: kHeaderHeight,
      child: header.isEmpty
          ? ColoredBox(color: scheme.surfaceContainerHigh)
          : ScoreCover(header),
    );
    Widget buildAvatar() => DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surface, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: UserAvatar(url: avatar, name: name, radius: kAvatarSize / 2),
      ),
    );
    Widget count(String label, String value) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(NumUtils.numFormat(value), style: const TextStyle(fontSize: 14)),
        Text(
          label,
          style: TextStyle(fontSize: 12, height: 1.2, color: scheme.outline),
        ),
      ],
    );
    Widget buildRight() => Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 5,
      children: [
        if (stats.isNotEmpty)
          Row(
            children: [
              for (final entry in stats.entries) ...[
                if (entry.key != stats.keys.first)
                  SizedBox(
                    height: 15,
                    child: VerticalDivider(
                      width: 1,
                      color: scheme.outline.withValues(alpha: .3),
                    ),
                  ),
                Expanded(child: count(entry.key, entry.value)),
              ],
            ],
          ),
        if (!isOwner)
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: followBusy ? null : onFollow,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                visualDensity: const VisualDensity(vertical: -1.8),
                tapTargetSize: MaterialTapTargetSize.padded,
                backgroundColor: following == true
                    ? scheme.onInverseSurface
                    : null,
              ),
              child: Text(
                followBusy
                    ? '处理中'
                    : following == true
                    ? '已关注'
                    : '关注',
              ),
            ),
          ),
      ],
    );
    List<Widget> buildLeft() => [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              name.isEmpty ? uid : name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            for (final badge in badges) StatusBadge(badge),
          ],
        ),
      ),
      if (description.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: SelectableText(
            description.trim().replaceAll(RegExp(r'\n{2,}'), '\n'),
            style: const TextStyle(fontSize: 14),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PlatformBadge(platform, fontSize: 10),
            Text(
              'UID: $uid',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ],
        ),
      ),
      if (error.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextButton(onPressed: onRetry, child: Text(error)),
        ),
    ];
    return Padding(
      padding: EdgeInsets.only(
        top: width >= 600 ? MediaQuery.viewPaddingOf(context).top : 0,
      ),
      child: width < 600
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HeaderLayoutWidget(
                  header: buildHeader(),
                  avatar: buildAvatar(),
                  actions: buildRight(),
                ),
                const SizedBox(height: 5),
                ...buildLeft(),
                const SizedBox(height: 5),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildHeader(),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 20),
                    buildAvatar(),
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: buildLeft(),
                      ),
                    ),
                    Expanded(flex: 3, child: buildRight()),
                    const SizedBox(width: 20),
                  ],
                ),
                const SizedBox(height: 5),
              ],
            ),
    );
  }
}
