import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:sopu/utils/tan8_svg.dart';

void main(List<String> args) {
  final archive = ZipDecoder().decodeBytes(File(args.first).readAsBytesSync());
  var pages = 0, removed = 0;
  for (final file in archive.files.where((f) => f.name.endsWith('.svg'))) {
    final before = XmlDocument.parse(utf8.decode(file.content as List<int>));
    final after = XmlDocument.parse(removeTan8Watermarks(before.toXmlString()));
    List<String> music(XmlDocument d) => d.descendants.whereType<XmlElement>().where((e) => e.getAttribute('class') != null && e.getAttribute('class') != 'Text').map((e) => e.toXmlString()).toList();
    final a = music(before), b = music(after);
    if (a.length != b.length || List.generate(a.length, (i) => a[i] == b[i]).contains(false)) throw StateError('谱面节点发生变化: ${file.name}');
    final diff = before.descendants.whereType<XmlElement>().length - after.descendants.whereType<XmlElement>().length;
    if (diff <= 0) throw StateError('样本水印未过滤: ${file.name}');
    pages++; removed += diff;
    stdout.writeln('PASS ${file.name} removed=$diff preservedMusicNodes=${a.length}');
  }
  if (pages == 0) throw StateError('没有 SVG 页');
  stdout.writeln('PASS pages=$pages removed=$removed');
}
