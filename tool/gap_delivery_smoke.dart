import 'dart:convert';
import 'dart:io';

import 'package:sopu/common/constants.dart';
import 'package:sopu/http/cc_api.dart';
import 'package:sopu/http/http.dart';
import 'package:sopu/http/tan8_api.dart';
import 'package:sopu/http/tan8_codec.dart';
import 'package:sopu/utils/data_fields.dart';

import 'gap_contract_smoke.dart' show ProbeProxy;

Future<void> main(List<String> args) async {
  HttpOverrides.global = ProbeProxy();
  Http.init();
  final session = jsonDecode(
    await File(Platform.environment['SOPU_TEST_TAN8_FILE']!).readAsString(),
  ) as Map;
  final cookies = (session['cookies'] as List)
      .map(
        (e) => Cookie(e['name'], e['value'])
          ..domain = e['domain']
          ..path = e['path'] ?? '/',
      )
      .toList();
  await Http.tan8Jar.saveFromResponse(Uri.parse(Tan8C.domain), cookies);
  final cc = jsonDecode(
    await File(Platform.environment['SOPU_TEST_CC_IDENTITY_FILE']!)
        .readAsString(),
  ) as Map;
  CcApi.uid = cc['uid'] ?? '';
  CcApi.serviceUid = cc['service_uid'] ?? '';
  CcApi.serviceKey = cc['service_key'] ?? '';
  CcApi.phpSessionId = cc['phpsessid'] ?? '';
  final report = <Map<String, dynamic>>[];
  Future<void> check(String api, Future<Object> Function() run) async {
    if (args.contains('--playlist-only') && api != 'tan8.playlistLifecycle') {
      return;
    }
    try {
      final evidence = await run();
      report.add({'api': api, 'status': 'PASS', 'evidence': evidence});
      stdout.writeln('PASS $api ${jsonEncode(evidence)}');
    } catch (e) {
      report.add({'api': api, 'status': 'FAIL', 'error': '$e'});
      stdout.writeln('FAIL $api $e');
    }
  }

  void require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  try {
    await check('tan8.alpha', () async {
      require(
        tan8Alpha.length == 64 && tan8Alpha.split('').toSet().length == 64,
        '字符表长度或唯一性错误',
      );
      return {'length': 64, 'unique': 64};
    });
    final own = await Tan8Api.getUserInfo();
    require(own['user'] is Map, '测试会话未登录');
    await check('tan8.init2023', () async {
      final info = await Tan8Api.scoreInfo('125516');
      require(info['_source'] == 'init2023', '加密详情未成功，仍在使用回退');
      return {
        'source': info['_source'],
        'hasTitle': textOf(info, ['songname']).isNotEmpty,
      };
    });
    await check('tan8.browseThreeAndReadback', () async {
      await Tan8Api.reportBrowse('125516');
      final history = await Tan8Api.myBrowseHistory(limit: 100);
      require(
        history.whereType<Map<String, dynamic>>().any(
          (r) => textOf(scoreData(r), ['id', 'yuepuid']) == '125516',
        ),
        '上报后未读到曲谱',
      );
      return {'readback': true, 'count': history.length};
    });
    await check('tan8.playlistLifecycle', () async {
      final title = 'sopu_dart_${DateTime.now().millisecondsSinceEpoch}';
      String id = '';
      try {
        await Tan8Api.createPlaylist(title);
        final created = (await Tan8Api.myPlaylists())
            .whereType<Map>()
            .firstWhere((r) => r['title'] == title);
        id = '${created['id']}';
        await Tan8Api.addPlaylistScores(id, ['125516']);
        var rows = await Tan8Api.playlistScores(id);
        require(rows.isNotEmpty, '添加后歌单为空');
        await Tan8Api.sortPlaylistScores(id, ['125516']);
        await Tan8Api.togglePlaylistPublic(id);
        await Tan8Api.removePlaylistScores(id, ['125516']);
        rows = await Tan8Api.playlistScores(id);
        require(rows.isEmpty, '移除后歌单仍非空');
      } finally {
        if (id.isNotEmpty) await Tan8Api.deletePlaylist(id);
      }
      require(
        !(await Tan8Api.myPlaylists()).whereType<Map>().any(
          (r) => r['title'] == title,
        ),
        '新建歌单未清理',
      );
      return {
        'created': true,
        'add': true,
        'sort': true,
        'toggle': true,
        'remove': true,
        'deleted': true,
      };
    });
    final uploader = Platform.environment['SOPU_TEST_UPLOADER'] ?? '';
    if (uploader.isNotEmpty) {
      await check('tan8.webCommentInsertDelete', () async {
        final message = 'sopu_dart_${DateTime.now().millisecondsSinceEpoch}';
        String cid = '';
        try {
          final raw = jsonDecode(
            await Tan8Api.webAddComment(
              '125516',
              message,
              uploaderUid: uploader,
            ),
          ) as Map;
          require('${raw['data']['code']}' == '1000', '网页发表未成功');
          final found = (await Tan8Api.comments(
            '125516',
            limit: 100,
          )).whereType<Map>().where((r) => r['message'] == message);
          require(found.isNotEmpty, '未读到本次评论');
          cid = '${found.first['id']}';
        } finally {
          if (cid.isNotEmpty) {
            final deleted =
                jsonDecode(await Tan8Api.webDelComment(cid, '125516')) as Map;
            require('${deleted['data']['code']}' == '1000', '网页删除未成功');
          }
        }
        require(
          !(await Tan8Api.comments(
            '125516',
            limit: 100,
          )).whereType<Map>().any((r) => r['message'] == message),
          '本次评论仍残留',
        );
        return {'inserted': true, 'readback': true, 'deleted': true};
      });
    }
    await check('cc.myFollowList', () async {
      final rows = itemsOf(await CcApi.myFollowList());
      return {'readable': true, 'count': rows.length};
    });
  } finally {
    await File(args.first)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    Http.tan8.close(force: true);
    Http.cc.close(force: true);
  }
  if (report.any((r) => r['status'] == 'FAIL')) exitCode = 1;
}
