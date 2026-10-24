// 单字段对照；手机号只从 stdin 读取，测试参数不进入应用配置。
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:sopu/http/http.dart';
import 'package:sopu/http/cc_api.dart';

Future<void> main(List<String> args) async {
  final phone = stdin.readLineSync()!.trim();
  final temp = await Directory.systemTemp.createTemp('sopu_sms_');
  Http.init(cookieDir: temp.path);
  Http.cc.interceptors.add(InterceptorsWrapper(onRequest: (o,h) {
    if (o.path.contains('urlparam=cginfo/userinfo/SendSmsNew')) {
      final q = {...o.uri.queryParameters};
      for (var i = 0; i < args.length; i += 2) {
        if (args[i] == 'User-Agent') { o.headers['User-Agent'] = args[i + 1]; }
        else { q[args[i]] = args[i + 1]; }
      }
      o.path = '${o.uri.scheme}://${o.uri.host}/?urlparam=cginfo/userinfo/SendSmsNew&${Uri(queryParameters: q..remove('urlparam')).query}';
      o.queryParameters.clear();
    }
    h.next(o);
  }, onResponse: (r,h) {
    final j = jsonDecode('${r.data}') as Map;
    stdout.writeln(jsonEncode({'returnCode':j['returnCode'],'returnMsg':j['returnMsg'],'fields':j.keys.toList(),'changedFields':[for(var i=0;i<args.length;i+=2) args[i]]}));
    h.next(r);
  }));
  try { await CcApi.sendCode(phone); }
  finally { Http.cc.close(force:true); Http.tan8.close(force:true); await temp.delete(recursive:true); }
}
