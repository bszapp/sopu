/// 虫虫钢琴 (com.yusi.chongchong) 端点层 — 与 ccpiano.py 函数一对一。
/// 协议: 全 GET; 公共查询参数无签名; 每成功响应顶层 PHPSESSID 吸收。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../common/constants.dart';
import 'http.dart';

abstract final class CcApi {
  static const _serviceType = CcC.serviceType;

  // 会话字段(登录后), 由 Sessions 注入/持久化
  static String uid = '';
  static String serviceUid = '';
  static String serviceKey = '';
  static String userToken = ''; // Bean.id 加密 token (getuserinfobyuids 用)
  static String cgUid = ''; // 数值平台 id
  static String phpSessionId = '';
  static String eqid = const Uuid().v4();
  static int _sessionVersion = 0;

  static int get sessionVersion => _sessionVersion;

  static void clearSession() {
    _sessionVersion++;
    uid = serviceUid = serviceKey = userToken = cgUid = phpSessionId = '';
  }

  static bool flag(dynamic value) {
    if (value is Map) {
      return flag(value['has_collect'] ?? value['is_followed_by'] ?? value['is_hit']);
    }
    return value == true || value == 1 || value == '1';
  }

  /// 对应 Api$Companion.j 拦截器(全量公共参数)
  static Map<String, String> _common({bool authenticated = true}) {
    final p = <String, String>{
      'version': CcC.version,
      'build': CcC.build,
      'platform': 'android',
      'channel': CcC.channel,
      'eqid': eqid,
      'language': 'zh-CN',
      'service_type': _serviceType,
    };
    if (authenticated && uid.isNotEmpty) {
      p['uid'] = uid;
      if (serviceUid.isNotEmpty) p['service_uid'] = serviceUid;
      if (serviceKey.isNotEmpty) p['service_key'] = serviceKey;
    }
    return p;
  }

  static Future<void> Function()? onSessionDirty;

  static Future<Map<String, dynamic>> _get(String route, Map<String, String?> params,
      {bool anonymous = false}) async {
    final version = _sessionVersion;
    final q = _common(authenticated: !anonymous);
    params.forEach((k, v) {
      if (v != null) q[k] = v;
    });
    final url = '${CcC.baseUrl}?urlparam=$route&${Uri(queryParameters: q).query}';
    final r = await Http.cc.get<String>(url);
    if (r.statusCode != 200 || (r.data?.isEmpty ?? true)) {
      throw CcApiError('HTTP${r.statusCode}', 'HTTP ${r.statusCode}');
    }
    Map<String, dynamic> j;
    try {
      final decoded = json.decode(r.data!);
      if (decoded is! Map<String, dynamic>) throw const FormatException('响应不是对象');
      j = decoded;
    } on FormatException {
      throw CcApiError('PARSE', 'JSON 解析失败');
    }
    if ('${j['returnCode']}' != '0000') {
      throw CcApiError('${j['returnCode'] ?? '?'}', '${j['returnMsg'] ?? ''}');
    }
    if (!anonymous && version != _sessionVersion && q.containsKey('uid')) {
      throw const CcApiError('SESSION_CHANGED', '账号已切换，请重新加载');
    }
    final sid = j['PHPSESSID'];
    if (!anonymous && version == _sessionVersion && sid is String && sid.isNotEmpty && sid != phpSessionId) {
      phpSessionId = sid;
      if (uid.isNotEmpty) await onSessionDirty?.call();
    }
    return j;
  }

  /// 列表型接口用 datas, 详情型接口兼容 list 载体
  static dynamic payload(Map<String, dynamic> j) {
    final l = j['list'];
    if (l is Map || l is List) return l;
    return j['datas'] ?? {};
  }

  /// 相对路径补全 s201 (res/statics/...)。host 尾 + path 头可能叠加出 //, 统一去重
  /// (scheme:// 后第一段双斜杠保留, 其余去重)。
  static String fileUrl(String path) {
    var u = path;
    if (!u.startsWith('http')) u = '${CcC.fileHost}${u.startsWith('/') ? '' : '/'}$u';
    final schemeEnd = u.indexOf('://') + 3;
    final head = u.substring(0, schemeEnd);
    final rest = u.substring(schemeEnd).replaceAll(RegExp('/{2,}'), '/');
    return '$head$rest';
  }

  // ---------- 搜索 / 浏览 ----------

  /// 按歌曲搜索(平铺列表, 含 play_json 直链)
  static Future<List<dynamic>> searchSongs(String kw, {int page = 1, int size = 20}) async {
    final j = await _get('pad/detail/searchForSongs', {
      'keywords': kw,
      'pageindex': '$page',
      'pagesize': '$size',
    });
    final datas = payload(j);
    final out = <dynamic>[];
    if (datas is Map) {
      for (final g in ((datas['list'] as List?) ?? [])) {
        if (g is Map) {
          for (final it in ((g['list'] as List?) ?? [])) {
            if (it is Map) out.add(it);
          }
        }
      }
    }
    return out;
  }

