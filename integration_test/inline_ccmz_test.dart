import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sopu/http/cc_api.dart';
import 'package:sopu/http/http.dart';
import 'package:sopu/pages/score_detail_page.dart';
import 'package:sopu/pages/sheet_web_page.dart';
import 'package:sopu/services/player_service.dart';
import 'package:sopu/services/sessions.dart';

import '../test/app_contract_test.dart' show ReplyAdapter, LayoutPlayerService;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('虫虫图片浏览与独立 AI 入口完整渲染五页 CCMZ', (tester) async {
    final bytes = await File(const String.fromEnvironment('SOPU_FIXTURE'))
        .readAsBytes();
    final temp = await Directory.systemTemp.createTemp('sopu_inline_ccmz_');
    Http.init(cookieDir: temp.path);
    CcApi.clearSession();
    Sessions.ccUser = {};
    Get.put<PlayerService>(LayoutPlayerService());
    initWebViewEnv(
      await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: '${temp.path}/webview',
        ),
      ),
    );
    var downloads = 0;
    Http.cc.httpClientAdapter = ReplyAdapter((o) {
      if (o.uri.path.endsWith('/page.png')) {
        return base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAABAAAAAKCAIAAAAy3EnLAAAAE0lEQVR4nGP4TyJgGNXwf0hqAACxUd4wZKJGVwAAAABJRU5ErkJggg==',
        );
      }
      if (o.uri.path.endsWith('/fixture.ccmz')) {
        downloads++;
        return bytes;
      }
      final route = o.uri.queryParameters['urlparam'];
      final Object data = route == 'pad/detail/operninfov003'
          ? {
              'old_id': '1072807',
              'name': 'Are You Lost',
              'author': '测试作者',
              'image_list': [],
              'play_json': 'https://s201.lzjoy.com/fixture.ccmz',
            }
          : route == 'pad/detail/getbookinfobyid'
          ? {
              'image_list': List.generate(
                5,
                (index) => 'https://s201.lzjoy.com/page.png?i=$index',
              ),
            }
          : route == 'pad/recommend/getRecommendByOpernId'
          ? {'song_list': []}
          : {'list': [], 'total_pages': 0};
      return {'returnCode': '0000', 'datas': data};
    });
    await tester.pumpWidget(
      GetMaterialApp(
        home: const ScoreDetailPage(platform: 'cc', id: '1072807'),
        builder: FlutterSmartDialog.init(),
      ),
    );
    for (var i = 0; i < 120 && find.text('1/5').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('1/5'), findsOneWidget);
    expect(find.byType(SheetWebPage), findsNothing);
    expect(downloads, 0);
    await tester.ensureVisible(find.byIcon(Icons.auto_stories_outlined));
    await tester.tap(find.byIcon(Icons.auto_stories_outlined));
    dynamic sheet;
    String status = '';
    for (var i = 0; i < 240; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byType(SheetWebPage).evaluate().isEmpty) continue;
      sheet = tester.state(find.byType(SheetWebPage));
      final InAppWebViewController? controller = sheet.webViewController;
      if (controller == null) continue;
      status =
          '${await controller.evaluateJavascript(source: 'window._status()')}';
      if (status.startsWith('err:')) throw StateError(status);
      if (status.startsWith('done:')) break;
    }
    if (!status.startsWith('done:')) {
      tester.printToConsole(
        'SHEET diagnostics: ${find.descendant(of: find.byType(SheetWebPage), matching: find.byType(Text)).evaluate().map((element) => (element.widget as Text).data).toList()}',
      );
    }
    expect(downloads, 1);
    expect(
      tester.widget<SheetWebPage>(find.byType(SheetWebPage)).embedded,
      isFalse,
    );
    expect(status, 'done:5');
    final InAppWebViewController controller = sheet.webViewController;
    final metrics = jsonDecode(
      '${await controller.evaluateJavascript(source: "JSON.stringify({pages:window.__pages,error:window.__err,network:performance.getEntriesByType('resource').filter(function(r){return /^https?:/.test(r.name)}).length})")}',
    ) as Map;
    expect(metrics['error'], '');
    expect(metrics['network'], 0);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('共 5 页'), findsOneWidget);
    tester.printToConsole(
      'PASS inlineCCMZ ${jsonEncode(metrics)} downloads=$downloads',
    );
    SmartDialog.dismiss(status: SmartStatus.allToast);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
    Http.cc.close(force: true);
    Http.tan8.close(force: true);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
