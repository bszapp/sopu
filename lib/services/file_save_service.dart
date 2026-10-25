import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:dio/dio.dart';

import '../utils/globals.dart';

enum SaveDestination { downloads, gallery }

abstract final class FileSaveService {
  static const _channel = MethodChannel('sopu/file_save');

  static Future<String> downloadAudio(String url, String name) async {
    final uri = Uri.parse(url);
    if (!['http', 'https'].contains(uri.scheme)) {
      throw const FormatException('试听音频地址无效');
    }
    final client = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 120),
        headers: const {'User-Agent': 'okhttp/4.9.3'},
      ),
    );
    try {
      final response = await client.getUri<List<int>>(
        uri,
        options: Options(responseType: ResponseType.bytes),
      );
      final mime = response.headers.value('content-type')?.split(';').first;
      if (mime == 'text/html' || mime == 'application/json') {
        throw const FormatException('服务器未返回音频文件');
      }
      const types = {
        'mp3': 'audio/mpeg',
        'm4a': 'audio/mp4',
        'aac': 'audio/aac',
        'ogg': 'audio/ogg',
        'flac': 'audio/flac',
        'wav': 'audio/wav',
      };
      final suffix = uri.path.split('.').last.toLowerCase();
      final extension = types.containsKey(suffix)
          ? suffix
          : types.keys.firstWhere(
              (key) => types[key] == mime,
              orElse: () => 'mp3',
            );
      return await saveBytes(
        '${safeName(name)}.$extension',
        Uint8List.fromList(response.data ?? const []),
        mimeType: types[extension]!,
      );
    } finally {
      client.close();
    }
  }

  static String safeName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .trim();
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return '曲谱';
    // 保留后缀；中文标题也限制长度，避免超过文件系统单个文件名上限。
    final dot = cleaned.lastIndexOf('.');
    final suffix = dot > 0 && cleaned.length - dot <= 10
        ? cleaned.substring(dot)
        : '';
    final stem = suffix.isEmpty
        ? cleaned
        : cleaned.substring(0, cleaned.length - suffix.length);
    return '${String.fromCharCodes(stem.runes.take(60))}$suffix';
  }

  static Future<String> saveBytes(
    String name,
    Uint8List bytes, {
    SaveDestination destination = SaveDestination.downloads,
    String mimeType = 'application/octet-stream',
  }) async {
    if (bytes.isEmpty) throw const FormatException('文件内容为空');
    final filename = safeName(name);
    if (Platform.isAndroid) {
      final location = await _channel.invokeMethod<String>('save', {
        'name': filename,
        'bytes': bytes,
        'mimeType': mimeType,
        'destination': destination.name,
      });
      if (location == null || location.isEmpty) {
        throw const FileSystemException('系统未返回保存位置');
      }
      return location;
    }
    if (destination == SaveDestination.gallery) {
      throw UnsupportedError('当前平台请保存到下载目录');
    }
    final directory = Directory(GPaths.downloads);
    await directory.create(recursive: true);
    final dot = filename.lastIndexOf('.');
    final stem = dot > 0 ? filename.substring(0, dot) : filename;
    final suffix = dot > 0 ? filename.substring(dot) : '';
    var file = File('${directory.path}/$filename');
    for (var n = 1; await file.exists(); n++) {
      file = File('${directory.path}/$stem ($n)$suffix');
    }
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 谱面透明区域铺成白色，再编码为 PNG，保证相册与查看器效果一致。
  static Future<String> saveImage(String name, Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      try {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
        canvas.drawImage(frame.image, ui.Offset.zero, ui.Paint());
        final picture = recorder.endRecording();
        final ui.Image image;
        try {
          image = await picture.toImage(frame.image.width, frame.image.height);
        } finally {
          picture.dispose();
        }
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          if (png == null) throw const FormatException('图片编码失败');
          return await saveBytes(
            '${safeName(name)}.png',
            png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
            destination: SaveDestination.gallery,
            mimeType: 'image/png',
          );
        } finally {
          image.dispose();
        }
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}
