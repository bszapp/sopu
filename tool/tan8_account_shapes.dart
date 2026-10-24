import 'dart:convert';
import 'dart:io';
import 'package:sopu/http/http.dart';
import 'package:sopu/http/tan8_api.dart';

dynamic shape(dynamic value, [int depth = 0]) {
  if (value is Map) return {for (final entry in value.entries) '${entry.key}': depth > 3 ? entry.value.runtimeType.toString() : shape(entry.value, depth + 1)};
  if (value is List) return {'length': value.length, if (value.isNotEmpty) 'first': depth > 3 ? value.first.runtimeType.toString() : shape(value.first, depth + 1)};
  if (value is String) return {'type': 'String', 'length': value.length};
  return value.runtimeType.toString();
}
Future<void> main(List<String> args) async {
  Http.init(cookieDir: '${args.first}/cookies');
  await Tan8Api.scoreInfo('125516');
  for (final path in [
    '/codeindex.php?d=member&c=dynamic&m=getYuepuAccessLogs&limit=20&start=0',
    '/codeindex.php?d=api&c=yuepuCollect&m=collectList&limit=20&start=0&action=1',
    '/codeindex.php?d=api&c=yuepuCollect&m=selfBuildPlaylist',
  ]) {
    final r = await Http.tan8.get<String>(path);
    final j = jsonDecode(r.data!);
    stdout.writeln(jsonEncode({'method': Uri.parse(path).queryParameters['m'], 'shape': shape(j)}));
  }
  Http.tan8.close(force: true); Http.cc.close(force: true);
}
