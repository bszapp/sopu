/// tan8 (弹琴吧) 端点层 — 与 tan8api.py 函数一对一。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';

import '../common/constants.dart';
import 'http.dart';
import 'tan8_codec.dart';

abstract final class Tan8Api {
  static const key = Tan8C.tan8Key;

  // ---------- 底层 ----------

  static Future<Response<String>> _get(String pathQs) =>
      tan8RetryFuture(() => Http.tan8.get(pathQs));

  static Future<Response<String>> _post(String pathQs, Map<String, String?> f) =>
      tan8RetryFuture(() => Http.tan8.post(pathQs,
          data: formEncode(f),
          options: Options(contentType: 'application/x-www-form-urlencoded')));

  static Future<Map<String, dynamic>> _postJson(String qs, Map<String, String?> f) =>
      _post(qs, f).then(parseJsonMap);

  static Future<Map<String, dynamic>> _getJson(String qs) =>
      _get(qs).then(parseJsonMap);

  /// authcode 包裹的 JSON 参数 (紧凑格式, 与原 App 一致)
  static String _wrap(Map<String, String?> j) =>
      tan8AuthCode(_compactJson(j), 'ENCODE', key);

  static String _compactJson(Object? o) {
    if (o is Map<String, dynamic>) {
      return '{${o.entries.map((e) => '"${e.key}":${json.encode(e.value)}').join(',')}}';
    }
    throw ArgumentError('仅支持平铺字符串 map');
  }

  // ---------- 曲谱信息 ----------

  /// init2023(需登录/免费成功=1000) 否则自动回退公开链 m=info + erji_yuepu_info_new。
  /// 1002 = 服务器拒绝内容授权(如 VIP 曲谱), 详情元数据仍可读。
  static Future<Map<String, dynamic>> scoreInfo(String yuepuid,
      {int instrumentType = 1, String getType = '2'}) async {
    final outer = await _postJson('/codeindex.php?d=api&c=getYuepuInfo&m=init2023',
        {'encryptionData': _wrap({
          'instrumentType': '$instrumentType',
          'yuepuid': yuepuid,
          'getType': getType,
          'isInReview': '0',
          'isvip': '0',
          'token': Tan8C.hardToken,
        })});
    final data = outer['data'] as Map<String, dynamic>? ?? outer;
    if ('${data['code']}' == '1000') {
      final d = json.decode(
          tan8AuthCode(data['result'] as String, 'DECODE', key)) as Map<String, dynamic>;
      d['_source'] = 'init2023';
      return d;
    }
    final info = await scoreInfoPublic(yuepuid, instrumentType: instrumentType);
    info['_source'] =
        'm=info fallback (init2023 code=${data['code']} msg=${data['message']})';
    info['_init_code'] = '${data['code']}';
    info['_init_msg'] = '${data['message']}';
    return info;
  }

  /// 公开元数据链: m=info → infoUrl(erji_yuepu_info_new)。
  static Future<Map<String, dynamic>> scoreInfoPublic(String yuepuid,
      {int instrumentType = 1}) async {
    final raw = await _getJson(
        '/codeindex.php?d=api&c=getYuepuInfo&m=info&yuepuType=$instrumentType&yuepuId=$yuepuid');
    final d = (raw['data'] as Map<String, dynamic>?) ?? {};
    if ('${d['code']}' != '1000') {
      throw Tan8ApiError('${d['code']}', '${d['message']}');
    }
    final r = Map<String, dynamic>.from((d['result'] as Map<String, dynamic>?) ?? {});
    r['songname'] ??= r['title'];
    final iu = (r['infoUrl'] ?? '').toString();
    if (iu.contains('codeindex.php?')) {
      try {
        final j2 = await _getJson('/codeindex.php?${iu.split('?')[1]}');
        final inner = (j2['data'] as Map<String, dynamic>?) ?? {};
        if ('${inner['code']}' == '1' && inner['result'] is Map<String, dynamic>) {
          final full = inner['result'] as Map<String, dynamic>;
          full.forEach((k, v) {
            if (v != null && v != '' && v != 0) r[k] = v;
          });
          r['songname'] ??= full['title'];
        }
      } catch (_) {/* 次要详情可选 */}
    }
    return r;
  }

