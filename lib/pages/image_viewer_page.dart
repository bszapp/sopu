/// 曲谱图片查看器: cc 网络图片列表 / tan8 zip 内 png 字节。
/// 每页可缩放, 底部页码快速跳转。
library;

import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../widgets/common.dart' show pageBottomScrollSpace;

class ImageViewerPage extends StatefulWidget {
  final String title;
  final List<String> urls;
  final List<Uint8List> bytesList;

  const ImageViewerPage.network({
    super.key,
    required this.title,
    required List<String> imageUrls,
  }) : urls = imageUrls,
       bytesList = const [];

  const ImageViewerPage.bytes({
    super.key,
    required this.title,
    required List<Uint8List> images,
  }) : urls = const [],
       bytesList = images;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get count => widget.bytesList.isNotEmpty
      ? widget.bytesList.length
      : widget.urls.length;

  bool get isBytes => widget.bytesList.isNotEmpty;

  void _jump(int i) {
    // 每页高度不精确, 按屏幕高比例估算
    final h = MediaQuery.of(context).size.height * 0.9;
    _controller.animateTo(
      i * h,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.title} · $count页')),
      body: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          ListView.builder(
            controller: _controller,
            padding: const EdgeInsets.only(
              top: 12,
              bottom: pageBottomScrollSpace,
            ),
            itemCount: count,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: Stack(
                alignment: Alignment.topRight,
                children: [
                  Container(
                    color: Colors.white,
                    child: InteractiveViewer(
                      maxScale: 5,
                      child: isBytes
                          ? Image.memory(
                              widget.bytesList[i],
                              fit: BoxFit.fitWidth,
                            )
                          : CachedNetworkImage(
                              imageUrl: widget.urls[i],
                              httpHeaders: const {'User-Agent': 'okhttp/4.9.3'},
                              progressIndicatorBuilder: (_, _, p) =>
                                  LinearProgressIndicator(
                                    value: p.progress ?? 0,
                                  ),
                              errorWidget: (_, _, _) => const Padding(
                                padding: EdgeInsets.all(30),
                                child: Icon(Icons.broken_image, size: 40),
                              ),
                            ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${i + 1}/$count',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (count > 1)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 40,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    scrollDirection: Axis.horizontal,
                    itemCount: count,
                    separatorBuilder: (_, _) => const SizedBox(width: 2),
                    itemBuilder: (_, i) => TextButton(
                      onPressed: () => _jump(i),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
