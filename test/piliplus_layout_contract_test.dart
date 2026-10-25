import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:sopu/http/cc_api.dart';
import 'package:sopu/http/http.dart';
import 'package:sopu/http/tan8_api.dart';
import 'package:sopu/http/tan8_codec.dart';
import 'package:sopu/pages/author_page.dart';
import 'package:sopu/pages/score_detail_page.dart';
import 'package:sopu/services/sessions.dart';

import 'app_contract_test.dart' show ReplyAdapter;

// PersistCookieJar and image codecs complete outside the fake clock.
Future<void> _flush(WidgetTester tester) async {
  for (var index = 0; index < 20; index++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
}

void main() {
  setUpAll(() async {
    final temp = await Directory.systemTemp.createTemp('sopu_ui_contract_');
    Http.init(cookieDir: temp.path);
  });
  setUp(() {
    Get.testMode = true;
    CcApi.clearSession();
    Sessions.ccUser = {};
    Sessions.tan8User = {};
  });
  tearDown(() {
    Get.reset();
  });

  test('专辑匿名请求不携带身份；Cookie 资料恢复保留鉴权字段', () async {
    CcApi.uid = 'encrypted-login-uid';
    CcApi.serviceUid = '42';
    CcApi.serviceKey = 'key';
    CcApi.cgUid = 'not-a-number';
    CcApi.phpSessionId = 'session';
    Http.cc.httpClientAdapter = ReplyAdapter((o) {
      final q = o.uri.queryParameters;
      if (q['urlparam'] == 'home/user/getAlbumDetail') {
        expect(q.keys, isNot(contains('uid')));
        expect(q.keys, isNot(contains('PHPSESSID')));
        expect(o.headers.keys, isNot(contains('Cookie')));
        expect(q['pageindex'], '2');
        return {
          'returnCode': '0000',
          'datas': {'list_music_book': [], 'total_count': 0},
        };
      }
      expect(q['urlparam'], 'home/user/indexV002');
      expect(q['userid'], '42');
      expect(q.keys, isNot(contains('uid')));
      expect(q.keys, isNot(contains('service_key')));
      expect(o.headers['Cookie'], 'PHPSESSID=session');
      return {
        'returnCode': '0000',
        'datas': {
          'userinfo': {
            'id': '42',
            'uid': '42',
            'nickname': '资料名',
            'phone': 'private',
          },
        },
      };
    });
    await CcApi.albumDetail('123', page: 2);
    final profile = await CcApi.me();
    expect(profile['nickname'], '资料名');
    expect(profile.containsKey('phone'), isFalse);
    expect(CcApi.uid, 'encrypted-login-uid');
    expect(CcApi.serviceKey, 'key');
  });

  testWidgets('虫虫楼中楼自动预取，灰底预览进入完整回复后自动分页', (tester) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pages = <String>[];
    Http.cc.httpClientAdapter = ReplyAdapter((o) {
      final q = o.uri.queryParameters;
      if (o.uri.path.endsWith('.png')) {
        return base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAABAAAAAKCAIAAAAy3EnLAAAAE0lEQVR4nGP4TyJgGNXwf0hqAACxUd4wZKJGVwAAAABJRU5ErkJggg==',
        );
      }
      switch (q['urlparam']) {
        case 'pad/detail/operninfov003':
          return {
            'returnCode': '0000',
            'list': {
              'id': 'new-id',
              'old_id': '1072807',
              'name': '回复测试谱',
              'author': '发布者',
            },
          };
        case 'pad/detail/getbookinfobyid':
          return {
            'returnCode': '0000',
            'list': {
              'id': 'book-id',
              'image_list': ['https://s201.lzjoy.com/test.png'],
              'image_num': 1,
            },
          };
        case 'pad/recommend/getRecommendByOpernId':
          return {
            'returnCode': '0000',
            'datas': {'song_list': []},
          };
        case 'pad/detail/getOpernDetailComment':
          return {
            'returnCode': '0000',
            'datas': {
              'total_pages': 1,
              'list': [
                {
                  'id': 'root',
                  'u_uid': '100',
                  'u_name': '根用户',
                  'content': '根评论',
                  'total_reply': '3',
                  'hits': '12',
                  'is_hit': '0',
                },
              ],
            },
          };
        case 'pad/detail/getOpernCommentReplyList':
          final page = q['pageindex']!;
          pages.add(page);
          final rows = switch (page) {
            '1' => [
              {
                'id': 'c1',
                'u_name': '子用户一',
                'content': '自动出现的子回复',
                'parent_id': 'root',
              },
            ],
            '2' => [
              {
                'id': 'c2',
                'u_name': '子用户二',
                'content': '下一页子回复',
                'parent_id': 'root',
              },
            ],
            _ => <Object>[],
          };
          return {
            'returnCode': '0000',
            'datas': {'total_reply': '0', 'list_reply': rows},
          };
        default:
          throw StateError('意外调用 ${q['urlparam']}');
      }
    });
    await tester.pumpWidget(
      GetMaterialApp(
        home: const ScoreDetailPage(platform: 'cc', id: '1072807'),
        builder: FlutterSmartDialog.init(),
      ),
    );
    await _flush(tester);
    expect(pages, ['1']);
    await tester.tap(find.widgetWithText(Tab, '评论'));
    await _flush(tester);
    expect(find.textContaining('自动出现的子回复', findRichText: true), findsOneWidget);
    final footer = find.text('共 3 条回复');
    await tester.ensureVisible(footer);
    await tester.tap(footer);
    await _flush(tester);
    expect(pages, ['1', '2', '3']);
    expect(find.text('下一页子回复', findRichText: true), findsOneWidget);
    expect(find.text('没有更多回复'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('弹琴吧作者 UID 可进入复制的主页，切换发布收藏保留资料', (tester) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var profileCalls = 0;
    Http.tan8.httpClientAdapter = ReplyAdapter((o) {
      final q = o.uri.queryParameters;
      if (q['m'] == 'init2023') {
        return {
          'data': {'code': '1002', 'message': 'metadata'},
        };
      }
      if (q['m'] == 'init') {
        return {
          'data': {'code': '1100', 'userid': '11539', 'username': '文武贝'},
        };
      }
      if (q['m'] == 'info') {
        return {
          'data': {
            'code': '1000',
            'result': {'title': '天空之城', 'isDianZan': 0, 'count_dianZan': 0},
          },
        };
      }
      if (q['m'] == 'getUserInfo') {
        profileCalls++;
        return {
          'data': {
            'code': '1000',
            'result': tan8AuthCode(
              jsonEncode({
                'uid': '11539',
                'username': '文武贝',
                'fansCount': '123',
                'followCount': '2',
                'yuepuGetLikeCount': '8',
              }),
              'ENCODE',
              Tan8Api.key,
            ),
          },
        };
      }
      if (q['type'] == 'comments') {
        return {'page_comments': [], 'page_count': 0};
      }
      if (q['m'] == 'erji_publish_yuepu_2023' ||
          q['m'] == 'erji_collect_yuepu_2023') {
        return {
          'data': {
            'result': {'pianoCount': '0'},
          },
        };
      }
      if (q['m'] == 'get_view_info') {
        return {
          'data': {'code': '1', 'result': []},
        };
      }
      throw StateError('图片或次要请求：${q['m']}');
    });
    await tester.pumpWidget(
      GetMaterialApp(
        home: const ScoreDetailPage(platform: 'tan8', id: '33414'),
        builder: FlutterSmartDialog.init(),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await _flush(tester);
    await tester.ensureVisible(find.text('文武贝'));
    await tester.tap(find.text('文武贝'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await _flush(tester);
    expect(find.byType(AuthorPage), findsOneWidget);
    expect(find.text('UID: 11539'), findsOneWidget);
    final count = profileCalls;
    await tester.tap(find.widgetWithText(Tab, '收藏'));
    await _flush(tester);
    await tester.tap(find.widgetWithText(Tab, '发布'));
    await _flush(tester);
    expect(profileCalls, count);
    expect(tester.takeException(), isNull);
  });
}
