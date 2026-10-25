import 'dart:convert';
import 'dart:io';

import 'package:sopu/http/http.dart';
import 'package:sopu/http/cc_api.dart';
import 'package:sopu/http/tan8_api.dart';
import 'package:sopu/utils/data_fields.dart';

import 'gap_contract_smoke.dart' show ProbeProxy;

Future<void> main(List<String> args) async {
  HttpOverrides.global = ProbeProxy();
  Http.init();
  final evidence = <String, dynamic>{};
  try {
    final cc = await CcApi.floorTab() as List;
    final groups = cc
        .whereType<Map>()
        .where((e) => '${e['container_type']}'.contains('opern_list'))
        .toList();
    if (groups.length < 2) throw StateError('虫虫未返回多个曲谱楼层');
    evidence['cc'] = {
      'scoreSections': groups.length,
      'titles': cc
          .whereType<Map>()
          .where((e) => e['container_type'] == 'title')
          .map((e) => (e['data'] as List).first['title'])
          .toList(),
    };
    final tan8 = await Tan8Api.homePage();
    final titles = tan8
        .whereType<Map>()
        .map((m) => textOf(m, ['title']))
        .where((t) => t.isNotEmpty)
        .toList();
    if (titles.isEmpty || titles.any((t) => t.startsWith('Muban_'))) {
      throw StateError('模块标题未正确读取');
    }
    evidence['tan8'] = {'modules': tan8.length, 'titles': titles};
    final album = await Tan8Api.collectionPage(
      'https://www.tan8.com/codeindex.php?d=admin&c=manage&m=erji_album_yuepu_new&yuepu_type=piano&album_id=27557',
    );
    final section = (album['sections'] as List).first as Map;
    final first = section['items'] as List;
    final next = await Tan8Api.collectionModuleItems(
      section['url'],
      start: first.length,
    );
    final ids = first.whereType<Map>().map((e) => '${e['id']}').toSet();
    if (first.isEmpty ||
        next == null ||
        next.isEmpty ||
        next.whereType<Map>().any((e) => ids.contains('${e['id']}'))) {
      throw StateError('合集曲目或分页异常');
    }
    evidence['tan8.collection'] = {
      'page1': first.length,
      'page2': next.length,
      'overlap': 0,
    };
    stdout.writeln('PASS ${jsonEncode(evidence)}');
    if (args.isNotEmpty) {
      await File(args.first)
          .writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
    }
  } finally {
    Http.cc.close(force: true);
    Http.tan8.close(force: true);
  }
}
