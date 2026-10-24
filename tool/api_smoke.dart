// 真实服务器逐项冒烟。公开接口先执行；账号阶段须另行明确启动。
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:sopu/http/http.dart';
import 'package:sopu/http/tan8_api.dart';
import 'package:sopu/http/cc_api.dart';
import 'package:sopu/utils/ccmz_decode.dart';

final results = <Map<String, dynamic>>[];
final samples = <String, dynamic>{};
void require(bool condition, String message) { if (!condition) throw StateError(message); }
Future<void> check(String name, Future<dynamic> Function() run, {bool nonEmpty = true}) async {
  final watch = Stopwatch()..start();
  try {
    final value = await run();
    if (nonEmpty) require(value != null && !(value is Map && value.isEmpty) && !(value is List && value.isEmpty) && value != '', '未返回预期数据');
    samples[name] = value;
    final status = (value is List && value.isEmpty) || (value is Map && value.isEmpty) ? 'EMPTY' : 'PASS';
    results.add({'api': name, 'status': status, 'ms': watch.elapsedMilliseconds});
    stdout.writeln('$status $name ${value is Map ? value.keys.take(12).join(',') : value is List ? 'count=${value.length}' : value}');
  } catch (e) {
    results.add({'api': name, 'status': 'FAIL', 'error': '$e', 'ms': watch.elapsedMilliseconds});
    stdout.writeln('FAIL $name $e');
  }
}

Future<void> main(List<String> args) async {
  final output = args.isEmpty ? 'tool/api_smoke_public.json' : args.first;
  final cookies = await Directory.systemTemp.createTemp('sopu_public_');
  Http.init(cookieDir: cookies.path);
  try {
    await publicApis();
    const account = [
      'tan8.sendCode','tan8.messageLogin','tan8.getUserInfo','tan8.myCollectList','tan8.myBrowseHistory','tan8.myLikeList','tan8.myPlaylists','tan8.myFollowLists',
      'tan8.collect.add','tan8.collect.del','tan8.follow.add','tan8.follow.del','tan8.addComment','tan8.likeComment.add','tan8.likeComment.del','tan8.delComment','tan8.admire',
      'tan8.webCollect.add','tan8.webCollect.del','tan8.webAddComment','tan8.webDelComment','tan8.webLikeComment',
      'cc.sendCode','cc.loginByCode','cc.me','cc.myCollectList','cc.myFollowList','cc.myFansList','cc.followCheck','cc.myBrowseHistory',
      'cc.collectAdd','cc.collectDel','cc.followAdd','cc.followDel','cc.commentAdd','cc.commentLike.add','cc.commentLike.del','cc.commentDel',
    ];
    for (final name in account) { results.add({'api': name, 'status': 'PENDING_ACCOUNT'}); }
    final file = File(output); await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert({'time': DateTime.now().toIso8601String(), 'results': results, 'publicSamples': samples}));
    final failed = results.where((e) => e['status'] == 'FAIL').length;
    stdout.writeln('公开接口: ${results.length - account.length} 项，失败 $failed 项；账号阶段待执行 ${account.length} 项。');
    exitCode = failed == 0 ? 0 : 1;
  } finally { Http.tan8.close(force: true); Http.cc.close(force: true); await cookies.delete(recursive: true); }
}

