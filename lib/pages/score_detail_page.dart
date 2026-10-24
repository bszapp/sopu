/// 曲谱详情页(两平台统一主体)。
/// 原则: 服务端给什么就展示什么, 不写客户端 VIP/付费挡板。
/// tan8: init2023 失败自动走公开 m=info 兜底; cc: operninfov003 详情。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import '../http/cc_api.dart';
import '../http/tan8_api.dart';
import '../services/player_service.dart';
import '../services/sessions.dart';
import '../utils/ccmz_decode.dart';
import '../utils/globals.dart';
import '../utils/ypad_decode.dart';
import '../widgets/common.dart';
import 'author_page.dart';
import 'image_viewer_page.dart';
import 'sheet_web_page.dart';

class ScoreDetailPage extends StatefulWidget {
  final String platform;
  final String id;
  const ScoreDetailPage({super.key, required this.platform, required this.id});

  @override
  State<ScoreDetailPage> createState() => _ScoreDetailPageState();
}

class _ScoreDetailPageState extends State<ScoreDetailPage> {
  Map<String, dynamic>? info;
  List<dynamic>? comments;
  String _ccFileUrl = '';
  bool _admireOn = false;
  int _admireCount = 0;
  bool _loading = true;
  bool _tan8Collected = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get isCc => widget.platform == 'cc';

  String _first(List<String> keys) {
    for (final k in keys) {
      final v = info?[k];
      if (v != null && '$v'.isNotEmpty && '$v' != 'null') return '$v';
    }
    return '';
  }

  String get title =>
      _first(['songname', 'name', 'title', 'learning_name', 'label_1_text']);
  String get cover => _first([
    'pic',
    'image_url',
    'titlepic',
    'image_1_url',
    'image_address',
    'photo_address',
  ]);
  String get authorName => _first([
    'upload_user_name',
    'uploader',
    'author',
    'compose',
    'label_3_text',
  ]);
  String get authorUid => _first(['author_uid', 'userid', 'uid', 'authorUid']);

  String get statsLine {
    if (info == null) return '';
    if (isCc) {
      return '播放 ${info!['hit_num'] ?? '-'} · 收藏 ${info!['collect_num'] ?? '-'} · '
          '评论 ${info!['comment_num'] ?? '-'}';
    }
    return '浏览 ${info!['views'] ?? '-'} · 收藏 ${info!['collect']?.toString().isNotEmpty == true ? info!['collect'] : '-'} · '
        '评论 ${info!['count_comments'] ?? '-'} · 赞 ${info!['dianZan'] ?? '-'}';
  }

  String get levelLine => isCc
      ? _first(['level_name', 'opern_level_name', 'copystatus_desc'])
      : _first(['label_2_text', 'level', 'keyTitle']);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final d = isCc
          ? await CcApi.opernDetail(widget.id)
          : await Tan8Api.scoreInfo(widget.id);
      if (!mounted) return;
      setState(() {
        info = d;
        _admireOn = '${d['isDianZan'] ?? '0'}' == '1';
        _admireCount = int.tryParse('${d['count_dianZan'] ?? '0'}') ?? 0;
        _tan8Collected = '${d['isCollect'] ?? '0'}' == '1';
        _loading = false;
      });
      await _ensureComment();
      await _checkCcCollected();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _ensureComment() async {
    try {
      if (isCc) {
        final r = await CcApi.opernComments(widget.id, page: 1, size: 20);
        final List<dynamic> list;
        if (r is List) {
          list = r;
        } else if (r is Map<String, dynamic>) {
          list = (r['list'] as List?) ?? const [];
        } else {
          list = const [];
        }
        if (mounted) setState(() => comments = list);
      } else {
        final r = await Tan8Api.comments(widget.id, limit: 20);
        if (mounted) setState(() => comments = r);
      }
    } catch (_) {
      // 评论失败不阻塞主体
      if (mounted) setState(() => comments = const []);
    }
  }

