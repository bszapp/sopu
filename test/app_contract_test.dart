import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:sopu/http/cc_api.dart';
import 'package:sopu/http/http.dart';
import 'package:sopu/http/tan8_api.dart';
import 'package:sopu/pages/score_detail_page.dart';
import 'package:sopu/pages/search_page.dart';
import 'package:sopu/services/sessions.dart';
import 'package:sopu/utils/data_fields.dart';
import 'package:sopu/utils/globals.dart';
import 'package:sopu/widgets/common.dart';
import 'package:sopu/widgets/app_shell.dart';
import 'package:sopu/widgets/player_bar.dart';
import 'package:sopu/services/player_service.dart';

class ReplyAdapter implements HttpClientAdapter {
  final FutureOr<Object> Function(RequestOptions) reply;
  final Map<String, List<String>> headers;
  ReplyAdapter(this.reply, {this.headers = const {}});
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    final value = await reply(options);
    if (value is Uint8List) {
      return ResponseBody.fromBytes(
        value,
        200,
        headers: {
          Headers.contentTypeHeader: ['image/png'],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(value),
      200,
      headers: {
        ...headers,
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

// 布局检查仅提供播放状态，不打开音频设备或发起网络播放。
class LayoutPlayerService extends PlayerService {
  // 这里只验证布局，跳过父类创建原生音频设备的初始化。
  @override
  // ignore: must_call_super
  void onInit() {}
  @override
  void onClose() {}
}

Future<void> _flush(WidgetTester tester) async {
  for (var index = 0; index < 20; index++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
}

void main() {
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('sopu_contract_');
    Http.init(cookieDir: temp.path);
  });
  setUp(() {
    Sessions.ccUser = {'cg_uid': '42', 'nickname': '测试用户'};
    CcApi.uid = 'test-session';
    CcApi.cgUid = '42';
    CcApi.serviceUid = '42';
    Get.testMode = true;
  });
  tearDown(() {
    Sessions.ccUser = {};
    CcApi.onSessionDirty = null;
    CcApi.clearSession();
    Get.reset();
  });
  tearDownAll(() {
    Http.cc.close(force: true);
    Http.tan8.close(force: true);
  });

  test('Cookie-only 登录选取长效会话，普通响应不能覆盖，退出丢弃旧响应', () async {
    Http.cc.httpClientAdapter = ReplyAdapter(
      (o) {
        expect(o.uri.queryParameters['area_code'], '86');
        expect(o.uri.queryParameters['user_phone'], '10000000000');
        expect(o.uri.queryParameters.containsKey('uid'), isFalse);
        return {
          'returnCode': '0000',
          'returnMsg': 'login_ok',
          'workDatas': {'is_score': 0},
        };
      },
      headers: {
        'set-cookie': [
          'PHPSESSID=long-session; Path=/; Max-Age=65723000000',
          'PHPSESSID=temporary-session; Path=/',
        ],
      },
    );
    final info = await CcApi.loginByCode(
      '100 0000 0000',
      '000000',
      area: '+86',
    );
    expect(info['PHPSESSID'], 'long-session');
    expect(CcApi.phpSessionId, 'long-session');
    expect(CcApi.uid, isEmpty);
    expect(Sessions.ccLoggedIn, isTrue);
    GPaths.appSupport = temp.path;
    Directory('${temp.path}/data').createSync();
    Sessions.ccUser = info;
    await Sessions.saveCc();
    CcApi.clearSession();
    Sessions.ccUser = {};
    await Sessions.init();
    expect(Sessions.ccLoggedIn, isTrue);
    expect(CcApi.phpSessionId, 'long-session');
    Http.cc.httpClientAdapter = ReplyAdapter((o) {
      expect(o.headers['Cookie'], 'PHPSESSID=long-session');
      expect(o.uri.queryParameters['PHPSESSID'], 'long-session');
      return {
        'returnCode': '0000',
        'PHPSESSID': 'temporary-body',
        'datas': {'list': []},
      };
    });
    await CcApi.myLearningHistory();
    expect(CcApi.phpSessionId, 'long-session');
    final entered = Completer<void>(), response = Completer<Object>();
    Http.cc.httpClientAdapter = ReplyAdapter((_) {
      entered.complete();
      return response.future;
    });
    final pending = CcApi.myLearningHistory();
    final assertion = expectLater(pending, throwsA(isA<CcApiError>()));
    await entered.future;
    CcApi.clearSession();
    response.complete({
      'returnCode': '0000',
      'PHPSESSID': 'stale',
      'datas': {'list': []},
    });
    await assertion;
    expect(CcApi.phpSessionId, isEmpty);
  });

  test('发码区号裸数字、号码去空格，同号码冷却阻止重复网络请求', () async {
    var requests = 0;
    Http.cc.httpClientAdapter = ReplyAdapter((o) {
      requests++;
      expect(o.uri.queryParameters['area_code'], '86');
      expect(o.uri.queryParameters['type'], '1');
      expect(o.uri.queryParameters['user_phone'], '10000000001');
      expect(o.headers.containsKey('Cookie'), isFalse);
      return {'returnCode': '0000'};
    });
    await CcApi.sendCode('100 0000 0001', area: '+86');
    await expectLater(
      CcApi.sendCode('10000000001'),
      throwsA(isA<CcApiError>().having((e) => e.code, 'code', 'COOLDOWN')),
    );
    expect(requests, 1);
    expect(CcApi.smsCooldownRemaining('10000000001'), greaterThan(0));
  });

  test('单曲收藏状态直接读取已认证回执，不扫描全部收藏', () async {
    CcApi.phpSessionId = 'test-session-cookie';
    Http.cc.httpClientAdapter = ReplyAdapter((o) {
      expect(o.uri.queryParameters['urlparam'], 'pad/detail/IsOpernCollected');
      expect(o.headers['Cookie'], 'PHPSESSID=test-session-cookie');
      return {
        'returnCode': '0000',
        'datas': {
          'has_collect': o.uri.queryParameters['opern_id'] == 'yes' ? '1' : '0',
        },
      };
    });
    expect(CcApi.flag(await CcApi.collectCheck('yes')), isTrue);
    expect(CcApi.flag(await CcApi.collectCheck('no')), isFalse);
  });

  test('学习历史上报使用 POST 新谱 ID，历史合并去重', () async {
    CcApi.phpSessionId = 'test-session-cookie';
    Http.cc.httpClientAdapter = ReplyAdapter((o) {
      final route = o.uri.queryParameters['urlparam'];
      if (route == 'home/user/addOneLadderPlayer') {
        expect(o.method, 'POST');
        expect(Uri.splitQueryString(o.data as String), {
          'opern_id': '889122',
          'album_id': '',
          'PHPSESSID': 'test-session-cookie',
        });
        return {'returnCode': '0000'};
      }
      return {
        'returnCode': '0000',
        'datas': {
          'total_pages': 1,
          'list': route == 'home/user/ladderPlayerOpernHistory'
              ? [
                  {'old_id': '36583', 'learning_id': '889122'},
                  {'old_id': 'common'},
                ]
              : [
                  {'old_id': 'common'},
                  {'old_id': 'older'},
                ],
        },
      };
    });
    await CcApi.reportBrowse('889122');
    final history = await CcApi.combinedBrowseHistory();
    expect((history['list'] as List).map((e) => e['old_id']), [
      '36583',
      'common',
      'older',
    ]);
    expect(history['has_more'], isFalse);
  });

  test('列表字段、会员与 AI 证据不会相互混用', () {
    const row = {
      'info': {
        'id': '125516',
        'name': '曲名',
        'titlepic': '//oss.tan8.com/cover.png',
        'maskName': '上传者',
      },
    };
    expect(ScoreCard.titleOf(row), '曲名');
    expect(ScoreCard.coverOf(row), 'https://oss.tan8.com/cover.png');
    expect(ScoreCard.authorOf(row), '上传者');
    expect(membershipOf({'is_vip': '1'}), 'VIP');
    expect(membershipOf({'sale_price': '6.00', 'paytype': '3'}), isNull);
    expect(aiLabelOf({'ccmz_page_1': '/preview.ccmz'}, 'cc'), 'AI 预览');
    expect(aiLabelOf({'play_json': '/full.ccmz'}, 'cc'), 'AI 谱');
    expect(
      aiLabelOf({'aiScrollScore': '0', 'showAIScrollScoreIcon': '1'}, 'tan8'),
      'AI 谱',
    );
    expect(userIdOf({'uid': 'encrypted-token', 'cg_uid': '42'}, 'cc'), '42');
    expect(
      userIdOf({'id': '123', 'u_uid': 'encrypted-token'}, 'cc', allowId: false),
      isEmpty,
    );
    expect(Sessions.ownsComment({'u_uid': 'test-session'}, isCc: true), isTrue);
    expect(
      Sessions.ownsComment({'u_uid': 'someone-else'}, isCc: true),
      isFalse,
    );
    expect(
      () => ensureWriteSucceeded('{"returncode":0,"message":"拒绝操作"}'),
      throwsStateError,
    );
  });

  test('弹琴吧收藏与关注检查覆盖第二页', () async {
    final starts = <String>[];
    Http.tan8.httpClientAdapter = ReplyAdapter((o) {
      final start = o.uri.queryParameters['start']!;
      starts.add(start);
      return {
        'data': {
          'code': '1000',
          'result': start == '0'
              ? List.generate(100, (i) => {'id': '$i', 'uid': '$i'})
              : [
                  {'id': 'target', 'uid': 'target'},
                ],
        },
      };
    });
    expect(await Tan8Api.isCollected('target'), isTrue);
    expect(await Tan8Api.isFollowing('self', 'target'), isTrue);
    expect(starts, ['0', '100', '0', '100']);
  });

  test('退出后旧请求不能恢复弹琴吧 Cookie', () async {
    final uri = Uri.parse('https://www.tan8.com/');
    await Http.tan8Jar.saveFromResponse(uri, [Cookie('session', 'old')]);
    final entered = Completer<void>(), response = Completer<Object>();
    Http.tan8.httpClientAdapter = ReplyAdapter(
      (_) {
        entered.complete();
        return response.future;
      },
      headers: {
        'set-cookie': ['session=stale; Path=/'],
      },
    );
    final pending = Http.tan8
        .get('/slow')
        .then<Object>((value) => value, onError: (Object error) => error);
    await entered.future;
    await Http.clearTan8Session();
    response.complete({
      'data': {'code': 1000},
    });
    expect(
      await pending,
      isA<DioException>().having(
        (e) => e.type,
        'type',
        DioExceptionType.cancel,
      ),
    );
    expect(await Http.tan8Jar.loadForRequest(uri), isEmpty);
  });

  test('服务端限制分页条数时仍继续查询，并拒绝重复页', () async {
    final starts = <String>[];
    Http.tan8.httpClientAdapter = ReplyAdapter((o) {
      final start = o.uri.queryParameters['start']!;
      starts.add(start);
      return {
        'data': {
          'code': '1000',
          'result': start == '0'
              ? [
                  {'id': 'first'},
                  {'id': 'second'},
                ]
              : [
                  {'id': 'target'},
                ],
        },
      };
    });
    expect(await Tan8Api.isCollected('target'), isTrue);
    expect(starts, ['0', '2']);
    Http.tan8.httpClientAdapter = ReplyAdapter(
      (_) => {
        'data': {
          'code': '1000',
          'result': [
            {'id': 'repeat'},
          ],
        },
      },
    );
    await expectLater(Tan8Api.isCollected('absent'), throwsFormatException);
  });

  testWidgets('一平台结果为空时另一平台仍能继续翻页', (tester) async {
    Http.tan8.httpClientAdapter = ReplyAdapter(
      (_) => {
        'data': {'code': 1, 'result': [], 'resultTotal': 0},
      },
    );
    final pages = <String>[];
    Http.cc.httpClientAdapter = ReplyAdapter((o) {
      final page = o.uri.queryParameters['pageindex']!;
      pages.add(page);
      return {
        'returnCode': '0000',
        'datas': {
          'list': [
            {
              'list': [
                if (page != '3')
                  {
                    'old_id': page,
                    'learning_name': '曲谱$page',
                    'upload_user_name': '作者',
                  },
              ],
            },
          ],
        },
      };
    });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SearchPage())),
    );
    // 持久化 Cookie 的文件 I/O 需要真实事件循环；同时等待搜索防抖。
    await tester.runAsync(() async {
      tester.widget<TextField>(find.byType(TextField)).controller!.text = '测试';
      await Future<void>.delayed(const Duration(milliseconds: 650));
    });
    await _flush(tester);
    expect(find.text('曲谱1'), findsOneWidget);
    await _flush(tester);
    expect(find.text('曲谱2'), findsOneWidget);
    expect(pages, ['1', '2', '3']);
  });

  testWidgets('导航与播放栏联动动画真实调整页面高度并释放底部安全区', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    playerOnHome.value = true;
    homeTabIndex.value = 0;
    addTearDown(() {
      playerOnHome.value = true;
      homeTabIndex.value = 0;
    });
    final player = Get.put<PlayerService>(LayoutPlayerService());
    player.state.track.value = const AuditionTrack(
      url: '',
      title: '布局曲谱',
      platform: 'cc',
      scoreId: '1',
      author: '布局作者',
    );
    const bodyKey = ValueKey('test.shell.body');
    await tester.pumpWidget(
      GetMaterialApp(
        home: const Scaffold(body: SizedBox.expand(key: bodyKey)),
        builder: (context, child) => MediaQuery(
          data: const MediaQueryData(
            size: Size(400, 800),
            padding: EdgeInsets.only(top: 44, bottom: 24),
          ),
          child: AppShell(child: child!),
        ),
      ),
    );
    await _flush(tester);
    final navRect = tester.getRect(find.byType(NavigationBar));
    for (final label in ['首页', '搜索', '我的']) {
      final rect = tester.getRect(find.text(label));
      expect(rect.top, greaterThanOrEqualTo(navRect.top));
      expect(rect.bottom, lessThanOrEqualTo(navRect.bottom));
    }
    Rect body() => tester.getRect(find.byKey(bodyKey));
    Rect bar() => tester.getRect(find.byType(MiniPlayerBar));
    expect(body().bottom, closeTo(bar().top, .01));
    final homeHeight = body().height;
    final homeBarTop = bar().top;
    playerOnHome.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(body().height, greaterThan(homeHeight));
    expect(body().height, lessThan(homeHeight + 62));
    await _flush(tester);
    expect(body().height, closeTo(homeHeight + 62, .01));
    expect(bar().top, closeTo(homeBarTop + 62, .01));
    expect(body().bottom, closeTo(bar().top, .01));
    expect(bar().bottom, closeTo(776, .01));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('shell.navigation.viewport')))
          .height,
      0,
    );
    playerOnHome.value = true;
    await _flush(tester);
    expect(body().height, closeTo(homeHeight, .01));
    player.state.track.value = null;
    await _flush(tester);
    expect(
      tester.getSize(find.byKey(const ValueKey('shell.player.region'))).height,
      0,
    );
    playerOnHome.value = false;
    await _flush(tester);
    expect(body().height, closeTo(800, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情自动请求图片并展示作者与可跳转的相关曲谱', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final opened = <String>[];
    var pictureRequests = 0;
    Http.cc.httpClientAdapter = ReplyAdapter((o) {
      if (o.uri.path.endsWith('sheet.png')) {
        pictureRequests++;
        return base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAABAAAAAKCAIAAAAy3EnLAAAAE0lEQVR4nGP4TyJgGNXwf0hqAACxUd4wZKJGVwAAAABJRU5ErkJggg==',
        );
      }
      final q = o.uri.queryParameters;
      Object data;
      switch (q['urlparam']) {
        case 'pad/detail/operninfov003':
          opened.add(q['old_id']!);
          data = {
            'old_id': q['old_id'],
            'name': q['old_id'] == '971970' ? '当前谱' : '关联谱',
            'author': '谱面作者',
            'image_list': ['https://s201.lzjoy.com/sheet.png'],
          };
        case 'pad/detail/getbookinfobyid':
          data = {
            'image_list': ['https://s201.lzjoy.com/sheet.png'],
          };
        case 'pad/recommend/getRecommendByOpernId':
          data = {
            'song_list': [
              {
                'old_id': '1072807',
                'learning_name': '关联谱',
                'upload_user_name': '推荐作者',
              },
            ],
          };
        case 'pad/detail/getOpernDetailComment':
          data = {'total_pages': 0, 'list': []};
        case 'home/user/getOpernCollectionList':
          data = {'total_pages': 0, 'list': []};
        default:
          data = {'has_collect': '0'};
      }
      return {'returnCode': '0000', 'datas': data};
    });
    await tester.pumpWidget(
      GetMaterialApp(
        home: const ScoreDetailPage(platform: 'cc', id: '971970'),
        builder: FlutterSmartDialog.init(),
      ),
    );
    await _flush(tester);
    expect(pictureRequests, 1);
    expect(find.byType(PageView), findsWidgets);
    expect(find.text('谱面作者'), findsWidgets);
    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(Tab, '简介'), findsOneWidget);
    expect(find.widgetWithText(Tab, '相关推荐'), findsNothing);
    await tester.ensureVisible(find.text('关联谱'));
    await _flush(tester);
    expect(find.text('关联谱'), findsOneWidget);
    tester.view.physicalSize = const Size(1400, 800);
    await _flush(tester);
    expect(find.widgetWithText(Tab, '相关推荐'), findsOneWidget);
    expect(find.widgetWithText(Tab, '简介'), findsNothing);
    expect(find.text('谱面作者'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('关联谱'));
    await _flush(tester);
    expect(opened, contains('1072807'));
    expect(pictureRequests, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('楼中楼分页忽略父体垃圾计数并可删除本人子回复', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var deleted = false;
    final pages = <String>[];
    Map<String, Object> reply(String id, String content, String owner) => {
      'id': id,
      'parent_id': 'root',
      'u_uid': owner,
      'u_name': owner,
      'content': content,
      'is_hit': '0',
    };
    Http.cc.httpClientAdapter = ReplyAdapter((o) {
      Object data;
      switch (o.uri.queryParameters['urlparam']) {
        case 'pad/detail/operninfov003':
          data = {'old_id': '1144422', 'name': '回复测试谱', 'author': '测试作者'};
        case 'pad/detail/getbookinfobyid':
          data = {'image_list': []};
        case 'pad/recommend/getRecommendByOpernId':
          data = {'song_list': []};
        case 'pad/detail/searchForSongs':
          data = {'list': []};
        case 'pad/detail/getOpernDetailComment':
          data = {
            'total_pages': 1,
            'list': [
              {
                'id': 'root',
                'u_uid': 'other',
                'u_name': '根用户',
                'content': '根评论',
                'total_reply': '10',
                'is_hit': '0',
              },
            ],
          };
        case 'pad/detail/IsOpernCollected':
          data = {'has_collect': '0'};
        case 'pad/detail/getOpernCommentReplyList':
          final page = o.uri.queryParameters['pageindex']!;
          pages.add(page);
          data = {
            'id': 'root',
            'total_reply': '0',
            'list_reply': switch (page) {
              '1' => [
                if (!deleted) reply('own-child', '本人子回复', 'test-session'),
                reply('child-2', '第二条子回复', 'other'),
              ],
              '2' => [reply('child-3', '第三条子回复', 'other')],
              _ => <Object>[],
            },
          };
        case 'user/center/delComment':
          deleted = true;
          data = {};
        default:
          throw StateError('意外请求 ${o.uri.queryParameters['urlparam']}');
      }
      return {'returnCode': '0000', 'datas': data};
    });
    await tester.pumpWidget(
      GetMaterialApp(
        home: const ScoreDetailPage(platform: 'cc', id: '1144422'),
        builder: FlutterSmartDialog.init(),
      ),
    );
    await _flush(tester);
    await tester.tap(find.widgetWithText(Tab, '评论'));
    await _flush(tester);
    expect(pages, ['1']);
    expect(find.textContaining('本人子回复', findRichText: true), findsOneWidget);
    await tester.ensureVisible(find.text('共 10 条回复'));
    await tester.tap(find.text('共 10 条回复'));
    await _flush(tester);
    expect(find.text('第三条子回复', findRichText: true), findsOneWidget);
    expect(find.text('没有更多回复'), findsOneWidget);
    expect(pages, ['1', '2', '3']);
    await tester.longPress(find.text('本人子回复', findRichText: true));
    await _flush(tester);
    await tester.tap(find.widgetWithText(ListTile, '删除'));
    await _flush(tester);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await _flush(tester);
    expect(find.text('本人子回复', findRichText: true), findsNothing);
    expect(find.text('第三条子回复', findRichText: true), findsOneWidget);
    SmartDialog.dismiss(status: SmartStatus.allToast);
    await tester.pump(const Duration(seconds: 3));
    await _flush(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('评论可取消赞、重新点赞并删除本人评论', (tester) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var liked = true, deleted = false;
    final routes = <String>[];
    Http.cc.httpClientAdapter = ReplyAdapter((o) {
      final route = o.uri.queryParameters['urlparam']!;
      routes.add(route);
      Object data;
      switch (route) {
        case 'pad/detail/getbookinfobyid':
          data = {'image_list': []};
        case 'pad/recommend/getRecommendByOpernId':
          data = {'song_list': []};
        case 'pad/detail/searchForSongs':
          data = {'list': []};
        case 'pad/detail/operninfov003':
          data = {
            'old_id': '971970',
            'name': '测试曲谱',
            'author': '测试作者',
            'play_json': '/test.ccmz',
          };
        case 'pad/detail/getOpernDetailComment':
          data = {
            'total_pages': 1,
            'list': [
              if (!deleted)
                {
                  'id': 'own-comment',
                  'u_uid': 'test-session',
                  'u_name': '测试用户',
                  'content': '本次测试评论',
                  'is_hit': liked ? '1' : '0',
                  'hits': liked ? 1 : 0,
                },
            ],
          };
        case 'pad/detail/IsOpernCollected':
          return {
            'returnCode': '0000',
            'datas': {'has_collect': '0'},
          };
        case 'home/user/getOpernCollectionList':
          data = {'total_pages': 0, 'list': []};
        case 'pad/detail/delCommentHits':
          liked = false;
          data = {};
        case 'pad/detail/addCommentHits':
          liked = true;
          data = {};
        case 'user/center/delComment':
          expect(o.uri.queryParameters['id'], 'own-comment');
          expect(o.uri.queryParameters['type'], 'opern');
          deleted = true;
          data = {};
        default:
          throw StateError('未预期请求 $route');
      }
      return {'returnCode': '0000', 'datas': data};
    });
    await tester.pumpWidget(
      GetMaterialApp(
        home: const ScoreDetailPage(platform: 'cc', id: '971970'),
        builder: FlutterSmartDialog.init(),
      ),
    );
    await _flush(tester);
    expect(find.text('AI 谱'), findsWidgets);
    await tester.tap(find.widgetWithText(Tab, '评论'));
    await _flush(tester);
    expect(find.byIcon(Icons.thumb_up), findsOneWidget);
    await tester.ensureVisible(find.byIcon(Icons.thumb_up));
    await tester.tap(find.byIcon(Icons.thumb_up));
    await _flush(tester);
    expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.thumb_up_outlined));
    await _flush(tester);
    expect(find.byIcon(Icons.thumb_up), findsOneWidget);
    await tester.longPress(find.text('本次测试评论', findRichText: true));
    await _flush(tester);
    await tester.tap(find.widgetWithText(ListTile, '删除'));
    await _flush(tester);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await _flush(tester);
    expect(find.text('本次测试评论', findRichText: true), findsNothing);
    expect(
      routes,
      containsAll([
        'pad/detail/delCommentHits',
        'pad/detail/addCommentHits',
        'user/center/delComment',
      ]),
    );
    expect(tester.takeException(), isNull);
    SmartDialog.dismiss(status: SmartStatus.allToast);
    await _flush(tester);
  });
}
