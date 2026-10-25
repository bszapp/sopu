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

/// 验证写操作的业务回执，保留纯文本回执供调用方进一步回读状态。
void ensureWriteSucceeded(dynamic value) {
  if (value is Response) value = value.data;
  if (value is String) {
    if (value.trim().isEmpty) throw const FormatException('服务器未返回操作回执');
    try {
      value = jsonDecode(value);
    } on FormatException {
      return;
    }
  }
  if (value is Map) {
    final code = value['returnCode'] ?? value['returncode'] ?? value['code'];
    if (code != null && !['0000', '1000', '1', '200'].contains('$code')) {
      throw StateError(textOfReceipt(value));
    }
    if (value['data'] is Map) ensureWriteSucceeded(value['data']);
  }
}

String textOfReceipt(Map value) =>
    '${value['returnMsg'] ?? value['message'] ?? value['msg'] ?? value['error'] ?? value['returncode'] ?? value['code'] ?? '操作未成功'}';

/// 双平台 dio 实例 + 阿里云 CC 挑战重试。
/// tan8: PHP 会话 Cookie 持久化 (PersistCookieJar)。
/// cc: API 层按请求携带登录 Cookie，下载资源不会附带账号 Cookie。
abstract final class Http {
  static late final Dio tan8;
  static late final Dio cc;
  static late final PersistCookieJar tan8Jar;
  static int _tan8SessionVersion = 0;
  static int get tan8SessionVersion => _tan8SessionVersion;
  static Future<void> _cookieWork = Future.value();

  static Future<void> _queueCookies(Future<void> Function() operation) {
    _cookieWork = _cookieWork
        .catchError((Object _) {})
        .then((_) => operation());
    return _cookieWork;
  }

  static Future<void> clearTan8Session() {
    _tan8SessionVersion++;
    return _queueCookies(() => tan8Jar.deleteAll());
  }

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
    tan8.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.extra['tan8SessionVersion'] = _tan8SessionVersion;
          handler.next(options);
        },
        onResponse: (response, handler) {
          if (response.requestOptions.extra['tan8SessionVersion'] !=
              _tan8SessionVersion) {
            handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                type: DioExceptionType.cancel,
                message: '账号已退出或切换，请重新加载',
              ),
            );
          } else {
            handler.next(response);
          }
        },
      ),
    );
    tan8.interceptors.add(_SessionCookies(tan8Jar));

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

class _SessionCookies extends CookieManager {
  _SessionCookies(super.jar);
  @override
  Future<void> saveCookies(Response response) => Http._queueCookies(() async {
    if (response.requestOptions.extra['tan8SessionVersion'] ==
        Http.tan8SessionVersion) {
      await super.saveCookies(response);
    }
  });
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