  /// cc ccmz 直链获取: 详情字段优先, 否则按标题回捞搜索结果里的 play_json。
  /// 服务器不给就是没有, 如实提示。
  Future<void> _ensureCcFileUrl() async {
    if (_ccFileUrl.isNotEmpty) return;
    _ccFileUrl = await CcApi.scoreFileUrl(widget.id, detail: info);
  }

  // ---------- 写操作 ----------

  bool _guardLogin() {
    final logged = isCc ? Sessions.ccLoggedIn : Sessions.tan8LoggedIn;
    if (!logged) {
      SmartDialog.showToast('请先登录${isCc ? '虫虫' : '弹琴吧'}账号');
      return false;
    }
    return true;
  }

  Future<void> _toggleCollect() async {
    if (!_guardLogin()) return;
    try {
      if (isCc) {
        final learningId = widget.id;
        final curOn = _ccCollected == true;
        if (curOn) {
          await CcApi.collectDel(learningId);
        } else {
          await CcApi.collectAdd(learningId);
        }
        _ccCollected = CcApi.flag(await CcApi.collectCheck(widget.id));
        if (_ccCollected == curOn) throw StateError('服务器返回的收藏状态未改变');
        SmartDialog.showToast(_ccCollected! ? '已收藏' : '已取消收藏');
      } else {
        final r = await Tan8Api.webCollect(widget.id, !_tan8Collected);
        final msg = r;
        SmartDialog.showToast(msg.isEmpty ? '已提交收藏请求' : msg);
        final items = await Tan8Api.myCollectList(limit: 100);
        _tan8Collected = items.whereType<Map>().any(
          (e) =>
              '${e['yuepuid'] ?? e['id'] ?? (e['info'] is Map ? e['info']['id'] : '')}' ==
              widget.id,
        );
        // tan8 收藏回执不回状态, 重新拉资料刷新展示
        try {
          final d = await Tan8Api.scoreInfo(widget.id);
          if (mounted) setState(() => info = d);
        } catch (_) {}
      }
      if (mounted) setState(() {});
    } catch (e) {
      SmartDialog.showToast('收藏失败: $e');
    }
  }

  bool? _ccCollected;

