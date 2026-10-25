/// 我的列表页: tan8 收藏/浏览历史/关注与粉丝列表 / cc 收藏(我的曲谱)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import '../http/cc_api.dart';
import '../http/tan8_api.dart';
import '../services/sessions.dart';
import '../widgets/common.dart';
import 'author_page.dart';
import 'playlist_page.dart';
import '../utils/data_fields.dart';

class MineListPage extends StatefulWidget {
  final String
  kind; // tan8_collect | tan8_history | tan8_follow | tan8_fans | cc_collect
  const MineListPage({super.key, required this.kind});

  @override
  State<MineListPage> createState() => _MineListPageState();
}

class _MineListPageState extends State<MineListPage> {
  static const _titles = {
    'history': '浏览历史',
    'tan8_collect': '我的收藏(弹琴吧)',
    'tan8_history': '浏览历史(弹琴吧)',
    'tan8_follow': '关注列表(弹琴吧)',
    'tan8_fans': '粉丝列表(弹琴吧)',
    'cc_collect': '我的收藏(虫虫)',
    'cc_follow': '关注列表(虫虫)',
    'cc_fans': '粉丝列表(虫虫)',
    'cc_history': '浏览历史(虫虫)',
    'tan8_likes': '我的点赞(弹琴吧)',
    'tan8_playlists': '我的歌单(弹琴吧)',
  };

  bool _loading = true;
  String _error = '';
  List<dynamic> _items = [];
  bool _isUserList = false;
  int _page = 1, _start = 0;
  bool _hasMore = true, _loadingMore = false;
  String _moreError = '';
  final List<String> _historyNotices = [];
  int _tan8HistoryStart = 0;
  int _ccHistoryPage = 1;
  bool _tan8HistoryMore = true;
  bool _ccHistoryMore = true;
  bool _historyLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get isCc => widget.kind.startsWith('cc_');

