/// 双平台会话: 登录信息持久化 (JSON 文件, 位于应用支持目录)。
/// tan8 鉴权靠 HTTP Cookie (PersistCookieJar), 这里只存用户资料;
/// 虫虫鉴权靠 uid/service_uid/service_key 查询参数 + PHPSESSID 跟随。
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../http/cc_api.dart';
import '../http/http.dart';
import '../http/tan8_api.dart';
import '../utils/globals.dart';

abstract final class Sessions {
  static final changed = ValueNotifier<int>(0);
  static Map<String, dynamic> tan8User = {};
  static Map<String, dynamic> ccUser = {};

  static bool get tan8LoggedIn => tan8User.isNotEmpty;
  static bool get ccLoggedIn => ccUser.isNotEmpty;

  static String get tan8Uid => '${tan8User['uid'] ?? ''}';
  static String get ccNumericId =>
      ccUser['cg_uid']?.toString().isNotEmpty == true
          ? ccUser['cg_uid']!.toString()
          : CcApi.cgUid;

  static Future<void> init() async {
    tan8User = _readJson('tan8_user.json');
    ccUser = _readJson('cc_user.json');
    _applyCc();
    final clientFile = File('${GPaths.appSupport}/data/cc_client_id.txt');
    if (clientFile.existsSync()) {
      final id = clientFile.readAsStringSync().trim();
      if (id.isNotEmpty) CcApi.eqid = id;
    } else {
      clientFile.writeAsStringSync(CcApi.eqid);
    }
    CcApi.onSessionDirty = () async {
      if (CcApi.uid.isEmpty) return;
      ccUser = {
        ...ccUser,
        'uid': CcApi.uid,
        'service_uid': CcApi.serviceUid,
        'service_key': CcApi.serviceKey,
        'id': CcApi.userToken,
        'cg_uid': CcApi.cgUid,
      };
      await saveCc();
    };
    // cookie jar 里可能有旧会话, 尝试无声恢复一份资料
    if (Sessions.tan8LoggedIn) {
      try {
        final u = await Tan8Api.getUserInfo();
        if ('${u['code']}' == '1000' && u['user'] is Map) {
          tan8User = Map<String, dynamic>.from(u['user']);
          await saveTan8();
        }
      } catch (_) {}
    }
  }

  static void _applyCc() {
    CcApi.uid = '${ccUser['uid'] ?? ''}';
    CcApi.serviceUid = '${ccUser['service_uid'] ?? ''}';
    CcApi.serviceKey = '${ccUser['service_key'] ?? ''}';
    CcApi.userToken = '${ccUser['id'] ?? ''}';
    CcApi.cgUid = '${ccUser['cg_uid'] ?? ''}';
    CcApi.phpSessionId = '${ccUser['PHPSESSID'] ?? ''}';
    if (ccUser['eqid'] is String && (ccUser['eqid'] as String).isNotEmpty) {
      CcApi.eqid = ccUser['eqid'] as String;
    }
  }

  static Map<String, dynamic> _readJson(String name) {
    try {
      return json.decode(File('${GPaths.appSupport}/data/$name').readAsStringSync())
          as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveTan8() async {
    File('${GPaths.appSupport}/data/tan8_user.json')
        .writeAsStringSync(json.encode(tan8User));
    changed.value++;
  }

  static Future<void> saveCc() async {
    if (CcApi.uid.isEmpty) return;
    ccUser.addAll({
      'uid': CcApi.uid, 'service_uid': CcApi.serviceUid,
      'service_key': CcApi.serviceKey, 'id': CcApi.userToken,
      'cg_uid': CcApi.cgUid,
    });
    ccUser['eqid'] = CcApi.eqid;
    ccUser['PHPSESSID'] = CcApi.phpSessionId;
    File('${GPaths.appSupport}/data/cc_user.json').writeAsStringSync(json.encode(ccUser));
    changed.value++;
  }

  static Future<void> logoutTan8() async {
    tan8User = {};
    final f = File('${GPaths.appSupport}/data/tan8_user.json');
    if (f.existsSync()) f.deleteSync();
    await Http.tan8Jar.deleteAll();
    changed.value++;
  }

  static Future<void> logoutCc() async {
    CcApi.clearSession();
    ccUser = {};
    try {
      final f = File('${GPaths.appSupport}/data/cc_user.json');
      if (f.existsSync()) f.deleteSync();
    } finally { changed.value++; }
  }
}
