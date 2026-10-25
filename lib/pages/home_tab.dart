/// 首页 Tab: 混合推荐 = 虫虫精选(瀑布) + 弹琴吧首页模块流。
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../utils/data_fields.dart';
import 'author_page.dart';

import '../http/cc_api.dart';
import '../http/tan8_api.dart';
import '../widgets/common.dart';
import '../widgets/piliplus/score_card_v.dart';

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
    final r = await CcApi.floorTab();
    if (r is List) return r;
    throw const FormatException('服务器未提供首页楼层列表');
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
          padding: EdgeInsets.zero,
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
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _ccSections(snap.data ?? const []),
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
          ],
        ),
      ),
    );
  }

  List<Widget> _ccSections(List<dynamic> modules) {
    final widgets = <Widget>[];
    var title = '';
    for (final module in modules.whereType<Map>()) {
      final type = '${module['container_type']}';
      final rows = module['data'];
      if (rows is! List || rows.isEmpty) continue;
      if (type == 'title') {
        title = textOf(rows.first as Map, ['title']);
        continue;
      }
      final list = rows
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (type.contains('opern_list')) {
        widgets.add(_section(title.isEmpty ? '推荐曲谱' : title, list, 'cc'));
      } else if (type == 'hot_musician_list') {
        widgets.add(
          SectionHeader(title.isEmpty ? '推荐音乐人' : title, platform: 'cc'),
        );
        widgets.add(
          SizedBox(
            height: 142,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final u = list[i], uid = userIdOf(list[i], 'cc');
                return SizedBox(
                  width: 132,
                  child: Card(
                    child: InkWell(
                      onTap: uid.isEmpty
                          ? null
                          : () => Get.to(
                              () => AuthorPage(
                                platform: 'cc',
                                uid: uid,
                                name: userNameOf(u),
                                photo: '${u['home_photo'] ?? ''}',
                              ),
                            ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          children: [
                            UserAvatar(
                              url: '${u['home_photo'] ?? ''}',
                              name: userNameOf(u),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              userNameOf(u),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              textOf(u, ['desc']),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      } else if (type == 'album_practice_list') {
        for (final group in list) {
          final albums = group['data'];
          if (albums is List) {
            widgets.add(
              _section(
                textOf(group, ['title']),
                albums
                    .whereType<Map>()
                    .map((e) => <String, dynamic>{...e, 'id': e['cid']})
                    .toList(),
                'cc',
              ),
            );
          }
        }
      } else if (type == 'home_index_hot_accompany') {
        final scores = <Map<String, dynamic>>[];
        for (final row in list) {
          final data = row['datas'];
          if (data is Map && '${data['opern_id'] ?? ''}'.isNotEmpty) {
            scores.add({
              ...Map<String, dynamic>.from(data),
              'old_id': data['opern_id'],
              'image_address': data['bg_img'],
            });
          }
        }
        if (scores.isNotEmpty) widgets.add(_section('热门伴奏', scores, 'cc'));
      }
    }
    return widgets;
  }

  Widget _section(
    String title,
    List<Map<String, dynamic>> items,
    String platform,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionHeader(title, platform: platform),
      SizedBox(
        height: 200,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) =>
              ScoreCardV({...items[i], '__platform': platform}),
        ),
      ),
    ],
  );

  Widget _tan8Section(Map<String, dynamic> mod) {
    final result = mod['result'];
    if (result is! Map) return const SizedBox.shrink();
    final items = result['result'];
    if (items is! List || items.isEmpty) return const SizedBox.shrink();
    final list = items
        .whereType<Map<String, dynamic>>()
        .where((e) => ScoreCard.idOf(e).isNotEmpty || e['jumpEvent'] is Map)
        .toList();
    if (list.isEmpty) return const SizedBox.shrink();
    final title = textOf(mod, ['title']);
    return _section(title.isEmpty ? '推荐' : title, list, 'tan8');
  }
}
