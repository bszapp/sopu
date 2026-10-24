import 'dart:convert';
import 'dart:io';

import 'package:sopu/http/http.dart';
import 'package:sopu/http/cc_api.dart';
import 'package:sopu/utils/ccmz_decode.dart';

Future<void> main(List<String> args) async {
  final dir = Directory(args[0]);
  await dir.create(recursive: true);
  Http.init(cookieDir: '${dir.path}/cookies');
  try {
    if (args.length > 1 && args[1] == 'full') {
      final url = await CcApi.scoreFileUrl('1072807');
      final bytes = await CcApi.downloadBytes(url);
      final package = decodeCcmz(bytes);
      final score = jsonDecode(package.scoreJson) as Map;
      await File('${dir.path}/1072807_dart_full.ccmz').writeAsBytes(bytes);
      stdout.writeln(jsonEncode({'id':'1072807','url':url,'bytes':bytes.length,'lines':(score['lines'] as List).length}));
      return;
    }
    final songs = await CcApi.searchSongs('Are You Lost', size: 100);
    final hits = songs
        .whereType<Map>()
        .where((e) => '${e['learning_name']}'.contains('极致还原'))
        .toList();
    if (hits.isEmpty) throw StateError('未找到截图曲谱');
    for (final hit in hits.take(1)) {
      final id = '${hit['old_id']}';
      final detail = await CcApi.opernDetail(id);
      final url = [
        detail['fingering_ccmz'],
        detail['ccmz_page_1'],
        detail['play_json'],
        hit['play_json'],
      ].firstWhere((v) => v != null && '$v'.isNotEmpty);
      final bytes = await CcApi.downloadBytes('$url');
      final pkg = decodeCcmz(bytes);
      final score = jsonDecode(pkg.scoreJson) as Map;
      await File('${dir.path}/$id.ccmz').writeAsBytes(bytes);
      await File('${dir.path}/$id.score.json').writeAsString(pkg.scoreJson);
      await File('${dir.path}/fixture.json').writeAsString(
        jsonEncode({
          'id': id,
          'title': hit['learning_name'],
          'url': url,
          'footer': score['footer'],
        }),
      );
      stdout.writeln(
        jsonEncode({
          'id': id,
          'title': hit['learning_name'],
          'type': pkg.type,
          'footer': score['footer'],
          'keys': score.keys.toList(),
        }),
      );
    }
  } finally {
    Http.cc.close(force: true);
    Http.tan8.close(force: true);
  }
}
