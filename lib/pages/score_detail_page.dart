/// 曲谱详情页(两平台统一主体)。
/// 原则: 服务端给什么就展示什么, 不写客户端 VIP/付费挡板。
/// tan8: init2023 失败自动走公开 m=info 兜底; cc: operninfov003 详情。
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import '../http/cc_api.dart';
import '../http/tan8_api.dart';
import '../http/http.dart';
import '../services/player_service.dart';
import '../services/file_save_service.dart';
import '../services/sessions.dart';
import '../utils/ccmz_decode.dart';
import '../utils/data_fields.dart';
import '../widgets/common.dart';
import '../widgets/score_image_save_menu.dart';
import '../widgets/piliplus/score_detail_layout.dart';
import '../widgets/piliplus/score_intro_panel.dart';
import '../widgets/piliplus/score_related_panel.dart';
import '../widgets/piliplus/action_item.dart';
import '../widgets/piliplus/score_reply_item.dart';
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
  final Map<String, CcmzPackage> _ccPackages = {};
  List<Uint8List> _pictures = [];
  double? _pictureAspectRatio;
  bool _picturesBusy = false, _relatedBusy = false;
  bool _numberedPictures = false;
  String _pictureError = '', _relatedError = '';
  List<Map<String, dynamic>> _related = [];
  int _pictureGeneration = 0, _relatedGeneration = 0;
  int _pictureIndex = 0;

  bool? _admireOn;
  int _admireCount = 0;
  bool _loading = true;
  bool? _tan8Collected;
  bool _collectBusy = false, _checkingCollect = false, _commentBusy = false;
  bool _commentsMore = true;
  int _commentPage = 1;
  int _commentOffset = 0;
  String _commentError = '', _collectError = '';
  bool _commentMoreScheduled = false;
  final Map<String, bool> _commentLikes = {};
  final Set<String> _busyComments = {};
  String _error = '';
  int _loadGeneration = 0, _commentGeneration = 0;
  late String _accountKey;
  final Map<String, _ReplyThread> _replyThreads = {};
  String _historyReportKey = '', _historyError = '';
  bool _historyBusy = false;
  bool? _authorFollowing;
  bool _authorFollowBusy = false;
  bool _authorBusy = false;
  String _authorError = '';

  @override
  void initState() {
    super.initState();
    _accountKey = _accountIdentity;
    Sessions.changed.addListener(_accountChanged);
    _load();
  }

  String get _accountIdentity => isCc
      ? Sessions.ccIdentityKey
      : '${Sessions.tan8LoggedIn}:${Sessions.tan8Uid}';

  void _accountChanged() {
    if (_accountKey == _accountIdentity || !mounted) return;
    _accountKey = _accountIdentity;
    _ccCollected = _tan8Collected = _admireOn = null;
    _commentGeneration++;
    _commentBusy = false;
    _replyThreads.clear();
    _commentLikes.clear();
    _historyReportKey = '';
    _historyBusy = false;
    _historyError = '';
    _load();
  }

  @override
  void dispose() {
    Sessions.changed.removeListener(_accountChanged);
    super.dispose();
  }

  bool get isCc => widget.platform == 'cc';

  String _first(List<String> keys) {
    return textOf(info ?? {}, keys);
  }

  String get title =>
      _first(['songname', 'name', 'title', 'learning_name', 'label_1_text']);
  String get cover => resourceUrl(
    _first([
      'pic',
      'image_url',
      'titlepic',
      'image_1_url',
      'image_address',
      'photo_address',
    ]),
    widget.platform,
  );
  String get authorName => _first([
    'upload_user_name',
    'username',
    'author',
    'maskName',
    'uploader',
    'compose',
    'label_3_text',
  ]);
  String get authorUid => _first(['author_uid', 'userid', 'authorUid']);

  String get statsLine {
    final raw = _first(isCc ? ['hit_num'] : ['views']);
    final count = int.tryParse(raw);
    if (count == null) return raw.isEmpty ? '-' : raw;
    final unit = count >= 100000000
        ? 100000000
        : count >= 10000
        ? 10000
        : 1;
    if (unit == 1) return '$count';
    final whole = count ~/ unit;
    final tenth = (count % unit) ~/ (unit ~/ 10);
    return '$whole${tenth == 0 ? '' : '.$tenth'}${unit == 10000 ? '万' : '亿'}';
  }

  String get _commentCount => _first(['comment_num', 'count_comments']);
  String get _collectCount =>
      _first(['collect_num', 'count_collect', 'collect']);

  String get levelLine => isCc
      ? _first(['level_name', 'opern_level_name', 'copystatus_desc'])
      : _first(['label_2_text', 'level', 'keyTitle']);

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = '';
      _authorBusy = false;
      _authorError = '';
    });
    try {
      var d = isCc
          ? await CcApi.opernDetail(widget.id)
          : await Tan8Api.scoreInfo(widget.id);
      if (!isCc &&
          (!d.containsKey('isDianZan') || !d.containsKey('count_dianZan'))) {
        try {
          final public = await Tan8Api.scoreInfoPublic(widget.id);
          d = {...public, ...d};
        } catch (_) {
          /* 次要统计失败时保留已取得的详情。 */
        }
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        info = d;
        _admireOn = flagOf(d['isDianZan']);
        _admireCount = int.tryParse('${d['count_dianZan'] ?? '0'}') ?? 0;
        _tan8Collected = flagOf(d['isCollect']);
        _loading = false;
      });
      _loadPictures();
      _loadRelated();
      if (isCc) {
        _checkAuthorFollow();
      } else {
        _loadTan8Author();
      }
      _reportLearningHistory();
      await _ensureComment();
      await _checkCollected();
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _ensureComment({bool more = false}) async {
    if (_commentBusy) return;
    if (more && !_commentsMore) return;
    final generation = ++_commentGeneration;
    setState(() {
      _commentBusy = true;
      _commentError = '';
    });
    if (!more) {
      _commentPage = 1;
      _commentOffset = 0;
    }
    try {
      List<dynamic> rows;
      int? totalPages;
      if (isCc) {
        final r = await CcApi.opernComments(
          widget.id,
          page: _commentPage,
          size: 20,
        );
        rows = itemsOf(r);
        totalPages = r is Map ? int.tryParse('${r['total_pages']}') : null;
      } else {
        final feeds = await Future.wait([
          Tan8Api.webComments(widget.id, page: _commentPage),
          Tan8Api.comments(
            widget.id,
            start: _commentOffset,
            limit: 20,
          ).catchError((Object _) => <dynamic>[]),
        ]);
        final states = {
          for (final row in feeds[1].whereType<Map<String, dynamic>>())
            commentIdOf(row): row,
        };
        rows = [
          for (final row in feeds[0].whereType<Map<String, dynamic>>())
            {...?states[commentIdOf(row)], ...row},
        ];
      }
      if (!mounted || generation != _commentGeneration) return;
      final known = more
          ? (comments ?? []).whereType<Map>().map(commentIdOf).toSet()
          : <String>{};
      final fresh = rows
          .whereType<Map<String, dynamic>>()
          .where((e) => !known.contains(commentIdOf(e)))
          .toList();
      if (more && rows.isNotEmpty && fresh.isEmpty) {
        throw StateError('服务器重复返回上一页评论');
      }
      setState(() {
        comments = [if (more) ...?comments, ...fresh];
        _commentsMore =
            rows.isNotEmpty &&
            (isCc
                ? (totalPages == null || _commentPage < totalPages)
                : rows.length >= 10);
        _commentPage++;
        _commentOffset += rows.length;
      });
      if (isCc && fresh.isNotEmpty) {
        for (final row in fresh.whereType<Map<String, dynamic>>()) {
          if ((int.tryParse('${row['total_reply'] ?? 0}') ?? 0) > 0) {
            await _loadReplies(row);
          }
        }
      }
    } catch (e) {
      if (mounted && generation == _commentGeneration) {
        setState(() => _commentError = '$e');
      }
    } finally {
      if (mounted && generation == _commentGeneration) {
        setState(() => _commentBusy = false);
      }
    }
  }

  void _scheduleMoreComments() {
    if (_commentMoreScheduled ||
        _commentBusy ||
        !_commentsMore ||
        _commentError.isNotEmpty) {
      return;
    }
    _commentMoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _commentMoreScheduled = false;
      if (mounted) _ensureComment(more: true);
    });
  }

  Future<void> _refreshVisibleComments() async {
    final count = comments?.length ?? 20;
    await _ensureComment();
    while (mounted &&
        _commentError.isEmpty &&
        _commentsMore &&
        (comments?.length ?? 0) < count) {
      await _ensureComment(more: true);
    }
    if (isCc && _commentError.isEmpty) {
      for (final id in _replyThreads.keys.toList()) {
        final parents = (comments ?? [])
            .whereType<Map<String, dynamic>>()
            .where((row) => commentIdOf(row) == id);
        if (parents.isEmpty) {
          _replyThreads.remove(id);
          continue;
        }
        final thread = _replyThreads[id]!;
        final target = thread.rows.length;
        await _loadReplies(parents.first, reset: true);
        while (mounted &&
            identical(_replyThreads[id], thread) &&
            thread.error.isEmpty &&
            thread.more &&
            thread.rows.length < target) {
          await _loadReplies(parents.first);
        }
      }
    }
  }

  Future<void> _reportLearningHistory() async {
    if (!(isCc ? Sessions.ccLoggedIn : Sessions.tan8LoggedIn) || _historyBusy) {
      return;
    }
    final learningId = isCc ? _first(['id', 'learning_id']) : widget.id;
    final key = '$_accountIdentity:$learningId';
    if (_historyReportKey == key) return;
    if (learningId.isEmpty || (isCc && CcApi.phpSessionId.isEmpty)) {
      setState(() => _historyError = '暂缺曲谱标识或登录会话，浏览记录未同步');
      return;
    }
    final account = _accountIdentity;
    setState(() {
      _historyBusy = true;
      _historyError = '';
    });
    try {
      if (isCc) {
        await CcApi.reportBrowse(learningId, albumId: _first(['album_id']));
      } else {
        await Tan8Api.reportBrowse(learningId);
      }
      if (mounted && account == _accountIdentity) _historyReportKey = key;
    } catch (e) {
      if (mounted && account == _accountIdentity) {
        setState(() => _historyError = '浏览记录同步失败：$e');
      }
    } finally {
      if (mounted && account == _accountIdentity) {
        setState(() => _historyBusy = false);
      }
    }
  }

  Future<void> _loadReplies(
    Map<String, dynamic> parent, {
    bool reset = false,
  }) async {
    final id = commentIdOf(parent);
    if (!isCc || id.isEmpty) return;
    final thread = _replyThreads.putIfAbsent(id, _ReplyThread.new);
    if (!reset && (thread.busy || !thread.more)) return;
    final generation = ++thread.generation, account = _accountIdentity;
    setState(() {
      thread.busy = true;
      thread.error = '';
    });
    try {
      final page = reset ? 1 : thread.page;
      final data = await CcApi.commentReplies(id, page: page);
      final rows = (data['list_reply'] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      if (!mounted ||
          generation != thread.generation ||
          account != _accountIdentity) {
        return;
      }
      final seen = reset ? <String>{} : thread.rows.map(commentIdOf).toSet();
      final fresh = rows.where((row) => seen.add(commentIdOf(row))).toList();
      if (!reset && rows.isNotEmpty && fresh.isEmpty) {
        throw StateError('服务器重复返回已加载回复');
      }
      setState(() {
        thread.rows = [if (!reset) ...thread.rows, ...fresh];
        thread.page = page + 1;
        thread.more = rows.isNotEmpty;
        thread.loaded = true;
      });
    } catch (e) {
      if (mounted &&
          generation == thread.generation &&
          account == _accountIdentity) {
        setState(() => thread.error = '$e');
      }
    } finally {
      if (mounted && generation == thread.generation) {
        setState(() => thread.busy = false);
      }
    }
  }

  Iterable<Map<String, dynamic>> _visibleComments() sync* {
    final pending = <Map<String, dynamic>>[
      ...(comments ?? []).whereType<Map<String, dynamic>>(),
      ..._replyThreads.values.expand((thread) => thread.rows),
    ];
    final seen = <String>{};
    while (pending.isNotEmpty) {
      final row = pending.removeLast();
      final ownId = commentIdOf(row);
      if (ownId.isNotEmpty && !seen.add(ownId)) continue;
      yield row;
      final loadedThread = _replyThreads[ownId];
      if (loadedThread?.loaded == true) {
        pending.addAll(loadedThread!.rows);
        continue;
      }
      for (final key in ['list_reply', 'replys', 'sub_comments', 'replies']) {
        if (row[key] is List) {
          pending.addAll((row[key] as List).whereType<Map<String, dynamic>>());
        }
      }
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
    if (!_guardLogin() || _collectBusy) return;
    if (_collected == null) {
      await _checkCollected();
      if (_collected == null || !mounted) return;
    }
    final original = _collected!;
    setState(() => _collectBusy = true);
    try {
      if (isCc) {
        final learningId = widget.id;
        final curOn = original;
        if (curOn) {
          await CcApi.collectDel(learningId);
        } else {
          await CcApi.collectAdd(learningId);
        }
      } else {
        ensureWriteSucceeded(await Tan8Api.webCollect(widget.id, !original));
      }
      await _checkCollected();
      if (_collected == null) throw StateError('请求已提交，收藏状态暂时无法确认');
      if (_collected == original) throw StateError('服务器返回的收藏状态未改变');
      await _refreshCounters();
      SmartDialog.showToast(_collected! ? '已收藏' : '已取消收藏');
    } catch (e) {
      SmartDialog.showToast('收藏失败: $e');
    } finally {
      if (mounted) setState(() => _collectBusy = false);
    }
  }

  bool? _ccCollected;

  Future<void> _refreshCounters() async {
    final generation = _loadGeneration;
    try {
      final current = isCc
          ? await CcApi.opernDetail(widget.id)
          : await Tan8Api.scoreInfoPublic(widget.id);
      if (!mounted || generation != _loadGeneration) return;
      setState(
        () => info = {
          ...?info,
          for (final key in [
            'hit_num',
            'views',
            'comment_num',
            'count_comments',
            'collect_num',
            'count_collect',
            'collect',
          ])
            if (current[key] != null) key: current[key],
        },
      );
    } catch (_) {
      // 写操作的状态已单独回读；统计暂时不可用时保留上次真实数量。
    }
  }

  bool? get _collected => isCc ? _ccCollected : _tan8Collected;

  Future<void> _checkCollected() async {
    if (!(isCc ? Sessions.ccLoggedIn : Sessions.tan8LoggedIn)) return;
    if (mounted) {
      setState(() {
        _checkingCollect = true;
        _collectError = '';
      });
    }
    try {
      final value = isCc
          ? CcApi.flag(await CcApi.collectCheck(widget.id))
          : await Tan8Api.isCollected(widget.id);
      if (isCc) {
        _ccCollected = value;
      } else {
        _tan8Collected = value;
      }
      if (mounted) setState(() {});
    } catch (e) {
      _ccCollected = _tan8Collected = null;
      if (mounted) setState(() => _collectError = '$e');
    } finally {
      if (mounted) setState(() => _checkingCollect = false);
    }
  }

  Future<void> _toggleAdmire() async {
    if (!_guardLogin()) return;
    try {
      final back = await Tan8Api.admire(widget.id);
      final txt = (back).replaceAll('\\', '');
      // 返回串含 '已取消点赞' → 完成取消; 否则视为已赞
      SmartDialog.showToast(txt);
      ensureWriteSucceeded(back);
      final current = await Tan8Api.scoreInfoPublic(widget.id);
      _admireOn = '${current['isDianZan'] ?? '0'}' == '1';
      _admireCount = int.tryParse('${current['count_dianZan'] ?? '0'}') ?? 0;
      if (mounted) setState(() {});
    } catch (e) {
      SmartDialog.showToast('点赞失败: $e');
    }
  }

  // ---------- 打开器 ----------

  Future<void> _loadTan8Author() async {
    if (_authorBusy) return;
    final generation = _loadGeneration;
    setState(() {
      _authorBusy = true;
      _authorError = '';
    });
    try {
      final uploader = await Tan8Api.initUploader(widget.id);
      final uid = textOf(uploader, ['userid']);
      if (!RegExp(r'^[1-9]\d*$').hasMatch(uid)) {
        throw StateError('曲谱接口未提供有效的发布者 UID');
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() => info = {...?info, 'author_uid': uid});
      _checkAuthorFollow();
      _loadRelated();
      final profile = await Tan8Api.userProfile(uid);
      if (!mounted || generation != _loadGeneration) return;
      setState(
        () => info = {
          ...?info,
          if (userNameOf(profile).isNotEmpty)
            'upload_user_name': userNameOf(profile),
          if (userPhotoOf(profile, 'tan8').isNotEmpty)
            'author_photo': userPhotoOf(profile, 'tan8'),
        },
      );
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _authorError = '$e');
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _authorBusy = false);
      }
    }
  }

  Future<void> _openAiScore() async {
    if (isCc) {
      SmartDialog.showLoading(msg: '读取谱型…');
      try {
        await _ensureCcFileUrl();
        final variants = <String, String>{};
        if (_ccFileUrl.isNotEmpty) variants['主谱'] = _ccFileUrl;
        for (final entry in {
          '弹唱谱': 'sing_ccmz',
          '指法谱': 'fingering_ccmz',
          '弹唱预览': 'sing_ccmz_one_page',
          '指法预览': 'fingering_ccmz_one_page',
        }.entries) {
          final path = textOf(info ?? {}, [entry.value]);
          if (path.isNotEmpty) {
            final url = CcApi.fileUrl(path);
            if (!variants.values.contains(url)) variants[entry.key] = url;
          }
        }
        SmartDialog.dismiss(status: SmartStatus.loading);
        if (!mounted) return;
        if (variants.isEmpty) {
          SmartDialog.showToast('服务器未提供 AI 谱资源');
          return;
        }
        final selected = variants.length == 1
            ? variants.values.first
            : await showDialog<String>(
                context: context,
                builder: (context) => SimpleDialog(
                  title: const Text('选择谱型'),
                  children: [
                    for (final variant in variants.entries)
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, variant.value),
                        child: Text(variant.key),
                      ),
                  ],
                ),
              );
        if (selected == null || !mounted) return;
        SmartDialog.showLoading(msg: '拉取谱面…');
        final pkg =
            _ccPackages[selected] ??
            decodeCcmz(await CcApi.downloadBytes(selected));
        _ccPackages[selected] = pkg;
        SmartDialog.dismiss(status: SmartStatus.loading);
        if (mounted) _openCcmzPackage(pkg);
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
  void _openCcmzPackage(CcmzPackage pkg) {
    Get.to(
      () => SheetWebPage.ccmz(
        title: title,
        scoreJson: pkg.scoreJson,
        infoJson: pkg.infoJson,
      ),
      fullscreenDialog: true,
    );
  }

  Future<void> _loadPictures() async {
    final generation = ++_pictureGeneration;
    setState(() {
      _picturesBusy = true;
      _pictureError = '';
      _pictures = [];
      _pictureIndex = 0;
    });
    try {
      final List<Uint8List> pages;
      if (isCc) {
        final book = await CcApi.bookInfoById(widget.id);
        if (mounted && generation == _pictureGeneration) {
          setState(
            () => info = {
              ...?info,
              'image_list': book['image_list'],
              'image_num': book['image_num'],
            },
          );
        }
        final raw = book['image_list'];
        final urls = raw is List
            ? raw
                  .map(
                    (e) => e is Map
                        ? textOf(e, ['url', 'image_url', 'image', 'src'])
                        : '$e',
                  )
                  .where((e) => e.isNotEmpty)
                  .map(CcApi.fileUrl)
                  .toList()
            : <String>[];
        if (urls.isEmpty) {
          pages = <Uint8List>[];
        } else {
          pages = [];
          for (final url in urls) {
            pages.add(await CcApi.downloadBytes(url));
          }
        }
      } else {
        pages = await Tan8Api.fetchImages(
          widget.id,
          numbered: _numberedPictures,
        );
      }
      if (mounted && generation == _pictureGeneration) {
        if (pages.isNotEmpty) {
          final codec = await ui.instantiateImageCodec(pages.first);
          final frame = await codec.getNextFrame();
          _pictureAspectRatio = frame.image.width / frame.image.height;
          frame.image.dispose();
          codec.dispose();
        }
        if (!mounted || generation != _pictureGeneration) return;
        setState(() => _pictures = pages);
      }
    } catch (e) {
      if (mounted && generation == _pictureGeneration) {
        setState(() => _pictureError = '$e');
      }
    } finally {
      if (mounted && generation == _pictureGeneration) {
        setState(() => _picturesBusy = false);
      }
    }
  }

  Future<void> _loadRelated() async {
    final generation = ++_relatedGeneration;
    setState(() {
      _relatedBusy = true;
      _relatedError = '';
      _related = [];
    });
    try {
      final keyword = _first([
        'keywords',
        'songname',
        'learning_name',
        'name',
        'title',
      ]);
      final rows = isCc
          ? ((await CcApi.recommendByOpernId(widget.id))['song_list']
                    as List? ??
                [])
          : keyword.isEmpty
          ? <dynamic>[]
          : itemsOf(await Tan8Api.search(keyword, limit: 20));
      if (!isCc && authorUid.isNotEmpty) {
        try {
          for (final mod in await Tan8Api.authorWorks(authorUid, limit: 20)) {
            final result = mod is Map ? mod['result'] : null;
            final values = result is Map ? result['result'] : null;
            if (values is List) rows.addAll(values.whereType<Map>());
          }
        } catch (_) {
          // 标题搜索结果已可用时，不因作者列表失败清空相关推荐。
        }
      }
      final seen = <String>{widget.id};
      final result = rows
          .whereType<Map<String, dynamic>>()
          .where((e) {
            final id = ScoreCard.idOf(e);
            return id.isNotEmpty && seen.add(id);
          })
          .map((e) => {...e, '__platform': widget.platform})
          .toList();
      if (mounted && generation == _relatedGeneration) {
        setState(() => _related = result);
      }
    } catch (e) {
      if (mounted && generation == _relatedGeneration) {
        setState(() => _relatedError = '$e');
      }
    } finally {
      if (mounted && generation == _relatedGeneration) {
        setState(() => _relatedBusy = false);
      }
    }
  }

  Future<void> _checkAuthorFollow() async {
    if (authorUid.isEmpty ||
        !(isCc ? Sessions.ccLoggedIn : Sessions.tan8LoggedIn)) {
      if (mounted) setState(() => _authorFollowing = null);
      return;
    }
    try {
      final followed = isCc
          ? CcApi.flag(await CcApi.followCheck(authorUid))
          : await Tan8Api.isFollowing(Sessions.tan8Uid, authorUid);
      if (mounted) setState(() => _authorFollowing = followed);
    } catch (_) {
      if (mounted) setState(() => _authorFollowing = null);
    }
  }

  Future<void> _toggleAuthorFollow() async {
    if (_authorFollowBusy || authorUid.isEmpty) return;
    if (!(isCc ? Sessions.ccLoggedIn : Sessions.tan8LoggedIn)) {
      SmartDialog.showToast('请先登录${isCc ? '虫虫' : '弹琴吧'}账号');
      return;
    }
    if (_authorFollowing == null) {
      await _checkAuthorFollow();
    }
    if (_authorFollowing == null || !mounted) return;
    final old = _authorFollowing!;
    setState(() => _authorFollowBusy = true);
    try {
      if (isCc) {
        if (old) {
          await CcApi.followDel(authorUid);
        } else {
          await CcApi.followAdd(authorUid);
        }
      } else {
        await Tan8Api.follow(authorUid, !old);
      }
      await _checkAuthorFollow();
      if (_authorFollowing == old) throw StateError('服务器未确认关注状态变化');
      SmartDialog.showToast(_authorFollowing! ? '已关注' : '已取消关注');
    } catch (e) {
      SmartDialog.showToast('关注操作失败：$e');
    } finally {
      if (mounted) setState(() => _authorFollowBusy = false);
    }
  }

  void _openPictures({int? index}) {
    if (_pictures.isEmpty) return;
    ImageViewerPage.open(
      ImageViewerPage.bytes(
        title: title,
        images: _pictures,
        initialIndex: index ?? _pictureIndex,
      ),
    );
  }

  Future<void> _savePictures(int index) => showScoreImageSaveMenu(
    context,
    title: '${title}_${widget.platform}_${widget.id}',
    index: index,
    count: _pictures.length,
    imageAt: (i) async => _pictures[i],
  );

  Widget _picturePane() => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxHeight < 120) {
        return const ColoredBox(color: Colors.white);
      }
      return Column(
        children: [
          if (!isCc)
            SizedBox(
              height: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final numbered in [false, true])
                    TextButton(
                      onPressed: _numberedPictures == numbered
                          ? null
                          : () {
                              setState(() => _numberedPictures = numbered);
                              _loadPictures();
                            },
                      child: Text(numbered ? '简谱' : '五线谱'),
                    ),
                ],
              ),
            ),
          Expanded(
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: Colors.black),
              child: _pictureContent(),
            ),
          ),
        ],
      );
    },
  );

  Widget _pictureContent() => Stack(
    fit: StackFit.expand,
    children: [
      ColoredBox(
        color: Colors.white,
        child: _picturesBusy
            ? const LoadingCenter(msg: '谱面加载中…')
            : _pictureError.isNotEmpty
            ? SingleChildScrollView(
                child: ErrorCenter(_pictureError, onRetry: _loadPictures),
              )
            : _pictures.isEmpty
            ? const Center(
                child: Text('暂无图片谱', style: TextStyle(color: Colors.black54)),
              )
            : PageView.builder(
                key: ValueKey(_pictureGeneration),
                itemCount: _pictures.length,
                onPageChanged: (index) => setState(() => _pictureIndex = index),
                itemBuilder: (context, index) => GestureDetector(
                  onTap: () => _openPictures(index: index),
                  onLongPress: () => _savePictures(index),
                  child: Image.memory(
                    _pictures[index],
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Center(child: Text('图片解码失败')),
                  ),
                ),
              ),
      ),
      if (_pictures.isNotEmpty)
        Positioned(
          top: 0,
          right: 0,
          child: ImagePageIndicator(
            index: _pictureIndex,
            count: _pictures.length,
          ),
        ),
      Positioned(
        right: 12,
        bottom: 12,
        child: IconButton.filled(
          tooltip: '试听',
          style: IconButton.styleFrom(shape: const CircleBorder()),
          onPressed: _playAudition,
          icon: const Icon(Icons.volume_up_outlined),
        ),
      ),
    ],
  );

  Widget _relatedSliver() => ScoreRelatedPanel(
    items: _related,
    loading: _relatedBusy,
    error: _relatedError,
    onReload: _loadRelated,
    onOpen: (item) => Get.to(
      () =>
          ScoreDetailPage(platform: widget.platform, id: ScoreCard.idOf(item)),
      preventDuplicates: false,
    ),
  );

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
        final path = await FileSaveService.saveBytes(name, b);
        SmartDialog.dismiss(status: SmartStatus.loading);
        SmartDialog.showToast('已下载 $name → $path');
      } else {
        final (zip, _, _) = await Tan8Api.fetchScoreZip(widget.id);
        final path = await FileSaveService.saveBytes(
          '${widget.id}.zip',
          zip,
          mimeType: 'application/zip',
        );
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

  Future<void> _openAuthor({String? uid, String? name, String? photo}) async {
    if (uid == null && !isCc && authorUid.isEmpty) {
      if (_authorBusy) {
        SmartDialog.showToast('发布者资料正在加载，请稍候');
        return;
      }
      await _loadTan8Author();
    }
    if (!mounted) return;
    final auid = uid ?? authorUid;
    if (auid.isEmpty) {
      SmartDialog.showToast(
        _authorError.isEmpty ? '未获取到该用户信息' : '发布者资料读取失败：$_authorError',
      );
      return;
    }
    Get.to(
      () => AuthorPage(
        platform: widget.platform,
        uid: auid,
        name: (name != null && name.isNotEmpty) ? name : authorName,
        photo:
            photo ??
            resourceUrl(
              _first(['author_photo', 'upload_user_img', 'user_avatar']),
              widget.platform,
            ),
      ),
      routeName: '/author/${widget.platform}/$auid',
      preventDuplicates: false,
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _loading || _error.isNotEmpty
          ? AppBar(title: const Text('详情'))
          : null,
      body: SafeArea(
        top: false,
        child: _loading
            ? const LoadingCenter()
            : _error.isNotEmpty
            ? ErrorCenter(_error, onRetry: _load)
            : ScoreDetailLayout(
                title: title,
                commentCount: _commentCount,
                aspectRatio: _pictureAspectRatio,
                onOpenScore: _openPictures,
                scoreView: _picturePane(),
                introBuilder: _introPanel,
                commentsBuilder: _commentsBody,
                relatedSliver: _relatedSliver(),
                onComment: () => _writeComment(),
              ),
      ),
    );
  }

  Widget _introPanel(BuildContext context) => SliverMainAxisGroup(
    slivers: [
      ScoreIntroPanel(
        title: title,
        author: authorName,
        authorPhoto: resourceUrl(
          _first(['author_photo', 'upload_user_img', 'user_avatar']),
          widget.platform,
        ),
        authorSubtitle: isCc
            ? '虫虫钢琴 · 曲谱发布者'
            : _authorBusy
            ? '发布者资料加载中…'
            : _authorError.isNotEmpty
            ? '发布者资料加载失败 · 点击重试'
            : '弹琴吧 · 曲谱发布者',
        onAuthor: () => _openAuthor(),
        following: _authorFollowing,
        followBusy: _authorFollowBusy,
        onFollow: authorUid.isEmpty ? null : _toggleAuthorFollow,
        stats: statsLine,
        description: [
          _first(['desc', 'info']),
          levelLine,
          _first(['composer', 'singer']),
        ].where((v) => v.isNotEmpty).join('\n'),
        scoreId: widget.id,
        badges: ScoreBadges({...?info, '__platform': widget.platform}),
        actions: [
          ActionItem(
            icon: const Icon(Icons.auto_stories_outlined),
            semanticsLabel: 'AI 谱',
            text: aiLabelOf(info ?? {}, widget.platform) ?? 'AI 谱',
            onTap: _openAiScore,
          ),
          ActionItem(
            icon: const Icon(Icons.star_outline),
            selectIcon: const Icon(Icons.star),
            selectStatus: _collected == true,
            semanticsLabel: '收藏',
            text: _collectCount.isEmpty ? '-' : _collectCount,
            onTap: _collectBusy || _checkingCollect ? null : _toggleCollect,
          ),
          ActionItem(
            icon: const Icon(Icons.download_outlined),
            semanticsLabel: '下载源',
            text: '下载源',
            onTap: _download,
          ),
          if (!isCc) ...[
            ActionItem(
              icon: const Icon(Icons.thumb_up_outlined),
              selectIcon: const Icon(Icons.thumb_up),
              selectStatus: _admireOn == true,
              semanticsLabel: '点赞',
              text: _admireCount > 0 ? '$_admireCount' : '点赞',
              onTap: _toggleAdmire,
            ),
          ],
        ],
      ),
      if (_historyError.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextButton(
              onPressed: _historyBusy ? null : _reportLearningHistory,
              child: Text(_historyError),
            ),
          ),
        ),
      if (_collectError.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('收藏状态暂时无法确认：$_collectError'),
          ),
        ),
    ],
  );

  List<Map<String, dynamic>> get _commentRoots {
    final rows = (comments ?? []).whereType<Map<String, dynamic>>().toList();
    if (isCc) return rows;
    final byId = {for (final row in rows) commentIdOf(row): row};
    final children = <String, List<Map<String, dynamic>>>{};
    final roots = <Map<String, dynamic>>[];
    for (final row in rows) {
      final parent = textOf(row, ['reply_comment_id', 'parent_id']);
      if (parent.isNotEmpty &&
          parent != '0' &&
          parent != commentIdOf(row) &&
          byId.containsKey(parent)) {
        children.putIfAbsent(parent, () => []).add(row);
      } else {
        roots.add(row);
      }
    }
    return [
      for (final row in roots)
        {
          ...row,
          '__children': children[commentIdOf(row)] ?? <Map<String, dynamic>>[],
        },
    ];
  }

  List<Map<String, dynamic>> _repliesOf(Map<String, dynamic> parent) {
    if (isCc) {
      final thread = _replyThreads[commentIdOf(parent)];
      if (thread != null && thread.loaded) return thread.rows;
      for (final key in ['list_reply', 'replys', 'sub_comments', 'replies']) {
        if (parent[key] is List) {
          return (parent[key] as List)
              .whereType<Map<String, dynamic>>()
              .toList();
        }
      }
      return [];
    }
    return (comments ?? [])
        .whereType<Map<String, dynamic>>()
        .where(
          (row) =>
              textOf(row, ['reply_comment_id', 'parent_id']) ==
              commentIdOf(parent),
        )
        .toList();
  }

  Widget _commentTile(Map<String, dynamic> row, {bool preview = true}) {
    final id = commentIdOf(row);
    final replies = preview ? _repliesOf(row) : <Map<String, dynamic>>[];
    final thread = _replyThreads[id];
    final count = int.tryParse('${row['total_reply'] ?? 0}') ?? replies.length;
    return _CommentTile(
      {...row, if (_commentLikes.containsKey(id)) '__liked': _commentLikes[id]},
      isCc: isCc,
      onAvatarTap: (uid, name, photo) =>
          _openAuthor(uid: uid, name: name, photo: photo),
      busy: _commentBusy || _busyComments.contains(id),
      onAction: (c, action) => _commentAction(c, action),
      replies: replies.take(3).toList(),
      replyCount: count > replies.length ? count : replies.length,
      replyBusy: thread?.busy == true,
      replyError: thread?.error ?? '',
      onShowReplies:
          preview &&
              (count > 0 ||
                  replies.isNotEmpty ||
                  thread?.error.isNotEmpty == true)
          ? () => _showReplies(row)
          : null,
    );
  }

  Widget _commentsBody(BuildContext context) {
    final roots = _commentRoots;
    return Stack(
      fit: StackFit.expand,
      children: [
        RefreshIndicator(
          onRefresh: _refreshVisibleComments,
          child: ListView.builder(
            key: const PageStorageKey('score-comments'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: roots.length + 2,
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '最新评论',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              }
              if (index <= roots.length) return _commentTile(roots[index - 1]);
              _scheduleMoreComments();
              if (_commentError.isNotEmpty) {
                return ErrorCenter(
                  _commentError,
                  onRetry: () =>
                      _ensureComment(more: (comments ?? []).isNotEmpty),
                );
              }
              if (_commentBusy) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    roots.isEmpty
                        ? '暂无评论'
                        : _commentsMore
                        ? '加载中…'
                        : '没有更多了',
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'score-reply-${widget.platform}-${widget.id}',
            tooltip: '发表评论',
            onPressed: () => _writeComment(),
            child: const Icon(Icons.reply),
          ),
        ),
      ],
    );
  }

  Future<void> _showReplies(Map<String, dynamic> parent) async {
    if (isCc && _replyThreads[commentIdOf(parent)]?.loaded != true) {
      await _loadReplies(parent);
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheetContext) {
        var scheduled = false;
        return StatefulBuilder(
          builder: (context, update) {
            final rows = _repliesOf(parent);
            final thread = _replyThreads[commentIdOf(parent)];
            final more = isCc ? thread?.more == true : _commentsMore;
            final error = isCc ? thread?.error ?? '' : _commentError;
            void loadMore() {
              if (scheduled || !more || error.isNotEmpty) return;
              scheduled = true;
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                if (!sheetContext.mounted || !mounted) return;
                if (isCc) {
                  await _loadReplies(parent);
                } else {
                  await _ensureComment(more: true);
                }
                scheduled = false;
                if (sheetContext.mounted) update(() {});
              });
            }

            Widget tile(Map<String, dynamic> row) => _CommentTile(
              {
                ...row,
                if (_commentLikes.containsKey(commentIdOf(row)))
                  '__liked': _commentLikes[commentIdOf(row)],
              },
              isCc: isCc,
              onAvatarTap: (uid, name, photo) =>
                  _openAuthor(uid: uid, name: name, photo: photo),
              busy: _busyComments.contains(commentIdOf(row)),
              onAction: (c, action) async {
                await _commentAction(c, action);
                if (sheetContext.mounted) update(() {});
              },
            );
            return SizedBox(
              height: MediaQuery.sizeOf(context).height * .82,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '回复（${rows.length}）',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: rows.length + 2,
                      itemBuilder: (context, index) {
                        if (index == 0) return tile(parent);
                        if (index <= rows.length) return tile(rows[index - 1]);
                        loadMore();
                        if (error.isNotEmpty) {
                          return ErrorCenter(
                            error,
                            onRetry: () async {
                              if (isCc) {
                                await _loadReplies(parent);
                              } else {
                                await _ensureComment(more: true);
                              }
                              if (sheetContext.mounted) update(() {});
                            },
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(child: Text(more ? '加载中…' : '没有更多回复')),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

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
      final parentId = reply == null ? '' : textOf(reply, ['parent_id']);
      final cid = isCc && parentId.isNotEmpty && parentId != '0'
          ? parentId
          : reply == null
          ? ''
          : commentIdOf(reply);
      final dynamic result = isCc
          ? await CcApi.commentAdd(widget.id, text, parentId: cid)
          : await Tan8Api.webAddComment(
              widget.id,
              text,
              uploaderUid: authorUid,
              replyUid: reply?['uid']?.toString(),
              replyUsername: reply?['username']?.toString(),
              replyCommentId: reply == null ? null : commentIdOf(reply),
            );
      ensureWriteSucceeded(result);
      await _refreshVisibleComments();
      final visible = _visibleComments().any(
        (c) => textOf(c, ['message', 'content', 'comment_content']) == text,
      );
      await _refreshCounters();
      SmartDialog.showToast(visible ? '评论已发布' : '请求已提交，评论暂未在列表中出现');
    } catch (e) {
      SmartDialog.showToast('发送失败: $e');
    }
  }

  Future<void> _commentAction(Map<String, dynamic> c, String action) async {
    if (!_guardLogin()) return;
    if (_commentBusy) return;
    if (action == 'refresh') {
      await _refreshVisibleComments();
      return;
    }
    if (action == 'reply') {
      await _writeComment(reply: c);
      return;
    }
    final cid = commentIdOf(c);
    if (cid.isEmpty) {
      SmartDialog.showToast('服务器未返回评论标识');
      return;
    }
    if (_busyComments.contains(cid)) return;
    if (action == 'delete') {
      if (!Sessions.ownsComment(c, isCc: isCc)) {
        SmartDialog.showToast('只能删除自己的评论');
        return;
      }
      final confirmed = await Get.dialog<bool>(
        AlertDialog(
          title: const Text('删除这条评论？'),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Get.back(result: true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _busyComments.add(cid));
    final beforeLikes =
        int.tryParse(textOf(c, ['likes', 'like_num', 'hits'])) ?? 0;
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
      ensureWriteSucceeded(result);
      if (!mounted) return;
      if (action == 'delete') {
        await _refreshVisibleComments();
        if (_commentError.isNotEmpty) throw StateError('操作已提交，暂时无法回读评论状态');
        final found = _visibleComments().where(
          (row) => commentIdOf(row) == cid,
        );
        if (found.isNotEmpty) throw StateError('删除后评论仍在列表中');
        await _refreshCounters();
        SmartDialog.showToast('评论已删除');
      } else {
        final liked = action == 'like';
        final count = (beforeLikes + (liked ? 1 : -1)).clamp(0, 1 << 62);
        setState(() {
          for (final row in _visibleComments().where(
            (row) => commentIdOf(row) == cid,
          )) {
            row[isCc ? 'is_hit' : 'islike'] = liked ? 1 : 0;
            row['likes'] = count;
          }
          _commentLikes[cid] = liked;
        });
      }
    } catch (e) {
      SmartDialog.showToast('操作失败: $e');
    } finally {
      if (mounted) setState(() => _busyComments.remove(cid));
    }
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile(
    this.c, {
    required this.isCc,
    required this.onAvatarTap,
    required this.busy,
    required this.onAction,
    this.replies = const [],
    this.replyCount = 0,
    this.replyBusy = false,
    this.replyError = '',
    this.onShowReplies,
  });
  final Map<String, dynamic> c;
  final bool isCc, busy, replyBusy;
  final void Function(String uid, String name, String photo) onAvatarTap;
  final void Function(Map<String, dynamic>, String) onAction;
  final List<Map<String, dynamic>> replies;
  final int replyCount;
  final String replyError;
  final VoidCallback? onShowReplies;

  @override
  Widget build(BuildContext context) {
    final platform = isCc ? 'cc' : 'tan8';
    final name = userNameOf(c);
    final avatar = userPhotoOf(c, platform);
    final uid = userIdOf(c, platform, allowId: false);
    final liked = flagOf(c[isCc ? 'is_hit' : 'islike']) ?? flagOf(c['__liked']);
    final target = textOf(
      c,
      isCc ? ['parent_nick', 'reply_nickname'] : ['reply_username'],
    );
    return ScoreReplyItem(
      name: name,
      avatar: avatar,
      time: textOf(c, [
        'datetime',
        'addtime',
        'time',
        'create_time',
        'publish_time',
      ]),
      message: textOf(c, ['message', 'content', 'comment_content']),
      replyTarget: target,
      likes: textOf(c, ['likes', 'like_num', 'hits']),
      member: membershipOf(c),
      liked: liked,
      onAvatar: uid.isEmpty ? null : () => onAvatarTap(uid, name, avatar),
      onReply: busy ? null : () => onAction(c, 'reply'),
      onLike: busy
          ? null
          : () => onAction(c, liked == true ? 'unlike' : 'like'),
      onDelete: !busy && Sessions.ownsComment(c, isCc: isCc)
          ? () => onAction(c, 'delete')
          : null,
      replies: [
        for (final reply in replies)
          ScoreReplyPreview(
            name: userNameOf(reply),
            message: textOf(reply, ['message', 'content', 'comment_content']),
            target: textOf(
              reply,
              isCc ? ['parent_nick', 'reply_nickname'] : ['reply_username'],
            ),
            onTap: onShowReplies ?? () => onAction(reply, 'reply'),
          ),
      ],
      replyFooter: onShowReplies == null
          ? null
          : InkWell(
              onTap: replyBusy ? null : onShowReplies,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text(
                  replyError.isNotEmpty
                      ? '回复加载失败，点击重试'
                      : replyBusy
                      ? '回复加载中…'
                      : '共 $replyCount 条回复',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
    );
  }
}

class _ReplyThread {
  List<Map<String, dynamic>> rows = [];
  int page = 1, generation = 0;
  bool busy = false, more = true, loaded = false;
  String error = '';
}
