/// 作者/用户主页(双平台):
/// cc: home/user/getOpernListByUploader + 关注三件套(add/del/isFollowed)。
/// tan8: authorHome 模组(erji_publish_yuepu_2023 等) + follow/delete_follow。
library;

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import '../http/cc_api.dart';
import '../http/tan8_api.dart';
import '../services/sessions.dart';
import '../widgets/common.dart';

class AuthorPage extends StatefulWidget {
  final String platform;
  final String uid;
  final String name;
  final String photo;
  const AuthorPage({
    super.key,
    required this.platform,
    required this.uid,
    this.name = '',
    this.photo = '',
  });

  @override
  State<AuthorPage> createState() => _AuthorPageState();
}

class _AuthorPageState extends State<AuthorPage> {
  List<Map<String, dynamic>> _works = [];
  Map<String, dynamic>? _extra; // tan8 发布/收藏汇总
  int _page = 1;
  bool _loading = true;
  String _error = '';
  bool _noMore = false;
  bool? _following;

  late String _userName = widget.name;

  bool get isCc => widget.platform == 'cc';
  String get name =>
      _userName.isEmpty || _userName == 'null' ? widget.name : _userName;

  @override
  void initState() {
    super.initState();
    _loadFirst();
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final page1 = await _fetchPage(1);
      if (isCc) _loadCcProfile();
      if (!mounted) return;
      setState(() {
        _works = page1;
        _page = 1;
        _loading = false;
        _noMore = page1.isEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadCcProfile() async {
    try {
      if (CcApi.uid == widget.uid ||
          CcApi.userToken == widget.uid ||
          Sessions.ccNumericId == widget.uid) {
        _following = false; // 自己
        if (mounted) setState(() {});
        return;
      }
      final r = await CcApi.followCheck(widget.uid);
      _following = CcApi.flag(r);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _fetchPage(int page) async {
    if (isCc) {
      final raw = await CcApi.opernListByUploader(
        widget.uid,
        page: page,
        size: 20,
      );
      dynamic data = raw;
      if (data is Map<String, dynamic>) data = data['list'] ?? const [];
      final list = (data as List?) ?? const [];
      if (page == 1) {
        for (final e in list) {
          if (e is Map<String, dynamic>) {
            final n =
                (e['upload_user_name'] ?? e['uploader'] ?? e['nickname'] ?? '')
                    .toString();
            if (n.isNotEmpty) {
              _userName = n;
              break;
            }
          }
        }
      }
      return list
          .whereType<Map<String, dynamic>>()
          .map((e) => e..['__platform'] = 'cc')
          .toList();
    }
    if (page == 1) {
      // tan8: 作者页模组(发布/收藏流)
      final mods = await Tan8Api.authorHome(widget.uid);
      final out = <Map<String, dynamic>>[];
      for (final m in mods.whereType<Map<String, dynamic>>()) {
        final result = m['result'];
        if (result is! Map) continue;
        for (final g in ((result['result'] as List?) ?? const [])) {
          if (g is Map<String, dynamic>) {
            if (g['id']?.toString().isNotEmpty == true) {
              out.add(g..['__platform'] = 'tan8');
            } else if (g['result'] is List) {
              for (final it in (g['result'] as List)) {
                if (it is Map<String, dynamic> &&
                    it['id']?.toString().isNotEmpty == true) {
                  out.add(it..['__platform'] = 'tan8');
                }
              }
            }
          }
        }
      }
      final sum = await Tan8Api.authorSummary(widget.uid);
      if (mounted) setState(() => _extra = sum);
      return out;
    }
    return const [];
  }

  Future<void> _loadMore() async {
    if (_loading || _noMore) return;
    try {
      final more = await _fetchPage(_page + 1);
      if (more.isEmpty) {
        _noMore = true;
      } else {
        _page++;
      }
      if (mounted) setState(() => _works.addAll(more));
    } catch (_) {
      _noMore = true;
      if (mounted) setState(() {});
    }
  }

  Future<void> _toggleFollow() async {
    if (isCc) {
      if (!Sessions.ccLoggedIn) {
        SmartDialog.showToast('请先登录虫虫账号');
        return;
      }
      try {
        final on = _following == true;
        if (on) {
          await CcApi.followDel(widget.uid);
        } else {
          await CcApi.followAdd(widget.uid);
        }
        _following = CcApi.flag(await CcApi.followCheck(widget.uid));
        if (_following == on) throw StateError('服务器返回的关注状态未改变');
        SmartDialog.showToast(_following! ? '已关注' : '已取消关注');
      } catch (e) {
        SmartDialog.showToast('操作失败: $e');
      }
      if (mounted) setState(() {});
      return;
    }
    if (!Sessions.tan8LoggedIn) {
      SmartDialog.showToast('请先登录弹琴吧账号');
      return;
    }
    try {
      final on = _following == true;
      final r = await Tan8Api.follow(widget.uid, !on);
      _following = !on;
      final msg = (r is Map ? (r['msg'] ?? r['message'] ?? '') : r).toString();
      SmartDialog.showToast(
        msg.isEmpty ? (_following! ? '已关注' : '已取消关注') : msg,
      );
      // 重新校对状态
      final l = await Tan8Api.myFollowLists(Sessions.tan8Uid, num: 100);
      final f = l['following']!;
      _following = f.any(
        (e) => e is Map && '${e['uid'] ?? e['id']}' == widget.uid,
      );
    } catch (e) {
      SmartDialog.showToast('操作失败: $e');
    }
    if (mounted) setState(() {});
  }

  String get _ccPhoto => widget.photo; // cc 详情已传完整头像 URL

  @override
  Widget build(BuildContext context) {
    final isSelf =
        isCc &&
        (CcApi.uid == widget.uid ||
            CcApi.userToken == widget.uid ||
            Sessions.ccNumericId == widget.uid);
    return Scaffold(
      appBar: AppBar(
        title: Text('作者主页', style: Theme.of(context).textTheme.titleMedium),
      ),
      body: _loading
          ? const LoadingCenter()
          : _error.isNotEmpty
          ? ErrorCenter(_error, onRetry: _loadFirst)
          : RefreshIndicator(
              onRefresh: _loadFirst,
              child: ListView(
                padding: const EdgeInsets.only(bottom: pageBottomScrollSpace),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        _Avatar(photo: _ccPhoto, name: name),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              PlatformBadge(widget.platform, fontSize: 10),
                              const SizedBox(height: 4),
                              Text(
                                name.isEmpty ? widget.uid : name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                isCc
                                    ? 'ID: ${widget.uid}'
                                    : 'UID: ${widget.uid}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isSelf)
                          FilledButton.tonal(
                            onPressed: (_following == null && isCc)
                                ? null
                                : _toggleFollow,
                            child: Text(_following == true ? '已关注' : '关注'),
                          ),
                      ],
                    ),
                  ),
                  if (!isCc && _extra != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          _Stat(
                            '发布',
                            '${(_extra!['publish'] is Map) ? ((_extra!['publish'] as Map)['total'] ?? '') : '-'}',
                          ),
                          _Stat(
                            '收藏',
                            '${(_extra!['collect'] is Map) ? ((_extra!['collect'] as Map)['total'] ?? '') : '-'}',
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  const Divider(height: 1),
                  for (final w in _works) ScoreRow(w),
                  if (_works.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          '暂无曲谱',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  if (!_noMore && !_loading)
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: OutlinedButton(
                        onPressed: _loadMore,
                        child: const Text('加载更多'),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String photo;
  final String name;
  const _Avatar({required this.photo, required this.name});

  @override
  Widget build(BuildContext context) {
    final url = photo.startsWith('http') ? photo : '';
    return CircleAvatar(
      radius: 30,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      backgroundImage: url.startsWith('http') ? NetworkImage(url) : null,
      child: url.startsWith('http')
          ? null
          : Text(
              name.isEmpty ? '?' : name[0],
              style: const TextStyle(fontSize: 22),
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
