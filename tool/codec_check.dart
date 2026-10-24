// tan8 算法层对拍校验 (dart run tool/codec_check.dart)
// 与外部 python(tan8api) 生成的 tool/codec_vectors.json 对拍。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sopu/http/tan8_codec.dart';

void fail(String m) {
  stdout.writeln('FAIL: $m');
  exitCode = 1;
}

void main() {
  final v = json.decode(File('tool/codec_vectors.json').readAsStringSync())
      as Map<String, dynamic>;

  String aesHex(Uint8List b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  // --- md5hex1 ---
  final h1 = tan8Md5hex1();
  h1 == v['md5hex1']
      ? stdout.writeln('PASS md5hex1')
      : fail('md5hex1 dart=$h1 py=${v['md5hex1']}');

  // --- authcode DECODE(python 编码的密文) ---
  final pairs = (v['authcode_encoded'] as List)
      .map((e) => (e[0] as String, e[1] as String))
      .toList();
  for (final (msg, enc) in pairs) {
    final out = tan8AuthCode(enc, 'DECODE', 'f817c2abf028ba8ef0a80fb61e20899f');
    out == msg
        ? stdout.writeln('PASS authcode decode (${out.length} chars)')
        : fail('authcode decode\n  dart=$out\n  py  =$msg');
  }

  // --- authcode ENCODE 自守恒(编码再用 decode 验证) ---
  for (final (msg, _) in pairs) {
    final enc = tan8AuthCode(msg, 'ENCODE', 'f817c2abf028ba8ef0a80fb61e20899f');
    final back = tan8AuthCode(enc, 'DECODE', 'f817c2abf028ba8ef0a80fb61e20899f');
    back == msg
        ? stdout.writeln('PASS authcode encode roundtrip (${enc.length} chars)')
        : fail('authcode roundtrip msg=$msg\n  back=$back');
  }
  // Dart 编码串导出, 由外部 python 复核签名一致性
  File('tool/dart_encoded.txt').writeAsStringSync(
      pairs.map((p) => tan8AuthCode(p.$1, 'ENCODE', 'f817c2abf028ba8ef0a80fb61e20899f')).join('\n'));

  // --- PWD66 ENCODE(与 python 输出一致, 输入=b64 文本) ---
  final pe = pwdEncode(v['pwd_input1']!, 137);
  pe == v['pwd_enc1']
      ? stdout.writeln('PASS pwdEncode 1')
      : fail('pwdEncode 1\ndart=$pe\npy  =${v['pwd_enc1']}');
  final pe2 = pwdEncode(v['pwd_input2']!, 999);
  pe2 == v['pwd_enc2']
      ? stdout.writeln('PASS pwdEncode 2')
      : fail('pwdEncode 2\ndart=$pe2\npy  =${v['pwd_enc2']}');

  // --- PWD66 DECODE(信封还原为原文) ---
  final pd = pwdDecode(v['pwd_enc1']!);
  pd == v['pwd_plain1']!
      ? stdout.writeln('PASS pwdDecode 1')
      : fail('pwdDecode 1\ndart=$pd\npy  =${v['pwd_plain1']}');
  final pd2 = pwdDecode(v['pwd_enc2']!);
  pd2 == v['pwd_plain2']!
      ? stdout.writeln('PASS pwdDecode 2')
      : fail('pwdDecode 2\ndart=$pd2\npy  =${v['pwd_plain2']}');

  // --- AES 解密 ---
  final ct = base64.decode(v['aes_ciphertext_b64']! as String);
  final dec = tan8AesDecrypt(ct, v['aes_encryption_key']! as String);
  final expect = base64.decode(v['aes_plaintext_b64']! as String);
  if (aesHex(dec) == aesHex(expect)) {
    stdout.writeln('PASS AES decrypt (${dec.length} bytes)');
  } else {
    fail('AES decrypt\n dart=${aesHex(dec)}\n py  =${aesHex(Uint8List.fromList(expect))}');
  }
}
