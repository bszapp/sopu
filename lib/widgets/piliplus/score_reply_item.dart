// Copied and adapted from PiliPlus lib/pages/video/reply/widgets/reply_item_grpc.dart.
// GPL-3.0-or-later; see SOURCE.md and LICENSE.
import 'package:flutter/material.dart';

import 'num_utils.dart';

import '../../utils/platform_utils.dart';
import '../common.dart';
import 'translucent_row.dart';
import 'text_more/text_more.dart';

class ScoreReplyItem extends StatelessWidget {
  const ScoreReplyItem({
    super.key,
    required this.name,
    required this.avatar,
    required this.time,
    required this.message,
    required this.likes,
    this.replyTarget = '',
    this.member,
    this.liked,
    this.onAvatar,
    this.onReply,
    this.onLike,
    this.onDelete,
    this.replies = const [],
    this.needDivider = true,
    this.replyFooter,
  });
  final String name, avatar, time, message, likes, replyTarget;
  final String? member;
  final bool? liked;
  final VoidCallback? onAvatar, onReply, onLike, onDelete;
  final List<Widget> replies;
  final bool needDivider;
  final Widget? replyFooter;

  String _formatLikes() => NumUtils.numFormat(likes);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    void showMore() => showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: .min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('回复'),
              onTap: onReply == null
                  ? null
                  : () {
                      Navigator.pop(sheetContext);
                      onReply!();
                    },
            ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onDelete!();
                },
              ),
          ],
        ),
      ),
    );
    Widget child = Padding(
      padding: const .fromLTRB(12, 14, 8, 5),
      child: _buildContent(context, colorScheme),
    );
    if (needDivider) {
      child = Column(
        mainAxisSize: .min,
        children: [
          child,
          Divider(
            indent: 55,
            endIndent: 15,
            height: 0.3,
            color: colorScheme.outline.withValues(alpha: 0.08),
          ),
        ],
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => onReply?.call(),
        onLongPress: showMore,
        onSecondaryTap: PlatformUtils.isMobile ? null : showMore,
        child: child,
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: onAvatar,
      child: TranslucentRow(
        spacing: 12,
        extraWidth: 46,
        children: [
          UserAvatar(url: avatar, name: name, radius: 17),
          Flexible(
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                Row(
                  spacing: 6,
                  mainAxisSize: .min,
                  children: [
                    Flexible(
                      child: Text(
                        name.isEmpty ? '用户' : name,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: TextStyle(
                          color: member != null
                              ? colorScheme.primary
                              : colorScheme.outline,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (member != null) StatusBadge(member!),
                  ],
                ),
                Text(
                  time,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: TextStyle(fontSize: 11, color: colorScheme.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, ColorScheme colorScheme) {
    const padding = EdgeInsets.only(left: 45, right: 6);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        _buildHeader(context, colorScheme),
        const SizedBox(height: 10),
        Padding(
          padding: padding,
          child: TextMore.rich(
            TextSpan(
              children: [
                if (replyTarget.isNotEmpty) ...[
                  const TextSpan(text: '回复 '),
                  TextSpan(
                    text: replyTarget,
                    style: TextStyle(color: colorScheme.primary),
                  ),
                  const TextSpan(text: '：'),
                ],
                TextSpan(text: message),
              ],
            ),
            primary: colorScheme.primary,
            style: const TextStyle(height: 1.75, fontSize: 14),
          ),
        ),
        const SizedBox(height: 4),
        buttonAction(context, colorScheme),
        if (replies.isNotEmpty || replyFooter != null)
          Padding(
            padding: const EdgeInsets.only(
              top: 5,
              bottom: 12,
              left: 42,
              right: 4,
            ),
            child: Material(
              animationDuration: Duration.zero,
              color: colorScheme.onInverseSurface,
              borderRadius: BorderRadius.circular(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...replies, ?replyFooter],
              ),
            ),
          ),
      ],
    );
  }

  Widget buttonAction(BuildContext context, ColorScheme colorScheme) {
    final textStyle = TextStyle(
      height: 1,
      fontSize: 12,
      fontWeight: .normal,
      color: colorScheme.outline,
    );
    const buttonStyle = ButtonStyle(
      visualDensity: .compact,
      tapTargetSize: .shrinkWrap,
      padding: WidgetStatePropertyAll(.zero),
    );
    return Row(
      children: [
        const SizedBox(width: 36),
        SizedBox(
          height: 32,
          child: TextButton(
            style: buttonStyle,
            onPressed: onReply,
            child: Row(
              spacing: 3,
              mainAxisSize: .min,
              children: [
                Icon(
                  Icons.reply,
                  size: 18,
                  color: colorScheme.outline.withValues(alpha: .8),
                ),
                Text('回复', style: textStyle),
              ],
            ),
          ),
        ),
        const SizedBox(width: 2),
        const Spacer(),
        SizedBox(
          height: 32,
          child: TextButton(
            style: buttonStyle,
            onPressed: onLike,
            child: Row(
              spacing: 4,
              mainAxisSize: .min,
              children: [
                Icon(
                  liked == true ? Icons.thumb_up : Icons.thumb_up_outlined,
                  size: 16,
                  color: liked == true
                      ? colorScheme.primary
                      : colorScheme.outline,
                ),
                if (_formatLikes().isNotEmpty && _formatLikes() != '0')
                  Text(
                    _formatLikes(),
                    style: textStyle.copyWith(
                      color: liked == true
                          ? colorScheme.primary
                          : colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 5),
      ],
    );
  }
}

// replyItemRow from reply_item_grpc.dart: compact, two-line child preview.
class ScoreReplyPreview extends StatelessWidget {
  const ScoreReplyPreview({
    super.key,
    required this.name,
    required this.message,
    required this.onTap,
    this.target = '',
    this.onLongPress,
  });
  final String name, message, target;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: name,
                style: TextStyle(color: scheme.primary),
              ),
              if (target.isNotEmpty) ...[
                const TextSpan(text: ' 回复 '),
                TextSpan(
                  text: target,
                  style: TextStyle(color: scheme.primary),
                ),
              ],
              TextSpan(text: '：$message'),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            height: 1.6,
            color: scheme.onSurface.withValues(alpha: .85),
          ),
        ),
      ),
    );
  }
}
