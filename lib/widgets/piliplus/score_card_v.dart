// Copied/adapted from PiliPlus common/widgets/video_card/video_card_v.dart:
// build, content and videoStat. GPL-3.0-or-later.
import 'package:flutter/material.dart';

import 'num_utils.dart';

import '../../utils/data_fields.dart';
import '../common.dart';

class ScoreCardV extends StatelessWidget {
  const ScoreCardV(this.item, {super.key});
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = scoreData(item);
    Widget stat(IconData icon, String value) => Row(
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
      width: 180,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => ScoreCard.open(item),
          onLongPress: () => ScoreCard.previewCover(item),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ScoreCover(ScoreCard.coverOf(item), previewOnTap: false),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: PlatformBadge('${item['__platform'] ?? ''}'),
                    ),
                    Positioned(
                      bottom: 6,
                      left: 6,
                      right: 6,
                      child: ScoreBadges(item),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          ScoreCard.titleOf(item),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(height: 1.38),
                        ),
                      ),
                      Row(
                        spacing: 4,
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
                      ScoreAuthorName(
                        item,
                        style: TextStyle(
                          height: 1.5,
                          fontSize: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.fontSize,
                          color: scheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