  static Future<List<dynamic>> hotKeys({int size = 40}) async {
    final j = await _get('pad/search/getsearchhotkey2_0_14', {'pagesize': '$size'});
    final d = payload(j);
    if (d is List) return d;
    return (d as Map)['list'] ?? [];
  }

  static Future<dynamic> opernList({int page = 1, int size = 20}) async {
    final j = await _get('pad/detail/getOpernList',
        {'vtype': '', 'vtype1': '', 'vtype2': '', 'vtype3': '', 'pageindex': '$page', 'pagesize': '$size'});
    return payload(j);
  }

  // ---------- 详情 / 评论 ----------

  static Future<Map<String, dynamic>> opernDetail(String oldId) async {
    final j = await _get('pad/detail/operninfov003',
        {'old_id': oldId, 'from_page': '', 'from_info': ''});
    final d = payload(j);
    if (d is! Map<String, dynamic>) throw const CcApiError('PARSE', '详情响应缺少对象');
    return d;
  }

  static Future<dynamic> opernComments(String oldId, {int page = 1, int size = 20}) async {
    final j = await _get('pad/detail/getOpernDetailComment',
        {'id': oldId, 'pageindex': '$page', 'pagesize': '$size'});
    final d = payload(j);
    return d;
  }

  static Future<dynamic> floorTab() async => payload(await _get('home/ccgq/tab', {}));

  /// 详情的 ccmz_page_1 是单页预览；先找完整文件，再回退预览。
  static Future<String> scoreFileUrl(String oldId, {Map<String, dynamic>? detail}) async {
    final info = detail ?? await opernDetail(oldId);
    for (final key in ['fingering_ccmz', 'play_json']) {
      final path = '${info[key] ?? ''}';
      if (path.isNotEmpty) return fileUrl(path);
    }
    final keyword = '${info['name'] ?? info['learning_name'] ?? ''}'.trim();
    if (keyword.isNotEmpty) {
      final songs = await searchSongs(keyword, size: 40);
      for (final item in songs.whereType<Map>()) {
        if ('${item['old_id']}' == oldId && '${item['play_json'] ?? ''}'.isNotEmpty) {
          return fileUrl('${item['play_json']}');
        }
      }
    }
    final preview = '${info['ccmz_page_1'] ?? ''}';
    return preview.isEmpty ? '' : fileUrl(preview);
  }

  /// 按作者浏览曲谱 (home/user/getOpernListByUploader, userid=数值平台 id)
  static Future<dynamic> opernListByUploader(String userid, {int page = 1, int size = 20}) async {
    final j = await _get('home/user/getOpernListByUploader',
        {'userid': userid, 'pageindex': '$page', 'pagesize': '$size'});
    return payload(j);
  }

  // ---------- 登录 ----------

  /// SendSmsNew: type 1=登录 2=注册 3=重置 4=注销 6=绑定 7=更换
  static Future<Map<String, dynamic>> sendCode(String phone, {String area = '86', int type = 1}) async {
    final j = await _get('cginfo/userinfo/SendSmsNew',
        {'area_code': area, 'user_phone': phone, 'type': '$type'}, anonymous: true);
    return j;
  }

  static Future<Map<String, dynamic>> loginByCode(String phone, String code, {String area = '86'}) async {
    final version = _sessionVersion;
    final j = await _get('cginfo/userinfo/LoginByCode',
        {'area_code': area, 'user_phone': phone, 'code': code}, anonymous: true);
    if (version != _sessionVersion) throw const CcApiError('SESSION_CHANGED', '账号已切换，请重新登录');
    final datas = j['datas'];
    var info = <String, dynamic>{};
    if (datas is Map) {
      final inner = datas['datas'];
      if (inner is Map<String, dynamic>) info = inner;
      if (info.isEmpty && (datas['uid'] != null || datas['id'] != null)) {
        info = datas as Map<String, dynamic>;
      }
    }
    if (info.isEmpty) throw CcApiError('NO_USERINFO', '登录响应缺少用户信息');
    if ('${info['uid'] ?? info['id'] ?? ''}'.isEmpty) {
      throw const CcApiError('NO_UID', '登录响应缺少账号标识');
    }
    _sessionVersion++;
    uid = '${info['uid'] ?? info['id'] ?? ''}';
    serviceUid = '${info['service_uid'] ?? ''}';
    serviceKey = '${info['service_key'] ?? ''}';
    userToken = '${info['id'] ?? ''}';
    cgUid = '${info['cg_uid'] ?? ''}';
    phpSessionId = '${j['PHPSESSID'] ?? ''}';
    await onSessionDirty?.call();
    return info;
  }

