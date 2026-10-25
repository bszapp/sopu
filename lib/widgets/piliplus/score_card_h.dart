// Copied/adapted from PiliPlus common/widgets/video_card/video_card_h.dart.
// GPL-3.0-or-later. Only model, resource, badge and navigation adapters differ.
import 'package:flutter/material.dart';

import 'num_utils.dart';

import '../../utils/data_fields.dart';
import '../common.dart';

class ScoreCardH extends StatelessWidget {
  const ScoreCardH(this.item, {super.key, this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = scoreData(item);
    final scheme = theme.colorScheme;
    Widget stat(IconData icon, dynamic value) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 3,
      children: [
        Icon(icon, size: 13, color: scheme.outline),
        Text(
          NumUtils.numFormat(value),
          style: TextStyle(fontSize: 11, color: scheme.outline),
        ),
      ],
    );
    return SizedBox(
      height: 110,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap ?? () => ScoreCard.open(item),
          onLongPress: () => ScoreCard.previewCover(item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ScoreCover(
                          ScoreCard.coverOf(item),
                          previewOnTap: false,
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: PlatformBadge('${item['__platform'] ?? ''}'),
                        ),
                        Positioned(
                          left: 6,
                          right: 6,
                          bottom: 6,
                          child: ScoreBadges(item),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          ScoreCard.titleOf(item),
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            fontSize: theme.textTheme.bodyMedium?.fontSize,
                            height: 1.42,
                            letterSpacing: .3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ScoreAuthorName(
                        item,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1,
                          color: scheme.outline,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        spacing: 8,
                        children: [
                          if (textOf(data, [
                            'hit_num',
                            'views',
                            'view',
                          ]).isNotEmpty)
                            stat(
                              Icons.play_arrow_outlined,
                              textOf(data, ['hit_num', 'views', 'view']),
                            ),
                          if (textOf(data, [
                            'comment_num',
                            'count_comments',
                          ]).isNotEmpty)
                            stat(
                              Icons.chat_bubble_outline,
                              textOf(data, ['comment_num', 'count_comments']),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
