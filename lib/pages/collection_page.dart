import 'package:flutter/material.dart';

import '../http/cc_api.dart';
import '../http/tan8_api.dart';
import '../utils/data_fields.dart';
import '../widgets/common.dart';
import '../widgets/piliplus/score_card_h.dart';

class CollectionPage extends StatefulWidget {
  const CollectionPage({
    super.key,
    required this.platform,
    required this.url,
    required this.title,
    required this.id,
  });
  final String platform, url, title, id;
  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  bool _loading = true;
  String _error = '';
  Map<String, dynamic> _info = {};
  List<Map<String, dynamic>> _sections = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final Map<String, dynamic> data;
      if (widget.platform == 'cc') {
        final raw = await CcApi.albumDetail(widget.id);
        final rows = raw is Map && raw['list_music_book'] is List
            ? raw['list_music_book'] as List
            : <dynamic>[];
        final pages = raw is Map ? int.tryParse('${raw['total_pages']}') : null;
        data = {
          'info': raw is Map ? Map<String, dynamic>.from(raw) : {},
          'sections': [
            {
              'title': '曲目',
              'items': rows,
              'url': '',
              'page': 1,
              'more': rows.isNotEmpty && (pages == null || pages > 1),
            },
          ],
        };
      } else {
        data = await Tan8Api.collectionPage(widget.url);
      }
      if (!mounted) return;
      setState(() {
        _info = data['info'] as Map<String, dynamic>;
        _sections = (data['sections'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _more(Map<String, dynamic> section) async {
    if (section['busy'] == true) return;
    setState(() {
      section['busy'] = true;
      section['error'] = '';
    });
    try {
      final rows = section['items'] as List;
      final List<dynamic>? next;
      int? totalPages;
      if (widget.platform == 'cc') {
        final page = (section['page'] as int? ?? 1) + 1;
        final data = await CcApi.albumDetail(widget.id, page: page);
        next = data is Map && data['list_music_book'] is List
            ? data['list_music_book'] as List
            : null;
        totalPages = data is Map
            ? int.tryParse('${data['total_pages']}')
            : null;
      } else {
        next = await Tan8Api.collectionModuleItems(
          section['url'],
          start: rows.length,
        );
      }
      if (next == null) throw const FormatException('合集曲目分页响应无法识别');
      final ids = rows
          .whereType<Map<String, dynamic>>()
          .map(ScoreCard.idOf)
          .toSet();
      final fresh = next
          .whereType<Map<String, dynamic>>()
          .where((r) => !ids.contains(ScoreCard.idOf(r)))
          .toList();
      if (next.isNotEmpty && fresh.isEmpty) throw StateError('服务器重复返回上一页曲目');
      if (!mounted) return;
      setState(() {
        rows.addAll(fresh);
        section['page'] = (section['page'] as int? ?? 1) + 1;
        section['more'] =
            next!.isNotEmpty &&
            (totalPages == null || section['page'] < totalPages);
      });
    } catch (e) {
      if (mounted) setState(() => section['error'] = '$e');
    } finally {
      if (mounted) setState(() => section['busy'] = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        textOf(_info, ['title', 'name']).isEmpty
            ? widget.title
            : textOf(_info, ['title', 'name']),
      ),
    ),
    body: _loading
        ? const LoadingCenter()
        : _error.isNotEmpty
        ? ErrorCenter(_error, onRetry: _load)
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (textOf(_info, ['info', 'desc']).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      textOf(_info, ['info', 'desc']),
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                for (final section in _sections) ...[
                  SectionHeader(
                    textOf(section, ['title']).isEmpty
                        ? '曲目'
                        : '${section['title']}',
                    platform: widget.platform,
                  ),
                  for (final row
                      in (section['items'] as List)
                          .whereType<Map<String, dynamic>>())
                    ScoreCardH({
                      ...scoreData(row),
                      '__platform': widget.platform,
                    }),
                  if ('${section['error'] ?? ''}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('${section['error']}'),
                    ),
                  if ((section['items'] as List).isNotEmpty &&
                      section['more'] != false)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: OutlinedButton(
                        onPressed: section['busy'] == true
                            ? null
                            : () => _more(section),
                        child: Text(section['busy'] == true ? '加载中…' : '加载更多'),
                      ),
                    ),
                ],
                if (_sections.isEmpty ||
                    _sections.every((s) => (s['items'] as List).isEmpty))
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('暂无曲目')),
                  ),
              ],
            ),
          ),
  );
}