  /// 曲谱音频(试听) URL — 按实测规律从封面 URL 推导:
  /// {封面目录}tan8_{id}.mp3?v=1{lastupdate}
  static String? auditionUrl(Map<String, dynamic> info,
      {String? coverKey, String yuepuid = ''}) {
    final cover = (info[coverKey ?? 'image_url'] ??
            info['pic'] ??
            info['titlepic'] ??
            '')
        .toString();
    if (cover.isEmpty) return null;
    final slash = cover.lastIndexOf('/');
    if (slash < 0 || !cover.contains('yuepuku/')) return null;
    final dir = cover.substring(0, slash + 1);
    final lu = (info['lastupdate'] ?? info['lastUpdate'] ?? '').toString();
    final q = lu.isNotEmpty && lu != '0' ? '?v=1$lu' : '';
    return '${dir}tan8_${yuepuid.isEmpty ? info['id'] : yuepuid}.mp3$q';
  }

  // ---------- 搜索 / 评论 ----------

  static Future<Map<String, dynamic>> search(String kw,
      {String inst = 'piano', int limit = 20, int start = 0}) async {
    final qs = ('d=api&c=dynamicTemplate&m=get_view_info&type=newSearch_${Uri.encodeComponent(inst)}_song'
            '&guolv_id1=${Uri.encodeComponent(kw)}&guolv_id2=&yuepu_type=&yuepu_cat_id=0&singer_id=0'
            '&album_id=0&book_id=0&lesson_id=0&uid=&keyword=&classid=&new_yuepu_type='
            '&category_id=&ptype=&orderBy=0&dataType=1&sort1=0&sort2=0&sort3=0&sort4=0'
            '&isJianpu=0&title=&singer=&squareType=&webScoreType='
            '&limit=$limit&start=$start');
    final outer = await _getJson('/codeindex.php?$qs');
    final d = (outer['data'] as Map<String, dynamic>?) ?? {};
    return {
      'message': d['message'],
      'total': d['resultTotal'],
      'result': d['result'] ?? [],
    };
  }

  static Future<Map<String, dynamic>> commentCount(String yuepuid) async {
    final raw = await _getJson(
        '/codeindex.php?d=admin&c=manage&m=get_yuepu_comment&yuepu_id=$yuepuid');
    return ((raw['data'] as Map<String, dynamic>?)?['result'] as Map<String, dynamic>?) ?? {};
  }

  /// 评论获取: sort = time | hot
  static Future<List<dynamic>> comments(String yuepuid,
      {String sort = 'time', int limit = 20, int start = 0}) async {
    final mid = sort == 'time' ? 727 : 726;
    final qs = ('d=api&c=dynamicTemplate&m=get_view_info&type=erji_yuepu_comment_$sort'
            '&guolv_id1=&guolv_id2=&yuepu_type=&yuepu_cat_id=0&singer_id=0'
            '&album_id=0&book_id=0&lesson_id=0&yuepu_id=$yuepuid&uid=&keyword=&classid='
            '&new_yuepu_type=&category_id=236&ptype=&model_id=$mid&orderBy=0&dataType=1'
            '&sort1=0&sort2=0&sort3=0&sort4=0&isJianpu=0&title=&singer=&squareType='
            '&webScoreType=&limit=$limit&start=$start');
    final outer = await _getJson('/codeindex.php?$qs');
    final d = (outer['data'] as Map<String, dynamic>?) ?? {};
    if (d['code'] != 1) return <dynamic>[];
    return (d['result'] as List?) ?? [];
  }

  // ---------- 曲谱文件链(下载/渲染) ----------

