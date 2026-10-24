/// 首页 Tab: 混合推荐 = 虫虫精选(瀑布) + 弹琴吧首页模块流。
library;

import 'package:flutter/material.dart';

import '../http/cc_api.dart';
import '../http/tan8_api.dart';
import '../widgets/common.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with AutomaticKeepAliveClientMixin {
  late Future<List<dynamic>> _ccList;
  late Future<List<dynamic>> _tan8Mods;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _ccList = _loadCc();
    _tan8Mods = Tan8Api.homePage();
  }

  Future<List<dynamic>> _loadCc() async {
    final r = await CcApi.opernList(page: 1, size: 20);
    if (r is List) return r;
    if (r is Map<String, dynamic>) return (r['list'] as List?) ?? const [];
    return const [];
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜谱', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _refresh());
        },
        child: ListView(
          padding: EdgeInsets.only(
            bottom:
                MediaQuery.of(context).padding.bottom + pageBottomScrollSpace,
          ),
          children: [
            FutureBuilder<List<dynamic>>(
              future: _ccList,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const LoadingCenter(msg: '虫虫钢琴加载中...');
                }
                if (snap.hasError) {
                  return ErrorCenter(
                    snap.error,
                    onRetry: () => setState(_refresh),
                  );
                }
                final items = (snap.data ?? const [])
                    .whereType<Map<String, dynamic>>()
                    .toList();
                for (final e in items) {
                  e['__platform'] = 'cc';
                }
                if (items.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader('虫虫钢琴 · 精选', platform: 'cc'),
                    SizedBox(
                      height: 224,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        scrollDirection: Axis.horizontal,
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => ScoreCard(items[i]),
                      ),
                    ),
                  ],
                );
              },
            ),
            FutureBuilder<List<dynamic>>(
              future: _tan8Mods,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const LoadingCenter(msg: '弹琴吧加载中...');
                }
                if (snap.hasError) {
                  return ErrorCenter(
                    snap.error,
                    onRetry: () => setState(_refresh),
                  );
                }
                final mods = (snap.data ?? []);
                if (mods.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: mods
                      .whereType<Map<String, dynamic>>()
                      .map((m) => _tan8Section(m))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _tan8Section(Map<String, dynamic> mod) {
    final result = mod['result'];
    if (result is! Map) return const SizedBox.shrink();
    dynamic items = result['result'];
    if (items is! List || items.isEmpty) return const SizedBox.shrink();
    final list =
        items
            .whereType<Map<String, dynamic>>()
            .where((e) => (e['id'] ?? '').toString().isNotEmpty)
            .toList()
          ..forEach((e) => e['__platform'] = 'tan8');
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          (mod['web_mod_id'] ?? '弹琴吧').toString(),
          platform: 'tan8',
        ),
        SizedBox(
          height: 224,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: list.length.clamp(0, 20),
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => ScoreCard(list[i]),
          ),
        ),
      ],
    );
  }
}
