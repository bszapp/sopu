/// tan8 算法层 — 与 tan8api.py 逐函数对齐的 Dart 移植。
/// authcode: Discuz 式 RC4(乱序 64 字符表, key 两半 md5 变换)
/// PWD66:    libqlyp 表旋转编码(checkYuepu 信封)
/// AES:      AES-256-CBC(零 IV) + PKCS7 解出曲谱 zip
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import '../common/constants.dart';

String md5hex(String s) => md5.convert(utf8.encode(s)).toString();

String _chunkRev(String x, [int n = 8]) {
  final out = StringBuffer();
  for (var k = 0; k < x.length; k += n) {
    final end = (k + n) < x.length ? k + n : x.length;
    final chunk = x.substring(k, end);
    out.write(String.fromCharCodes(chunk.runes.toList().reversed));
  }
  return out.toString();
}

/// 64 字符乱序表(Tan8Util.strToIntCode)
const String tan8Alpha =
    'A4CDE+GHIJKbMNOPQRvTUVWXYZaLcdefghijklmnopqrstuSwxyz0123B56789F/';

/// libqlyp PWD66 表(ParWCtr::encode_array)
const String tan8Pwd =
    'aY56Z1defghijkpqrxyzABstuvwCFGbcHDEIJKLMNOTU+VW23X4lmno78/PQRS90-=';

String _b64Pad(String s) => s + '=' * ((4 - s.length % 4) % 4);

/// PWD66 编码: 表旋转 + 位置 23 包 b64(seed)
String pwdEncode(String text, int seed) {
  final ss = seed % 65 == 0 ? 1 : seed % 65;
  final buf = StringBuffer();
  for (final c in _chunkRev(text).runes) {
    final i = tan8Pwd.indexOf(String.fromCharCode(c));
    if (i < 0) {
      throw ArgumentError(
        'pwdEncode: 非法字符(输入应为 base64 文本): ${String.fromCharCode(c)}',
      );
    }
    buf.writeCharCode(tan8Pwd.codeUnitAt((i + ss) % 66));
  }
  final out = buf.toString();
  final sb = base64.encode(utf8.encode(seed.toString()));
  return out.substring(0, 23) + sb + out.substring(23);
}

/// PWD66 解码(响应信封)
String pwdDecode(String blob) {
  final seed = int.parse(
    utf8.decode(base64.decode(_b64Pad(blob.substring(23, 27)))),
  );
  final ss = seed % 65 == 0 ? 1 : seed % 65;
  final t = blob.substring(0, 23) + blob.substring(27);
  final buf = StringBuffer();
  for (final c in t.replaceAll('_', '=').runes) {
    final i = tan8Pwd.indexOf(String.fromCharCode(c));
    if (i < 0) {
      throw ArgumentError('pwdDecode: 非法字符: ${String.fromCharCode(c)}');
    }
    buf.writeCharCode(tan8Pwd.codeUnitAt(((i - ss) + 66 * 2) % 66));
  }
  final o = _chunkRev(buf.toString());
  return utf8.decode(base64.decode(_b64Pad(o)), allowMalformed: true);
}

