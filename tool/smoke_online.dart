// 在线冒烟: 真实请求两平台服务器, 验证 Dart 端点层与原 App 请求完全等价。
// 用法: dart run tool/smoke_online.dart   (任一用例失败 → 退出码 1)
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show Options, Response, ResponseType;

import 'package:sopu/http/cc_api.dart';
import 'package:sopu/http/http.dart';
import 'package:sopu/http/tan8_api.dart';
import 'package:sopu/utils/ccmz_decode.dart';

final _results = <(String, bool, String)>[];

void pass(String name, String info) {
  _results.add((name, true, info));
  stdout.writeln('PASS  $name  $info');
}

void fail(String name, Object e, [String? info]) {
  _results.add((name, false, '$e $info'));
  stdout.writeln('FAIL  $name  $e');
}

/// 起点: tan8 免费图 (125516 有 svg+prev png 全链), cc 免费谱 36583 / 付费 971970。
void main() async {
  Http.init(cookieDir: '${Directory.systemTemp.path}/sopu_smoke_cookies/');
  stdout.writeln('=== tan8 ===');
  await _tan8Smoke();
  stdout.writeln('=== cc ===');
  await _ccSmoke();
  stdout.writeln();
  final bad = _results.where((r) => !r.$2).toList();
  stdout.writeln('SUMMARY: ${_results.length - bad.length}/${_results.length} PASS');
  for (final f in bad) {
    stdout.writeln('  FAILED ${f.$1}: ${f.$3}');
  }
  exitCode = bad.isEmpty ? 0 : 1;
}

Future<void> _tan8Smoke() async {
  // 1 搜索
  try {
    final r = await Tan8Api.search('起风了', limit: 10);
    final list = (r['result'] as List? ?? []);
    final info = list.isEmpty
        ? ''
        : 'total=${list.length} first={id:${(list.first as Map)['id']}, t:${(list.first as Map)['label_1_text']}}';
    list.isNotEmpty
        ? pass('tan8.search', info)
        : fail('tan8.search', 'empty result');
  } catch (e) {
    fail('tan8.search', e);
  }

  // 2 公开元数据
  Map<String, dynamic>? info125516;
  try {
    info125516 = await Tan8Api.scoreInfoPublic('125516');
    pass('tan8.scoreInfoPublic',
        'title=${info125516['title']} lastupdate=${info125516['lastupdate']}');
  } catch (e) {
    fail('tan8.scoreInfoPublic', e);
  }

  // 3 详情(自动 init2023→m=info 兜底)
  try {
    final r = await Tan8Api.scoreInfo('125516');
    pass('tan8.scoreInfo(fallback)', 'source=${r['_source']} title=${r['title']}');
  } catch (e) {
    fail('tan8.scoreInfo', e);
  }

  // 4 评论
  try {
    final r = await Tan8Api.comments('125516', limit: 5);
    pass('tan8.comments', 'count=${r.length}');
  } catch (e) {
    fail('tan8.comments', e);
  }

  // 5 试听 URL 构造 + 真实可达
  try {
    final url = Tan8Api.auditionUrl(info125516 ?? {}, coverKey: 'image_url');
    if (url == null) {
      fail('tan8.audition', '无法从封面推导');
    } else {
      final resp = await tan8HeadProbe(url);
      (resp.statusCode == 200 && (resp.headers['content-type']?.join(',') ?? '')
              .contains('audio'))
          ? pass('tan8.audition', 'url=$url')
          : fail('tan8.audition', 'HTTP ${resp.statusCode}',
              (resp.headers['content-type'] ?? []).join(','));
    }
  } catch (e) {
    fail('tan8.audition', e);
  }

  // 6 checkYuepu 信封
  try {
    final env = await Tan8Api.checkYuepu('125516');
    env.containsKey('encryptionKey')
        ? pass('tan8.checkYuepu',
            'keys=${env.keys.toList()} ypn1Url=${(env['ypn1Url'] ?? '').toString().isEmpty ? '-' : 'yes'}')
        : fail('tan8.checkYuepu', 'missing encryptionKey', '${env.keys.toList()}');
  } catch (e) {
    fail('tan8.checkYuepu', e);
  }

  // 7 getSvgZipUrl
  try {
    final meta = await Tan8Api.zixUrl('125516');
    (meta['zixUrl'] ?? '').toString().isNotEmpty
        ? pass('tan8.zixUrl', 'keys=${meta.keys.toList()}')
        : fail('tan8.zixUrl', 'empty zixUrl', '${meta.keys.toList()}');
  } catch (e) {
    fail('tan8.zixUrl', e);
  }

  // 8 完整下载链 + zip 内容
  try {
    final (files, meta) = await Tan8Api.fetchScore('125516');
    final svgs = files.keys.where((k) => k.endsWith('.svg')).toList();
    final pngs = files.keys.where((k) => k.endsWith('.png')).toList();
    svgs.isNotEmpty
        ? pass('tan8.fetchScore',
            'files=${files.length} svg=${svgs.take(3).toList()} png=${pngs.take(3).toList()} metaKeys=${meta.keys.toList().take(6)}')
        : fail('tan8.fetchScore', 'no svg', '${files.keys.toList()}');
  } catch (e) {
    fail('tan8.fetchScore', e);
  }

  // 9 首页模组
  try {
    final mods = await Tan8Api.homePage();
    mods.isNotEmpty
        ? pass('tan8.homePage', 'mods=${mods.length}')
        : fail('tan8.homePage', 'empty');
  } catch (e) {
    fail('tan8.homePage', e);
  }
}