  /// getSvgZipUrl → {zixUrl, version, fileName, pages}
  static Future<Map<String, dynamic>> zixUrl(String yuepuid,
      {int instrumentType = 1, String key = 'wxp', int isFingering = 0}) async {
    final outer = await _postJson('/codeindex.php?d=api&c=getYuepuInfo&m=getSvgZipUrl',
        {'encryptionData': _wrap({
          'key': key,
          'isFingering': '$isFingering',
          'yuepuid': yuepuid,
          'instrumentType': '$instrumentType',
        })});
    final data = outer['data'] as Map<String, dynamic>? ?? outer;
    if ('${data['code']}' != '1000') {
      throw Tan8ApiError('${data['code']}', '${data['message']}');
    }
    return json.decode(tan8AuthCode(data['result'] as String, 'DECODE', Tan8Api.key))
        as Map<String, dynamic>;
  }

  /// checkYuepu → 服务端密钥信封 {code, result:{encryptionKey, ypn1Url,...}}
  static Future<Map<String, dynamic>> checkYuepu(String yuepuid,
      {int instrumentType = 1}) async {
    final js = json.encode({
      'yuepuVerificationCode': tan8Md5hex1(),
      'appType': '2',
      'appVersion': Tan8C.appVersion,
      'compileType': '1',
      'yuepuid': yuepuid,
      'instrumentType': instrumentType,
      'accessKeyId': 'no',
      'accessKeySecret': 'no',
    });
    final parm = pwdEncode(base64.encode(utf8.encode(js)), r(100, 999))
        .replaceAll('=', '_');
    final body = await _post('/codeindex.php?d=api&c=checkYuepu&m=init', {'parm': parm});
    final encBlob = pwdDecode(body.data ?? '');
    final env = json.decode(encBlob) as Map<String, dynamic>;
    final data = env['data'] as Map<String, dynamic>? ?? env;
    if ('${data['code']}' != '1000') {
      throw Tan8ApiError('${data['code']}', '${data['message']}');
    }
    return (data['result'] as Map<String, dynamic>?) ?? {};
  }

  static int r(int min, int max) =>
      min + Random().nextInt(max - min + 1);

  static Future<Uint8List> _downloadBytes(String url) async {
    final resp =
        await Http.tan8.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
    if (resp.statusCode != 200) {
      throw Tan8ApiError('${resp.statusCode}', '文件下载 HTTP ${resp.statusCode}');
    }
    return Uint8List.fromList(resp.data!);
  }

  /// 原始图片页与 SVG 共用服务端文件名，ZIP 中的 prev PNG 仅供预览。
  static Future<List<Uint8List>> fetchImages(String yuepuid,
      {int instrumentType = 1}) async {
    final meta = await zixUrl(yuepuid, instrumentType: instrumentType);
    final pages = int.tryParse('${meta['pages']}') ?? 0;
    final filename = '${meta['fileName'] ?? ''}';
    final source = Uri.tryParse('${meta['zixUrl'] ?? ''}');
    if (pages <= 0 || filename.isEmpty || source == null || !source.hasAuthority) {
      throw const Tan8ApiError('NO_IMAGES', '服务器未提供完整图片页信息');
    }
    final images = <Uint8List>[];
    for (var page = 0; page < pages; page++) {
      final url = source.resolve('$filename.$page.png').replace(query: '').toString();
      final bytes = await _downloadBytes(url);
      if (bytes.length < 24 || bytes[0] != 137 || bytes[1] != 80 || bytes[2] != 78 || bytes[3] != 71) {
        throw Tan8ApiError('BAD_IMAGE', '第 ${page + 1} 页未返回有效 PNG');
      }
      images.add(bytes);
    }
    return images;
  }