/// authcode (tan8 变体): ENCODE/DECODE 对称流变换。
/// 生成函数里 keyc 用当前毫秒, 与原 App 一致。
String tan8AuthCode(String string, String operation, String key) {
  final h = md5hex(key);
  final keya = md5hex(h.substring(0, 16));
  final keyb = md5hex(h.substring(16));
  String keyc, payload;
  if (operation == 'DECODE') {
    final s = string.replaceAll('_', '=').replaceAll('-', '+');
    keyc = s.substring(0, 4);
    payload = latin1.decode(base64.decode(_b64Pad(s.substring(4))));
  } else {
    final s = base64.encode(utf8.encode(string)).replaceAll('=', '');
    keyc = md5hex(DateTime.now().millisecondsSinceEpoch.toString())
        .substring(28);
    payload = '0000000000${md5hex(s + keyb).substring(0, 16)}$s';
  }
  final cryptkey = keya + md5hex(keya + keyc);
  // RC4 初始化
  final box = List<int>.generate(256, (i) => i);
  var j = 0;
  for (var i = 0; i < 256; i++) {
    j = (j + box[i] + cryptkey.codeUnitAt(i % cryptkey.length)) % 256;
    final tmp = box[i];
    box[i] = box[j];
    box[j] = tmp;
  }
  var i = 0;
  j = 0;
  final acc = StringBuffer();
  for (final rune in payload.runes) {
    i = (i + 1) % 256;
    j = (j + box[i]) % 256;
    final tmp = box[i];
    box[i] = box[j];
    box[j] = tmp;
    final n = tan8Alpha.indexOf(String.fromCharCode(rune));
    final xor = box[(box[i] + box[j]) % 256] % 64;
    // python: ALPHA[n ^ xor] — find 未命中时为负索引(-1^xor=-(xor+1)), 即从表尾倒数。
    if (n < 0) {
      acc.writeCharCode(tan8Alpha.codeUnitAt(tan8Alpha.length - 1 - xor));
    } else {
      acc.writeCharCode(tan8Alpha.codeUnitAt(n ^ xor));
    }
  }
  final result = acc.toString();
  if (operation == 'DECODE') {
    final sig = md5hex(result.substring(26) + keyb).substring(0, 16);
    if (sig != result.substring(10, 26)) {
      throw const Tan8CodecError('authcode DECODE 签名不匹配');
    }
    final b = result.substring(26);
    return utf8.decode(base64.decode(_b64Pad(b)), allowMalformed: true);
  }
  return keyc +
      base64
          .encode(utf8.encode(result))
          .replaceAll('=', '_')
          .replaceAll('+', '-');
}

/// md5hex1 — yuepuVerificationCode: ewrwerw.{version}.{certHex}.{CONST-1}
String tan8Md5hex1() {
  final hex = base64
      .decode(Tan8C.certB64)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final src =
      'ewrwerw.${Tan8C.appVersion}.$hex.4e581348e5aebc671daf638d9090f6eb-1';
  return md5hex(src);
}

/// AES-256-CBC(零 IV) 解密 + PKCS7 去填充 (YuepuCrypt::decode)。
/// key = md5(encryptionKey + keystore) 前 32 字符的 ASCII 字节。
Uint8List tan8AesDecrypt(Uint8List blob, String encryptionKey) {
  final hexKey = md5hex(encryptionKey + Tan8C.cryptKeystore).substring(0, 32);
  final key = Uint8List.fromList(hexKey.codeUnits);

  final cbc = CBCBlockCipher(AESEngine())
    ..init(false, ParametersWithIV(KeyParameter(key), Uint8List(16)));
  final out = BytesBuilder();
  for (var off = 0; off + 16 <= blob.length; off += 16) {
    final block = Uint8List(16);
    final dec = cbc.process(Uint8List.sublistView(blob, off, off + 16));
    block.setRange(0, 16, dec.sublist(0, 16));
    out.add(block);
  }
  final dec = out.toBytes();
  if (dec.isEmpty) throw const Tan8CodecError('AES 解密结果为空(密钥不对?)');
  final pad = dec.last;
  if (pad < 1 || pad > 16 || pad > dec.length) {
    throw const Tan8CodecError('PKCS7 填充非法 — 服务器 encryptionKey 不匹配?');
  }
  for (var i = dec.length - pad; i < dec.length; i++) {
    if (dec[i] != pad) {
      throw const Tan8CodecError('PKCS7 填充非法 — 服务器 encryptionKey 不匹配?');
    }
  }
  return Uint8List.sublistView(dec, 0, dec.length - pad);
}

class Tan8CodecError implements Exception {
  final String message;
  const Tan8CodecError(this.message);
  @override
  String toString() => 'Tan8CodecError: $message';
}
