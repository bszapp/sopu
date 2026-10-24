/// 混合搜索页: 两平台并搜, 平台徽章区分, 平台筛选, 分页加载。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../http/cc_api.dart';
import '../http/tan8_api.dart';
import '../widgets/common.dart';

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
  bool _noMoreGeneric = false;

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
    _noMoreGeneric = false;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final f1 = Tan8Api.search(kw, limit: 20, start: 0);
      final f2 = CcApi.searchSongs(kw, page: 1, size: 20);
      final r1 = await f1;
      final r2 = await f2;
      if (!mounted || generation != _requestGeneration) return;
      final tan8Items = ((r1['result'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((e) => e..['__platform'] = 'tan8')
          .where((e) => (e['id'] ?? '').toString().isNotEmpty)
          .toList();
      final ccItems = r2
          .whereType<Map<String, dynamic>>()
          .map((e) => e..['__platform'] = 'cc')
          .toList();
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
    if (_loadingMore || _loading || _error.isNotEmpty || _noMoreGeneric) return;
    _loadingMore = true;
    final generation = _requestGeneration;
    final keyword = _kwController.text.trim();
    try {
      if (_filter != 'cc') {
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
          _noMoreGeneric = true;
        } else {
          _tan8Start += items.length;
          _result.addAll(items);
        }
      }
      if (_filter != 'tan8') {
        final more = await CcApi.searchSongs(keyword, page: _ccPage, size: 20);
        if (!mounted || generation != _requestGeneration) return;
        final items = more
            .whereType<Map<String, dynamic>>()
            .map((e) => e..['__platform'] = 'cc')
            .toList();
        if (items.isNotEmpty) {
          _ccPage++;
          _result.addAll(items);
        }
      }
    } catch (_) {
      // 静默: 加载更多失败不惊扰
    } finally {
      _loadingMore = false;
      if (mounted && generation == _requestGeneration) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: TextField(
            controller: _kwController,
            decoration: InputDecoration(
              hintText: '搜索两平台曲谱...',
              border: InputBorder.none,
              suffixIcon: _kwController.text.isEmpty
                  ? const Icon(Icons.search)
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _kwController.clear();
                        setState(_result.clear);
                      },
                    ),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _doSearch(),
          ),
          pinned: true,
          snap: false,
          floating: true,
          automaticallyImplyLeading: false,
          centerTitle: false,
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('全部'),
                  selected: _filter == 'all',
                  onSelected: (_) {
                    setState(() {
                      _filter = 'all';
                      _applyFilter();
                    });
                  },
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: const Text('弹琴吧'),
                  selected: _filter == 'tan8',
                  onSelected: (_) {
                    setState(() {
                      _filter = 'tan8';
                      _applyFilter();
                    });
                  },
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: const Text('虫虫'),
                  selected: _filter == 'cc',
                  onSelected: (_) {
                    setState(() {
                      _filter = 'cc';
                      _applyFilter();
                    });
                  },
                ),
                const SizedBox(width: 10),
                Text(
                  _result.isEmpty ? '' : '共 ${_result.length} 条',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
        if (_loading)
          const SliverFillRemaining(child: LoadingCenter(msg: '搜索中...'))
        else if (_error.isNotEmpty)
          SliverFillRemaining(child: ErrorCenter(_error, onRetry: _doSearch))
        else if (_result.isEmpty)
          const SliverFillRemaining(
            child: Center(
              child: Text('输入关键词搜索两平台曲谱', style: TextStyle(color: Colors.grey)),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(bottom: pageBottomScrollSpace),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                if (i == _result.length - 4) _loadMore();
                final item = _result[i];
                if (item.isEmpty) return null;
                if (_filter == 'all' || item['__platform'] == _filter) {
                  return ScoreRow(item);
                }
                return const SizedBox.shrink();
              }, childCount: _result.length),
            ),
          ),
      ],
    );
  }

  void _applyFilter() {
    // 实时筛选 UI (不重新请求)
    setState(() {});
  }
}