  /// 保留服务器谱面解密后的原始 ZIP，供源文件下载使用。
  static Future<(Uint8List, Map<String, dynamic>, Map<String, dynamic>)> fetchScoreZip(
      String yuepuid, {int instrumentType = 1}) async {
    final env = await checkYuepu(yuepuid, instrumentType: instrumentType);
    final encKey = env['encryptionKey'] as String?;
    if (encKey == null) throw Tan8ApiError('NO_KEY', '服务器未返回 encryptionKey');
    final meta = await zixUrl(yuepuid, instrumentType: instrumentType);
    final url = (meta['zixUrl'] ?? '').toString();
    if (url.isEmpty) throw Tan8ApiError('NO_URL', '服务器未返回 zixUrl');
    return (tan8AesDecrypt(await _downloadBytes(url), encKey), meta, env);
  }

  /// 完整下载链: checkYuepu → getSvgZipUrl → AES 解密 → zip。
  /// 返回解密后的 zip 解出文件(name → bytes) + meta。
  static Future<(Map<String, Uint8List>, Map<String, dynamic>)> fetchScore(
      String yuepuid,
      {int instrumentType = 1}) async {
    final (plain, meta, env) = await fetchScoreZip(yuepuid, instrumentType: instrumentType);
    final encKey = env['encryptionKey'] as String;

    final files = <String, Uint8List>{};
    final z = ZipDecoder().decodeBytes(plain);
    for (final f in z.files) {
      if (f.isFile) files[f.name] = Uint8List.fromList(f.content as List<int>);
    }

    Uint8List? ypn1;
    if ((env['ypn1Url'] ?? '').toString().isNotEmpty) {
      final raw =
          await _downloadBytes((env['ypn1Url'] as String).replaceAll('\\/', '/'));
      try {
        ypn1 = tan8AesDecrypt(raw, encKey);
      } catch (_) {
        ypn1 = raw; // 部分 ypn1 未加密
      }
    }
    if (ypn1 != null) files['download.ypn1'] = ypn1;
    return (files, meta);
  }

  // ---------- 登录 ----------

  static Future<Map<String, dynamic>> sendCode(String phone, {String area = '86'}) async {
    final j = {'areaCode': area, 'phone': phone};
    final outer = await _postJson('/codeindex.php?d=ios&c=member&m=sendMessage',
        {'encryptionData': _wrap(j)});
    return (outer['data'] as Map<String, dynamic>?) ?? outer;
  }

  /// 验证码登录; 成功后调用 getUserInfo 落档。
  static Future<Map<String, dynamic>> messageLogin(String phone, String code,
      {String area = '86'}) async {
    final j = {'areaCode': area, 'phone': phone, 'messageCode': code};
    final outer = await _postJson('/codeindex.php?d=ios&c=member&m=messageLogin',
        {'encryptionData': _wrap(j)});
    return (outer['data'] as Map<String, dynamic>?) ?? outer;
  }

  /// getUserInfo (session cookie 鉴权)。返回 data + 'user' = authcode 解出。
  static Future<Map<String, dynamic>> getUserInfo() async {
    final today = _yyyyMMdd(DateTime.now());
    final outer = await _postJson('/codeindex.php?d=api&c=member&m=getUserInfo',
        {'receiveDate': tan8AuthCode(today, 'ENCODE', key)});
    final d = (outer['data'] as Map<String, dynamic>?) ?? outer;
    final out = Map<String, dynamic>.from(d);
    if ('${d['code']}' == '1000') {
      out['user'] =
          json.decode(tan8AuthCode(d['result'] as String, 'DECODE', key));
    }
    return out;
  }

  static String _yyyyMMdd(DateTime t) =>
      '${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}';

  // ---------- 首页 / 作者 ----------

  static Future<List<dynamic>> recommend() async {
    final j = await _getJson('/codeindex.php?d=tan8&c=index&m=recommend');
    final d = (j['data'] as Map<String, dynamic>?) ?? {};
    return (d['result'] as List?) ?? [];
  }

