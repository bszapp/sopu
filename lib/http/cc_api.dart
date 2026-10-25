/// 虫虫钢琴 (com.yusi.chongchong) 端点层 — 与 ccpiano.py 函数一对一。
/// 已验证 GET 接口 + 学习历史 POST；登录 Cookie 与身份令牌分别保存。
library;

import 'dart:convert';
import 'dart:io' show Cookie;
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
  static bool get hasSession => uid.isNotEmpty || phpSessionId.isNotEmpty;
  static String get numericUserId => [
    cgUid,
    serviceUid,
  ].firstWhere((value) => RegExp(r'^\d+$').hasMatch(value), orElse: () => '');

  static void clearSession() {
    _sessionVersion++;
    uid = serviceUid = serviceKey = userToken = cgUid = phpSessionId = '';
  }

  static bool flag(dynamic value) {
    if (value is Map) {
      return flag(
        value['has_collect'] ?? value['is_followed_by'] ?? value['is_hit'],
      );
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

  static Future<Map<String, dynamic>> _get(
    String route,
    Map<String, String?> params, {
    bool anonymous = false,
  }) => _request(route, params, anonymous: anonymous);

  static Future<Map<String, dynamic>> _request(
    String route,
    Map<String, String?> params, {
    bool anonymous = false,
    bool cookieOnly = false,
    bool post = false,
  }) async {
    final version = _sessionVersion;
    final q = _common(authenticated: !anonymous && !cookieOnly);
    if (!anonymous && phpSessionId.isNotEmpty) q['PHPSESSID'] = phpSessionId;
    if (!post) {
      params.forEach((k, v) {
        if (v != null) q[k] = v;
      });
    }
    final url =
        '${CcC.baseUrl}?urlparam=$route&${Uri(queryParameters: q).query}';
    final options = Options(
      headers: {
        if (!anonymous && phpSessionId.isNotEmpty)
          'Cookie': 'PHPSESSID=$phpSessionId',
      },
      contentType: post ? Headers.formUrlEncodedContentType : null,
    );
    final r = post
        ? await Http.cc.post<String>(
            url,
            data: formEncode(params),
            options: options,
          )
        : await Http.cc.get<String>(url, options: options);
    if (r.statusCode != 200 || (r.data?.isEmpty ?? true)) {
      throw CcApiError('HTTP${r.statusCode}', 'HTTP ${r.statusCode}');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(r.data!);
    } on FormatException {
      throw const CcApiError('PARSE', 'JSON 解析失败');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const CcApiError('PARSE', '响应缺少对象');
    }
    final j = decoded;
    if ('${j['returnCode']}' != '0000') {
      throw CcApiError('${j['returnCode'] ?? '?'}', '${j['returnMsg'] ?? ''}');
    }
    if (!anonymous && version != _sessionVersion) {
      throw const CcApiError('SESSION_CHANGED', '账号已切换，请重新加载');
    }
    if (route == 'cginfo/userinfo/LoginByCode') {
      j['_loginSession'] =
          _loginCookie(r.headers['set-cookie'] ?? const []) ?? j['PHPSESSID'];
    } else if (!anonymous && uid.isNotEmpty && phpSessionId.isEmpty) {
      // 不用普通响应中的临时会话覆盖登录时确认的长效 Cookie。
      final value = j['PHPSESSID'];
      if (value is String && value.isNotEmpty) {
        phpSessionId = value;
        await onSessionDirty?.call();
      }
    }
    return j;
  }

  static String? _loginCookie(List<String> headers) {
    String? selected;
    var longest = -1;
    for (final header in headers) {
      for (final entry in header.split(
        RegExp(r',(?=\s*PHPSESSID=)', caseSensitive: false),
      )) {
        try {
          final cookie = Cookie.fromSetCookieValue(entry.trim());
          if (cookie.name != 'PHPSESSID' ||
              cookie.value.isEmpty ||
              (cookie.maxAge != null && cookie.maxAge! <= 0) ||
              (cookie.maxAge == null &&
                  cookie.expires != null &&
                  cookie.expires!.isBefore(DateTime.now()))) {
            continue;
          }
          final lifetime =
              cookie.maxAge ??
              (cookie.expires?.difference(DateTime.now()).inSeconds ?? 0);
          if (lifetime >= longest) {
            selected = cookie.value;
            longest = lifetime;
          }
        } on FormatException {
          /* 跳过不相关或损坏的 Cookie，继续读取后续长效项。 */
        }
      }
    }
    return selected;
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
    if (!u.startsWith('http')) {
      u = '${CcC.fileHost}${u.startsWith('/') ? '' : '/'}$u';
    }
    final schemeEnd = u.indexOf('://') + 3;
    final head = u.substring(0, schemeEnd);
    final rest = u.substring(schemeEnd).replaceAll(RegExp('/{2,}'), '/');
    return '$head$rest';
  }

  // ---------- 搜索 / 浏览 ----------

  /// 按歌曲搜索(平铺列表, 含 play_json 直链)
  static Future<List<dynamic>> searchSongs(
    String kw, {
    int page = 1,
    int size = 20,
  }) async {
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
    final j = await _get('pad/search/getsearchhotkey2_0_14', {
      'pagesize': '$size',
    });
    final d = payload(j);
    if (d is List) return d;
    return (d as Map)['list'] ?? [];
  }

  static Future<dynamic> opernList({int page = 1, int size = 20}) async {
    final j = await _get('pad/detail/getOpernList', {
      'vtype': '',
      'vtype1': '',
      'vtype2': '',
      'vtype3': '',
      'pageindex': '$page',
      'pagesize': '$size',
    });
    return payload(j);
  }

  static Future<dynamic> albumDetail(
    String id, {
    int page = 1,
    int size = 20,
  }) async => payload(
    await _request('home/user/getAlbumDetail', {
      'id': id,
      'pageindex': '$page',
      'pagesize': '$size',
      'type': '1',
    }, anonymous: true),
  );

  /// 图片谱唯一真源；服务端把详情放在响应顶层 list，而非 datas。
  static Future<Map<String, dynamic>> bookInfoById(String id) async {
    final data = payload(await _get('pad/detail/getbookinfobyid', {'id': id}));
    if (data is! Map) throw const CcApiError('PARSE', '图片谱资料缺少对象');
    return Map<String, dynamic>.from(data);
  }

  /// 服务端关联推荐，匿名 GET 返回 song_list。
  static Future<Map<String, dynamic>> recommendByOpernId(String id) async {
    final data = payload(
      await _request('pad/recommend/getRecommendByOpernId', {
        'id': id,
      }, anonymous: true),
    );
    if (data is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(data);
  }

  // ---------- 详情 / 评论 ----------

  static Future<Map<String, dynamic>> opernDetail(String oldId) async {
    final j = await _get('pad/detail/operninfov003', {
      'old_id': oldId,
      'from_page': '1',
      'from_info': '1',
    });
    final d = payload(j);
    if (d is! Map<String, dynamic>) throw const CcApiError('PARSE', '详情响应缺少对象');
    return d;
  }

  static Future<dynamic> opernComments(
    String oldId, {
    int page = 1,
    int size = 20,
  }) async {
    final j = await _get('pad/detail/getOpernDetailComment', {
      'id': oldId,
      'pageindex': '$page',
      'pagesize': '$size',
    });
    final d = payload(j);
    return d;
  }

  static Future<dynamic> floorTab() async =>
      payload(await _get('home/ccgq/tab', {}));

  /// 详情的 ccmz_page_1 是单页预览；先找完整文件，再回退预览。
  static Future<String> scoreFileUrl(
    String oldId, {
    Map<String, dynamic>? detail,
  }) async {
    final info = detail ?? await opernDetail(oldId);
    for (final key in ['play_json']) {
      final path = '${info[key] ?? ''}';
      if (path.isNotEmpty) return fileUrl(path);
    }
    final keyword = '${info['name'] ?? info['learning_name'] ?? ''}'.trim();
    if (keyword.isNotEmpty) {
      final songs = await searchSongs(keyword, size: 40);
      for (final item in songs.whereType<Map>()) {
        if ('${item['old_id']}' == oldId &&
            '${item['play_json'] ?? ''}'.isNotEmpty) {
          return fileUrl('${item['play_json']}');
        }
      }
    }
    final preview = '${info['ccmz_page_1'] ?? ''}';
    return preview.isEmpty ? '' : fileUrl(preview);
  }

  /// 按作者浏览曲谱 (home/user/getOpernListByUploader, userid=数值平台 id)
  static Future<dynamic> opernListByUploader(
    String userid, {
    int page = 1,
    int size = 20,
  }) async {
    final j = await _get('home/user/getOpernListByUploader', {
      'userid': userid,
      'pageindex': '$page',
      'pagesize': '$size',
    });
    return payload(j);
  }

  // ---------- 登录 ----------

  static final _smsDeadlines = <String, DateTime>{};
  static String _area(String area) {
    final value = area
        .replaceAll(RegExp(r'\s+'), '')
        .replaceFirst(RegExp(r'^\+'), '');
    if (!RegExp(r'^\d+$').hasMatch(value)) {
      throw const CcApiError('AREA', '国家区号应为数字');
    }
    return value;
  }

  static String _phone(String phone) => phone.replaceAll(RegExp(r'\s+'), '');
  static int smsCooldownRemaining(
    String phone, {
    String area = '86',
    int type = 1,
  }) {
    final until = _smsDeadlines['${_area(area)}:${_phone(phone)}:$type'];
    final milliseconds = until?.difference(DateTime.now()).inMilliseconds ?? 0;
    return milliseconds > 0 ? (milliseconds / 1000).ceil() : 0;
  }

  /// SendSmsNew：登录 type=1，区号为裸数字；同一号码 60 秒冷却。
  static Future<Map<String, dynamic>> sendCode(
    String phone, {
    String area = '86',
    int type = 1,
  }) async {
    final key = '${_area(area)}:${_phone(phone)}:$type';
    final remaining = smsCooldownRemaining(phone, area: area, type: type);
    if (remaining > 0) throw CcApiError('COOLDOWN', '请在 $remaining 秒后重试');
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    _smsDeadlines[key] = deadline;
    try {
      return await _get('cginfo/userinfo/SendSmsNew', {
        'area_code': _area(area),
        'user_phone': _phone(phone),
        'type': '$type',
      }, anonymous: true);
    } catch (_) {
      if (_smsDeadlines[key] == deadline) _smsDeadlines.remove(key);
      rethrow;
    }
  }

  static Map<String, dynamic> _userInfo(dynamic value) {
    if (value is! Map) return {};
    for (final key in ['datas', 'userinfo', 'user']) {
      final nested = _userInfo(value[key]);
      if (nested.isNotEmpty) return nested;
    }
    return value['uid'] != null || value['id'] != null
        ? Map<String, dynamic>.from(value)
        : {};
  }

  static Future<Map<String, dynamic>> loginByCode(
    String phone,
    String code, {
    String area = '86',
  }) async {
    final version = _sessionVersion;
    final j = await _get('cginfo/userinfo/LoginByCode', {
      'area_code': _area(area),
      'user_phone': _phone(phone),
      'code': code.trim(),
    }, anonymous: true);
    if (version != _sessionVersion) {
      throw const CcApiError('SESSION_CHANGED', '账号已切换，请重新登录');
    }
    final info = _userInfo(j['datas']);
    final session = '${j['_loginSession'] ?? ''}';
    if (info.isEmpty && session.isEmpty) {
      throw const CcApiError('NO_SESSION', '登录成功回执未提供有效会话');
    }
    _sessionVersion++;
    // 新登录清空旧账号令牌，不能把 Cookie 登录与旧账号资料混合。
    uid = '${info['uid'] ?? ''}';
    serviceUid = '${info['service_uid'] ?? ''}';
    serviceKey = '${info['service_key'] ?? ''}';
    userToken = '${info['id'] ?? ''}';
    cgUid = '${info['cg_uid'] ?? ''}';
    phpSessionId = session;
    await onSessionDirty?.call();
    return {...info, if (session.isNotEmpty) 'PHPSESSID': session};
  }

  /// 他人资料只接受数值平台 UID，返回的关系字段不作为“我已关注”的判据。
  static Future<Map<String, dynamic>> userProfile(String userId) async {
    final j = await _get('home/user/indexV002', {'userid': userId});
    final data = payload(j);
    if (data is! Map || data['userinfo'] is! Map) {
      throw const CcApiError('PARSE', '服务器未返回用户资料');
    }
    final info = Map<String, dynamic>.from(data['userinfo']);
    info.removeWhere(
      (key, _) => ['phone', 'user_phone', 'mobile'].contains(key),
    );
    return info;
  }

  /// 用登录响应中的数值 cg_uid/service_uid 搭配 PHPSESSID 恢复公开资料。
  /// indexV002 返回的资料 uid 不覆盖登录鉴权 uid/service_uid/service_key。
  static Future<Map<String, dynamic>> recoverIdentityProfile() async {
    final candidate = [
      cgUid,
      serviceUid,
    ].firstWhere((value) => RegExp(r'^\d+$').hasMatch(value), orElse: () => '');
    if (candidate.isEmpty || phpSessionId.isEmpty) {
      throw const CcApiError('NO_IDENTITY', '登录响应缺少数值用户标识或会话');
    }
    final j = await _request('home/user/indexV002', {
      'userid': candidate,
    }, cookieOnly: true);
    final data = payload(j);
    if (data is! Map || data['userinfo'] is! Map) {
      throw const CcApiError('PARSE', '服务器未返回用户资料');
    }
    final profile = Map<String, dynamic>.from(data['userinfo']);
    profile.removeWhere(
      (key, _) => ['phone', 'user_phone', 'mobile'].contains(key),
    );
    return profile;
  }

  /// 登录返回的鉴权字段保持原值；仅用 Cookie + 数值用户 ID 恢复展示资料。
  static Future<Map<String, dynamic>> me() async {
    return recoverIdentityProfile();
  }

  // ---------- 收藏 / 关注 / 评论 ----------

  static Future<void> collectAdd(String learningId) => _get(
    'cginfo/userinfo/usercollectionlearning',
    {'learning_id': learningId},
  );

  static Future<void> collectDel(String learningId) => _get(
    'cginfo/userinfo/usercancelcollectionlearning',
    {'learning_id': learningId},
  );

  static Future<dynamic> collectCheck(String oldId) async {
    if (uid.isEmpty) {
      throw const CcApiError('NO_IDENTITY', '当前会话尚未取得账号标识，无法确认收藏状态');
    }
    final j = await _get('pad/detail/IsOpernCollected', {'opern_id': oldId});
    final data = j['datas'];
    if (data is! Map ||
        ![true, false, 0, 1, '0', '1'].contains(data['has_collect'])) {
      throw const CcApiError('PARSE', '服务器未提供收藏状态');
    }
    return Map<String, dynamic>.from(data);
  }

  static Future<Map<String, dynamic>> commentReplies(
    String parentId, {
    int page = 1,
    int size = 20,
  }) async {
    final d = payload(
      await _get('pad/detail/getOpernCommentReplyList', {
        'id': parentId,
        'pageindex': '$page',
        'pagesize': '$size',
      }),
    );
    if (d is! Map || d['list_reply'] is! List) {
      throw const CcApiError('PARSE', '服务器未提供回复列表');
    }
    return Map<String, dynamic>.from(d);
  }

  static Future<void> reportBrowse(
    String learningId, {
    String albumId = '',
  }) async {
    if (!hasSession || phpSessionId.isEmpty) {
      throw const CcApiError('LOGIN', '需要有效登录会话才能记录浏览');
    }
    if (!RegExp(r'^\d+$').hasMatch(learningId)) {
      throw const CcApiError('ID', '详情缺少新体系曲谱 ID');
    }
    await _request('home/user/addOneLadderPlayer', {
      'album_id': albumId,
      'opern_id': learningId,
      'PHPSESSID': phpSessionId,
    }, post: true);
  }

  static Future<dynamic> myLearningHistory({
    int page = 1,
    int size = 20,
  }) async => payload(
    await _get('home/user/ladderPlayerOpernHistory', {
      'pageindex': '$page',
      'pagesize': '$size',
      'PHPSESSID': phpSessionId,
    }),
  );

  /// 主 App 历史与学习历史分表读取，学习记录优先交错合并；不假装拥有浏览时间。
  static Future<Map<String, dynamic>> combinedBrowseHistory({
    int page = 1,
    int size = 20,
  }) async {
    final warnings = <String>[];
    var successes = 0;
    Future<(List<Map<String, dynamic>>, bool)> read(
      String label,
      Future<dynamic> Function() run,
    ) async {
      try {
        final raw = await run();
        final dynamic rows = raw is List
            ? raw
            : raw is Map
            ? raw['list']
            : null;
        if (rows is! List) throw const FormatException('历史列表格式错误');
        successes++;
        final total = raw is Map ? int.tryParse('${raw['total_pages']}') : null;
        return (
          rows.whereType<Map<String, dynamic>>().toList(),
          rows.isNotEmpty && (total == null || page < total),
        );
      } catch (e) {
        warnings.add('$label加载失败：$e');
        return (<Map<String, dynamic>>[], true);
      }
    }

    final result = await Future.wait([
      read('学习历史', () => myLearningHistory(page: page, size: size)),
      read('浏览历史', () => myBrowseHistory(page: page, size: size)),
    ]);
    if (successes == 0) throw CcApiError('HISTORY', warnings.join('；'));
    final rows = <Map<String, dynamic>>[], seen = <String>{};
    for (var i = 0; i < result[0].$1.length || i < result[1].$1.length; i++) {
      for (final list in [result[0].$1, result[1].$1]) {
        if (i >= list.length) continue;
        final row = list[i],
            id =
                '${list[i]['old_id'] ?? list[i]['learning_id'] ?? list[i]['id'] ?? ''}';
        if (id.isEmpty || seen.add(id)) rows.add(row);
      }
    }
    return {
      'list': rows,
      'has_more': result.any((r) => r.$2),
      'warnings': warnings,
    };
  }

  static Future<dynamic> myCollectList({int page = 1, int size = 20}) async {
    final j = await _get('home/user/getOpernCollectionList', {
      'pageindex': '$page',
      'pagesize': '$size',
      'keyword': '',
    });
    return payload(j);
  }

  /// 用户提供的 5.1.25 抓包：home/user/GetOpernHistory。
  static Future<dynamic> myBrowseHistory({int page = 1, int size = 20}) async =>
      payload(
        await _get('home/user/GetOpernHistory', {
          'pageindex': '$page',
          'pagesize': '$size',
        }),
      );

  static Future<void> followAdd(String uidBy) =>
      _get('home/user/addOneFollow', {'uid_by': uidBy});

  static Future<void> followDel(String uidBy) =>
      _get('home/user/delOneFollow', {'uid_by': uidBy});

  static Future<dynamic> followCheck(String uidBy) async {
    final j = await _get('home/user/isFollowed', {'uid_by': uidBy});
    final data = j['datas'];
    if (data is! Map || !data.containsKey('is_followed_by')) {
      throw const CcApiError('PARSE', '服务器未提供当前关注状态');
    }
    return data;
  }

  static Future<dynamic> myFollowList({int page = 1, int size = 20}) async {
    final j = await _get('home/user/getMyFollowList', {
      'userid': numericUserId,
      'pageindex': '$page',
      'pagesize': '$size',
    });
    return payload(j);
  }

  static Future<dynamic> myFansList({int page = 1, int size = 20}) async {
    final j = await _get('home/user/getFollowMeList', {
      'userid': numericUserId,
      'pageindex': '$page',
      'pagesize': '$size',
    });
    return payload(j);
  }

  static Future<dynamic> commentAdd(
    String opernId,
    String content, {
    String parentId = '',
  }) async {
    final j = await _get('cginfo/userinfo/usercomment', {
      'learning_id': opernId,
      'comment_id': parentId,
      'comment_content': content,
    });
    return j['datas'] ?? j;
  }

  static Future<dynamic> commentLike(String commentId, bool on) async {
    final j = await _get(
      on ? 'pad/detail/addCommentHits' : 'pad/detail/delCommentHits',
      {'comment_id': commentId, 'uid': uid},
    );
    return j['workDatas'] ?? j['datas'] ?? j;
  }

  /// type: 曲谱评论=opern, 专辑评论=album
  static Future<dynamic> commentDel(
    String commentId, {
    String type = 'opern',
  }) async {
    final j = await _get('user/center/delComment', {
      'id': commentId,
      'type': type,
    });
    return j['workDatas'] ?? j['datas'] ?? j;
  }

  // ---------- 文件 ----------

  static Future<Uint8List> downloadBytes(String urlOrPath) async {
    final url = fileUrl(urlOrPath);
    final r = await Http.cc.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    if (r.statusCode != 200) {
      throw CcApiError('HTTP${r.statusCode}', 'HTTP ${r.statusCode}');
    }
    final b = r.data!;
    if (b.isEmpty) throw CcApiError('EMPTY', '空文件');
    return Uint8List.fromList(b);
  }
}
