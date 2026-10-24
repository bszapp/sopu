// 解剖 getSvgZipUrl 失败密文: acc[:10] 应为 '0000000000'(RC4 对), 否则 cryptkey 不对。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sopu/http/http.dart';
import 'package:sopu/http/tan8_api.dart';
import 'package:sopu/http/tan8_codec.dart';

String md5h(String s) => md5.convert(utf8.encode(s)).toString();

String alphaChar(String x, [int n = 8]) {
  final out = StringBuffer();
  for (var k = 0; k < x.length; k += n) {
    final end = (k + n) < x.length ? k + n : x.length;
    out.write(String.fromCharCodes(x.substring(k, end).runes.toList().reversed));
  }
  return out.toString();
}

// 复刻 authcode DECODE 但暴露中间态
Map<String, String> authcodeDebug(String string, String key) {
  final h = md5h(key);
  final keya = md5h(h.substring(0, 16));
  final keyb = md5h(h.substring(16));
  final s = string.replaceAll('_', '=').replaceAll('-', '+');
  final keyc = s.substring(0, 4);
  final payload = latin1.decode(base64.decode(_b64Pad(s.substring(4))));
  final cryptkey = keya + md5h(keya + keyc);
  final box = List<int>.generate(256, (i) => i);
  var j = 0;
  for (var i = 0; i < 256; i++) {
    j = (j + box[i] + cryptkey.codeUnitAt(i % cryptkey.length)) % 256;
    final tmp = box[i]; box[i] = box[j]; box[j] = tmp;
  }
  var i = 0; j = 0;
  final acc = StringBuffer();
  for (final rune in payload.runes) {
    i = (i + 1) % 256;
    j = (j + box[i]) % 256;
    final tmp = box[i]; box[i] = box[j]; box[j] = tmp;
    final n = tan8Alpha.indexOf(String.fromCharCode(rune));
    final xor = box[(box[i] + box[j]) % 256] % 64;
    if (n < 0) {
      acc.writeCharCode(tan8Alpha.codeUnitAt(tan8Alpha.length - 1 - xor));
    } else {
      acc.writeCharCode(tan8Alpha.codeUnitAt(n ^ xor));
    }
  }
  final result = acc.toString();
  final sig = md5h(result.substring(26) + keyb).substring(0, 16);
  return {
    'keyc': keyc,
    'keyb': keyb,
    'acc_len': '${result.length}',
    'acc_0_26': result.substring(0, result.length > 26 ? 26 : result.length),
    'sig_expect_s16': sig,
    'sig_actual_in_acc': result.length >= 26 ? result.substring(10, 26) : '',
    'payload_b64_head': result.substring(result.length > 26 ? 26 : 0, result.length > 58 ? 58 : result.length),
  };
}

String _b64Pad(String s) => s + '=' * ((4 - s.length % 4) % 4);

void main() async {
  Http.init(cookieDir: '${Directory.systemTemp.path}/sopu_smoke_cookies/');
  // 复刻 smoke 的 tan8 调用顺序, 逐步打印 DECODE 结果
  final calls = <String, Future<Object?> Function()>{
    'search': () => Tan8Api.search('起风了', limit: 10),
    'scoreInfoPublic': () => Tan8Api.scoreInfoPublic('125516'),
    'scoreInfo': () => Tan8Api.scoreInfo('125516'),
    'comments': () => Tan8Api.comments('125516', limit: 5),
    'audition': () async {
      final info = await Tan8Api.scoreInfoPublic('125516');
      return Tan8Api.auditionUrl(info, coverKey: 'image_url') ?? '';
    },
    'checkYuepu': () => Tan8Api.checkYuepu('125516'),
    'zixUrl': () => Tan8Api.zixUrl('125516'),
  };
  for (final e in calls.entries) {
    try {
      await e.value();
      stdout.writeln('OK    ${e.key}');
    } catch (ex) {
      stdout.writeln('THROW ${e.key}: $ex');
    }
    // 每个 API 调用后立刻试 zixUrl, 看 DECODE 是否被打断
    try {
      await Tan8Api.zixUrl('125516');
      stdout.writeln('      +zixUrl after ${e.key}: OK');
    } catch (ex) {
      stdout.writeln('      +zixUrl after ${e.key}: FAIL $ex');
    }
  }
}
