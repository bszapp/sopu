import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:sopu/http/http.dart';
import 'package:sopu/http/tan8_api.dart';
Future<void> main(List<String> args) async {
  Http.init(cookieDir:'${args.first}/cookies');
  final cookies=await Http.tan8Jar.loadForRequest(Uri.parse('https://www.tan8.com/'));
  await File('${args.first}/python_cookies.json').writeAsString(jsonEncode({'cookies':[
    for(final c in cookies){'name':c.name,'value':c.value,'domain':'www.tan8.com','path':c.path??'/','secure':c.secure,'expires':0},
  ]}));
  Http.tan8.interceptors.add(InterceptorsWrapper(onResponse:(r,h){
    if(r.requestOptions.path.contains('tbypk')) stdout.writeln(jsonEncode({'status':r.statusCode,'redirects':[for(final d in r.redirects){'status':d.statusCode,'method':d.method,'url':d.location.toString()}],'location':r.headers.value('location'),'body':r.data}));h.next(r);
  }));
  try {
    Http.tan8.options.followRedirects=false;
    await Tan8Api.webAddComment('125516','');
  }finally{Http.cc.close(force:true);Http.tan8.close(force:true);}
}
