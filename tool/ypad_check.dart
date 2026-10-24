import 'dart:convert';
import 'dart:io';
import 'package:sopu/utils/ypad_decode.dart';

Future<void> main(List<String> args) async {
  final rows = <Map<String, dynamic>>[];
  for (final f in Directory(args.first).listSync(recursive: true).whereType<File>().where((f) => RegExp(r'\.ypad2?$').hasMatch(f.path))) {
    final package = decodeYpad(await f.readAsBytes());
    final summary = {...package.summary(), 'file': f.uri.pathSegments.last};
    rows.add(summary); stdout.writeln('PASS ${jsonEncode(summary)}');
  }
  if (rows.isEmpty) { exitCode = 1; throw StateError('没有样本'); }
  if (args.length > 1) await File(args[1]).writeAsString(const JsonEncoder.withIndent('  ').convert(rows));
}
