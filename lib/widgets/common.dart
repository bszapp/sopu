/// 通用 widgets: 平台徽章 / 两平台谱卡 / 区块标题 / 空态。
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 页面末尾可滚动留白，避免最后一项贴住播放栏。
const pageBottomScrollSpace = 96.0;

/// platform 标记: 'tan8' 弹琴吧 / 'cc' 虫虫
class PlatformBadge extends StatelessWidget {
  final String platform;
  final double fontSize;
  const PlatformBadge(this.platform, {super.key, this.fontSize = 10});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isTan8 = platform == 'tan8';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isTan8
            ? colorScheme.primaryContainer.withValues(alpha: .85)
            : const Color(0xFF7B4DE2).withValues(alpha: .88),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isTan8 ? '弹琴吧' : '虫虫',
        style: TextStyle(
          fontSize: fontSize,
          height: 1.35,
          color: isTan8 ? colorScheme.onPrimaryContainer : Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? platform;
  final VoidCallback? onMore;
  const SectionHeader(this.title, {super.key, this.platform, this.onMore});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
      child: Row(
        children: [
          if (platform != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PlatformBadge(platform!, fontSize: 9),
            ),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (onMore != null)
            TextButton(onPressed: onMore, child: const Text('更多')),
        ],
      ),
    );
  }
}

/// 封面图 (含失败兜底)
class ScoreCover extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  const ScoreCover(this.url, {super.key, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: const Icon(Icons.music_note, size: 30, color: Colors.grey),
      );
    }
    final uri = url!.startsWith('http') ? url! : 'https://$url!';
    return CachedNetworkImage(
      imageUrl: uri,
      fit: fit,
      httpHeaders: const {'User-Agent': 'okhttp/4.9.3'},
      errorWidget: (_, _, _) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: const Icon(Icons.music_note, size: 30, color: Colors.grey),
      ),
      placeholder: (_, _) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
    );
  }
}

/// 通用谱卡(两平台字段都从 raw map 里宽容取值)
class ScoreCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const ScoreCard(this.item, {super.key});

  static String titleOf(Map<String, dynamic> m) =>
      (m['learning_name'] ??
              m['label_1_text'] ??
              m['title'] ??
              m['songname'] ??
              '')
          .toString();
  static String authorOf(Map<String, dynamic> m) =>
      (m['upload_user_name'] ??
              m['label_3_text'] ??
              m['author'] ??
              m['uploader'] ??
              m['compose'] ??
              m['username'] ??
              '')
          .toString();
  static String coverOf(Map<String, dynamic> m) =>
      (m['image_address'] ??
              m['image_1_url'] ??
              m['pic'] ??
              m['image_url'] ??
              m['photo_address'] ??
              '')
          .toString();
  static String idOf(Map<String, dynamic> m) =>
      (m['old_id'] ?? m['id'] ?? m['yuepuid'] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Get.toNamed(
          '/score',
          parameters: {'platform': item['__platform'] ?? '', 'id': idOf(item)},
        ),
        child: SizedBox(
          width: 132,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 150,
                width: double.infinity,
                child: Stack(
                  children: [
                    Positioned.fill(child: ScoreCover(coverOf(item))),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: PlatformBadge(item['__platform'] ?? ''),
                    ),
                  ],
                ),
              ),
              // 弹性文本区: 不依赖固定卡高, 溢出由内部裁剪
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          titleOf(item),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, height: 1.25),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        authorOf(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
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

/// 横卡片(列表行, 搜索/列表用)
class ScoreRow extends StatelessWidget {
  final Map<String, dynamic> item;
  const ScoreRow(this.item, {super.key});

  @override
  Widget build(BuildContext context) {
    final isCc = item['__platform'] == 'cc';
    final stats = isCc
        ? '播放 ${(item['hit_num'] ?? '-')}'
        : (item['label_2_text']?.toString() ?? '');
    final extra = (item['opern_type_desc'] ?? item['label_4_text'] ?? '')
        .toString();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Get.toNamed(
          '/score',
          parameters: {
            'platform': item['__platform'] ?? '',
            'id': ScoreCard.idOf(item),
          },
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              SizedBox(
                width: 78,
                height: 78,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ScoreCover(ScoreCard.coverOf(item)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PlatformBadge(item['__platform'] ?? ''),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            ScoreCard.titleOf(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${ScoreCard.authorOf(item)}${extra.isNotEmpty ? ' · $extra' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.bar_chart,
                          size: 13,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          stats,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 12,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${item['comment_num'] ?? item['count_comments'] ?? ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
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
    );
  }
}

class LoadingCenter extends StatelessWidget {
  final String? msg;
  const LoadingCenter({super.key, this.msg});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 2.4),
          if (msg != null) ...[
            const SizedBox(height: 10),
            Text(
              msg!,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    ),
  );
}

class ErrorCenter extends StatelessWidget {
  final dynamic error;
  final VoidCallback? onRetry;
  const ErrorCenter(this.error, {super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final msg = error is Exception ? '$error' : '$error';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 34, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              '加载失败'.padRight(4),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              OutlinedButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ],
        ),
      ),
    );
  }
}
