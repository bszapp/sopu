import 'dart:convert';
import 'dart:io';
import 'package:sopu/http/http.dart';
import 'package:sopu/http/tan8_api.dart';

Future<void> main(List<String> args) async {
  Http.init(cookieDir:'${args.first}/cookies');
  try {
    if(args.length>1 && args[1]=='pages') {
      final out=Directory(args[2]);await out.create(recursive:true);
      for(final id in ['125516','116415']) {
        final images=await Tan8Api.fetchImages(id);
        final result=<Map<String,dynamic>>[];
        for(var i=0;i<images.length;i++){
          final b=images[i];await File('${out.path}/${id}_$i.png').writeAsBytes(b);
          int number(int offset)=>b[offset]*16777216+b[offset+1]*65536+b[offset+2]*256+b[offset+3];
          result.add({'page':i+1,'bytes':b.length,'width':number(16),'height':number(20)});
        }
        stdout.writeln(jsonEncode({'id':id,'pages':result}));
      }
      return;
    }
    for (final type in ['1','2']) {
      final d=await Tan8Api.scoreInfo('125516',getType:type);
      stdout.writeln(jsonEncode({'getType':type,'keys':d.keys.toList(),'fields':{
        for(final e in d.entries)
          if(RegExp('pic|image|page|name_title|source',caseSensitive:false).hasMatch(e.key)) e.key:e.value,
      }}));
    }
    final env=await Tan8Api.checkYuepu('125516');
    stdout.writeln(jsonEncode({'envelopeKeys':env.keys.toList(),'urls':{
      for(final e in env.entries) if(e.key.toLowerCase().contains('url')) e.key:e.value,
    }}));
    final(files,meta)=await Tan8Api.fetchScore('125516');
    stdout.writeln(jsonEncode({'meta':meta,'files':files.keys.toList()}));
    for(final e in files.entries.where((e)=>e.key.endsWith('.txt'))) {
      final text=utf8.decode(e.value,allowMalformed:true);
      stdout.writeln(jsonEncode({'name':e.key,'text':text.length>2500?text.substring(0,2500):text}));
    }
  } finally {Http.cc.close(force:true);Http.tan8.close(force:true);}
}