  static const homeTabType = <String, Map<String, int>>{
    'music': {'piano': 2, 'guitar': 3, 'ukulele': 13, 'keyboard': 24, 'violin': 29},
    'music_new': {'piano': 103, 'guitar': 118, 'ukulele': 111, 'keyboard': 112, 'violin': 113},
    'feature': {'piano': 104, 'guitar': 119, 'keyboard': 120, 'violin': 121, 'ukulele': 122},
    'learn': {'piano': 16, 'guitar': 15, 'ukulele': 17, 'keyboard': 25, 'violin': 30},
  };

  static Future<List<dynamic>> homeChannels({String tab = 'music_new'}) async {
    final type = homeTabType[tab]!['piano']!;
    final j = await _getJson(
        '/codeindex.php?d=admin&c=manage&m=get_view_category&type=$type');
    return (j['type_data'] as List?) ?? [];
  }

  /// 首页全部模块数据(每 module: mod_id/web_mod_id/result)。
  static Future<List<dynamic>> homePage() async {
    final chans = await homeChannels();
    if (chans.isEmpty) return [];
    final qsUrl = ((chans[0] as Map<String, dynamic>?)?['mod_container_url'] ?? '')
        .toString()
        .split('?')
        .skip(1)
        .join('?');
    if (qsUrl.isEmpty) return [];
    final outer = await _getJson('/codeindex.php?$qsUrl');
    final mods = ((outer['mod_container_data'] as Map<String, dynamic>?)?['data'] as List?) ?? [];
    final out = <Map<String, dynamic>>[];
    for (final rec in mods.whereType<Map<String, dynamic>>()) {
      final url = (rec['mod_data_url'] ?? '').toString();
      dynamic result;
      if (url.contains('codeindex.php?')) {
        try {
          final d = await _getJson('/codeindex.php?${url.split('?')[1]}');
          result = d['data'];
        } catch (e) {
          result = {'error': '$e'};
        }
      }
      out.add({'mod_id': rec['mod_id'], 'web_mod_id': rec['web_mod_id'], 'result': result});
    }
    return out;
  }

  static Future<Map<String, dynamic>> authorSummary(String uid) async {
    final pub = await _getJson(
        '/codeindex.php?d=admin&c=manage&m=erji_publish_yuepu_2023&uid=$uid');
    final col = await _getJson(
        '/codeindex.php?d=admin&c=manage&m=erji_collect_yuepu_2023&uid=$uid');
    return {
      'publish': ((pub['data'] as Map<String, dynamic>?)?['result']) ?? {},
      'collect': ((col['data'] as Map<String, dynamic>?)?['result']) ?? {},
    };
  }

  static Future<List<dynamic>> authorHome(String uid, {int yuepuType = 1}) async {
    final outer = await _getJson(
        '/codeindex.php?d=admin&c=manage&m=get_view_category_rel'
        '&category_id=319&yuepu_type=$yuepuType&uid=$uid');
    final mods = ((outer['mod_container_data'] as Map<String, dynamic>?)?['data'] as List?) ?? [];
    final out = <Map<String, dynamic>>[];
    for (final rec in mods.whereType<Map<String, dynamic>>()) {
      final url = (rec['mod_data_url'] ?? '').toString();
      dynamic result;
      if (url.contains('codeindex.php?')) {
        try {
          final d = await _getJson('/codeindex.php?${url.split('?')[1]}');
          result = d['data'];
        } catch (e) {
          result = {'error': '$e'};
        }
      }
      out.add({'mod_id': rec['mod_id'], 'result': result});
    }
    return out;
  }

  // ---------- 我的 / 写操作 ----------

  static Future<List<dynamic>> myCollectList(
      {int limit = 20, int start = 0, String action = '1'}) async {
    final d = await _getJson(
        '/codeindex.php?d=api&c=yuepuCollect&m=collectList&limit=$limit&start=$start&action=$action');
    return _accountList(d);
  }

