import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import '../services/player_service.dart';
import 'common.dart';

final playerOnHome = ValueNotifier<bool>(true);

Future<void> _control(Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    SmartDialog.showToast('播放失败：$e');
  }
}

void openPlayer(BuildContext context) {
  showModalBottomSheet<void>(
    context: Get.overlayContext ?? context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _PlayerPanel(),
  );
}

class MiniPlayerBar extends StatelessWidget {
  final bool bottomSafeArea;
  const MiniPlayerBar({super.key, this.bottomSafeArea = true});
  @override
  Widget build(BuildContext context) {
    final player = PlayerService.I;
    return Obx(() {
      final state = player.state, track = state.track.value;
      if (track == null) return const SizedBox.shrink();
      final duration = state.duration.value.inMilliseconds,
          position = state.position.value.inMilliseconds;
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: SafeArea(
          top: false,
          bottom: bottomSafeArea,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => openPlayer(context),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: ScoreCover(track.cover),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              state.error.value.isNotEmpty
                                  ? '播放失败，点击重试'
                                  : '${track.author.isEmpty ? '未知作者' : track.author} · ${track.platformName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (state.buffering.value)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      IconButton(
                        key: const ValueKey('player.toggle'),
                        onPressed: () => _control(player.toggle),
                        icon: Icon(
                          state.playing.value
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_fill,
                        ),
                        iconSize: 34,
                      ),
                      IconButton(
                        key: const ValueKey('player.stop'),
                        onPressed: () => _control(player.stop),
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
              LinearProgressIndicator(
                value: duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0,
                minHeight: 2,
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _PlayerPanel extends StatelessWidget {
  const _PlayerPanel();
  String time(Duration value) =>
      '${value.inSeconds ~/ 60}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) {
    final player = PlayerService.I;
    return Obx(() {
      final state = player.state, track = state.track.value;
      if (track == null) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Text('暂无播放内容'),
        );
      }
      final duration = state.duration.value.inMilliseconds;
      final position = state.position.value.inMilliseconds.clamp(
        0,
        duration > 0 ? duration : 0,
      );
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('曲谱试听', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 20),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: ScoreCover(track.cover),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  track.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  track.author.isEmpty ? '未知作者' : track.author,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                PlatformBadge(track.platform),
                const SizedBox(height: 18),
                if (state.error.value.isNotEmpty)
                  Text(
                    '播放失败：${state.error.value}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                Slider(
                  value: position.toDouble(),
                  max: duration > 0 ? duration.toDouble() : 1,
                  onChanged: duration > 0
                      ? (value) => _control(
                          () => player.seekTo(
                            Duration(milliseconds: value.round()),
                          ),
                        )
                      : null,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(time(state.position.value)),
                    Text(time(state.duration.value)),
                  ],
                ),
                const SizedBox(height: 8),
                IconButton.filled(
                  tooltip: state.playing.value ? '暂停' : '播放',
                  onPressed: () => _control(player.toggle),
                  iconSize: 42,
                  padding: const EdgeInsets.all(14),
                  icon: Icon(
                    state.playing.value ? Icons.pause : Icons.play_arrow,
                  ),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  icon: const Icon(Icons.library_music_outlined),
                  label: const Text('打开原曲谱'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    Get.toNamed(
                      '/score',
                      parameters: {
                        'platform': track.platform,
                        'id': track.scoreId,
                      },
                      preventDuplicates: false,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
