import 'dart:convert';
import 'dart:io';
import 'dart:ui' show instantiateImageCodec;
import 'package:flutter/material.dart';
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
import 'package:sopu/widgets/common.dart';
import 'package:sopu/pages/score_detail_page.dart';
import 'package:sopu/pages/sheet_web_page.dart';
import 'package:sopu/pages/image_viewer_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const output = String.fromEnvironment('SOPU_E2E_OUTPUT');
  testWidgets('真实搜索、详情、AI 谱和源文件下载', (tester) async {
    final directory = await Directory.systemTemp.createTemp('sopu_ui_');
    GPaths.appSupport = directory.path;
    GPaths.downloads = '${directory.path}/downloads';
    GPaths.cookiesTan8 = '${directory.path}/cookies';
    await Directory('${directory.path}/data').create();
    await Directory(GPaths.downloads).create();
    Http.init(cookieDir: GPaths.cookiesTan8);
    await Sessions.init();
    MediaKit.ensureInitialized(); Get.put(PlayerService());
    if (Platform.isWindows) {
      initWebViewEnv(await WebViewEnvironment.create(settings: WebViewEnvironmentSettings(userDataFolder: '${directory.path}/webview')));
    }
    await tester.pumpWidget(const app.MyApp());
    tester.printToConsole('UI_STAGE boot');
    Future<void> waitFor(bool Function() condition, String label, {int seconds = 120}) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) throw StateError('等待超时: $label');
        await tester.pump(const Duration(milliseconds: 200));
      }
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('搜索')));
    tester.printToConsole('UI_STAGE search tab');
    await tester.pump(const Duration(seconds: 1));
    final results = <Map<String, dynamic>>[];
    const selectedPlatform = String.fromEnvironment('SOPU_TEST_PLATFORM');
    for (final platform in ['cc', 'tan8'].where((p) => selectedPlatform.isEmpty || p == selectedPlatform)) {
      final keyword = platform == 'cc' ? '晴天' : '再一次见面';
      await tester.enterText(find.byType(TextField), keyword);
      await tester.pump(const Duration(milliseconds: 800));
      final rows = find.byWidgetPredicate((w) => w is ScoreRow && w.item['__platform'] == platform && ScoreCard.titleOf(w.item).contains(keyword));
      await waitFor(() => rows.evaluate().isNotEmpty, '$platform 搜索结果');
      final row = tester.widget<ScoreRow>(rows.first);
      final id = ScoreCard.idOf(row.item), title = ScoreCard.titleOf(row.item);
      tester.printToConsole('UI_STAGE $platform search found $id');
      await tester.ensureVisible(rows.first); await tester.tap(rows.first);
      await tester.pump(const Duration(seconds: 1));
      await waitFor(() => find.text(platform == 'cc' ? 'AI 谱(ccmz)' : 'AI 谱(svg)').evaluate().isNotEmpty, '$platform 详情');
      tester.printToConsole('UI_STAGE $platform detail ready');
      await tester.tap(find.text(platform == 'cc' ? 'AI 谱(ccmz)' : 'AI 谱(svg)'));
      await tester.pump(const Duration(seconds: 1));
      await waitFor(() => find.byType(SheetWebPage).evaluate().isNotEmpty, '$platform AI 谱页面');
      tester.printToConsole('UI_STAGE $platform sheet route');
      final dynamic state = tester.state(find.byType(SheetWebPage));
      await waitFor(() => state.webViewController != null, '$platform WebView');
      tester.printToConsole('UI_STAGE $platform webview created');
      final InAppWebViewController controller = state.webViewController;
      String status = '';
      for (var i = 0; i < 240; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        status = '${await controller.evaluateJavascript(source: 'window._status && window._status()')}';
        if (status.startsWith('err:')) {
          if (output.isNotEmpty) { await Directory(output).create(recursive: true); await File('$output/${platform}_failure.json').writeAsString(jsonEncode({'status': status, 'dom': await controller.evaluateJavascript(source: 'document.body.innerHTML.slice(0,2000)')})); }
          throw StateError('$platform: $status');
        }
        if (status.startsWith('done:')) break;
      }
      expect(status, startsWith('done:'));
      final metrics = await controller.evaluateJavascript(source: '''JSON.stringify({pages:window.__pages,svg:document.querySelectorAll('svg').length,shapes:document.querySelectorAll('path,line,rect,text,use').length,width:document.body.scrollWidth,height:document.body.scrollHeight,font:document.fonts.status,error:window.__err,networkResources:performance.getEntriesByType('resource').filter(function(r){return /^https?:/.test(r.name)}).length,csp:document.querySelector('meta[http-equiv="Content-Security-Policy"]').content})''');
      final m = jsonDecode('$metrics') as Map<String, dynamic>;
      expect(m['shapes'], greaterThan(10)); expect(m['height'], greaterThan(100)); expect(m['error'], isEmpty);
      expect(m['networkResources'], 0); expect(m['csp'], contains("connect-src 'none'"));
      if (platform == 'tan8') {
        final remaining = await controller.evaluateJavascript(source: '''document.querySelectorAll('svg .Text[fill="#8c8c8c"]').length''');
        expect(remaining, 0);
      }
      final screenshot = await controller.takeScreenshot();
      expect(screenshot, isNotNull);
      if (output.isNotEmpty) { await Directory(output).create(recursive: true); await File('$output/${platform}_$id.png').writeAsBytes(screenshot!); }
      results.add({'platform': platform, 'keyword': keyword, 'id': id, 'title': title, 'status': status, 'metrics': m});
      Get.back(); await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ScoreDetailPage), findsOneWidget);
      if(platform=='tan8') {
        await tester.tap(find.text('预览'));await tester.pump(const Duration(seconds:1));
        await waitFor(()=>find.byType(ImageViewerPage).evaluate().isNotEmpty,'完整图片谱');
        final viewer=tester.widget<ImageViewerPage>(find.byType(ImageViewerPage));
        expect(viewer.bytesList.length,3);
        for(final bytes in viewer.bytesList){
          final codec=await instantiateImageCodec(bytes);
          final frame=await codec.getNextFrame();expect(frame.image.width,greaterThan(1000));
          frame.image.dispose();codec.dispose();
        }
        results.last['imagePages']=viewer.bytesList.length;
        Get.back();await tester.pump(const Duration(seconds:1));
      }
      await tester.tap(find.text('下载源')); await tester.pump(const Duration(seconds: 1));
      final ext = platform == 'cc' ? 'ccmz' : 'zip';
      await waitFor(() => File('${GPaths.downloads}/$id.$ext').existsSync(), '$platform 源文件下载');
      results.last['downloadBytes'] = File('${GPaths.downloads}/$id.$ext').lengthSync();
      if (platform == 'tan8') {
        await tester.tap(find.text('演奏数据')); await tester.pump(const Duration(seconds: 1));
        await waitFor(() => find.text('下载演奏数据原包').evaluate().length >= 2, 'ypad/ypad2 详情');
        await tester.tap(find.text('下载演奏数据原包').first); await tester.pump(const Duration(seconds: 1));
        await waitFor(() => Directory(GPaths.downloads).listSync().whereType<File>().any((f) => f.path.endsWith('.ypad')), 'ypad 保存');
        results.last['playbackPackages'] = 2;
        await tester.tap(find.text('关闭')); await tester.pump(const Duration(milliseconds: 500));
      }
      if (output.isNotEmpty) await File('$output/ui_flow.json').writeAsString(const JsonEncoder.withIndent('  ').convert(results));
      Get.back(); await tester.pump(const Duration(seconds: 1));
    }
    Http.cc.close(force: true); Http.tan8.close(force: true);
    await Get.delete<PlayerService>(force: true);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