  Future<void> _load({bool more = false}) async {
    if (widget.kind == 'history') {
      await _loadHistory(reset: true);
      return;
    }
    if (more && (_loading || _loadingMore || !_hasMore)) return;
    if (!more) {
      _page = 1;
      _start = 0;
      _hasMore = true;
    }
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = '';
      }
      _moreError = '';
    });
    _isUserList =
        widget.kind.endsWith('_follow') || widget.kind.endsWith('_fans');
    try {
      dynamic r;
      switch (widget.kind) {
        case 'tan8_collect':
          r = await Tan8Api.myCollectList(start: _start);
          break;
        case 'tan8_history':
          r = await Tan8Api.myBrowseHistory(start: _start);
          break;
        case 'tan8_likes':
          r = await Tan8Api.myLikeList(start: _start);
          break;
        case 'tan8_playlists':
          r = await Tan8Api.myPlaylists();
          break;
        case 'cc_follow':
        case 'cc_fans':
          _isUserList = true;
          r = widget.kind == 'cc_follow'
              ? await CcApi.myFollowList(page: _page)
              : await CcApi.myFansList(page: _page);
          break;
        case 'tan8_follow':
        case 'tan8_fans':
          _isUserList = true;
          final lists = await Tan8Api.myFollowLists(
            Sessions.tan8Uid,
            start: _start,
          );
          r = widget.kind == 'tan8_follow'
              ? lists['following']
              : lists['followers'];
          break;
        case 'cc_collect':
          r = await CcApi.myCollectList(page: _page);
          break;
        case 'cc_history':
          r = await CcApi.combinedBrowseHistory(page: _page);
          break;
        default:
          r = const [];
      }
      if (!mounted) return;
      final rows = r == '' ? <dynamic>[] : itemsOf(r);
      if (more && rows.isNotEmpty) {
        String key(dynamic value) => value is Map<String, dynamic>
            ? (_isUserList
                  ? userIdOf(value, isCc ? 'cc' : 'tan8')
                  : ScoreCard.idOf(value))
            : '$value';
        final known = _items.map(key).where((id) => id.isNotEmpty).toSet();
        if (widget.kind != 'cc_history' &&
            rows.every((row) => known.contains(key(row)))) {
          throw StateError('服务器重复返回上一页，暂时无法继续翻页');
        }
      }
      final totalPages = r is Map ? int.tryParse('${r['total_pages']}') : null;
      setState(() {
        if (!more) _items = [];
        if (widget.kind == 'cc_history') {
          final seen = _items
              .whereType<Map<String, dynamic>>()
              .map(ScoreCard.idOf)
              .toSet();
          _items.addAll(
            rows.whereType<Map<String, dynamic>>().where(
              (row) => seen.add(ScoreCard.idOf(row)),
            ),
          );
        } else {
          _items.addAll(rows);
        }
        _start += rows.length;
        _hasMore =
            widget.kind != 'tan8_playlists' &&
            rows.isNotEmpty &&
            (totalPages == null || _page < totalPages) &&
            (r is! Map || r['has_more'] != false);
        _page++;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (more) {
          _moreError = '$e';
        } else {
          _error = '$e';
        }
      });
    }
  }

  Future<void> _loadHistory({required bool reset}) async {
    if (!reset && _historyLoadingMore) return;
    if (reset) {
      _tan8HistoryStart = 0;
      _ccHistoryPage = 1;
      _tan8HistoryMore = true;
      _ccHistoryMore = true;
      setState(() {
        _loading = true;
        _error = '';
        _items = [];
      });
    } else {
      setState(() => _historyLoadingMore = true);
    }
    final notices = <String>[];
    Future<List<Map<String, dynamic>>> fetch(String platform) async {
      final isTan8 = platform == 'tan8';
      final name = isTan8 ? '弹琴吧' : '虫虫';
      if (!(isTan8 ? Sessions.tan8LoggedIn : Sessions.ccLoggedIn)) {
        notices.add('$name未登录');
        return [];
      }
      if (!reset && !(isTan8 ? _tan8HistoryMore : _ccHistoryMore)) return [];
      try {
        final dynamic raw = isTan8
            ? await Tan8Api.myBrowseHistory(start: _tan8HistoryStart)
            : await CcApi.combinedBrowseHistory(page: _ccHistoryPage);
        final dynamic data = raw is List
            ? raw
            : (raw is Map ? raw['list'] : null);
        if (data is! List) throw const FormatException('服务器未返回可识别的历史列表');
        if (isTan8) {
          _tan8HistoryStart += data.length;
          _tan8HistoryMore = data.isNotEmpty;
        } else {
          _ccHistoryPage++;
          _ccHistoryMore = raw is Map
              ? raw['has_more'] != false
              : data.isNotEmpty;
          if (raw is Map && raw['warnings'] is List) {
            notices.addAll((raw['warnings'] as List).map((e) => '$e'));
          }
        }
        return data
            .whereType<Map<String, dynamic>>()
            .map((item) => <String, dynamic>{...item, '__platform': platform})
            .toList();
      } catch (e) {
        notices.add('$name历史加载失败：$e');
        return [];
      }
    }

    final lists = await Future.wait([fetch('tan8'), fetch('cc')]);
    final merged = <Map<String, dynamic>>[];
    for (var i = 0; i < lists[0].length || i < lists[1].length; i++) {
      if (i < lists[0].length) merged.add(lists[0][i]);
      if (i < lists[1].length) merged.add(lists[1][i]);
    }
    if (!mounted) return;
    setState(() {
      _historyNotices
        ..clear()
        ..addAll(notices);
      final seen = _items
          .whereType<Map<String, dynamic>>()
          .map((row) => '${row['__platform']}:${ScoreCard.idOf(row)}')
          .toSet();
      _items.addAll(
        merged.where(
          (row) => seen.add('${row['__platform']}:${ScoreCard.idOf(row)}'),
        ),
      );
      _loading = false;
      _historyLoadingMore = false;
    });
  }

  Widget _historyBody() => RefreshIndicator(
    onRefresh: () => _loadHistory(reset: true),
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        if (_historyNotices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(_historyNotices.join('\n')),
          ),
        for (final item in _items) _rowOf(item),
        if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('暂无浏览记录')),
          ),
        if (_historyLoadingMore) const LoadingCenter(),
        if (!_historyLoadingMore &&
            ((Sessions.tan8LoggedIn && _tan8HistoryMore) ||
                (Sessions.ccLoggedIn && _ccHistoryMore)))
          Padding(
            padding: const EdgeInsets.all(14),
            child: OutlinedButton(
              onPressed: () => _loadHistory(reset: false),
              child: const Text('加载更多'),
            ),
          ),
      ],
    ),
  );

  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '歌单名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    try {
      await Tan8Api.createPlaylist(title);
      await _load();
    } catch (e) {
      SmartDialog.showToast('创建失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[widget.kind] ?? '列表'),
        actions: [
          if (widget.kind == 'tan8_playlists')
            IconButton(
              onPressed: _loading ? null : _createPlaylist,
              icon: const Icon(Icons.add),
              tooltip: '新建歌单',
            ),
          if (widget.kind == 'history')
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
            ),
        ],
      ),
      body: _loading
          ? const LoadingCenter()
          : widget.kind == 'history'
          ? _historyBody()
          : _error.isNotEmpty
          ? ErrorCenter(_error, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: _items.length + 1,
                itemBuilder: (_, i) => i == _items.length
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            if (_items.isEmpty) const Text('暂无数据'),
                            if (_moreError.isNotEmpty) Text(_moreError),
                            if (_loadingMore) const CircularProgressIndicator(),
                            if (_hasMore && !_loadingMore)
                              OutlinedButton(
                                onPressed: () => _load(more: true),
                                child: Text(_moreError.isEmpty ? '加载更多' : '重试'),
                              ),
                          ],
                        ),
                      )
                    : _isUserList
                    ? _UserRow(
                        _userOf(_items[i]),
                        platform: isCc ? 'cc' : 'tan8',
                      )
                    : _rowOf(_items[i]),
              ),
            ),
    );
  }

  Widget _rowOf(dynamic item) {
    if (item is! Map<String, dynamic>) {
      return ListTile(title: Text('$item'));
    }
    // tan8 收藏列表项内嵌曲谱 info
    final info = item['info'];
    final m = <String, dynamic>{
      ...item,
      if (info is Map<String, dynamic>) ...info,
    };
    m['__platform'] = item['__platform'] ?? (isCc ? 'cc' : 'tan8');
    if (widget.kind == 'tan8_playlists') {
      final id = textOf(m, ['id', 'albumId']);
      final title = textOf(m, ['title', 'name']);
      return ListTile(
        leading: const Icon(Icons.queue_music),
        title: Text(title),
        subtitle: Text('${m['yuepuCounts'] ?? '-'} 首'),
        trailing: const Icon(Icons.chevron_right),
        onTap: id.isEmpty
            ? null
            : () async {
                await Get.to(() => PlaylistPage(id: id, title: title));
                if (mounted) _load();
              },
      );
    }
    return ScoreRow(m);
  }

  Map<String, dynamic> _userOf(dynamic u) {
    if (u is Map<String, dynamic>) return u;
    return {'uid': '$u'};
  }
}

class _UserRow extends StatelessWidget {
  final Map<String, dynamic> u;
  final String platform;
  const _UserRow(this.u, {required this.platform});

  @override
  Widget build(BuildContext context) {
    final name = userNameOf(u), uid = userIdOf(u, platform);
    final full = userPhotoOf(u, platform);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: UserAvatar(url: full, name: name),
        title: Row(
          children: [
            Expanded(
              child: Text(
                name.isEmpty ? '用户' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (membershipOf(u) != null) StatusBadge(membershipOf(u)!),
          ],
        ),
        subtitle: Text('UID: $uid', style: const TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          if (uid.isEmpty) {
            SmartDialog.showToast('无有效用户 id');
            return;
          }
          Get.to(
            () => AuthorPage(
              platform: platform,
              uid: uid,
              name: name,
              photo: full,
            ),
          );
        },
      ),
    );
  }
}
