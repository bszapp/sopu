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

  Future<void> _load() async {
    if (widget.kind == 'history') {
      await _loadHistory(reset: true);
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      dynamic r;
      switch (widget.kind) {
        case 'tan8_collect':
          r = await Tan8Api.myCollectList();
          break;
        case 'tan8_history':
          r = await Tan8Api.myBrowseHistory();
          break;
        case 'tan8_likes':
          r = await Tan8Api.myLikeList();
          break;
        case 'tan8_playlists':
          r = await Tan8Api.myPlaylists();
          break;
        case 'cc_follow':
        case 'cc_fans':
          _isUserList = true;
          r = widget.kind == 'cc_follow'
              ? await CcApi.myFollowList()
              : await CcApi.myFansList();
          break;
        case 'tan8_follow':
        case 'tan8_fans':
          _isUserList = true;
          final lists = await Tan8Api.myFollowLists(Sessions.tan8Uid);
          r = widget.kind == 'tan8_follow'
              ? lists['following']
              : lists['followers'];
          break;
        case 'cc_collect':
          r = await CcApi.myCollectList();
          if (r is Map<String, dynamic>) r = r['list'] ?? const [];
          break;
        case 'cc_history':
          r = await CcApi.myBrowseHistory();
          break;
        default:
          r = const [];
      }
      if (!mounted) return;
      setState(() {
        _items = r is List
            ? r
            : (r is Map && r['list'] is List ? r['list'] as List : const []);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
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
            : await CcApi.myBrowseHistory(page: _ccHistoryPage);
        final dynamic data = raw is List
            ? raw
            : (raw is Map ? raw['list'] : null);
        if (data is! List) throw const FormatException('服务器未返回可识别的历史列表');
        if (isTan8) {
          _tan8HistoryStart += data.length;
          _tan8HistoryMore = data.isNotEmpty;
        } else {
          _ccHistoryPage++;
          _ccHistoryMore = data.isNotEmpty;
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
      _items.addAll(merged);
      _loading = false;
      _historyLoadingMore = false;
    });
  }

  Widget _historyBody() => RefreshIndicator(
    onRefresh: () => _loadHistory(reset: true),
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: pageBottomScrollSpace),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[widget.kind] ?? '列表'),
        actions: [
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
          : _items.isEmpty
          ? const Center(
              child: Text('暂无数据', style: TextStyle(color: Colors.grey)),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: pageBottomScrollSpace),
              itemCount: _items.length,
              itemBuilder: (_, i) => _isUserList
                  ? _UserRow(_userOf(_items[i]), platform: isCc ? 'cc' : 'tan8')
                  : _rowOf(_items[i]),
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
      return ListTile(title: Text('${m['title'] ?? m['name'] ?? m}'));
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
    final name =
        (u['username'] ?? u['webname'] ?? u['nickname'] ?? u['name'] ?? '用户')
            .toString();
    final uid = (u['uid'] ?? u['user_id'] ?? u['id'] ?? '').toString();
    final av = (u['user_avatar'] ?? u['avatar'] ?? u['face'] ?? '').toString();
    final full = av.startsWith('http') ? av : (av.isEmpty ? '' : 'https:$av');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest,
          backgroundImage: full.startsWith('http') ? NetworkImage(full) : null,
          child: full.startsWith('http')
              ? null
              : Text(
                  name.isEmpty ? '?' : name[0],
                  style: const TextStyle(fontSize: 14),
                ),
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
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
