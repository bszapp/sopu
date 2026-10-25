import '../common/constants.dart';

String textOf(Map data, Iterable<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value == null || value is Map || value is List) continue;
    final text = '$value'.trim();
    if (text.isNotEmpty && text != 'null') return text;
  }
  return '';
}

bool? flagOf(dynamic value) {
  if (value == true || value == 1 || value == '1') return true;
  if (value == false || value == 0 || value == '0') return false;
  return null;
}

List<dynamic> itemsOf(dynamic raw) {
  if (raw is List) return raw;
  if (raw is Map) {
    for (final key in ['list', 'dataList', 'result']) {
      if (raw[key] is List) return raw[key] as List;
      if (raw[key] is Map) return itemsOf(raw[key]);
    }
  }
  throw const FormatException('服务器未返回可识别的列表');
}

Map<String, dynamic> scoreData(Map<String, dynamic> raw) => {
  ...raw,
  if (raw['info'] is Map) ...Map<String, dynamic>.from(raw['info']),
};

String resourceUrl(String raw, String platform) {
  final value = raw.trim();
  if (value.isEmpty || value == 'null') return '';
  if (value.startsWith('//')) return 'https:$value';
  final uri = Uri.tryParse(value);
  if (uri == null) return '';
  if (uri.scheme == 'http' || uri.scheme == 'https') return uri.toString();
  if (uri.hasScheme) return '';
  final base = platform == 'cc' ? CcC.fileHost : '${Tan8C.domain}/';
  return Uri.parse(base).resolveUri(uri).toString();
}

String userNameOf(Map data) => textOf(data, [
  'nickname',
  'webname',
  'u_name',
  'upload_user_name',
  'user_name',
  'username',
  'name',
]);

String userPhotoOf(Map data, String platform) => resourceUrl(
  textOf(data, [
    'head_portrait_image',
    'user_avatar',
    'user_big_avatar',
    'u_photo',
    'upload_user_img',
    'author_photo',
    'avatar',
    'face',
    'face_url',
    'user_photo',
  ]),
  platform,
);

/// 虫虫作品/关注接口需要数值平台 ID，不能拿登录 token 当主页 ID。
String userIdOf(Map data, String platform, {bool allowId = true}) {
  final keys = platform == 'cc'
      ? ['cg_uid', 'u_uid', 'author_uid', 'userid', 'user_id', 'uid', 'id']
      : ['uid', 'user_id', 'userid', 'author_uid', 'id'];
  for (final key in keys) {
    if (key == 'id' && !allowId) continue;
    final value = textOf(data, [key]);
    if (value.isNotEmpty &&
        (platform != 'cc' || RegExp(r'^\d+$').hasMatch(value))) {
      return value;
    }
  }
  return '';
}

String commentIdOf(Map data) => textOf(data, ['comment_id', 'cid', 'id']);

String? membershipOf(Map data) {
  if ([
    'svip',
    'is_svip',
    'is_svip_forever',
  ].any((k) => flagOf(data[k]) == true)) {
    return 'SVIP';
  }
  if ([
    'vip',
    'is_vip',
    'isvip',
    'is_vip_forever',
  ].any((k) => flagOf(data[k]) == true)) {
    return 'VIP';
  }
  return null;
}

/// 资源地址和服务端图标只用于展示；不据此增加付费访问门禁。
String? aiLabelOf(Map data, String platform) {
  if (platform == 'cc') {
    if (textOf(data, ['play_json', 'fingering_ccmz', 'sing_ccmz']).isNotEmpty) {
      return 'AI 谱';
    }
    if (textOf(data, [
      'ccmz_page_1',
      'fingering_ccmz_one_page',
      'sing_ccmz_one_page',
    ]).isNotEmpty) {
      return 'AI 预览';
    }
  } else if (textOf(data, ['aiIconUrl']).isNotEmpty ||
      flagOf(data['showAIScrollScoreIcon']) == true ||
      (data['jumpEvent2'] is Map &&
          data['jumpEvent2']['event_id'] == 'open_SVGPiano')) {
    return 'AI 谱';
  }
  return null;
}
