import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'package:sopu/http/http.dart';
import 'package:sopu/http/cc_api.dart';
import 'package:sopu/http/tan8_api.dart';
import 'package:sopu/utils/data_fields.dart';
import 'package:sopu/utils/ccmz_decode.dart';

import 'gap_contract_smoke.dart' show ProbeProxy;

// 只读验证已交付契约；不发短信，不写历史、评论、收藏、关注或试用。
Future<void> main(List<String> args) async {
  HttpOverrides.global = ProbeProxy();
  Http.init();
  if (args.contains('--only-replies')) {
    Http.cc.interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) {
          final query = response.requestOptions.uri.queryParameters;
          stdout.writeln(
            'READ public route=${query['urlparam']} id=${query['id']}',
          );
          stdout.writeln(
            'READ reply page=${query['pageindex']} size=${query['pagesize']} HTTP=${response.statusCode}',
          );
          if (response.statusCode != 200) {
            final body = '${response.data}';
            stdout.writeln(
              body.substring(0, body.length > 180 ? 180 : body.length),
            );
          }
          handler.next(response);
        },
      ),
    );
  }
  final report = <Map<String, dynamic>>[];
  Future<void> check(String name, Future<Object> Function() action) async {
    if (args.contains('--only-replies') && name != 'cc.commentReplies.pages') {
      return;
    }
    if (args.contains('--only-comment-state') && name != 'tan8.commentState') {
      return;
    }
    try {
      final evidence = await action();
      report.add({'api': name, 'status': 'PASS', 'evidence': evidence});
      stdout.writeln('PASS $name ${jsonEncode(evidence)}');
    } catch (e) {
      report.add({'api': name, 'status': 'FAIL', 'error': '$e'});
      stdout.writeln('FAIL $name $e');
    }
  }

  await check('tan8.initUploader.authorProfile', () async {
    final data = await Tan8Api.initUploader('33414');
    if ('${data['userid']}' != '11539') throw StateError('上传者 UID 不匹配');
    final profile = await Tan8Api.userProfile('${data['userid']}');
    if (userNameOf(profile).isEmpty) throw StateError('作者主页缺少姓名');
    return {
      'authorUid': '11539',
      'name': userNameOf(profile),
      'avatar': userPhotoOf(profile, 'tan8').isNotEmpty,
    };
  });
  await check('tan8.webComments.pagesAndReplies', () async {
    final rows = <Map<String, dynamic>>[];
    final pages = <int>[];
    for (var page = 1; page <= 3; page++) {
      final data = (await Tan8Api.webComments(
        '33414',
        page: page,
      )).whereType<Map<String, dynamic>>().toList();
      pages.add(data.length);
      rows.addAll(data);
    }
    final ids = rows.map(commentIdOf).toSet();
    final replies = rows
        .where(
          (row) =>
              textOf(row, ['reply_uid']).isNotEmpty &&
              '${row['reply_uid']}' != '0',
        )
        .length;
    if (ids.length != rows.length || replies == 0) {
      throw StateError('分页重叠或无回复数据');
    }
    return {'pages': pages, 'unique': ids.length, 'replyTargets': replies};
  });
  await check('tan8.commentState', () async {
    final app = (await Tan8Api.comments('33414')).whereType<Map>().toList();
    final web = (await Tan8Api.webComments('33414')).whereType<Map>().toList();
    final states = {
      for (final row in app) commentIdOf(row): flagOf(row['islike']),
    };
    final matched = web.where((row) => states[commentIdOf(row)] != null).length;
    if (web.isEmpty || matched != web.length) {
      throw StateError('评论 ID 或点赞状态不完整');
    }
    return {
      'appRows': app.length,
      'webRows': web.length,
      'matchedStates': matched,
    };
  });
  await check('tan8.search.keyword', () async {
    final rows = itemsOf(await Tan8Api.search('天空之城'))
        .whereType<Map<String, dynamic>>()
        .toList();
    final titles = rows
        .map((e) => textOf(scoreData(e), ['title', 'songname', 'label_1_text']))
        .toList();
    if (!titles.any((title) => title.contains('天空之城'))) {
      throw StateError('搜索结果未包含目标关键词');
    }
    return {'count': rows.length, 'firstTitles': titles.take(3).toList()};
  });
  await check('cc.getbookinfobyid.allFiveImages', () async {
    final data = await CcApi.bookInfoById('1072807');
    final images = data['image_list'];
    if (images is! List || images.length != 5) throw StateError('图片列表应有 5 页');
    final bytes = <int>[];
    for (final image in images) {
      final path = image is Map
          ? textOf(image, ['url', 'image_url', 'image', 'src'])
          : '$image';
      final body = await CcApi.downloadBytes(CcApi.fileUrl(path));
      final png =
          body.length > 8 && body[0] == 137 && body[1] == 80 && body[2] == 78;
      final jpg = body.length > 3 && body[0] == 255 && body[1] == 216;
      if (!png && !jpg) throw StateError('第 ${bytes.length + 1} 页返回非图片');
      bytes.add(body.length);
    }
    return {'pages': images.length, 'bytes': bytes};
  });
  await check('cc.album.anonymousPages', () async {
    final a = await CcApi.albumDetail('103571', page: 1, size: 5);
    final b = await CcApi.albumDetail('103571', page: 2, size: 5);
    final one = (a['list_music_book'] as List).whereType<Map>();
    final two = (b['list_music_book'] as List).whereType<Map>();
    final ids = one
        .map((e) => textOf(e, ['old_id', 'learning_id', 'id']))
        .toSet();
    if (one.length != 5 ||
        two.length != 5 ||
        two.any(
          (e) => ids.contains(textOf(e, ['old_id', 'learning_id', 'id'])),
        )) {
      throw StateError('专辑分页不完整或重叠');
    }
    return {
      'total': a['total_count'],
      'page1': one.length,
      'page2': two.length,
      'overlap': 0,
    };
  });
  await check('cc.recommendByOpernId', () async {
    final data = await CcApi.recommendByOpernId('1072807');
    final rows = data['song_list'];
    if (rows is! List || rows.isEmpty) throw StateError('关联推荐为空');
    return {'count': rows.length};
  });
  await check('cc.commentReplies.pages', () async {
    // Match the application's actual list -> thread flow.
    await CcApi.opernComments('1072807');
    final a =
        (await CcApi.commentReplies('5686738', page: 1, size: 3))['list_reply']
            as List;
    final b =
        (await CcApi.commentReplies('5686738', page: 2, size: 3))['list_reply']
            as List;
    final ids = a.whereType<Map>().map(commentIdOf).toSet();
    if (a.isEmpty ||
        b.isEmpty ||
        b.whereType<Map>().any((e) => ids.contains(commentIdOf(e)))) {
      throw StateError('楼中楼分页为空或存在重叠');
    }
    return {'page1': a.length, 'page2': b.length, 'overlap': 0};
  });
  await check('cc.aiScoreUrls.decodeVariants', () async {
    final detail = await CcApi.opernDetail('934024');
    final lengths = <String, int>{};
    for (final key in ['sing_ccmz', 'fingering_ccmz']) {
      final path = textOf(detail, [key]);
      if (path.isEmpty) throw StateError('详情缺少 $key');
      final body = await CcApi.downloadBytes(CcApi.fileUrl(path));
      final package = decodeCcmz(body);
      if (package.scoreJson.isEmpty || package.infoJson.isEmpty) {
        throw StateError('$key 解码内容为空');
      }
      lengths[key] = body.length;
    }
    return lengths;
  });

  final identityFile = Platform.environment['SOPU_TEST_CC_IDENTITY_FILE'];
  if (identityFile != null && identityFile.isNotEmpty) {
    final saved = jsonDecode(await File(identityFile).readAsString()) as Map;
    CcApi.uid = '${saved['uid'] ?? ''}';
    CcApi.serviceUid = '${saved['service_uid'] ?? ''}';
    CcApi.serviceKey = '${saved['service_key'] ?? ''}';
    CcApi.userToken = '${saved['id'] ?? saved['user_id'] ?? ''}';
    CcApi.cgUid = '${saved['cg_uid'] ?? saved['service_uid'] ?? ''}';
    CcApi.phpSessionId = '${saved['PHPSESSID'] ?? saved['phpsessid'] ?? ''}';
    await check('cc.cookieOnlyIdentityAndFollowLists', () async {
      final auth = [
        CcApi.uid,
        CcApi.serviceUid,
        CcApi.serviceKey,
        CcApi.userToken,
      ];
      final profile = await CcApi.me();
      final following = itemsOf(await CcApi.myFollowList());
      final fans = itemsOf(await CcApi.myFansList());
      if (userNameOf(profile).isEmpty || profile.containsKey('phone')) {
        throw StateError('资料缺少姓名或包含私密字段');
      }
      if (jsonEncode(auth) !=
          jsonEncode([
            CcApi.uid,
            CcApi.serviceUid,
            CcApi.serviceKey,
            CcApi.userToken,
          ])) {
        throw StateError('资料覆盖了鉴权字段');
      }
      return {
        'profile': true,
        'authPreserved': true,
        'following': following.length,
        'fans': fans.length,
      };
    });
  }
  if (args.isNotEmpty) {
    await File(args.first)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  }
  Http.cc.close(force: true);
  Http.tan8.close(force: true);
  if (report.any((row) => row['status'] == 'FAIL')) exitCode = 1;
}
