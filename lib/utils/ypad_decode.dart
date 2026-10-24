import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// ypad/ypad2：12 字节前缀 + gzip(JSON)，兼容对象/数组末尾多余逗号。
class YpadPackage {
  final Map<String, dynamic> data;
  final int sourceBytes;
  final int decodedBytes;
  const YpadPackage(this.data, this.sourceBytes, this.decodedBytes);
  int _int(dynamic value) => int.tryParse('$value') ?? 0;
  String get scoreId => '${data['ypid'] ?? ''}';
  int get pageCount => _int(data['pageCount']);
  int get ticksPerBeat => _int(data['ticksPerTempo']);
  int get totalTicks => _int(data['totalTicks']);
  List<Map<String, dynamic>> get tracks =>
      ((data['tracksData']?['trackData'] as List?) ?? const []).whereType<Map<String, dynamic>>().toList();
  int get eventCount => tracks.fold(0, (n,t) => n + ((t['events'] as List?)?.length ?? 0));
  List<Map<String, dynamic>> get tempoEvents =>
      ((data['tempoEvents'] as List?) ?? const []).whereType<Map<String, dynamic>>().toList();
  Map<String, dynamic> summary() => {'scoreId': scoreId, 'pages': pageCount, 'tracks': tracks.length, 'events': eventCount, 'ticksPerBeat': ticksPerBeat, 'totalTicks': totalTicks, 'sourceBytes': sourceBytes, 'decodedBytes': decodedBytes};
}

YpadPackage decodeYpad(Uint8List bytes) {
  if (bytes.length < 15 || bytes[12] != 31 || bytes[13] != 139 || bytes[14] != 8) {
    throw const FormatException('ypad/ypad2 的第 12 字节处缺少 gzip 文件头');
  }
  final plain = gzip.decode(Uint8List.sublistView(bytes, 12));
  final source = utf8.decode(plain);
  final cleaned = StringBuffer();
  var quoted = false, escaped = false;
  for (var i = 0; i < source.length; i++) {
    final ch = source[i];
    if (quoted) {
      cleaned.write(ch);
      if (escaped) { escaped = false; }
      else if (ch == r'\') { escaped = true; }
      else if (ch == '"') { quoted = false; }
    } else {
      if (ch == '"') quoted = true;
      if (ch == ',') {
        var j = i + 1;
        while (j < source.length && source[j].trim().isEmpty) { j++; }
        if (j < source.length && (source[j] == '}' || source[j] == ']')) continue;
      }
      cleaned.write(ch);
    }
  }
  final value = jsonDecode(cleaned.toString());
  if (value is! Map<String, dynamic>) throw const FormatException('ypad 根节点不是对象');
  final package = YpadPackage(value, bytes.length, plain.length);
  final trackData = value['tracksData'];
  if (trackData is! Map || package.ticksPerBeat <= 0) throw const FormatException('ypad 缺少轨道或时基');
  if (int.tryParse('${trackData['trackCount']}') != package.tracks.length) throw const FormatException('ypad 轨道数不符');
  for (final track in package.tracks) {
    if (track['events'] is! List || int.tryParse('${track['eventCount']}') != (track['events'] as List).length) {
      throw const FormatException('ypad 轨道事件数不符');
    }
  }
  return package;
}
