import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:media_kit/media_kit.dart';
import 'package:get/get.dart';
import 'package:sopu/main.dart' as app;
import 'package:sopu/http/http.dart';
import 'package:sopu/pages/author_page.dart';
import 'package:sopu/pages/image_viewer_page.dart';
import 'package:sopu/pages/score_detail_page.dart';
import 'package:sopu/pages/search_page.dart';
import 'package:sopu/pages/sheet_web_page.dart';
import 'package:sopu/services/sessions.dart';
import 'package:sopu/services/player_service.dart';
import 'package:sopu/utils/globals.dart';
import 'package:sopu/widgets/common.dart';
import 'package:sopu/widgets/player_bar.dart';
import 'package:sopu/widgets/piliplus/score_card_h.dart';
import 'package:sopu/widgets/piliplus/score_detail_layout.dart';
import 'package:sopu/widgets/piliplus/score_intro_panel.dart';
import 'package:sopu/widgets/piliplus/score_reply_item.dart';

import '../tool/gap_contract_smoke.dart' show ProbeProxy;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const output = String.fromEnvironment('SOPU_E2E_OUTPUT');
  testWidgets('真实搜索、图片、作者、楼中楼、AI 谱和双平台试听', (tester) async {
    HttpOverrides.global = ProbeProxy();
    final directory = await Directory.systemTemp.createTemp('sopu_final_ui_');
    GPaths.appSupport = directory.path;
    GPaths.downloads = '${directory.path}/downloads';
    GPaths.cookiesTan8 = '${directory.path}/cookies';
    await Directory('${directory.path}/data').create();
    await Directory(GPaths.downloads).create();
    Http.init(cookieDir: GPaths.cookiesTan8);
    await Sessions.init();
    MediaKit.ensureInitialized();
    final player = Get.put(PlayerService());
    initWebViewEnv(
      await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: '${directory.path}/webview',
        ),
      ),
    );
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: boundary, child: const app.MyApp()),
    );
    Future<void> waitFor(
      bool Function() condition,
      String label, {
      int seconds = 120,
    }) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) throw StateError('等待超时：$label');
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    Future<void> screenshot(String name) async {
      if (output.isEmpty) return;
      await Directory(output).create(recursive: true);
      await tester.pump(const Duration(milliseconds: 300));
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$output/$name.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    }

    final results = <Map<String, dynamic>>[];
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('搜索'),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    final selected = const String.fromEnvironment('SOPU_TEST_PLATFORM');
    for (final platform in [
      'cc',
      'tan8',
    ].where((p) => selected.isEmpty || p == selected)) {
      final id = platform == 'cc' ? '1072807' : '125516';
      final keyword = platform == 'cc' ? 'Are You Lost' : '再一次见面';
      final expectedPages = platform == 'cc' ? 5 : 3;
      await tester.enterText(find.byType(TextField), keyword);
      await tester.pump(const Duration(seconds: 1));
      final rows = find.byWidgetPredicate(
        (widget) =>
            widget is ScoreCardH &&
            widget.item['__platform'] == platform &&
            ScoreCard.idOf(widget.item) == id,
      );
      final searchScroll = find
          .descendant(
            of: find.byType(SearchPage),
            matching: find.byType(CustomScrollView),
          )
          .first;
      for (
        var attempt = 0;
        attempt < 30 && rows.evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 500));
        if (attempt > 2) await tester.drag(searchScroll, const Offset(0, -350));
      }
      expect(rows, findsWidgets, reason: '$platform 未在真实搜索中找到 $id');
      await tester.ensureVisible(rows.first);
      await screenshot('${platform}_search');
      await tester.tap(rows.first);
      await tester.pump(const Duration(seconds: 1));
      await waitFor(
        () => find.text('1/$expectedPages').evaluate().isNotEmpty,
        '$platform 完整图片列表',
      );
      expect(find.byType(SheetWebPage), findsNothing);
      final dynamic state = tester.state(find.byType(ScoreDetailPage));
      final String author = state.authorName;
      final String authorUid = state.authorUid;
      expect(author, isNotEmpty);
      expect(authorUid, isNotEmpty);
      await screenshot('${platform}_detail');
      final scoreImage = find
          .descendant(
            of: find.byType(ScoreDetailPage),
            matching: find.byWidgetPredicate(
              (widget) => widget is Image && widget.image is MemoryImage,
            ),
          )
          .hitTestable()
          .first;
      await tester.ensureVisible(scoreImage);
      await tester.tap(scoreImage);
      await tester.pump(const Duration(seconds: 1));
      final viewer = tester.widget<ImageViewerPage>(
        find.byType(ImageViewerPage),
      );
      expect(viewer.bytesList.length, expectedPages);
      for (final bytes in viewer.bytesList) {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, greaterThan(500));
        frame.image.dispose();
        codec.dispose();
      }
      Get.back();
      await tester.pump(const Duration(milliseconds: 600));
      final owner = find.descendant(
        of: find.byType(ScoreIntroPanel),
        matching: find.text(author),
      );
      await tester.ensureVisible(owner.first);
      await tester.tap(owner.first);
      await tester.pump(const Duration(seconds: 1));
      await waitFor(
        () =>
            find.byType(AuthorPage).evaluate().isNotEmpty &&
            find.text('UID: $authorUid').evaluate().isNotEmpty,
        '$platform 作者主页',
      );
      await screenshot('${platform}_author');
      if (platform == 'tan8') {
        await tester.tap(find.widgetWithText(Tab, '收藏'));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('UID: $authorUid'), findsOneWidget);
        await tester.tap(find.widgetWithText(Tab, '发布'));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('UID: $authorUid'), findsOneWidget);
      }
      Get.back();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(
        find
            .descendant(
              of: find.byType(TabBar),
              matching: find.textContaining('评论'),
            )
            .first,
      );
      await tester.pump(const Duration(seconds: 1));
      await waitFor(
        () => find.byType(ScoreReplyItem).evaluate().isNotEmpty,
        '$platform 评论',
      );
      if (platform == 'cc') {
        final preview = find.byType(ScoreReplyPreview).hitTestable();
        for (
          var attempt = 0;
          attempt < 25 && preview.evaluate().isEmpty;
          attempt++
        ) {
          await tester.drag(
            find.byKey(const PageStorageKey('score-comments')),
            const Offset(0, -450),
          );
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(preview, findsWidgets, reason: '有回复的父评论应自动加载楼中楼');
        await screenshot('cc_comments');
        await tester.tap(preview.first);
        await tester.pump(const Duration(seconds: 1));
        await waitFor(
          () => find.textContaining('回复（').evaluate().isNotEmpty,
          '完整回复楼层',
        );
        await screenshot('cc_reply_thread');
        Get.back();
        await tester.pump(const Duration(milliseconds: 600));
      } else {
        await screenshot('tan8_comments');
      }
      final firstTab = find
          .descendant(
            of: find.byType(ScoreDetailLayout),
            matching: find.byType(Tab),
          )
          .first;
      await tester.tap(firstTab);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.ensureVisible(find.byIcon(Icons.auto_stories_outlined));
      await tester.tap(find.byIcon(Icons.auto_stories_outlined));
      for (var attempt = 0; attempt < 240; attempt++) {
        await tester.pump(const Duration(milliseconds: 500));
        if (find.byType(SimpleDialog).evaluate().isNotEmpty) {
          await tester.tap(find.text('主谱'));
          await tester.pump(const Duration(milliseconds: 300));
        }
        if (find.byType(SheetWebPage).evaluate().isNotEmpty) break;
      }
      expect(find.byType(SheetWebPage), findsOneWidget);
      final dynamic sheet = tester.state(find.byType(SheetWebPage));
      try {
        await waitFor(
          () => sheet.webViewController != null,
          '$platform WebView',
          seconds: 45,
        );
      } catch (_) {
        final text = find
            .descendant(
              of: find.byType(SheetWebPage),
              matching: find.byType(Text),
            )
            .evaluate()
            .map((element) => (element.widget as Text).data)
            .toList();
        tester.printToConsole('WEBVIEW diagnostics: ${jsonEncode(text)}');
        await screenshot('${platform}_webview_failure');
        rethrow;
      }
      final InAppWebViewController controller = sheet.webViewController;
      var status = '';
      for (var attempt = 0; attempt < 240; attempt++) {
        await tester.pump(const Duration(milliseconds: 500));
        status =
            '${await controller.evaluateJavascript(source: 'window._status && window._status()')}';
        if (status.startsWith('err:')) throw StateError(status);
        if (status.startsWith('done:')) break;
      }
      expect(status, startsWith('done:'));
      final metrics = jsonDecode(
        '${await controller.evaluateJavascript(source: "JSON.stringify({pages:window.__pages,error:window.__err,shapes:document.querySelectorAll('path,line,rect,text,use').length,network:performance.getEntriesByType('resource').filter(function(r){return /^https?:/.test(r.name)}).length})")}',
      ) as Map;
      expect(metrics['error'], isEmpty);
      expect(metrics['shapes'], greaterThan(10));
      expect(metrics['network'], 0);
      final shot = await controller.takeScreenshot();
      if (output.isNotEmpty && shot != null) {
        await File('$output/${platform}_ai.png').writeAsBytes(shot);
      }
      Get.back();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.ensureVisible(find.text('下载源'));
      await tester.tap(find.text('下载源'));
      final extension = platform == 'cc' ? 'ccmz' : 'zip';
      await waitFor(
        () => File('${GPaths.downloads}/$id.$extension').existsSync(),
        '$platform 源文件下载',
      );
      await tester.ensureVisible(find.byTooltip('试听'));
      await tester.tap(find.byTooltip('试听'));
      await waitFor(
        () =>
            player.state.track.value?.scoreId == id &&
            player.state.position.value.inMilliseconds > 500,
        '$platform 试听解码',
      );
      expect(player.state.error.value, isEmpty);
      await player.pause();
      await tester.pump(const Duration(milliseconds: 300));
      expect(player.state.playing.value, isFalse);
      final bar = find.byType(MiniPlayerBar);
      await tester.tap(
        find.descendant(
          of: bar,
          matching: find.text(player.state.track.value!.title),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byTooltip('打开原曲谱'), findsOneWidget);
      await player.resume();
      await waitFor(() => player.state.playing.value, '$platform 继续播放');
      await screenshot('${platform}_audition');
      await tester.tap(find.byTooltip('打开原曲谱'));
      await tester.pump(const Duration(milliseconds: 700));
      final detail = tester.widget<ScoreDetailPage>(
        find.byType(ScoreDetailPage),
      );
      expect(detail.id, id);
      expect(detail.platform, platform);
      await player.stop();
      results.add({
        'platform': platform,
        'id': id,
        'imagePages': expectedPages,
        'authorUid': authorUid,
        'authorName': author,
        'ai': metrics,
        'auditionPauseResume': true,
        'sourceBytes': File('${GPaths.downloads}/$id.$extension').lengthSync(),
      });
      if (output.isNotEmpty) {
        await File('$output/ui_flow.json')
            .writeAsString(const JsonEncoder.withIndent('  ').convert(results));
      }
      tester.printToConsole('PASS final $platform ${jsonEncode(results.last)}');
      Get.back();
      await tester.pump(const Duration(milliseconds: 600));
      Get.back();
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpWidget(const SizedBox());
    Http.cc.close(force: true);
    Http.tan8.close(force: true);
    await player.disposePlayer();
  }, timeout: const Timeout(Duration(minutes: 12)));
}
