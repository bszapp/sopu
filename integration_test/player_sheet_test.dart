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
import 'package:sopu/services/sessions.dart';
import 'package:sopu/services/player_service.dart';
import 'package:sopu/utils/globals.dart';
import 'package:sopu/utils/ccmz_decode.dart';
import 'package:sopu/pages/sheet_web_page.dart';
import 'package:sopu/pages/score_detail_page.dart';
import 'package:sopu/widgets/player_bar.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const fixture = String.fromEnvironment('SOPU_FIXTURE');
  const output = String.fromEnvironment('SOPU_OUTPUT');
  const samples = String.fromEnvironment('SOPU_SAMPLES');
  const skipSheet = bool.fromEnvironment('SOPU_SKIP_SHEET');
  testWidgets('缺少页脚的虫虫谱面与双平台播放器', (tester) async {
    tester.printToConsole('STAGE start');
    final dir = await Directory.systemTemp.createTemp('sopu_player_sheet_');
    GPaths.appSupport = dir.path;
    GPaths.cookiesTan8 = '${dir.path}/cookies';
    GPaths.downloads = '${dir.path}/downloads';
    await Directory('${dir.path}/data').create();
    await Directory(GPaths.downloads).create();
    Http.init(cookieDir: GPaths.cookiesTan8);
    await Sessions.init();
    MediaKit.ensureInitialized();
    final player = Get.put(PlayerService());
    tester.printToConsole('STAGE player initialized');
    if (!skipSheet) {
      initWebViewEnv(
        await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(
            userDataFolder: '${dir.path}/webview',
          ),
        ),
      );
    }
    tester.printToConsole('STAGE webview environment');
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: boundary, child: const app.MyApp()),
    );
    tester.printToConsole('STAGE app mounted');
    Future<void> waitFor(
      bool Function() condition,
      String label, {
      int seconds = 60,
    }) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) throw StateError('等待超时：$label');
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    final result = <String, dynamic>{};
    await Directory(output).create(recursive: true);
    await tester.pump(const Duration(seconds: 1));
    await waitFor(() => Get.key.currentState != null, '主导航');
    if (!skipSheet) {
      final pkg = decodeCcmz(await File(fixture).readAsBytes());
      tester.printToConsole('STAGE fixture decoded');
      Get.to(
        () => SheetWebPage.ccmz(
          title: 'Are You Lost · 1072807',
          scoreJson: pkg.scoreJson,
          infoJson: pkg.infoJson,
        ),
        transition: Transition.noTransition,
      );
      await tester.pump(const Duration(seconds: 1));
      await waitFor(
        () => find.byType(SheetWebPage).evaluate().isNotEmpty,
        '曲谱路由',
      );
      tester.printToConsole('STAGE sheet mounted');
      final dynamic sheet = tester.state(find.byType(SheetWebPage));
      await waitFor(() => sheet.webViewController != null, 'WebView 初始化');
      final InAppWebViewController controller = sheet.webViewController;
      String status = '';
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        status =
            '${await controller.evaluateJavascript(source: 'window._status()')}';
        if (status.startsWith('err:')) throw StateError(status);
        if (status.startsWith('done:')) break;
      }
      expect(status, startsWith('done:'));
      await tester.pump(const Duration(seconds: 8));
      await controller.evaluateJavascript(
        source: 'window.scrollTo(0,document.body.scrollHeight)',
      );
      await tester.pump(const Duration(seconds: 2));
      final metrics = jsonDecode(
        '${await controller.evaluateJavascript(source: '''JSON.stringify({status:window._status(),error:window.__err,svg:document.querySelectorAll('svg').length,shapes:document.querySelectorAll('path,line,rect,text,use').length,pages:window.__pages,network:performance.getEntriesByType('resource').filter(function(r){return /^https?:/.test(r.name)}).length})''')}',
      );
      expect(metrics['error'], isEmpty);
      expect(metrics['shapes'], greaterThan(10));
      expect(metrics['network'], 0);
      expect(metrics['pages'], 5);
      result['cc1072807'] = metrics;
      await controller.evaluateJavascript(source: 'window.scrollTo(0,0)');
      final shot = await controller.takeScreenshot();
      expect(shot, isNotNull);
      await File('$output/cc_1072807.png').writeAsBytes(shot!);
      tester.printToConsole('PASS cc1072807 $metrics');
      Get.back();
      await tester.pump(const Duration(seconds: 1));
    }
    final public = jsonDecode(
      await File(samples).readAsString(),
    )['publicSamples'];
    for (final platform in ['cc', 'tan8']) {
      final Map info =
          public[platform == 'cc'
              ? 'cc.opernDetail.971970'
              : 'tan8.scoreInfoPublic'];
      final cover = '${info[platform == 'cc' ? 'photo_address' : 'image_url']}';
      final track = AuditionTrack(
        platform: platform,
        scoreId: platform == 'cc' ? '971970' : '125516',
        url: platform == 'cc'
            ? '${info['audition_urtext']}'
            : '${cover.substring(0, cover.lastIndexOf('/') + 1)}tan8_125516.mp3',
        title: '${info[platform == 'cc' ? 'name' : 'songname']}',
        cover: cover,
        author: '${info[platform == 'cc' ? 'author' : 'maskName']}',
      );
      await player.play(track);
      await waitFor(
        () =>
            player.state.position.value.inMilliseconds > 600 &&
            player.state.duration.value > Duration.zero,
        '$platform 音频解码',
      );
      expect(player.state.error.value, isEmpty);
      final duration = player.state.duration.value;
      final bar = find.byType(MiniPlayerBar);
      final navigation = find.byType(NavigationBar);
      expect(
        tester.getRect(bar).bottom,
        lessThanOrEqualTo(tester.getRect(navigation).top + 1),
      );
      await tester.tap(
        find.descendant(
          of: bar,
          matching: find.byKey(const ValueKey('player.toggle')),
        ),
      );
      await waitFor(() => !player.state.playing.value, '$platform 暂停');
      final paused = player.state.position.value;
      await tester.pump(const Duration(seconds: 1));
      expect(
        (player.state.position.value - paused).inMilliseconds.abs(),
        lessThan(400),
      );
      await tester.tap(
        find.descendant(of: bar, matching: find.text(track.title)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('打开原曲谱'), findsOneWidget);
      expect(find.text(track.author), findsOneWidget);
      await player.seekTo(const Duration(seconds: 10));
      await player.resume();
      await waitFor(
        () =>
            player.state.position.value.inSeconds >= 10 &&
            player.state.playing.value,
        '$platform 续播',
      );
      await tester.pump(const Duration(seconds: 1));
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final screenshot = await render.toImage(pixelRatio: 1);
      final png = await screenshot.toByteData(format: ui.ImageByteFormat.png);
      await File('$output/player_$platform.png')
          .writeAsBytes(png!.buffer.asUint8List());
      screenshot.dispose();
      final original = find.text('打开原曲谱');
      await tester.ensureVisible(original);
      await tester.tap(original);
      await tester.pump(const Duration(seconds: 1));
      final detail = tester.widget<ScoreDetailPage>(
        find.byType(ScoreDetailPage),
      );
      expect(detail.platform, platform);
      expect(detail.id, track.scoreId);
      result['player.$platform'] = {
        'durationMs': duration.inMilliseconds,
        'paused': true,
        'resumed': true,
        'seekSeconds': 10,
        'scoreId': detail.id,
        'cover': track.cover.isNotEmpty,
        'author': track.author.isNotEmpty,
      };
      tester.printToConsole(
        'PASS player.$platform ${result['player.$platform']}',
      );
      Get.back();
      await tester.pump(const Duration(seconds: 1));
      await player.stop();
      await tester.pump(const Duration(milliseconds: 300));
    }
    await File('$output/player_sheet.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(result));
    Http.cc.close(force: true);
    Http.tan8.close(force: true);
    await tester.pumpWidget(const SizedBox());
    await player.disposePlayer();
  }, timeout: const Timeout(Duration(minutes: 8)));
}
