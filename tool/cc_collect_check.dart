import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:sopu/http/http.dart';
import 'package:sopu/http/cc_api.dart';
Future<void> main(List<String> args) async {
  Http.init(cookieDir:'${args.first}/cookies');
  final s=jsonDecode(await File('${args.first}/cc_session.json').readAsString());
  CcApi.uid=s['uid'];CcApi.userToken=s['id'];CcApi.cgUid=s['cg_uid'];CcApi.serviceUid=s['service_uid'];CcApi.serviceKey=s['service_key'];CcApi.eqid=s['eqid'];
  String mode='normal';
  Http.cc.interceptors.add(InterceptorsWrapper(onRequest:(o,h){
    if(o.path.contains('IsOpernCollected')) {
      final q={...o.uri.queryParameters};
      if(mode=='numeric')q['uid']=CcApi.cgUid;
      if(mode=='idToken')q['uid']=CcApi.userToken;
      if(mode=='learning')q['learning_id']=q['opern_id']!;
      o.path=o.uri.replace(queryParameters:q).toString();o.queryParameters.clear();
    }
    h.next(o);
  }));
  Future<void> probe(String stage)async {
    final raw=await CcApi.myCollectList(size:100);
    final items=(raw is Map?raw['list']:raw)as List;
    final matches=items.whereType<Map>().where((e)=>'${e['old_id']??e['learning_id']??e['id']}'=='971970').toList();
    stdout.writeln(jsonEncode({'stage':stage,'inList':matches.isNotEmpty,'record':matches.map((e)=>{for(final k in ['id','old_id','learning_id','puid']) k:e[k]}).toList()}));
    for(final m in ['normal','numeric','idToken','learning']){mode=m;final r=await CcApi.collectCheck('971970');stdout.writeln(jsonEncode({'mode':m,'has_collect':r is Map?r['has_collect']:r}));}
  }
  try {
    await probe('before');await CcApi.collectAdd('971970');await probe('added');
  }finally{await CcApi.collectDel('971970');await probe('deleted');Http.cc.close(force:true);Http.tan8.close(force:true);}
}
