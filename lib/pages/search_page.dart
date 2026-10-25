/// 混合搜索页: 两平台并搜, 平台徽章区分, 平台筛选, 分页加载。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../http/cc_api.dart';
import '../http/tan8_api.dart';
import '../widgets/common.dart';
import '../widgets/piliplus/score_card_h.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with AutomaticKeepAliveClientMixin {
  final _kwController = TextEditingController();
  final _result = <Map<String, dynamic>>[];
  bool _loading = false;
  String _error = '';
  // 平台筛选: all / tan8 / cc
  String _filter = 'all';

  int _tan8Start = 0;
  int _ccPage = 2;
  bool _loadingMore = false;
  bool _tan8More = true, _ccMore = true;
  String _moreError = '';
  String _notice = '';
  bool get _canLoadMore =>
      (_filter != 'cc' && _tan8More) || (_filter != 'tan8' && _ccMore);

  Timer? _debounce;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _kwController.addListener(() {
      _debounce?.cancel();
      _requestGeneration++;
      setState(() {
        _result.clear();
        _error = '';
        _loading = _kwController.text.trim().isNotEmpty;
      });
      _debounce = Timer(const Duration(milliseconds: 500), () {
        if (_kwController.text.trim().isNotEmpty) {
          _doSearch();
        }
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _kwController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _doSearch() async {
    _debounce?.cancel();
    final kw = _kwController.text.trim();
    final generation = ++_requestGeneration;
    if (kw.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    _result.clear();
    _tan8Start = 20;
    _ccPage = 2;
    _tan8More = _ccMore = true;
    _loadingMore = false;
    _moreError = '';
    _notice = '';
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final failures = <String, String>{};
      final responses = await Future.wait<dynamic>([
        Tan8Api.search(kw, limit: 20, start: 0).catchError((Object e) {
          failures['tan8'] = '弹琴吧：$e';
          return <String, dynamic>{'result': <dynamic>[]};
        }),
        CcApi.searchSongs(kw, page: 1, size: 20).catchError((Object e) {
          failures['cc'] = '虫虫：$e';
          return <dynamic>[];
        }),
      ]);
      final r1 = responses[0] as Map<String, dynamic>;
      final r2 = responses[1] as List;
      if (!mounted || generation != _requestGeneration) return;
      if (failures.length == 2) throw StateError(failures.values.join('\n'));
      _notice = failures.values.join('\n');
      final tan8Items = ((r1['result'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((e) => e..['__platform'] = 'tan8')
          .where((e) => (e['id'] ?? '').toString().isNotEmpty)
          .toList();
      final ccItems = r2
          .whereType<Map<String, dynamic>>()
          .map((e) => e..['__platform'] = 'cc')
          .toList();
      _tan8Start = tan8Items.length;
      _tan8More = tan8Items.isNotEmpty || failures.containsKey('tan8');
      _ccMore = ccItems.isNotEmpty || failures.containsKey('cc');
      _ccPage = ccItems.isNotEmpty ? 2 : 1;
      // 交错合并, 徽章区分
      final merged = <Map<String, dynamic>>[];
      final maxLen = [
        tan8Items.length,
        ccItems.length,
      ].reduce((a, b) => a > b ? a : b);
      for (var i = 0; i < maxLen; i++) {
        if (i < ccItems.length) merged.add(ccItems[i]);
        if (i < tan8Items.length) merged.add(tan8Items[i]);
      }
      _result.addAll(merged);
      _loading = false;
      setState(() {});
    } catch (e) {
      if (!mounted || generation != _requestGeneration) return;
      _loading = false;
      setState(() => _error = '$e');
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || _error.isNotEmpty || !_canLoadMore) return;
    setState(() => _loadingMore = true);
    final generation = _requestGeneration;
    final keyword = _kwController.text.trim();
    try {
      if (_filter != 'cc' && _tan8More) {
        final more = await Tan8Api.search(
          keyword,
          limit: 20,
          start: _tan8Start,
        );
        if (!mounted || generation != _requestGeneration) return;
        final items = ((more['result'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((e) => e..['__platform'] = 'tan8')
            .toList();
        if (items.isEmpty) {
          _tan8More = false;
        } else {
          _tan8Start += items.length;
          _result.addAll(items);
        }
      }
      if (_filter != 'tan8' && _ccMore) {
        final more = await CcApi.searchSongs(keyword, page: _ccPage, size: 20);
        if (!mounted || generation != _requestGeneration) return;
        final items = more
            .whereType<Map<String, dynamic>>()
            .map((e) => e..['__platform'] = 'cc')
            .toList();
        if (items.isNotEmpty) {
          _ccPage++;
          _result.addAll(items);
        } else {
          _ccMore = false;
        }
      }
      _moreError = '';
    } catch (e) {
      if (mounted && generation == _requestGeneration) _moreError = '$e';
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loadingMore = false);
      }
    }
  }

  // Tab decoration and horizontal card grid copied from PiliPlus search_result
  // and search_panel/video. Only platform filters and score models differ.
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final visible = _result
        .where((item) => _filter == 'all' || item['__platform'] == _filter)
        .toList();
    return DefaultTabController(
      length: 3,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: TextField(
              controller: _kwController,
              decoration: InputDecoration(
                hintText: '搜索两平台曲谱',
                border: InputBorder.none,
                suffixIcon: _kwController.text.isEmpty
                    ? const Icon(Icons.search)
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _kwController.clear,
                      ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _doSearch(),
            ),
            pinned: true,
            floating: true,
            automaticallyImplyLeading: false,
            centerTitle: false,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(52),
              child: TabBar(
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                splashFactory: NoSplash.splashFactory,
                padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
                tabs: const [
                  Tab(text: '全部'),
                  Tab(text: '弹琴吧'),
                  Tab(text: '虫虫钢琴'),
                ],
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorWeight: 0,
                indicatorPadding: const EdgeInsets.symmetric(
                  horizontal: 3,
                  vertical: 8,
                ),
                indicator: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: scheme.onSecondaryContainer,
                unselectedLabelColor: scheme.outline,
                labelStyle: const TextStyle(fontSize: 13),
                dividerHeight: 0,
                dividerColor: Colors.transparent,
                onTap: (index) =>
                    setState(() => _filter = ['all', 'tan8', 'cc'][index]),
              ),
            ),
          ),
          if (_notice.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_notice),
              ),
            ),
          if (_loading)
            const SliverFillRemaining(child: LoadingCenter(msg: '搜索中…'))
          else if (_error.isNotEmpty)
            SliverFillRemaining(child: ErrorCenter(_error, onRetry: _doSearch))
          else if (visible.isEmpty && _result.isEmpty)
            const SliverFillRemaining(
              child: Center(child: Text('输入关键词搜索两平台曲谱')),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.only(top: 7),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 600,
                  mainAxisExtent: 110,
                  mainAxisSpacing: 2,
                ),
                itemCount: visible.length,
                itemBuilder: (context, index) => ScoreCardH(visible[index]),
              ),
            ),
            SliverList.builder(
              itemCount: 1,
              itemBuilder: (context, index) {
                if (_canLoadMore && !_loadingMore && _moreError.isEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _loadMore();
                  });
                }
                if (_moreError.isNotEmpty) {
                  return ErrorCenter(_moreError, onRetry: _loadMore);
                }
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: _loadingMore
                        ? const CircularProgressIndicator()
                        : Text(_canLoadMore ? '加载中…' : '没有更多了'),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
