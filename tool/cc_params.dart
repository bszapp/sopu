import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:sopu/http/http.dart';
import 'package:sopu/http/cc_api.dart';

Future<void> main(List<String> args) async {
  final dir = await Directory.systemTemp.createTemp('sopu_params_');
  Http.init(cookieDir: dir.path);
  final drops = <String>{};
  Http.cc.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
    if (o.uri.host == 'gangqinpu.lzjoy.com') {
      final q = {...o.uri.queryParameters}..removeWhere((k, v) => drops.contains(k));
      o.path = o.uri.replace(queryParameters: q).toString();
      o.queryParameters.clear();
    }
    h.next(o);
  }));
  final result = <Map<String, dynamic>>[];
  for (final name in ['none','sdkversion','brand','model','osversion','language','is_world','eqid','channel','platform','version','build','service_type','all_device']) {
    drops.clear();
    if (name == 'all_device') { drops.addAll(['sdkversion','brand','model','osversion','is_world']); }
    else if (name != 'none') { drops.add(name); }
    try {
      final data = await CcApi.opernList(size: 2);
      final list = data is List ? data : data['list'];
      if (list is! List || list.isEmpty) throw StateError('无曲谱');
      result.add({'omitted': name, 'status': 'PASS', 'count': list.length});
      stdout.writeln('PASS omitted=$name count=${list.length}');
    } catch (e) { result.add({'omitted': name, 'status': 'FAIL', 'error': '$e'}); stdout.writeln('FAIL omitted=$name $e'); }
  }
  if (args.isNotEmpty) await File(args.first).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
  Http.cc.close(force: true); Http.tan8.close(force: true); await dir.delete(recursive: true);
}