  static Future<List<dynamic>> myBrowseHistory({int limit = 20, int start = 0}) async {
    final d = await _getJson(
        '/codeindex.php?d=member&c=dynamic&m=getYuepuAccessLogs&limit=$limit&start=$start');
    return _accountList(d);
  }

  static List<dynamic> _accountList(Map<String, dynamic> outer) {
    final d = outer['data'] is Map ? outer['data'] as Map : outer;
    final code = '${d['code'] ?? ''}';
    if (code.isNotEmpty && code != '1000' && code != '1') {
      throw Tan8ApiError(code, '${d['message'] ?? d['msg'] ?? '服务器未提供列表'}');
    }
    final r = d['result'];
    if (r is List) return r;
    if (r is Map) {
      if (r['dataList'] is List) return r['dataList'] as List;
      if (r['list'] is List) return r['list'] as List;
    }
    return [];
  }

  static Future<List<dynamic>> myLikeList({int limit = 20, int start = 0}) async =>
      _accountList(await _getJson('/codeindex.php?d=api&c=yuepuCollect&m=likeYuepuList&dataType=1&limit=$limit&start=$start'));

  static Future<dynamic> myPlaylists() async {
    final j = await _getJson('/codeindex.php?d=api&c=yuepuCollect&m=selfBuildPlaylist');
    final d = j['data'] as Map? ?? j;
    return d['result'] ?? d;
  }

  static Future<List<dynamic>> banner() async =>
      (await _getJson('/codeindex.php?c=manage&m=getBanner&d=admin'))['result'] as List? ?? [];

  static Future<List<dynamic>> authorWorks(String uid, {String scope = 'publish', bool album = false}) async {
    final s = (await authorSummary(uid))[scope];
    final url = s is Map ? '${s[album ? 'pianoAlbum' : 'piano'] ?? ''}' : '';
    if (!url.contains('?')) return [];
    final j = await _getJson('/codeindex.php?${url.split('?').skip(1).join('?')}');
    final container = j['mod_container_data'];
    final mods = container is Map ? container['data'] : null;
    final out = <dynamic>[];
    for (final rec in (mods is List ? mods : const []).whereType<Map>()) {
      final u = '${rec['mod_data_url'] ?? ''}';
      if (u.contains('codeindex.php?')) {
        final d = await _getJson('/codeindex.php?${u.split('?').skip(1).join('?')}');
        out.add({'mod_id': rec['mod_id'], 'result': d['data']});
      }
    }
    return out;
  }

  static Future<Map<String, dynamic>> related(String id, {int limit = 20}) async {
    final d = await scoreInfo(id);
    final kw = '${d['songname'] ?? d['title'] ?? ''}'.trim();
    if (kw.isEmpty) return {'keyword': '', 'result': []};
    return {...await search(kw, limit: limit), 'keyword': kw};
  }

  static Future<String> webCollect(String id, bool on) async =>
      (await _post('/codeindex.php?d=common&c=collectyp&m=${on ? 'addCollect' : 'delCollect'}', {'ypid': id})).data ?? '';

  static Future<String> webAddComment(String id, String message) async =>
      (await _post('/tbypk.php?d=web&c=piano_yuepu&m=ajax&type=insert_comment', {'message': message, 'yuepuid': id})).data ?? '';

  static Future<String> webDelComment(String cid, String tid) async =>
      (await _post('/tbypk.php?d=web&c=piano_yuepu&m=ajax&type=del_comment', {'commentid': cid, 'tid': tid})).data ?? '';

  static Future<String> webLikeComment(String cid, String tid, bool on) async =>
      (await _post('/codeindex.php?d=web&c=piano_yuepu&m=ajax&type=upCommentLikes', {'tid': tid, 'commentid': cid, 'likes': on ? '1' : '0'})).data ?? '';

