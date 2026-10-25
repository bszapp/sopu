// Images use the copied PiliPlus comment GalleryViewer and HeroDialogRoute.
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../http/cc_api.dart';
import '../widgets/piliplus/image_viewer/gallery_viewer.dart';
import '../widgets/piliplus/image_viewer/hero_dialog_route.dart';

class ImageViewerPage extends StatelessWidget {
  final String title;
  final List<String> urls;
  final List<Uint8List> bytesList;
  final int initialIndex;

  const ImageViewerPage.network({
    super.key,
    required this.title,
    required List<String> imageUrls,
    this.initialIndex = 0,
  }) : urls = imageUrls,
       bytesList = const [];

  const ImageViewerPage.bytes({
    super.key,
    required this.title,
    required List<Uint8List> images,
    this.initialIndex = 0,
  }) : urls = const [],
       bytesList = images;

  static Future<void> open(ImageViewerPage page) =>
      Get.key.currentState!.push<void>(
        HeroDialogRoute<void>(
          settings: const RouteSettings(name: '/images'),
          pageBuilder: (context, animation, secondaryAnimation) => page,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isBytes = bytesList.isNotEmpty;
    final count = isBytes ? bytesList.length : urls.length;
    if (count == 0) return const ColoredBox(color: Colors.black);
    return GalleryViewer(
      title: title,
      initIndex: initialIndex.clamp(0, count - 1),
      whiteBackground: isBytes,
      images: isBytes
          ? bytesList.map((bytes) => MemoryImage(bytes)).toList()
          : urls
                .map(
                  (url) => CachedNetworkImageProvider(
                    url,
                    headers: const {'User-Agent': 'okhttp/4.9.3'},
                  ),
                )
                .toList(),
      imageAt: (index) async =>
          isBytes ? bytesList[index] : await CcApi.downloadBytes(urls[index]),
    );
  }
}

/// 沿用原图片页右上角页码样式，放在 PageView 外以保持固定。
class ImagePageIndicator extends StatelessWidget {
  const ImagePageIndicator({
    super.key,
    required this.index,
    required this.count,
  });
  final int index, count;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${index + 1}/$count',
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    ),
  );
}
