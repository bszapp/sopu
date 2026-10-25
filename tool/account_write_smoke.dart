// 真实账号写接口验证；只清理本次创建的评论，收藏/关注恢复进入时状态。
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:sopu/http/http.dart';
import 'package:sopu/http/cc_api.dart';
import 'package:sopu/http/tan8_api.dart';

final results = <Map<String, dynamic>>[];
late Directory directory;
void require(bool value, String message) { if (!value) throw StateError(message); }
dynamic unpack(dynamic value) {
  if (value is Response) value = value.data;
  if (value is String) { try { return jsonDecode(value); } catch (_) { return value; } }
  return value;
}
void receipt(dynamic value) {
  value = unpack(value);
  if (value is Map) {
    if (value['data'] is Map) value = value['data'];
    final code = value['returnCode'] ?? value['code'];
    if (code != null) require(['0000','1000','1','200'].contains('$code'), '服务器拒绝: ${value['message'] ?? value['msg'] ?? value['returnMsg'] ?? code}');
  }
}
Future<bool> check(String name, Future<dynamic> Function() run) async {
  try {
    final value = await run(); receipt(value);
    results.add({'api':name,'status':'PASS'});
    stdout.writeln('PASS $name');
    return true;
  } catch (e) {
    results.add({'api':name,'status':'FAIL','error':'$e'});
    stdout.writeln('FAIL $name $e');
    return false;
  } finally {
    await File('${directory.path}/account_writes.json').writeAsString(const JsonEncoder.withIndent('  ').convert(results));
  }
}
List<Map> list(dynamic raw) {
  if (raw is Map) raw = raw['list'] ?? raw['dataList'] ?? raw['result'];
  return raw is List ? raw.whereType<Map>().toList() : [];
}
String id(Map e) => '${e['old_id'] ?? e['yuepuid'] ?? e['id'] ?? (e['info'] is Map ? e['info']['id'] : '')}';
String cid(Map e) => '${e['comment_id'] ?? e['id'] ?? e['cid'] ?? ''}';
String body(Map e) => '${e['message'] ?? e['comment_content'] ?? e['content'] ?? ''}';
String user(Map e) => '${e['cg_uid'] ?? e['uid'] ?? e['user_id'] ?? e['userid'] ?? e['id'] ?? ''}';

Future<void> ccWrites() async {
  const score = '971970';
  final detail = await CcApi.opernDetail(score);
  final author = '${detail['author_uid'] ?? ''}';
  require(author.isNotEmpty, '曲谱缺少作者');
  Future<bool> collected() async => list(await CcApi.myCollectList(size:100)).any((e) => id(e) == score);
  final originalCollect = await collected();
  try {
    for (final on in [!originalCollect, originalCollect]) {
      await check(on ? 'cc.collectAdd' : 'cc.collectDel', () async {
        if (on) { await CcApi.collectAdd(score); } else { await CcApi.collectDel(score); }
        require(await collected() == on, '收藏列表状态未改变');
        require(CcApi.flag(await CcApi.collectCheck(score)) == on, '收藏检查与列表不一致');
      });
    }
  } finally {
    if (await collected() != originalCollect) {
      await check('cc.collect.restore', () => originalCollect ? CcApi.collectAdd(score) : CcApi.collectDel(score));
    }
  }
  Future<bool> followed() async => list(await CcApi.myFollowList(size:100)).any((e) => user(e) == author);
  final originalFollow = await followed();
  try {
    for (final on in [!originalFollow, originalFollow]) {
      await check(on ? 'cc.followAdd' : 'cc.followDel', () async {
        if (on) { await CcApi.followAdd(author); } else { await CcApi.followDel(author); }
        require(await followed() == on, '关注列表状态未改变');
        require(CcApi.flag(await CcApi.followCheck(author)) == on, '关注检查与列表不一致');
      });
    }
  } finally {
    if (await followed() != originalFollow) await check('cc.follow.restore', () => originalFollow ? CcApi.followAdd(author) : CcApi.followDel(author));
  }
  final message = '搜谱接口测试，稍后删除。${DateTime.now().millisecondsSinceEpoch}';
  String ownComment = '';
  await check('cc.commentAdd', () async {
    final r = await CcApi.commentAdd(score, message); receipt(r);
    final found = list(await CcApi.opernComments(score,size:100)).where((e) => body(e) == message);
    require(found.isNotEmpty, '提交后评论列表中未出现本次评论');
    ownComment = cid(found.first); require(ownComment.isNotEmpty, '评论缺少标识');
    await File('${directory.path}/cc_cleanup.json').writeAsString(jsonEncode({'score':score,'comment':ownComment,'message':message}));
  });
  if (ownComment.isNotEmpty) {
    try {
      for (final on in [true,false]) {
        await check('cc.commentLike.${on ? 'add' : 'del'}', () async {
          final r = await CcApi.commentLike(ownComment,on); receipt(r);
          final entries = list(await CcApi.opernComments(score,size:100));
          final own = entries.firstWhere((e) => cid(e) == ownComment);
          final flag = own['is_hit'];
          require(flag != null, '评论列表缺少点赞状态，无法确认操作结果');
          require(CcApi.flag(flag) == on, '评论点赞状态未改变');
        });
      }
    } finally {
      await check('cc.commentDel', () async {
        final r = await CcApi.commentDel(ownComment); receipt(r);
        require(!list(await CcApi.opernComments(score,size:100)).any((e) => cid(e) == ownComment), '删除后评论仍存在');
        return r;
      });
    }
  }
}