  Future<void> _checkCcCollected() async {
    if (!isCc || !Sessions.ccLoggedIn) return;
    try {
      final r = await CcApi.collectCheck(widget.id);
      // 服务器 1/true = 已收藏
      _ccCollected = CcApi.flag(r);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _toggleAdmire() async {
    if (!_guardLogin()) return;
    try {
      final back = await Tan8Api.admire(widget.id);
      final txt = (back).replaceAll('\\', '');
      // 返回串含 '已取消点赞' → 完成取消; 否则视为已赞
      SmartDialog.showToast(txt);
      final current = await Tan8Api.scoreInfoPublic(widget.id);
      _admireOn = '${current['isDianZan'] ?? '0'}' == '1';
      _admireCount = int.tryParse('${current['count_dianZan'] ?? '0'}') ?? 0;
      if (mounted) setState(() {});
    } catch (e) {
      SmartDialog.showToast('点赞失败: $e');
    }
  }

  // ---------- 打开器 ----------

  Future<void> _openPlaybackData() async {
    SmartDialog.showLoading(msg: '读取演奏数据...');
    try {
      final (files, _) = await Tan8Api.fetchScore(widget.id);
      final packages = files.entries
          .where((e) => RegExp(r'\.ypad2?$').hasMatch(e.key))
          .toList();
      final parsed = [
        for (final entry in packages) (entry, decodeYpad(entry.value)),
      ];
      SmartDialog.dismiss(status: SmartStatus.loading);
      if (!mounted) return;
      if (parsed.isEmpty) {
        SmartDialog.showToast('服务器未返回 ypad/ypad2 文件');
        return;
      }
      Get.dialog(
        AlertDialog(
          title: const Text('演奏数据'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (entry, package) in parsed) ...[
                  Text(
                    entry.key,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${package.pageCount} 页 · ${package.tracks.length} 轨 · ${package.eventCount} 个事件\n每拍 ${package.ticksPerBeat} ticks · 总计 ${package.totalTicks} ticks',
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      try {
                        final path = await saveToDownloads(
                          entry.key.replaceAll('/', '_'),
                          entry.value,
                        );
                        SmartDialog.showToast('已保存 → $path');
                      } catch (e) {
                        SmartDialog.showToast('保存失败: $e');
                      }
                    },
                    icon: const Icon(Icons.download),
                    label: const Text('下载演奏数据原包'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Get.back(), child: const Text('关闭')),
          ],
        ),
      );
    } catch (e) {
      SmartDialog.dismiss(status: SmartStatus.loading);
      SmartDialog.showToast('读取失败: $e');
    }
  }

  Future<void> _openAiScore() async {
    if (isCc) {
      SmartDialog.showLoading(msg: '拉取 ccmz 文件...');
      try {
        await _ensureCcFileUrl();
        if (_ccFileUrl.isEmpty) {
          SmartDialog.dismiss(status: SmartStatus.loading);
          SmartDialog.showToast('该曲谱未提供数据文件(以服务器实际返回为准)');
          return;
        }
        final bytes = await CcApi.downloadBytes(_ccFileUrl);
        SmartDialog.dismiss(status: SmartStatus.loading);
        await _openCcmzBytes(bytes);
      } catch (e) {
        SmartDialog.dismiss(status: SmartStatus.loading);
        SmartDialog.showToast('打开失败: $e');
      }
    } else {
      SmartDialog.showLoading(msg: '获取谱面 svg...');
      try {
        final (files, _) = await Tan8Api.fetchScore(widget.id);
        final svgs = files.entries.where((e) => e.key.endsWith('.svg')).toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        SmartDialog.dismiss(status: SmartStatus.loading);
        if (svgs.isEmpty) {
          SmartDialog.showToast('未获得谱面文件(以服务器实际返回为准)');
          return;
        }
        final raw = svgs
            .map((f) => utf8.decode(f.value, allowMalformed: true))
            .toList();
        Get.to(
          () => SheetWebPage.svg(title: title, svgs: raw),
          fullscreenDialog: true,
        );
      } catch (e) {
        SmartDialog.dismiss(status: SmartStatus.loading);
        SmartDialog.showToast('获取失败: $e');
      }
    }
  }

  /// ccmz → (data, info) 双 json 解码(纯 Dart, 对应 ccmz-tool ccmzScore.ts)。
  Future<void> _openCcmzBytes(Uint8List bytes) async {
    final pkg = decodeCcmz(bytes);
    Get.to(
      () => SheetWebPage.ccmz(
        title: title,
        scoreJson: pkg.scoreJson,
        infoJson: pkg.infoJson,
      ),
      fullscreenDialog: true,
    );
  }

  Future<void> _openPictures() async {
    if (isCc) {
      final raw = ((info?['image_list'] as List?) ?? const [])
          .map((e) => '$e')
          .where((e) => e.isNotEmpty)
          .map((e) => e.startsWith('http') ? e : CcApi.fileUrl(e))
          .toList();
      if (raw.isEmpty) {
        SmartDialog.showToast('该曲谱无图片页(cc 图片谱以服务器实际返回为准)');
        return;
      }
      Get.to(
        () => ImageViewerPage.network(title: title, imageUrls: raw),
        fullscreenDialog: true,
      );
      return;
    }
    SmartDialog.showLoading(msg: '获取谱面图片...');
    try {
      final images = await Tan8Api.fetchImages(widget.id);
      SmartDialog.dismiss(status: SmartStatus.loading);
      if (!mounted) return;
      if (images.isEmpty) {
        SmartDialog.showToast('未获得图片页(以服务器实际返回为准)');
        return;
      }
      Get.to(
        () => ImageViewerPage.bytes(title: title, images: images),
        fullscreenDialog: true,
      );
    } catch (e) {
      SmartDialog.dismiss(status: SmartStatus.loading);
      SmartDialog.showToast('获取失败: $e');
    }
  }

  Future<void> _download() async {
    try {
      SmartDialog.showLoading(msg: '下载中...');
      if (isCc) {
        await _ensureCcFileUrl();
        if (_ccFileUrl.isEmpty) {
          SmartDialog.dismiss(status: SmartStatus.loading);
          SmartDialog.showToast('该平台未提供可下载文件');
          return;
        }
        final b = await CcApi.downloadBytes(_ccFileUrl);
        final ext = _ccFileUrl.split('.').last.split('?').first;
        final name = '${widget.id}.${ext.isNotEmpty ? ext : 'ccmz'}';
        final path = await saveToDownloads(name, b);
        SmartDialog.dismiss(status: SmartStatus.loading);
        SmartDialog.showToast('已下载 $name → $path');
      } else {
        final (zip, _, _) = await Tan8Api.fetchScoreZip(widget.id);
        final path = await saveToDownloads('${widget.id}.zip', zip);
        SmartDialog.dismiss(status: SmartStatus.loading);
        SmartDialog.showToast('已下载 → $path');
      }
    } catch (e) {
      SmartDialog.dismiss(status: SmartStatus.loading);
      SmartDialog.showToast('下载失败: $e');
    }
  }

  // ---------- 试听 ----------

  Future<void> _playAudition() async {
    if (info == null) return;
    final url = isCc
        ? (info?['audition_urtext'] ?? info?['audition'] ?? '').toString()
        : (Tan8Api.auditionUrl(info!, yuepuid: widget.id) ?? '');
    if (url.isEmpty) {
      SmartDialog.showToast('该曲谱无试听音频');
      return;
    }
    try {
      await PlayerService.I.play(
        AuditionTrack(
          url: url,
          title: title,
          platform: widget.platform,
          scoreId: widget.id,
          cover: cover,
          author: authorName,
        ),
      );
    } catch (e) {
      SmartDialog.showToast('试听失败：$e');
    }
  }

  void _openAuthor({String? uid, String? name, String? photo}) {
    final auid = uid ?? authorUid;
    if (auid.isEmpty) {
      SmartDialog.showToast('未获取到该用户信息');
      return;
    }
    Get.to(
      () => AuthorPage(
        platform: widget.platform,
        uid: auid,
        name: (name != null && name.isNotEmpty) ? name : authorName,
        photo: photo ?? (isCc ? _first(['author_photo']) : ''),
      ),
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('详情', style: t.titleMedium)),
      body: _loading
          ? const LoadingCenter()
          : _error.isNotEmpty
          ? ErrorCenter(_error, onRetry: _load)
          : _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.only(bottom: pageBottomScrollSpace),
      children: [
        // 信息卡
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 104,
                height: 142,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ScoreCover(cover),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PlatformBadge(widget.platform, fontSize: 11),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => _openAuthor(),
                      child: Text(
                        authorName.isEmpty ? '作者 $authorUid' : authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isCc ? c.primary : Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (levelLine.isNotEmpty) ...[
                      Text(
                        levelLine,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      _first(['name_en', 'composer', 'singer', 'keyTitle']),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      statsLine,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if ((info?['desc'] ?? info?['info'] ?? '')
                        .toString()
                        .isNotEmpty)
                      Text(
                        '${info!['desc'] ?? info!['info']}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 动作条
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _playAudition,
                icon: const Icon(Icons.volume_up, size: 18),
                label: const Text('试听'),
              ),
              OutlinedButton.icon(
                onPressed: _openAiScore,
                icon: const Icon(Icons.auto_stories, size: 18),
                label: Text(isCc ? 'AI 谱(ccmz)' : 'AI 谱(svg)'),
              ),
              OutlinedButton.icon(
                onPressed: _openPictures,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: Text(isCc ? '图片(按需)' : '预览'),
              ),
              if (!isCc)
                OutlinedButton.icon(
                  onPressed: _openPlaybackData,
                  icon: const Icon(Icons.piano, size: 18),
                  label: const Text('演奏数据'),
                ),
              OutlinedButton.icon(
                onPressed: _download,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('下载源'),
              ),
              OutlinedButton.icon(
                onPressed: _toggleCollect,
                icon: Icon(
                  (isCc ? _ccCollected == true : _tan8Collected)
                      ? Icons.collections_bookmark
                      : Icons.collections_bookmark_outlined,
                  size: 18,
                ),
                label: Text(
                  (isCc ? _ccCollected == true : _tan8Collected)
                      ? '取消收藏'
                      : '收藏',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _writeComment(),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('发表评论'),
              ),
              if (!isCc)
                OutlinedButton.icon(
                  onPressed: _toggleAdmire,
                  icon: Icon(
                    _admireOn ? Icons.thumb_up : Icons.thumb_up_outlined,
                    size: 18,
                  ),
                  label: Text(_admireCount > 0 ? '赞 $_admireCount' : '赞'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 10),
        if (_sourceNote.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              _sourceNote,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ),
        for (final c in (comments ?? const []))
          _CommentTile(
            c,
            isCc: isCc,
            onAvatarTap: (uid, name, photo) =>
                _openAuthor(uid: uid, name: name, photo: photo),
            onChanged: _ensureComment,
            onAction: (action) => _commentAction(c, action),
          ),
        if (comments == null) const LoadingCenter(msg: '评论加载中...'),
        if ((comments ?? const []).isEmpty)
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('暂无评论', style: TextStyle(color: Colors.grey)),
          ),
      ],
    );
  }

  String get _sourceNote => '${info?['_source'] ?? ''}';

  Future<void> _writeComment({Map<String, dynamic>? reply}) async {
    if (!_guardLogin()) return;
    final controller = TextEditingController();
    final text = await Get.dialog<String>(
      AlertDialog(
        title: Text(reply == null ? '发表评论' : '回复评论'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 6,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Get.back(result: controller.text.trim());
              }
            },
            child: const Text('发送'),
          ),
        ],
      ),
    );
    if (text == null || !mounted) return;
    try {
      final cid = '${reply?['id'] ?? reply?['cid'] ?? ''}';
      final dynamic result = isCc
          ? await CcApi.commentAdd(widget.id, text, parentId: cid)
          : (await Tan8Api.addComment(
              widget.id,
              text,
              replyCommentId: reply == null ? null : cid,
              replyUid: reply?['uid']?.toString(),
              replyUsername: reply?['username']?.toString(),
            )).data;
      SmartDialog.showToast('$result');
      await _ensureComment();
    } catch (e) {
      SmartDialog.showToast('发送失败: $e');
    }
  }

  Future<void> _commentAction(Map<String, dynamic> c, String action) async {
    if (!_guardLogin()) return;
    if (action == 'reply') {
      await _writeComment(reply: c);
      return;
    }
    final cid = '${c['id'] ?? c['cid'] ?? c['comment_id'] ?? ''}';
    if (cid.isEmpty) {
      SmartDialog.showToast('服务器未返回评论标识');
      return;
    }
    try {
      final dynamic result;
      if (action == 'delete') {
        result = isCc
            ? await CcApi.commentDel(cid)
            : await Tan8Api.delComment(cid, widget.id);
      } else {
        result = isCc
            ? await CcApi.commentLike(cid, action == 'like')
            : (await Tan8Api.likeComment(
                cid,
                widget.id,
                action == 'like',
              )).data;
      }
      SmartDialog.showToast('$result');
      await _ensureComment();
    } catch (e) {
      SmartDialog.showToast('操作失败: $e');
    }
  }
}

Future<String> saveToDownloads(String name, Uint8List b) async {
  final f = File('${GPaths.downloads}/$name');
  await f.writeAsBytes(b);
  return f.path;
}

class _CommentTile extends StatelessWidget {
  final Map<String, dynamic> c;
  final bool isCc;
  final void Function(String uid, String name, String photo) onAvatarTap;
  final VoidCallback onChanged;
  final void Function(String) onAction;
  const _CommentTile(
    this.c, {
    required this.isCc,
    required this.onAvatarTap,
    required this.onChanged,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final name =
        (c['u_name'] ?? c['username'] ?? c['user_name'] ?? c['nickname'] ?? '')
            .toString();
    final avatar =
        (c['u_photo'] ??
                c['user_avatar'] ??
                c['avatar'] ??
                c['face_url'] ??
                c['user_photo'] ??
                '')
            .toString();
    final uid = (c['u_uid'] ?? c['uid'] ?? c['user_id'] ?? c['userid'] ?? '')
        .toString();
    final text = (c['message'] ?? c['content'] ?? c['comment_content'] ?? '')
        .toString();
    final time =
        (c['addtime'] ??
                c['time'] ??
                c['create_time'] ??
                c['publish_time'] ??
                '')
            .toString();
    final likes = c['likes'] ?? c['like_num'] ?? c['hits'] ?? '';
    final vip = (c['vip'] ?? c['is_vip'] ?? 0) == 1 || c['vip'] == true;
    final av = avatar.startsWith('http') || avatar.isEmpty
        ? avatar
        : (isCc ? CcApi.fileUrl(avatar) : avatar);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: uid.isNotEmpty ? () => onAvatarTap(uid, name, av) : null,
            child: CircleAvatar(
              radius: 15,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
              backgroundImage: av.startsWith('http') ? NetworkImage(av) : null,
              onBackgroundImageError: av.startsWith('http') ? (_, _) {} : null,
              child: av.startsWith('http')
                  ? null
                  : Text(
                      name.isEmpty ? '?' : name[0],
                      style: const TextStyle(fontSize: 12),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name.isEmpty ? '用户' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: vip
                              ? const Color(0xFFD48806)
                              : Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                SelectableText(
                  text,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: () => onAction('reply'),
                      child: const Text('回复'),
                    ),
                    TextButton(
                      onPressed: () => onAction('like'),
                      child: const Text('点赞'),
                    ),
                    TextButton(
                      onPressed: () => onAction('unlike'),
                      child: const Text('取消赞'),
                    ),
                    if (uid.isNotEmpty &&
                        uid == (isCc ? Sessions.ccNumericId : Sessions.tan8Uid))
                      TextButton(
                        onPressed: () => onAction('delete'),
                        child: const Text('删除'),
                      ),
                  ],
                ),
                if ('$likes'.isNotEmpty && '$likes' != '0')
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.thumb_up_alt_outlined,
                          size: 12,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '$likes',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                // 子回复
                for (final r
                    in ((c['replys'] ?? c['sub_comments'] ?? c['replies'])
                            as List?) ??
                        const [])
                  if (r is Map<String, dynamic>)
                    Padding(
                      padding: const EdgeInsets.only(left: 24, top: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText.rich(
                              TextSpan(
                                style: const TextStyle(fontSize: 12),
                                children: [
                                  TextSpan(
                                    text:
                                        '${r['username'] ?? r['nickname'] ?? ''} ',
                                    style: const TextStyle(
                                      color: Color(0xFF4A67D6),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if ('$r'.contains('reply_username') ||
                                      (r['reply_username'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                    TextSpan(
                                      text: '回复 ${r['reply_username']}: ',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  TextSpan(
                                    text:
                                        '${r['message'] ?? r['content'] ?? r['comment_content'] ?? ''}',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
