import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart' show CookieManager;

import '../common/constants.dart';

const _kDefaultCookieDir = 'sopu_cookies/';

class Tan8ApiError implements Exception {
  final String code;
  final String message;
  const Tan8ApiError(this.code, this.message);
  @override
  String toString() => 'Tan8ApiError($code): $message';
}

class CcApiError implements Exception {
  final String code;
  final String msg;
  const CcApiError(this.code, this.msg);
  @override
  String toString() => 'CcApiError($code): $msg';
}

/// 双平台 dio 实例 + 阿里云 CC 挑战重试。
/// tan8: PHP 会话 Cookie 持久化 (PersistCookieJar)。
/// cc: 无 cookie 全凭公共查询参数。
abstract final class Http {
  static late final Dio tan8;
  static late final Dio cc;
  static late final PersistCookieJar tan8Jar;

  /// [cookieDir] 不传时落到系统临时目录(调用方在 main 里传 GPaths.cookiesTan8)。
  static void init({String? cookieDir}) {
    final dir = cookieDir ?? '${Directory.systemTemp.path}/$_kDefaultCookieDir';
    Directory(dir).createSync(recursive: true);
    tan8Jar = PersistCookieJar(storage: FileStorage(dir), ignoreExpires: true);
    tan8 = Dio(
      BaseOptions(
        baseUrl: Tan8C.domain,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 90),
        headers: {'User-Agent': Tan8C.userAgent},
        // 原样拿字符串自己 parse, 规避服务端偶发 content-type 混合
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    tan8.interceptors.add(CookieManager(tan8Jar));

    cc = Dio(
      BaseOptions(
        baseUrl: CcC.baseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 120),
        headers: {'User-Agent': CcC.userAgent},
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
  }
}

/// 带阿里云 CC 挑战重试的 tan8 请求: 404/502/503 → 吸收 acw_tc → 重试。
Future<Response<String>> tan8RetryFuture(
  Future<Response<String>> Function() doWork,
) async {
  var attempt = 0;
  Duration wait = const Duration(milliseconds: 1200);
  while (true) {
    try {
      final r = await doWork();
      if ([404, 502, 503].contains(r.statusCode) && attempt < 2) {
        await Future<void>.delayed(wait);
        wait = const Duration(milliseconds: 2500);
        attempt++;
        continue;
      }
      return r;
    } on DioException catch (e) {
      final st = e.response?.statusCode;
      if ((st == 404 || st == 502 || st == 503) && attempt < 2) {
        await Future<void>.delayed(wait);
        wait = const Duration(milliseconds: 2500);
        attempt++;
        continue;
      }
      rethrow;
    }
  }
}

/// URL 编码(form 表单) 工具。
String formEncode(Map<String, String?> fields) {
  final out = <String>[];
  fields.forEach((k, v) {
    if (v == null) return;
    out.add('${Uri.encodeComponent(k)}=${Uri.encodeComponent(v)}');
  });
  return out.join('&');
}

Future<Map<String, dynamic>> parseJsonMap(Response<String> r) async {
  if (r.statusCode != 200 || (r.data?.isEmpty ?? true)) {
    throw Tan8ApiError('${r.statusCode}', 'HTTP ${r.statusCode}');
  }
  try {
    return json.decode(r.data!) as Map<String, dynamic>;
  } on FormatException catch (e) {
    throw Tan8ApiError('PARSE', 'JSON 解析失败: ${e.message}');
  }
}