Future<void> publicApis() async {
  Map<String, dynamic> tanInfo = {}, ccInfo = {};
  String tanUid = '', ccUid = '';
  await check('tan8.search', () async { final r = await Tan8Api.search('起风了', limit: 10); require((r['result'] as List).isNotEmpty, '搜索结果为空'); return r; });
  await check('tan8.scoreInfoPublic', () async { tanInfo = await Tan8Api.scoreInfoPublic('125516'); require('${tanInfo['songname'] ?? tanInfo['title'] ?? ''}'.isNotEmpty, '缺少标题'); return tanInfo; });
  await check('tan8.scoreInfo', () async { final d = await Tan8Api.scoreInfo('125516'); require('${d['songname'] ?? d['title'] ?? ''}'.isNotEmpty, '缺少标题'); tanUid = '${d['uid'] ?? d['author_uid'] ?? tanInfo['uid'] ?? ''}'; return d; });
  await check('tan8.commentCount', () => Tan8Api.commentCount('125516'));
  await check('tan8.comments.time', () async { final c = await Tan8Api.comments('125516', limit: 5); if (tanUid.isEmpty && c.isNotEmpty) tanUid = '${c.first['uid'] ?? ''}'; return c; }, nonEmpty: false);
  await check('tan8.comments.hot', () => Tan8Api.comments('125516', sort: 'hot', limit: 5), nonEmpty: false);
  await check('tan8.checkYuepu', () async { final d = await Tan8Api.checkYuepu('125516'); require(d['encryptionKey'] != null, '无密钥'); return {'hasKey': true}; });
  await check('tan8.zixUrl', () async { final d = await Tan8Api.zixUrl('125516'); require('${d['zixUrl'] ?? ''}'.isNotEmpty, '缺少下载地址'); return d; });
  await check('tan8.fetchScoreZip', () async { final (zip, _, _) = await Tan8Api.fetchScoreZip('125516'); final files = ZipDecoder().decodeBytes(zip).files; require(files.isNotEmpty, 'ZIP 为空'); return {'bytes': zip.length, 'files': files.map((e) => e.name).toList()}; });
  await check('tan8.fetchScore', () async { final (files, _) = await Tan8Api.fetchScore('125516'); require(files.keys.any((e) => e.endsWith('.svg')), '缺少 SVG'); return {'files': files.keys.toList()}; });
  await check('tan8.audition', () async { final url = Tan8Api.auditionUrl(tanInfo, yuepuid: '125516'); require(url != null, '缺少试听地址'); final r = await Http.tan8.head(url!); require(r.statusCode == 200 && '${r.headers.value('content-type')}'.contains('audio'), '音频不可用'); return {'audio': true}; });
  await check('tan8.homeChannels', () => Tan8Api.homeChannels());
  await check('tan8.homePage', () => Tan8Api.homePage());
  await check('tan8.recommend', () => Tan8Api.recommend(), nonEmpty: false);
  await check('tan8.banner', () => Tan8Api.banner(), nonEmpty: false);
  await check('tan8.authorSummary', () { require(tanUid.isNotEmpty, '详情未提供作者 UID'); return Tan8Api.authorSummary(tanUid); });
  await check('tan8.authorHome', () { require(tanUid.isNotEmpty, '详情未提供作者 UID'); return Tan8Api.authorHome(tanUid); }, nonEmpty: false);
  await check('tan8.authorWorks.publish', () => Tan8Api.authorWorks(tanUid), nonEmpty: false);
  await check('tan8.authorWorks.collect', () => Tan8Api.authorWorks(tanUid, scope: 'collect'), nonEmpty: false);
  await check('tan8.related', () => Tan8Api.related('125516', limit: 5));
  await check('cc.hotKeys', () => CcApi.hotKeys());
  await check('cc.floorTab', () => CcApi.floorTab());
  await check('cc.opernList', () => CcApi.opernList(size: 10));
  await check('cc.searchSongs', () => CcApi.searchSongs('起风了', size: 30));
  for (final id in ['971970', '36583']) {
    await check('cc.opernDetail.$id', () async { final d = await CcApi.opernDetail(id); require('${d['name'] ?? d['learning_name'] ?? d['title'] ?? ''}'.isNotEmpty, '缺少标题'); if (id == '971970') { ccInfo = d; ccUid = '${d['author_uid'] ?? d['uid'] ?? ''}'; } return d; });
  }
  await check('cc.opernComments', () => CcApi.opernComments('971970', size: 5), nonEmpty: false);
  await check('cc.opernListByUploader', () { require(ccUid.isNotEmpty, '缺少作者 UID'); return CcApi.opernListByUploader(ccUid, size: 5); }, nonEmpty: false);
  await check('cc.collectCheck', () => CcApi.collectCheck('971970'));
  await check('cc.downloadBytes/decodeCcmz', () async {
    final all = await CcApi.searchSongs('起风了', size: 60);
    final hit = all.whereType<Map>().firstWhere((e) => '${e['old_id']}' == '971970', orElse: () => {});
    final paths = [ccInfo['fingering_ccmz'], ccInfo['ccmz_page_1'], ccInfo['play_json'], hit['play_json']];
    final path = paths.firstWhere((e) => e != null && '$e'.isNotEmpty, orElse: () => null);
    require(path != null, '服务器未返回文件');
    final bytes = await CcApi.downloadBytes('$path'); final pkg = decodeCcmz(bytes);
    require(json.decode(pkg.scoreJson) is Map, '谱面 JSON 格式错误');
    return {'bytes': bytes.length, 'type': pkg.type, 'info': pkg.infoJson.isNotEmpty};
  });
  await check('cc.audition', () async { final url = '${ccInfo['audition_urtext'] ?? ''}'; require(url.isNotEmpty, '缺少试听地址'); final r = await Http.cc.head(url, options: Options(receiveTimeout: const Duration(seconds: 30))); require(r.statusCode == 200 && '${r.headers.value('content-type')}'.contains('audio'), '音频不可用'); return {'audio': true}; });
}
