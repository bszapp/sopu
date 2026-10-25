/// ccmz 文件解码(纯 Dart) — 对应 ccmz-tool ccmzScore.ts:
/// 首字节 type(1/2); type=2 时数据字节偶+1 奇-1; 余下为 zip,
/// 内含 data.ccxml(type1)或 score.json(type2) + info.json。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class CcmzPackage {
  final int type;
  final String scoreJson; // data.ccxml / score.json 原文
  final String infoJson; // info.json 原文(无则空串)
  const CcmzPackage({
    required this.type,
    required this.scoreJson,
    required this.infoJson,
  });
}

/// 解析失败抛 StateError/FormatError, 由调用方给用户提示。
CcmzPackage decodeCcmz(Uint8List bytes) {
  if (bytes.isEmpty) {
    throw StateError('ccmz 文件为空');
  }
  final type = bytes[0];
  Uint8List data = Uint8List.sublistView(bytes, 1);
  if (type == 2) {
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      out[i] = data[i] % 2 == 0 ? data[i] + 1 : data[i] - 1;
    }
    data = out;
  } else if (type != 1) {
    throw StateError('不支持的加密方式($type)');
  }
  final z = ZipDecoder().decodeBytes(data);
  String file(String name) {
    final f = z.findFile(name);
    if (f == null) throw StateError('zip 内缺少 $name');
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  return CcmzPackage(
    type: type,
    scoreJson: file(type == 1 ? 'data.ccxml' : 'score.json'),
    infoJson: () {
      try {
        return file('info.json');
      } catch (_) {
        return '';
      }
    }(),
  );
}
