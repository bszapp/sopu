import 'package:xml/xml.dart';

/// 弹琴吧页眉/页脚水印已转成 Text 路径；只过滤浅灰文字，保留谱面图形。
String removeTan8Watermarks(String source) {
  final doc = XmlDocument.parse(source);
  final root = doc.rootElement;
  final box = root.getAttribute('viewBox')?.trim().split(RegExp(r'[ ,]+'));
  final height = box != null && box.length == 4
      ? double.tryParse(box[3])
      : null;
  final nodes = root.descendants.whereType<XmlElement>().toList();
  for (final node in nodes) {
    final classes = (node.getAttribute('class') ?? '').split(RegExp(r'\s+'));
    final fill = (node.getAttribute('fill') ?? '').toLowerCase();
    if (!classes.contains('Text') || fill != '#8c8c8c') continue;
    final move = RegExp(r'^\s*[Mm]\s*([-+\d.eE]+)[ ,]+([-+\d.eE]+)')
        .firstMatch(node.getAttribute('d') ?? '');
    final y = double.tryParse(move?.group(2) ?? node.getAttribute('y') ?? '');
    if (height != null &&
        y != null &&
        (y <= height * .08 || y >= height * .92)) {
      node.parent?.children.remove(node);
    }
  }
  return doc.toXmlString();
}
