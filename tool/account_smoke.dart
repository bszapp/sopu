// 运行时输入手机号与验证码；测试会话仅写入调用方指定的工作目录。
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:sopu/http/http.dart';
import 'package:sopu/http/cc_api.dart';
import 'package:sopu/http/tan8_api.dart';

Future<void> main(List<String> args) async {
  if (args.length < 3) { stdout.writeln('用法: account_smoke.dart <cc|tan8> <send|login|read|params> <工作目录>'); exitCode = 2; return; }
  final cc = args[0] == 'cc', action = args[1];
  final dir = Directory(args[2]); await dir.create(recursive: true);
  Http.init(cookieDir: '${dir.path}/cookies');
  final state = File('${dir.path}/${args[0]}_session.json');
  final report = <Map<String, dynamic>>[];
  Future<void> saveCc() async => state.writeAsString(jsonEncode({'uid': CcApi.uid,'id': CcApi.userToken,'cg_uid': CcApi.cgUid,'service_uid': CcApi.serviceUid,'service_key': CcApi.serviceKey,'eqid': CcApi.eqid}));
  if (cc && state.existsSync()) {
    final s = jsonDecode(await state.readAsString());
    CcApi.uid = s['uid'] ?? ''; CcApi.userToken = s['id'] ?? ''; CcApi.cgUid = s['cg_uid'] ?? ''; CcApi.serviceUid = s['service_uid'] ?? ''; CcApi.serviceKey = s['service_key'] ?? ''; CcApi.eqid = s['eqid'] ?? CcApi.eqid;
  }
  Future<dynamic> test(String name, Future<dynamic> Function() run) async {
    try {
      final value = await run();
      report.add({'api': name, 'status': 'PASS', 'shape': value is Map ? value.keys.join(',') : value is List ? 'list:${value.length}' : value.runtimeType.toString()});
      stdout.writeln('PASS $name ${report.last['shape']}');
      return value;
    } catch (e) { report.add({'api': name, 'status': 'FAIL', 'error': '$e'}); stdout.writeln('FAIL $name $e'); return null; }
  }
  try {
    if (action == 'send' || action == 'login') {
      stdout.writeln('输入测试手机号：'); final phone = stdin.readLineSync()!.trim();
      if (action == 'send') {
        await test('${args[0]}.sendCode', () async {
          final d = cc ? await CcApi.sendCode(phone) : await Tan8Api.sendCode(phone);
          if (!cc && '${d['code']}' != '1000' && '${d['code']}' != '1') throw StateError('${d['code']}: ${d['message']}');
          return {'accepted': true};
        });
      } else {
        stdout.writeln('输入短信验证码：'); final code = stdin.readLineSync()!.trim();
        await test('${args[0]}.login', () async {
          final d = cc ? await CcApi.loginByCode(phone, code) : await Tan8Api.messageLogin(phone, code);
          if (cc) { await saveCc(); return {'login': CcApi.uid.isNotEmpty, 'fields': d.keys.toList()}; }
          if ('${d['code']}' != '1000') throw StateError('${d['code']}: ${d['message']}');
          final user = await Tan8Api.getUserInfo();
          if (user['user'] is! Map) throw StateError('登录后未返回用户资料');
          await state.writeAsString(jsonEncode(user['user']));
          return {'login': true, 'fields': (user['user'] as Map).keys.toList()};
        });
      }
    } else if (action == 'read' || action == 'params') {
      if (cc) {
        if (CcApi.uid.isEmpty) throw StateError('缺少登录会话');
        await test('cc.me', () async { final r = await CcApi.me(); await saveCc(); return r; });
        if (action == 'read') {
          await test('cc.myCollectList', () => CcApi.myCollectList());
          await test('cc.myBrowseHistory', () => CcApi.myBrowseHistory());
          await test('cc.myFollowList', () => CcApi.myFollowList());
          await test('cc.myFansList', () => CcApi.myFansList());
          await test('cc.collectCheck', () => CcApi.collectCheck('971970'));
          await test('cc.followCheck', () => CcApi.followCheck('1991869'));
        } else {
          final drops = <String>{};
          Http.cc.interceptors.add(InterceptorsWrapper(onRequest: (o,h) {
            final q = {...o.uri.queryParameters}..removeWhere((k,v) => drops.contains(k));
            o.path = o.uri.replace(queryParameters: q).toString(); o.queryParameters.clear(); h.next(o);
          }));
          for (final key in ['none','uid','service_uid','service_key','eqid','version','build','platform','channel','language','service_type']) {
            drops.clear(); if (key != 'none') drops.add(key);
            await test('cc.history.omit.$key', () => CcApi.myBrowseHistory(size: 2));
          }
        }
      } else {
        final u = await test('tan8.getUserInfo', () async { final u = await Tan8Api.getUserInfo(); if (u['user'] is! Map) throw StateError('${u['code']}: ${u['message']}'); return u['user']; });
        await test('tan8.myCollectList', () => Tan8Api.myCollectList());
        await test('tan8.myBrowseHistory', () => Tan8Api.myBrowseHistory());
        await test('tan8.myLikeList', () => Tan8Api.myLikeList());
        await test('tan8.myPlaylists', () => Tan8Api.myPlaylists());
        if (u is Map) await test('tan8.myFollowLists', () => Tan8Api.myFollowLists('${u['uid']}'));
      }
    } else { throw ArgumentError('未知操作'); }
  } catch (e) { stderr.writeln(e); exitCode = 1; }
  await File('${dir.path}/${args[0]}_$action.json').writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  if (report.any((r) => r['status'] == 'FAIL')) exitCode = 1;
  Http.cc.close(force: true); Http.tan8.close(force: true);
}