  static Future<Map<String, List<dynamic>>> myFollowLists(String selfUid,
      {int num = 20}) async {
    final f = await _getJson(
        '/codeindex.php?d=tan8&c=myself&m=my_follow&uid=$selfUid&start=0&num=$num');
    final g = await _getJson(
        '/codeindex.php?d=tan8&c=myself&m=my_fans&uid=$selfUid&start=0&num=$num');
    final df = ((f['data'] as Map<String, dynamic>?)?['result']);
    final dg = ((g['data'] as Map<String, dynamic>?)?['result']);
    return {
      'following': (df is List) ? df : ((df is Map) ? ((df['result'] as List?) ?? []) : []),
      'followers': (dg is List) ? dg : ((dg is Map) ? ((dg['result'] as List?) ?? []) : []),
    };
  }

  /// 收藏/取消: GET c=collect|m=followPiano|delfollowPiano&d=tan8 &album &yid
  static Future<Map<String, dynamic>> collect(String yuepuid, bool on,
      {bool album = false}) async {
    final act = on ? 'followPiano' : 'delfollowPiano';
    try {
      final raw = await _getJson(
          '/codeindex.php?c=$act&m=$act&d=tan8&album=${album ? 1 : 0}&yid=$yuepuid');
      return (raw['data'] as Map<String, dynamic>?) ?? {};
    } on Tan8ApiError catch (e) {
      if (e.code != '404' || album) rethrow;
      final text = (await webCollect(yuepuid, on)).trim();
      try {
        final result = jsonDecode(text);
        if (result is Map<String, dynamic>) return result;
      } on FormatException {
        // 网页收藏接口也会以纯文本返回操作回执。
      }
      if (text.isEmpty) {
        throw const Tan8ApiError('EMPTY', '收藏接口未返回操作结果');
      }
      return {'message': text};
    }
  }

  /// 关注/取关: POST d=tan8&c=myself&m=follow|delete_follow {by_uid}
  static Future<dynamic> follow(String byUid, bool on) async {
    final act = on ? 'follow' : 'delete_follow';
    final raw = await _post(
        '/codeindex.php?d=tan8&c=myself&m=$act', {'by_uid': byUid});
    final j = json.decode(raw.data ?? '{}');
    return j['data'];
  }

  /// 发表评论: POST d=tan8&c=publish&m=common_comment
  static Future<Response<String>> addComment(String yuepuid, String message,
      {String? replyUid, String? replyUsername, String? replyCommentId}) async {
    final f = <String, String?>{
      'tid': yuepuid,
      'mid': '2',
      'message': message,
      'reply_uid': replyUid,
      'reply_username': replyUsername,
      'reply_comment_id': replyCommentId,
    };
    final back = await _post(
        '/codeindex.php?d=tan8&c=publish&m=common_comment&${Tan8C.paramCommon}', f);
    return back;
  }

  /// 评论点赞/取消: POST c=common&m=add|del_message_like_logs {cid, tid}
  static Future<Response<String>> likeComment(String cid, String tid, bool on) {
    final act = on ? 'add_message_like_logs' : 'del_message_like_logs';
    return _post('/codeindex.php?d=tan8&c=common&m=$act', {'cid': cid, 'tid': tid});
  }

  /// 删除自己评论: GET d=tan8&c=yuepu&m=del_comment&id&tid&mid&isalbum
  static Future<Map<String, dynamic>> delComment(String cid, String tid) async {
    final raw = await _getJson(
        '/codeindex.php?d=tan8&c=yuepu&m=del_comment&id=$cid&tid=$tid&mid=2&isalbum=0');
    return (raw['data'] as Map<String, dynamic>?) ?? {};
  }

  /// 曲谱点赞/取消(同端点重复调用即切换): POST d=api&c=yuepuAdmire&m=admire
  static Future<String> admire(String yuepuid, {int instrumentType = 1}) async {
    final raw = await _post('/codeindex.php?d=api&c=yuepuAdmire&m=admire', {
      'yuepuId': yuepuid,
      'yuepuType': '$instrumentType',
      'dataType': '1',
    });
    return raw.data ?? '';
  }
}
