import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 全局目录: 应用支持目录 / 会话与 Cookie / 下载。
abstract final class GPaths {
  static late String appSupport;
  static late String downloads;
  static late String cookiesTan8;

  static Future<void> init() async {
    final support = (await getApplicationSupportDirectory()).path;
    appSupport = support;
    final ds = Directory('$support/data/');
    if (!ds.existsSync()) ds.createSync(recursive: true);
    cookiesTan8 = Directory('$support/cookies/tan8/').path;

    String? def;
    if (Platform.isAndroid) {
      final ext = (await getExternalStorageDirectory())?.path;
      def = ext != null ? '$ext/downloads' : '$support/downloads';
    } else if (Platform.isIOS || Platform.isMacOS) {
      def = '$support/Downloads';
    } else if (Platform.isWindows) {
      def = '${Platform.environment['USERPROFILE'] ?? ''}\\Downloads';
      if (def.isEmpty || !Directory(def).existsSync()) {
        def = '$support/Downloads';
      }
    } else {
      def = '$support/Downloads';
    }
    try {
      final d = Directory(def);
      if (!d.existsSync()) d.createSync(recursive: true);
      downloads = def;
    } catch (_) {
      downloads = '$support/Downloads';
      Directory(downloads).createSync(recursive: true);
    }
  }
}
