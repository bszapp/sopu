// Copied/adapted from PiliPlus pages/member/view.dart and member_favorite/view.dart.
// GPL-3.0-or-later. Controllers/models are replaced by the two score platforms.
import 'package:flutter/material.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import '../http/cc_api.dart';
import '../http/http.dart';
import '../http/tan8_api.dart';
import '../services/sessions.dart';
import '../utils/data_fields.dart';
import '../widgets/common.dart';
import '../widgets/piliplus/dynamic_sliver_app_bar/dynamic_sliver_app_bar.dart';
import '../widgets/piliplus/member_info_card.dart';
import '../widgets/piliplus/score_card_h.dart';
import '../widgets/piliplus/scroll_behavior.dart';

class AuthorPage extends StatefulWidget {
  const AuthorPage({
    super.key,
    required this.platform,
    required this.uid,
    this.name = '',
    this.photo = '',
  });
  final String platform, uid, name, photo;
  @override
  State<AuthorPage> createState() => _AuthorPageState();
}

class _AuthorPageState extends State<AuthorPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Map<String, dynamic> _profile = {}, _extra = {};
  bool _loading = true, _followBusy = false;
  bool? _following;
  String _profileError = '', _followError = '';
  late String _accountKey;
  late String _name = widget.name;
  late String _photo = resourceUrl(widget.photo, widget.platform);
  bool get isCc => widget.platform == 'cc';
  String get _accountIdentity => isCc
      ? Sessions.ccIdentityKey
      : '${Sessions.tan8LoggedIn}:${Sessions.tan8Uid}';
  bool get _isSelf => isCc
      ? Sessions.ccNumericId == widget.uid
      : Sessions.tan8Uid == widget.uid;
  late final bool _showCollections = !isCc || _isSelf;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _showCollections ? 2 : 1,
      vsync: this,
    );
    _accountKey = _accountIdentity;
    Sessions.changed.addListener(_accountChanged);
    _loadProfile().whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
    _loadFollow();
  }

  void _accountChanged() {
    if (!mounted || _accountKey == _accountIdentity) return;
    setState(() {
      _accountKey = _accountIdentity;
      _following = null;
    });
    _loadFollow();
  }

  @override
  void dispose() {
    Sessions.changed.removeListener(_accountChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final data = isCc
          ? (_isSelf ? await CcApi.me() : await CcApi.userProfile(widget.uid))
          : await Tan8Api.userProfile(widget.uid);
      if (!mounted) return;
      setState(() {
        _profile = data;
        _loading = false;
        if (userNameOf(data).isNotEmpty) _name = userNameOf(data);
        if (userPhotoOf(data, widget.platform).isNotEmpty) {
          _photo = userPhotoOf(data, widget.platform);
        }
        _profileError = '';
      });
    } catch (e) {
      if (mounted) setState(() => _profileError = '资料加载失败，点击重试：$e');
    }
    if (!isCc) {
      try {
        final summary = await Tan8Api.authorSummary(widget.uid);
        if (mounted) setState(() => _extra = summary);
      } catch (e) {
        if (mounted) {
          setState(() => _profileError = '作品统计加载失败，点击重试：$e');
        }
      }
    }
  }

  Future<void> _loadFollow() async {
    if (_isSelf || !(isCc ? Sessions.ccLoggedIn : Sessions.tan8LoggedIn)) {
      return;
    }
    final account = _accountIdentity;
    try {
      final followed = isCc
          ? CcApi.flag(await CcApi.followCheck(widget.uid))
          : await Tan8Api.isFollowing(Sessions.tan8Uid, widget.uid);
      if (!mounted || account != _accountIdentity) return;
      setState(() {
        _following = followed;
        _followError = '';
      });
    } catch (e) {
      if (mounted && account == _accountIdentity) {
        setState(() => _followError = '关注状态读取失败：$e');
      }
    }
  }

  Future<void> _toggleFollow() async {
    if (_followBusy || _isSelf) return;
    if (!(isCc ? Sessions.ccLoggedIn : Sessions.tan8LoggedIn)) {
      SmartDialog.showToast('请先登录${isCc ? '虫虫' : '弹琴吧'}账号');
      return;
    }
    if (_following == null) await _loadFollow();
    if (_following == null || !mounted) return;
    final original = _following!;
    setState(() => _followBusy = true);
    try {
      if (isCc) {
        if (original) {
          await CcApi.followDel(widget.uid);
        } else {
          await CcApi.followAdd(widget.uid);
        }
      } else {
        ensureWriteSucceeded(await Tan8Api.follow(widget.uid, !original));
      }
      await _loadFollow();
      if (_following == null || _following == original) {
        throw StateError('服务器未确认关注状态变化');
      }
      SmartDialog.showToast(_following! ? '已关注' : '已取消关注');
    } catch (e) {
      SmartDialog.showToast('关注操作失败：$e');
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPage(String scope, int page) async {
    if (isCc) {
      if (scope == 'collect' && (!_isSelf || !Sessions.ccLoggedIn)) {
        throw StateError('请登录本人账号后查看收藏');
      }
      final raw = scope == 'collect'
          ? await CcApi.myCollectList(page: page)
          : await CcApi.opernListByUploader(widget.uid, page: page);
      return itemsOf(raw)
          .whereType<Map<String, dynamic>>()
          .map((e) => {...e, '__platform': 'cc'})
          .toList();
    }
    final mods = await Tan8Api.authorWorks(
      widget.uid,
      scope: scope,
      start: (page - 1) * 20,
      limit: 20,
    );
    final rows = <Map<String, dynamic>>[];
    void append(dynamic raw) {
      if (raw is List) {
        for (final e in raw) {
          append(e);
        }
      }
      if (raw is Map<String, dynamic>) {
        if (raw['id']?.toString().isNotEmpty == true &&
            ScoreCard.titleOf(raw).isNotEmpty) {
          rows.add({...raw, '__platform': 'tan8'});
        } else {
          for (final key in ['result', 'dataList', 'list']) {
            if (raw[key] != null) append(raw[key]);
          }
        }
      }
    }

    for (final mod in mods.whereType<Map>()) {
      append(mod['result']);
    }
    return rows;
  }

  Map<String, String> get _stats {
    final result = <String, String>{};
    final keys = isCc
        ? {
            '粉丝': 'total_fans_num',
            '关注': 'total_follow_num',
            '获藏': 'total_collect_by_num',
          }
        : {'粉丝': 'fansCount', '关注': 'followCount', '获赞': 'yuepuGetLikeCount'};
    for (final e in keys.entries) {
      final value = textOf(_profile, [e.value]);
      if (value.isNotEmpty) result[e.key] = value;
    }
    if (result.isEmpty && _extra.isNotEmpty) {
      for (final e in {'发布': 'publish', '收藏': 'collect'}.entries) {
        final data = _extra[e.value];
        if (data is Map && data['pianoCount'] != null) {
          result[e.key] = '${data['pianoCount']}';
        }
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final padding = MediaQuery.viewPaddingOf(context);
    final member = membershipOf(_profile);
    return Material(
      color: scheme.surface,
      child: _loading
          ? const LoadingCenter()
          : ExtendedNestedScrollView(
              onlyOneScrollInBody: true,
              scrollBehavior: const NoOverscrollIndicator(),
              pinnedHeaderSliverHeightBuilder: () =>
                  kToolbarHeight + padding.top,
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                DynamicSliverAppBar.medium(
                  title: Text(_name.isEmpty ? widget.uid : _name),
                  flexibleSpace: MemberInfoCard(
                    name: _name,
                    avatar: _photo,
                    header: resourceUrl(
                      textOf(_profile, ['home_photo', 'background_image']),
                      widget.platform,
                    ),
                    description: textOf(_profile, [
                      'personal_profile',
                      'self_introduction',
                      'signature',
                    ]),
                    uid: widget.uid,
                    platform: widget.platform,
                    stats: _stats,
                    badges: [
                      ?member,
                      if (flagOf(_profile['is_teacher']) == true) '教师',
                      if (flagOf(_profile['is_yinyueren']) == true) '音乐人',
                    ],
                    isOwner: _isSelf,
                    following: _following,
                    followBusy: _followBusy,
                    onFollow: _toggleFollow,
                    error: [
                      _profileError,
                      _followError,
                    ].where((e) => e.isNotEmpty).join('\n'),
                    onRetry: () {
                      _loadProfile();
                      _loadFollow();
                    },
                  ),
                ),
              ],
              body: Padding(
                padding: EdgeInsets.only(
                  left: padding.left,
                  right: padding.right,
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 45,
                      child: TabBar(
                        labelPadding: EdgeInsets.zero,
                        controller: _tabController,
                        tabs: [
                          const Tab(text: '发布'),
                          if (_showCollections) const Tab(text: '收藏'),
                        ],
                        dividerColor: scheme.outline.withValues(alpha: .2),
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          for (final scope in [
                            'publish',
                            if (_showCollections) 'collect',
                          ])
                            _AuthorWorksTab(
                              key: ValueKey(
                                '${widget.platform}:${widget.uid}:$scope:$_accountKey',
                              ),
                              scope: scope,
                              fetch: (page) => _fetchPage(scope, page),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _AuthorWorksTab extends StatefulWidget {
  const _AuthorWorksTab({super.key, required this.scope, required this.fetch});
  final String scope;
  final Future<List<Map<String, dynamic>>> Function(int page) fetch;
  @override
  State<_AuthorWorksTab> createState() => _AuthorWorksTabState();
}

class _AuthorWorksTabState extends State<_AuthorWorksTab>
    with AutomaticKeepAliveClientMixin {
  final _items = <Map<String, dynamic>>[];
  bool _busy = false, _end = false, _scheduled = false;
  String _error = '';
  int _page = 1, _generation = 0;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_busy) return;
    final generation = ++_generation;
    if (refresh) {
      _page = 1;
      _end = false;
    }
    if (_end) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final rows = await widget.fetch(_page);
      if (!mounted || generation != _generation) return;
      final known = refresh ? <String>{} : _items.map(ScoreCard.idOf).toSet();
      final fresh = rows.where((e) => known.add(ScoreCard.idOf(e))).toList();
      if (rows.isNotEmpty && fresh.isEmpty) throw StateError('服务器重复返回上一页');
      setState(() {
        if (refresh) _items.clear();
        _items.addAll(fresh);
        _page++;
        _end = rows.isEmpty;
      });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = '$e');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _scheduleMore() {
    if (_scheduled || _busy || _end || _error.isNotEmpty) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: CustomScrollView(
        key: PageStorageKey('author-${widget.scope}'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 600,
              mainAxisExtent: 110,
              mainAxisSpacing: 2,
            ),
            itemCount: _items.length,
            itemBuilder: (context, index) => ScoreCardH(_items[index]),
          ),
          SliverList.builder(
            itemCount: 1,
            itemBuilder: (context, index) {
              _scheduleMore();
              if (_error.isNotEmpty) return ErrorCenter(_error, onRetry: _load);
              if (_busy) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Center(child: Text(_items.isEmpty ? '暂无曲谱' : '没有更多了')),
              );
            },
          ),
        ],
      ),
    );
  }
}
