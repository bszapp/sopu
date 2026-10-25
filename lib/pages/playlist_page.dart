import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import '../http/tan8_api.dart';
import '../utils/data_fields.dart';
import '../widgets/common.dart';

class PlaylistPage extends StatefulWidget {
  const PlaylistPage({super.key, required this.id, required this.title});
  final String id, title;
  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true, _busy = false;
  String _error = '';
  bool? _public;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Tan8Api.playlistScores(widget.id);
      final playlists = await Tan8Api.myPlaylists();
      final mine = playlists.whereType<Map>().where(
        (e) => '${e['id']}' == widget.id,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows
            .whereType<Map<String, dynamic>>()
            .map(
              (e) => <String, dynamic>{...scoreData(e), '__platform': 'tan8'},
            )
            .toList();
        _public = mine.isEmpty ? null : flagOf(mine.first['isopen']);
        _loading = false;
        _error = '';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _write(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (e) {
      SmartDialog.showToast('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加曲谱'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '曲谱编号',
            hintText: '多个编号用空格或逗号分隔',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (text == null) return;
    final ids = text
        .trim()
        .split(RegExp(r'[\s,，]+'))
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty || ids.any((id) => !RegExp(r'^\d+$').hasMatch(id))) {
      SmartDialog.showToast('请输入有效的数字曲谱编号');
      return;
    }
    await _write(() => Tan8Api.addPlaylistScores(widget.id, ids));
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确认删除“${widget.title}”？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy) return;
    setState(() => _busy = true);
    try {
      await Tan8Api.deletePlaylist(widget.id);
      if (mounted) Get.back(result: true);
    } catch (e) {
      SmartDialog.showToast('删除失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(
          onPressed: _busy ? null : _add,
          icon: const Icon(Icons.playlist_add),
          tooltip: '添加曲谱',
        ),
        PopupMenuButton<String>(
          enabled: !_busy,
          onSelected: (value) {
            if (value == 'delete') {
              _delete();
            } else {
              _write(() => Tan8Api.togglePlaylistPublic(widget.id));
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'public',
              child: Text(
                _public == null
                    ? '切换公开状态'
                    : _public!
                    ? '设为私密'
                    : '设为公开',
              ),
            ),
            const PopupMenuItem(value: 'delete', child: Text('删除歌单')),
          ],
        ),
      ],
    ),
    body: _loading
        ? const LoadingCenter()
        : _error.isNotEmpty
        ? ErrorCenter(_error, onRetry: _load)
        : Column(
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_rows.isEmpty)
                const Expanded(child: Center(child: Text('歌单暂无曲谱')))
              else
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: _rows.length,
                    onReorderItem: (oldIndex, newIndex) async {
                      if (_busy) return;
                      final ordered = [..._rows];
                      ordered.insert(newIndex, ordered.removeAt(oldIndex));
                      await _write(
                        () => Tan8Api.sortPlaylistScores(
                          widget.id,
                          ordered.map(ScoreCard.idOf).toList(),
                        ),
                      );
                    },
                    itemBuilder: (context, index) {
                      final row = _rows[index],
                          id = ScoreCard.idOf(_rows[index]);
                      return Row(
                        key: ValueKey(id),
                        children: [
                          Expanded(child: ScoreRow(row)),
                          IconButton(
                            tooltip: '从歌单移除',
                            onPressed: _busy
                                ? null
                                : () => _write(
                                    () => Tan8Api.removePlaylistScores(
                                      widget.id,
                                      [id],
                                    ),
                                  ),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          const SizedBox(width: 40),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
  );
}
