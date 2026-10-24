/// 应用常量。所有值均为静态打包资产(逆向自 com.tan8 v9.9.8 / com.yusi.chongchong v5.1.25)。
library;

abstract final class AppMeta {
  static const appName = '搜谱';
  static const package = 'com.sopu.sopu';
}

/// tan8 (弹琴吧) — 见 http/tan8_codec.dart 的算法移植。
abstract final class Tan8C {
  static const domain = 'https://www.tan8.com';
  static const appVersion = '9.9.8';
  static const tan8Key = 'f817c2abf028ba8ef0a80fb61e20899f'; // CommonConstant.TAN8_KEY
  static const hardToken = 'TWESA4839KWIELNK5645KOKW';
  static const cryptKeystore = 'FgwvQ2YSyEXm6cMBoWSjk4IwUDv1s4r'; // YuepuCrypt CRYPTData +0x38
  static const certB64 = // APK 签名 cert(与原 App 打包值逐字节一致; yuepuVerificationCode 用)
      'MIICUTCCAbqgAwIBAgIEUeZMnjANBgkqhkiG9w0BAQUFADBsMRAwDgYDVQQGEwc3N211c2ljMRAw'
      'DgYDVQQIEwc3N211c2ljMRAwDgYDVQQHEwc3N211c2ljMRAwDgYDVQQKEwc3N211c2ljMRAwDgYD'
      'VQQLEwc3N211c2ljMRAwDgYDVQQDEwc3N211c2ljMCAXDTEzMDcxNzA3NDk1MFoYDzMwMTIxMTE3'
      'MDc0OTUwWjBsMRAwDgYDVQQGEwc3N211c2ljMRAwDgYDVQQIEwc3N211c2ljMRAwDgYDVQQHEwc3'
      'N211c2ljMRAwDgYDVQQKEwc3N211c2ljMRAwDgYDVQQLEwc3N211c2ljMRAwDgYDVQQDEwc3N211'
      'c2ljMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCOwInqh3FzkZkru9jVBtLfxrdnVVtvg5rp'
      'K7JZ7lfVyfWN3fMCJkvxeOkDNjneFvrjttmTApcKpPDdHiyU+U1yZM/ejKR8OiNZGTlCO61G6LEy'
      'nQdYQon/P855z1F8l0ePaa0e+gFSm/4wYX4p08V578NLzQHD/6K3NzrLvsWAuwIDAQABMA0GCSqG'
      'SIb3DQEBBQUAA4GBAEQXAzMwp3zAz91OnnUNKRAADhPxgn3xdIOOB7JKBJKts6xnJmDaXZb2GD5D'
      '8d5ggIU9eC6CXR/4qU98qPVDqVLPWeAcHb1oRP9T3uPQD3HYYejEgbdInn+l63Gy3x1qQzOGY31X'
      'QXUiphaS/Eqi8wzMBKFw2jTt312QiaeDG51G';
  static const userAgent = 'Dalvik/2.1.0';
  static const paramCommon = 'muban_data_ver=13&dataVersion=2023&app_version=$appVersion&platform=android';

  // 音频(试听)资源构造规律(实测 oss 直链, 无需额外端点):
  // https://oss.tan8.com/yuepuku/{a}/{b}/{id}/tan8_{id}.mp3?v=1{lastupdate}
  // 前缀 = 封面 image_url 去掉文件名; lastupdate 在 m=info 数据里。
}

/// 虫虫钢琴 (com.yusi.chongchong)。
abstract final class CcC {
  static const baseUrl = 'https://gangqinpu.lzjoy.com/';
  static const fileHost = 'https://s201.lzjoy.com/';
  static const version = '5.1.25';
  static const build = '50102005';
  static const channel = 'official';
  static const serviceType = 'ccgq';
  static const userAgent = 'okhttp/4.9.3';
}

/// tan8 乐器类型枚举 (TYPE_TEXT)。
const Map<int, String> tan8Instrument = {
  1: 'piano',
  2: 'guitar',
  3: 'ukulele',
  4: 'keyboard',
  5: 'violin',
};

const List<String> tan8InstrumentNames = ['钢琴', '吉他', '尤克里里', '键盘乐', '小提琴'];