  /// getuserinfobyuids (Api.h0) — 注意 'id' 与 'uid' 是两个不同加密 token。
  static Future<Map<String, dynamic>> me() async {
    final j = await _get('cginfo/userinfo/getuserinfobyuids',
        {'id': userToken.isNotEmpty ? userToken : uid});
    final datas = j['datas'];
    var info = datas is Map ? datas['datas'] : null;
    if (info is Map<String, dynamic> && info['uid'] != null) {
      uid = '${info['uid'] ?? uid}' == '' ? uid : '${info['uid']}';
      userToken = '${info['id'] ?? userToken}';
      cgUid = '${info['cg_uid'] ?? cgUid}';
      serviceUid = '${info['service_uid'] ?? serviceUid}';
      serviceKey = '${info['service_key'] ?? serviceKey}';
      phpSessionId = '${j['PHPSESSID'] ?? phpSessionId}';
      await onSessionDirty?.call();
      return info;
    }
    return datas is Map<String, dynamic> ? datas : {};
  }

  // ---------- 收藏 / 关注 / 评论 ----------

  static Future<void> collectAdd(String learningId) =>
      _get('cginfo/userinfo/usercollectionlearning', {'learning_id': learningId});

  static Future<void> collectDel(String learningId) =>
      _get('cginfo/userinfo/usercancelcollectionlearning', {'learning_id': learningId});

  static Future<dynamic> collectCheck(String oldId) async {
    final j = await _get('pad/detail/IsOpernCollected', {'opern_id': oldId});
    final data = j['datas'];
    if (uid.isEmpty || data is! Map) return data ?? j;
    // 实测旧检查接口的 has_collect 固定为 0；收藏列表能反映添加/删除。
    var page = 1;
    while (true) {
      final raw = await myCollectList(page: page, size: 100);
      if (raw is! Map || raw['list'] is! List) {
        throw const CcApiError('PARSE', '服务器未返回收藏列表，无法确认状态');
      }
      final entries = raw['list'] as List;
      final found = entries.whereType<Map>().any((e) =>
          '${e['old_id'] ?? e['learning_id'] ?? e['id'] ?? ''}' == oldId);
      if (found) return {...data, 'has_collect': '1'};
      final totalPages = int.tryParse('${raw['total_pages']}');
      if (entries.isEmpty || (totalPages != null ? page >= totalPages : entries.length < 100)) {
        return {...data, 'has_collect': '0'};
      }
      page++;
    }
  }

  static Future<dynamic> myCollectList({int page = 1, int size = 20}) async {
    final j = await _get('home/user/getOpernCollectionList',
        {'pageindex': '$page', 'pagesize': '$size', 'keyword': ''});
    return payload(j);
  }

  /// 用户提供的 5.1.25 抓包：home/user/GetOpernHistory。
  static Future<dynamic> myBrowseHistory({int page = 1, int size = 20}) async =>
      payload(await _get('home/user/GetOpernHistory', {'pageindex': '$page', 'pagesize': '$size'}));

  static Future<void> followAdd(String uidBy) =>
      _get('home/user/addOneFollow', {'uid_by': uidBy});

  static Future<void> followDel(String uidBy) =>
      _get('home/user/delOneFollow', {'uid_by': uidBy});

  static Future<dynamic> followCheck(String uidBy) async {
    final j = await _get('home/user/isFollowed', {'uid_by': uidBy});
    return j['datas'] ?? j;
  }

  static Future<dynamic> myFollowList({int page = 1, int size = 20}) async {
    final j = await _get('home/user/getMyFollowList',
        {'userid': cgUid.isNotEmpty ? cgUid : serviceUid, 'pageindex': '$page', 'pagesize': '$size'});
    return payload(j);
  }

  static Future<dynamic> myFansList({int page = 1, int size = 20}) async {
    final j = await _get('home/user/getFollowMeList',
        {'userid': cgUid.isNotEmpty ? cgUid : serviceUid, 'pageindex': '$page', 'pagesize': '$size'});
    return payload(j);
  }

  static Future<dynamic> commentAdd(String opernId, String content, {String parentId = ''}) async {
    final j = await _get('cginfo/userinfo/usercomment',
        {'learning_id': opernId, 'comment_id': parentId, 'comment_content': content});
    return j['datas'] ?? j;
  }

  static Future<dynamic> commentLike(String commentId, bool on) async {
    final j = await _get(on ? 'pad/detail/addCommentHits' : 'pad/detail/delCommentHits',
        {'comment_id': commentId, 'uid': uid});
    return j['workDatas'] ?? j['datas'] ?? j;
  }

  /// type: 曲谱评论=opern, 专辑评论=album
  static Future<dynamic> commentDel(String commentId, {String type = 'opern'}) async {
    final j = await _get('user/center/delComment', {'id': commentId, 'type': type});
    return j['workDatas'] ?? j['datas'] ?? j;
  }

  // ---------- 文件 ----------

  static Future<Uint8List> downloadBytes(String urlOrPath) async {
    final url = fileUrl(urlOrPath);
    final r = await Http.cc.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
    if (r.statusCode != 200) throw CcApiError('HTTP${r.statusCode}', 'HTTP ${r.statusCode}');
    final b = r.data!;
    if (b.isEmpty) throw CcApiError('EMPTY', '空文件');
    return Uint8List.fromList(b);
  }
}
