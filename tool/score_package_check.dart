import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:sopu/http/http.dart';
import 'package:sopu/http/tan8_api.dart';
import 'package:sopu/http/tan8_codec.dart';

Future<void> main(List<String> args) async {
  final out = Directory(args.first); await out.create(recursive: true);
  Http.init(cookieDir: '${out.path}/cookies');
  final result = <Map<String, dynamic>>[];
  for (final id in ['125516','116415']) {
    final (files, _) = await Tan8Api.fetchScore(id);
    final env = await Tan8Api.checkYuepu(id);
    final ypa2Url = '${env['ypa2Url'] ?? ''}'.replaceAll(r'\/', '/');
    if (ypa2Url.isNotEmpty) {
      try {
        final r = await Http.tan8.get<List<int>>(ypa2Url, options: Options(responseType: ResponseType.bytes));
        if (r.statusCode != 200) throw StateError('ypad2 HTTP ${r.statusCode}');
        final raw = Uint8List.fromList(r.data!);
        try { files['download.ypad2'] = tan8AesDecrypt(raw, '${env['encryptionKey']}'); }
        catch (_) { files['download.ypad2'] = raw; }
      } catch (e) {
        stdout.writeln('$id ypad2 unavailable: $e');
        result.add({'id': id, 'file': 'ypad2', 'status': 'SERVER_UNAVAILABLE', 'error': '$e'});
      }
    }
    stdout.writeln('$id files=${files.keys.toList()}');
    for (final e in files.entries.where((e) => RegExp(r'\.(ypad|ypad2|ypa2|ypn1)$').hasMatch(e.key))) {
      final b = e.value;
      final dir = Directory('${out.path}/$id'); await dir.create(recursive: true);
      await File('${dir.path}/${e.key.replaceAll('/', '_')}').writeAsBytes(b);
      final starts = <int>[];
      for (var i = 0; i < b.length - 2 && i < 128; i++) {
        if (b[i] == 31 && b[i+1] == 139 && b[i+2] == 8) starts.add(i);
      }
      stdout.writeln('$id ${e.key} bytes=${b.length} header=${b.take(40).map((x) => x.toRadixString(16).padLeft(2,'0')).join(' ')} gzip=$starts');
      for (final offset in starts) {
        try {
          final data = gzip.decode(b.sublist(offset));
          await File('${dir.path}/${e.key.replaceAll('/', '_')}.decoded').writeAsBytes(data);
          final text = utf8.decode(data, allowMalformed: true);
          final preview = const LineSplitter().convert(text).take(6).map((s) => s.length > 150 ? s.substring(0,150) : s).toList();
          stdout.writeln('  offset=$offset decoded=${data.length} preview=$preview');
          result.add({'id': id, 'file': e.key, 'bytes': b.length, 'gzipOffset': offset, 'decodedBytes': data.length, 'preview': preview});
        } catch (ex) { stdout.writeln('  offset=$offset failed=$ex'); }
      }
    }
  }
  await File('${out.path}/summary.json').writeAsString(const JsonEncoder.withIndent('  ').convert(result));
  Http.cc.close(force: true); Http.tan8.close(force: true);
}
