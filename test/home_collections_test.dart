import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sopu/http/http.dart';
import 'package:sopu/pages/home_tab.dart';
import 'package:sopu/widgets/common.dart';

import 'app_contract_test.dart' show ReplyAdapter;

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
    final temp = await Directory.systemTemp.createTemp('sopu_home_contract_');
    Http.init(cookieDir: temp.path);
  });
  setUp(() => Get.testMode = true);
  tearDown(() {
    Get.reset();
  });
  tearDownAll(() {
    Http.cc.close(force: true);
    Http.tan8.close(force: true);
  });
  testWidgets('首页显示多个虫虫楼层与弹琴吧真实标题', (tester) async {
    Http.cc.httpClientAdapter = ReplyAdapter((o) {
      expect(o.uri.queryParameters['urlparam'], 'home/ccgq/tab');
      return {
        'returnCode': '0000',
        'datas': [
          {
            'container_type': 'title',
            'data': [
              {'title': '热度飙升'},
            ],
          },
          {
            'container_type': 'limited_time_free_opern_list',
            'data': [
              {'old_id': '1', 'learning_name': '谱一', 'upload_user_name': '作者一'},
            ],
          },
          {
            'container_type': 'title',
            'data': [
              {'title': '全网首发'},
            ],
          },
          {
            'container_type': 'new_hot_opern_list',
            'data': [
              {'old_id': '2', 'learning_name': '谱二', 'upload_user_name': '作者二'},
            ],
          },
        ],
      };
    });
    Http.tan8.httpClientAdapter = ReplyAdapter((o) {
      final method = o.uri.queryParameters['m'];
      if (method == 'get_view_category') {
        return {
          'type_data': [
            {
              'mod_container_url':
                  'https://www.tan8.com/codeindex.php?m=container',
            },
          ],
        };
      }
      if (method == 'container') {
        return {
          'mod_container_data': {
            'data': [
              {
                'title': '热门合集',
                'web_mod_id': 'Muban_AlbumHengList',
                'mod_data_url': 'https://www.tan8.com/codeindex.php?m=rows',
              },
            ],
          },
        };
      }
      return {
        'data': {
          'code': '1000',
          'result': [
            {
              'id': '3',
              'title': '合集入口',
              'author': '作者',
              'jumpEvent': {
                'parm1': 'https://www.tan8.com/codeindex.php?m=erji_album_yuepu_new&album_id=3',
              },
            },
          ],
        },
      };
    });
    await tester.pumpWidget(const GetMaterialApp(home: HomeTab()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await _flush(tester);
    expect(find.text('热度飙升'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('全网首发'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('全网首发'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('热门合集'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('热门合集'), findsOneWidget);
    expect(find.text('Muban_AlbumHengList'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('合集卡片进入合集路由，避免使用合集ID打开单谱', (tester) async {
    String? route;
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: '/',
        getPages: [
          GetPage(
            name: '/',
            page: () => const Scaffold(
              body: ScoreCard({
                '__platform': 'tan8',
                'id': '3',
                'title': '合集入口',
                'author': '作者',
                'jumpEvent': {
                  'parm1': 'https://www.tan8.com/codeindex.php?m=erji_album_yuepu_new&album_id=3',
                },
              }),
            ),
          ),
          GetPage(
            name: '/collection',
            page: () {
              route = '/collection';
              return const Scaffold(body: Text('合集详情'));
            },
          ),
          GetPage(
            name: '/score',
            page: () {
              route = '/score';
              return const Scaffold();
            },
          ),
        ],
      ),
    );
    await _flush(tester);
    await tester.tap(find.text('合集入口'));
    await _flush(tester);
    expect(route, '/collection');
    expect(find.text('合集详情'), findsOneWidget);
  });
}