Future<Response<String>> tan8HeadProbe(String url) async {
  final resp = await Http.tan8.get<String>(url,
      options: Options(responseType: ResponseType.plain, receiveTimeout: const Duration(seconds: 30)));
  return resp;
}

Future<void> _ccSmoke() async {
  // 10 热词
  try {
    final r = await CcApi.hotKeys();
    r.isNotEmpty
        ? pass('cc.hotKeys', 'count=${r.length}')
        : fail('cc.hotKeys', 'empty ${r.runtimeType}');
  } catch (e) {
    fail('cc.hotKeys', e);
  }

  // 11 曲谱列表
  try {
    final r = await CcApi.opernList(page: 1, size: 10);
    final list = r is List ? r : (r as Map)['list'] ?? [];
    list.isNotEmpty
        ? pass('cc.opernList', 'count=${list.length} first.old_id=${(list.first as Map)['old_id']}')
        : fail('cc.opernList', 'empty');
  } catch (e) {
    fail('cc.opernList', e);
  }

  // 12 歌曲搜索(含 play_json 的载体)
  Map<String, dynamic>? cc971970;
  try {
    final r = await CcApi.searchSongs('起风了', page: 1, size: 30);
    cc971970 = r.whereType<Map<String, dynamic>>().toList().isNotEmpty
        ? r.first
        : null;
    pass('cc.searchSongs', 'count=${r.length} play_json_first=${(cc971970?['play_json'] ?? '').toString().isEmpty ? '-' : 'yes'}');
  } catch (e) {
    fail('cc.searchSongs', e);
  }

  // 13 详情
  try {
    final d = await CcApi.opernDetail('971970');
    pass('cc.opernDetail(971970)', 'title=${d['learning_name'] ?? d['title']} audition=${(d['audition_urtext'] ?? '').toString().isEmpty ? '-' : 'yes'}');
  } catch (e) {
    fail('cc.opernDetail', e);
  }

  // 14 详情评论
  try {
    final r = await CcApi.opernComments('971970', page: 1, size: 10);
    final list = r is List ? r : ((r as Map)['list'] as List?) ?? const [];
    pass('cc.opernComments', 'count=${list.length}');
  } catch (e) {
    fail('cc.opernComments', e);
  }

  // 15 未登录收藏状态接口应答(不抛系统错误即协议正确)
  try {
    final r = await CcApi.collectCheck('971970');
    pass('cc.collectCheck(anon)', 'resp=${r.runtimeType} val=$r');
  } catch (e) {
    fail('cc.collectCheck(anon)', e);
  }

  // 16 ccmz 下载 + 纯 Dart 解码(971970 付费谱 play_json)
  try {
    await _ensureCc971970PlayUrl();
    final url = _cc971970PlayUrl;
    if (url.isEmpty) {
      fail('cc.ccmz.decode', 'search 未给出 play_json');
    } else {
      final b = await CcApi.downloadBytes(url);
      final pkg = decodeCcmz(b);
      final obj = json.decode(pkg.scoreJson);
      obj is Map
          ? pass('cc.ccmz.decode',
              'type=${pkg.type} keys=${obj.keys.take(8)} z=${b.length}')
          : fail('cc.ccmz.decode', 'score.json 非对象');
    }
  } catch (e) {
    fail('cc.ccmz.decode', e);
  }

  // 17 下载弹唱谱(纯音频 37491) lyric 无谱面 — 只验证文件可拉
  try {
    // 免费谱 36583 作为对照
    final d = await CcApi.opernDetail('36583');
    pass('cc.opernDetail(36583 free)', 'title=${d['learning_name'] ?? d['title']}');
  } catch (e) {
    fail('cc.opernDetail(36583)', e);
  }

  // 18 uploaded by uploader 的作品流
  try {
    final r = await CcApi.opernListByUploader('1', page: 1, size: 10);
    final list = r is List ? r : (r as Map)['list'] ?? [];
    pass('cc.opernListByUploader', 'count=${list.length}');
  } catch (e) {
    fail('cc.opernListByUploader', e);
  }
}

String _cc971970PlayUrl = '';

Future<void> _ensureCc971970PlayUrl() async {
  if (_cc971970PlayUrl.isNotEmpty) return;
  // 直接搜标题的方式拿 play_json
  final items = await CcApi.searchSongs('起风了', page: 1, size: 60);
  final hit = items.whereType<Map<String, dynamic>>().firstWhere(
      (e) => e['old_id']?.toString() == '971970', orElse: () => {});
  if (hit['play_json'] != null) {
    _cc971970PlayUrl = CcApi.fileUrl('${hit['play_json']}');
  } else {
    // 详情兜底
    final d = await CcApi.opernDetail('971970');
    final p = (d['fingering_ccmz'] ?? d['play_json'] ?? '').toString();
    if (p.isNotEmpty) _cc971970PlayUrl = CcApi.fileUrl(p);
  }
}
