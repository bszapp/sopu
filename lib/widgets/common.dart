/// 通用 widgets: 平台徽章 / 两平台谱卡 / 区块标题 / 空态。
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../utils/data_fields.dart';
import '../http/cc_api.dart';
import '../pages/image_viewer_page.dart';

void _previewImage(String url, String title) {
  ImageViewerPage.open(ImageViewerPage.network(title: title, imageUrls: [url]));
}

/// 首页列表可能省略上传者，按已知谱 ID 从详情补全。
class ScoreAuthorName extends StatelessWidget {
  final Map<String, dynamic> item;
  final TextStyle? style;
  const ScoreAuthorName(this.item, {super.key, this.style});
  static final _names = <String, Future<String>>{};

  @override
  Widget build(BuildContext context) {
    final name = ScoreCard.authorOf(item);
    final id = ScoreCard.idOf(item);
    if (item['__platform'] == 'cc' &&
        '${item['jump_url'] ?? ''}'.contains('://detail/album/')) {
      return Text(
        '合集 · ${item['opern_num'] ?? '-'} 首',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    Widget text(String value) =>
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    if (name.isNotEmpty || item['__platform'] != 'cc' || id.isEmpty) {
      return text(name.isEmpty ? '作者信息未提供' : name);
    }
    return FutureBuilder<String>(
      future: _names.putIfAbsent(id, () async {
        try {
          return ScoreCard.authorOf(await CcApi.opernDetail(id));
        } catch (_) {
          _names.remove(id);
          rethrow;
        }
      }),
      builder: (context, snapshot) => text(
        snapshot.data?.isNotEmpty == true
            ? snapshot.data!
            : snapshot.connectionState == ConnectionState.waiting
            ? '作者加载中…'
            : '作者信息暂不可用',
      ),
    );
  }
}

class UserAvatar extends StatelessWidget {
  final String url, name;
  final double radius;
  final bool previewOnTap;
  const UserAvatar({
    super.key,
    required this.url,
    required this.name,
    this.radius = 24,
    this.previewOnTap = true,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: !previewOnTap || url.isEmpty ? null : () => _previewImage(url, name),
    child: ClipOval(
      child: SizedBox.square(
        dimension: radius * 2,
        child: url.isEmpty
            ? _fallback(context)
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => _fallback(context),
                placeholder: (_, _) => _fallback(context),
              ),
      ),
    ),
  );
  Widget _fallback(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Center(child: Text(name.isEmpty ? '?' : name.characters.first)),
  );
}

class StatusBadge extends StatelessWidget {
  final String label;
  const StatusBadge(this.label, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        color: Theme.of(context).colorScheme.onSecondaryContainer,
      ),
    ),
  );
}

class ScoreBadges extends StatelessWidget {
  final Map<String, dynamic> item;
  const ScoreBadges(this.item, {super.key});
  @override
  Widget build(BuildContext context) {
    final data = scoreData(item), platform = '${item['__platform'] ?? ''}';
    final member = platform == 'tan8' ? membershipOf(data) : null;
    final ai = aiLabelOf(data, platform);
    final serverVipIcon = platform == 'tan8'
        ? resourceUrl(textOf(data, ['image_3_url']), platform)
        : '';
    final price = double.tryParse(textOf(data, ['sale_price']));
    return Wrap(
      spacing: 4,
      runSpacing: 3,
      children: [
        if (member != null) StatusBadge(member),
        if (member == null && serverVipIcon.isNotEmpty)
          CachedNetworkImage(
            imageUrl: serverVipIcon,
            height: 16,
            width: 32,
            fit: BoxFit.contain,
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        if (price != null && price > 0)
          StatusBadge('¥${price.toStringAsFixed(2)}'),
        if (ai != null) StatusBadge(ai),
      ],
    );
  }
}

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
  final bool previewOnTap;
  const ScoreCover(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.previewOnTap = true,
  });

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: const Icon(Icons.music_note, size: 30, color: Colors.grey),
      );
    }
    final uri = url!.startsWith('//') ? 'https:$url' : url!;
    return GestureDetector(
      onTap: previewOnTap ? () => _previewImage(uri, '封面') : null,
      child: CachedNetworkImage(
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
      ),
    );
  }
}

/// 通用谱卡(两平台字段都从 raw map 里宽容取值)
class ScoreCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const ScoreCard(this.item, {super.key});

  static String titleOf(Map<String, dynamic> m) => textOf(scoreData(m), [
    'learning_name',
    'label_1_text',
    'title',
    'songname',
    'name',
  ]);
  static String authorOf(Map<String, dynamic> m) => textOf(scoreData(m), [
    'upload_user_name',
    'label_4_text',
    'uploader',
    'maskName',
    'author',
    'compose',
    'username',
    'label_3_text',
  ]);
  static String coverOf(Map<String, dynamic> m) => resourceUrl(
    textOf(scoreData(m), [
      'image_address',
      'image_1_url',
      'pic',
      'image_url',
      'photo_address',
      'titlepic',
    ]),
    '${m['__platform'] ?? ''}',
  );
  static String idOf(Map<String, dynamic> m) =>
      textOf(scoreData(m), ['old_id', 'yuepuid', 'id']);

  static void previewCover(Map<String, dynamic> item) {
    final cover = coverOf(item);
    if (cover.isNotEmpty) _previewImage(cover, titleOf(item));
  }

  static void open(Map<String, dynamic> item) {
    final platform = '${item['__platform'] ?? ''}';
    final jump = item['jumpEvent'];
    final url = platform == 'tan8' && jump is Map
        ? '${jump['parm1'] ?? ''}'
        : '${item['jump_url'] ?? ''}';
    final uri = Uri.tryParse(url);
    final isAlbum = platform == 'tan8'
        ? uri != null &&
              (uri.queryParameters.containsKey('album_id') ||
                  uri.queryParameters['m'] == 'getAlbumInfo')
        : uri != null &&
              uri.scheme == 'ccpiano' &&
              uri.host == 'detail' &&
              uri.path.startsWith('/album/');
    if (isAlbum) {
      Get.toNamed(
        '/collection',
        parameters: {
          'platform': platform,
          'url': url,
          'title': titleOf(item),
          'id': platform == 'cc' ? uri.pathSegments.last : idOf(item),
        },
      );
      return;
    }
    final id = idOf(item);
    if (id.isEmpty) return;
    Get.toNamed('/score', parameters: {'platform': platform, 'id': id});
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => open(item),
        onLongPress: () => previewCover(item),
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
                    Positioned.fill(
                      child: ScoreCover(coverOf(item), previewOnTap: false),
                    ),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: PlatformBadge(item['__platform'] ?? ''),
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
              // 弹性文本区: 不依赖固定卡高, 溢出由内部裁剪
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 33,
                        child: Text(
                          titleOf(item),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, height: 1.25),
                        ),
                      ),
                      const SizedBox(height: 4),
                      ScoreAuthorName(
                        item,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.1,
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
  final VoidCallback? onTap;
  const ScoreRow(this.item, {super.key, this.onTap});

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
        onTap: onTap ?? () => ScoreCard.open(item),
        onLongPress: () => ScoreCard.previewCover(item),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              SizedBox(
                width: 78,
                height: 78,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ScoreCover(
                    ScoreCard.coverOf(item),
                    previewOnTap: false,
                  ),
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
                    ScoreBadges(item),
                    const SizedBox(height: 4),
                    ScoreAuthorName(
                      item,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (extra.isNotEmpty)
                      Text(extra, maxLines: 1, overflow: TextOverflow.ellipsis),
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