Future<void> tan8Writes() async {
  const score = '125516';
  final own = await Tan8Api.getUserInfo(); require(own['user'] is Map,'弹琴吧未登录');
  final self = '${own['user']['uid']}';
  final comments = list(await Tan8Api.comments(score));
  final author = comments.map(user).firstWhere((e) => e.isNotEmpty && e != self);
  Future<bool> collected() async => list(await Tan8Api.myCollectList(limit:100)).any((e) => id(e) == score);
  for (final web in [false,true]) {
    final original = await collected();
    try {
      for (final on in [!original,original]) {
        await check('tan8.${web ? 'webCollect' : 'collect'}.${on ? 'add' : 'del'}', () async {
          final r = web ? await Tan8Api.webCollect(score,on) : await Tan8Api.collect(score,on); receipt(r);
          require(await collected() == on,'收藏列表状态未改变'); return r;
        });
      }
    } finally {
      if (await collected() != original) await check('tan8.collect.restore', () => Tan8Api.collect(score,original));
    }
  }
  Future<bool> followed() async => list((await Tan8Api.myFollowLists(self,num:100))['following']).any((e) => user(e) == author);
  final originalFollow = await followed();
  try {
    for (final on in [!originalFollow,originalFollow]) {
      await check('tan8.follow.${on ? 'add' : 'del'}', () async {
        final r = await Tan8Api.follow(author,on); receipt(r);
        require(await followed() == on, '关注列表状态未改变'); return r;
      });
    }
  } finally {
    if (await followed() != originalFollow) await check('tan8.follow.restore', () => Tan8Api.follow(author,originalFollow));
  }
  final before = await Tan8Api.scoreInfoPublic(score);
  final originalLike = '${before['isDianZan'] ?? '0'}' == '1';
  try {
    await check('tan8.admire', () async {
      final r = await Tan8Api.admire(score); receipt(r);
      require(('${(await Tan8Api.scoreInfoPublic(score))['isDianZan']}' == '1') != originalLike, '点赞状态未改变'); return r;
    });
  } finally {
    if (('${(await Tan8Api.scoreInfoPublic(score))['isDianZan']}' == '1') != originalLike) await check('tan8.admire.restore', () => Tan8Api.admire(score));
  }
  for (final web in [false,true]) {
    final message = '搜谱接口测试，稍后删除。${DateTime.now().millisecondsSinceEpoch}';
    String ownComment = '';
    await check(web ? 'tan8.webAddComment' : 'tan8.addComment', () async {
      final r = web ? await Tan8Api.webAddComment(score,message) : await Tan8Api.addComment(score,message); receipt(r);
      final found = list(await Tan8Api.comments(score,limit:100)).where((e) => body(e) == message);
      require(found.isNotEmpty,'提交后评论列表中未出现本次评论');
      ownComment = cid(found.first); require(ownComment.isNotEmpty,'评论缺少标识');
      await File('${directory.path}/tan8_cleanup.json').writeAsString(jsonEncode({'score':score,'comment':ownComment,'message':message}));
      return r;
    });
    if (ownComment.isEmpty && web) {
      await check('tan8.webComment.fixture', () async {
        final response = await Tan8Api.addComment(score, message);
        receipt(response);
        final found = list(await Tan8Api.comments(score, limit: 100)).where((e) => body(e) == message);
        require(found.isNotEmpty, '无法创建网页点赞/删除测试用的本人评论');
        ownComment = cid(found.first);
        await File('${directory.path}/tan8_cleanup.json').writeAsString(jsonEncode({'score': score, 'comment': ownComment, 'message': message}));
        return response;
      });
    }
    if (ownComment.isEmpty) continue;
    try {
      for (final on in [true,false]) {
        await check('tan8.${web ? 'webLikeComment' : 'likeComment'}.${on ? 'add' : 'del'}', () async {
          final r = web ? await Tan8Api.webLikeComment(ownComment,score,on) : await Tan8Api.likeComment(ownComment,score,on); receipt(r);
          final own = list(await Tan8Api.comments(score,limit:100)).firstWhere((e) => cid(e) == ownComment);
          final state = own['islike'];
          require(state != null, '评论未返回个人点赞状态，无法确认操作结果');
          require(CcApi.flag(state) == on, '评论点赞状态未改变'); return r;
        });
      }
    } finally {
      await check(web ? 'tan8.webDelComment' : 'tan8.delComment', () async {
        final r = web ? await Tan8Api.webDelComment(ownComment,score) : await Tan8Api.delComment(ownComment,score); receipt(r);
        require(!list(await Tan8Api.comments(score,limit:100)).any((e) => cid(e) == ownComment),'删除后评论仍存在'); return r;
      });
      if (web && list(await Tan8Api.comments(score, limit: 100)).any((e) => cid(e) == ownComment && body(e) == message)) {
        await check('tan8.webComment.cleanup', () async {
          final response = await Tan8Api.delComment(ownComment, score);
          receipt(response);
          require(!list(await Tan8Api.comments(score, limit: 100)).any((e) => cid(e) == ownComment), '未能清理本次测试评论');
          return response;
        });
      }
    }
  }
}
Future<void> main(List<String> args) async {
  directory = Directory(args[0]);
  Http.init(cookieDir:'${directory.path}/cookies');
  final session = jsonDecode(await File('${directory.path}/cc_session.json').readAsString());
  CcApi.uid=session['uid']; CcApi.userToken=session['id']; CcApi.cgUid=session['cg_uid'];
  CcApi.serviceUid=session['service_uid']; CcApi.serviceKey=session['service_key']; CcApi.eqid=session['eqid'];
  try {
    if (args.length < 2 || args[1] == 'cc') await ccWrites();
    if (args.length < 2 || args[1] == 'tan8') await tan8Writes();
  } finally { Http.cc.close(force:true); Http.tan8.close(force:true); }
  if (results.any((e) => e['status']=='FAIL')) exitCode=1;
}
