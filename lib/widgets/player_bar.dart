import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import '../services/player_service.dart';
import '../services/file_save_service.dart';
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
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .82,
      child: const _PlayerPanel(),
    ),
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

// AudioPage.build/_buildInfo/_buildDuration/_buildControls copied from
// PiliPlus pages/audio/view.dart (GPL-3.0-or-later). Queue-only controls are
// omitted because the existing audition service exposes one current track.
class _PlayerPanel extends StatefulWidget {
  const _PlayerPanel();
  @override
  State<_PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<_PlayerPanel> {
  bool _downloading = false;

  Future<void> _download(AuditionTrack track) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final path = await FileSaveService.downloadAudio(
        track.url,
        '${track.title}_${track.platform}_${track.scoreId}',
      );
      SmartDialog.showToast('音频已保存 → $path');
    } catch (e) {
      SmartDialog.showToast('音频下载失败：$e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  String time(Duration value) =>
      '${value.inSeconds ~/ 60}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) {
    final player = PlayerService.I;
    return Obx(() {
      final state = player.state, track = state.track.value;
      if (track == null) return const Center(child: Text('暂无播放内容'));
      final scheme = Theme.of(context).colorScheme;
      final padding = MediaQuery.viewPaddingOf(context);
      final isPortrait =
          MediaQuery.sizeOf(context).height >= MediaQuery.sizeOf(context).width;
      final duration = state.duration.value.inMilliseconds;
      final position = state.position.value.inMilliseconds.clamp(
        0,
        duration > 0 ? duration : 0,
      );
      void openScore() {
        Navigator.of(context).pop();
        Get.toNamed(
          '/score',
          parameters: {'platform': track.platform, 'id': track.scoreId},
          preventDuplicates: false,
        );
      }

      Widget info() => Column(
        children: [
          Expanded(
            child: Center(
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  Center(
                    child: SizedBox.square(
                      dimension: 170,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ScoreCover(track.cover),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    track.title,
                    style: const TextStyle(height: 1.7, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  if (track.author.isNotEmpty) ...[
                    Text(track.author),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    spacing: 6,
                    children: [
                      Icon(
                        Icons.headphones_outlined,
                        size: 14,
                        color: scheme.outline,
                      ),
                      PlatformBadge(track.platform),
                      Flexible(
                        child: Text(
                          track.scoreId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (state.error.value.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '播放失败：${state.error.value}',
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
      Widget progress() => SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: SliderComponentShape.noOverlay,
        ),
        child: Slider(
          value: position.toDouble(),
          max: duration > 0 ? duration.toDouble() : 1,
          onChanged: duration > 0
              ? (value) => _control(
                  () => player.seekTo(Duration(milliseconds: value.round())),
                )
              : null,
        ),
      );
      Widget durations() => SizedBox(
        height: 30,
        child: DefaultTextStyle(
          style: TextStyle(fontSize: 13, color: scheme.outline),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(time(state.position.value)),
              Text(time(state.duration.value)),
            ],
          ),
        ),
      );
      Widget controls() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            tooltip: '打开原曲谱',
            onPressed: openScore,
            icon: const Icon(Icons.library_music_outlined, size: 26),
          ),
          IconButton(
            tooltip: state.playing.value ? '暂停' : '播放',
            onPressed: () => _control(player.toggle),
            icon: state.buffering.value
                ? const SizedBox.square(
                    dimension: 30,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    state.playing.value
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 40,
                  ),
          ),
          IconButton(
            tooltip: '下载音频',
            onPressed: _downloading ? null : () => _download(track),
            icon: _downloading
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded, size: 26),
          ),
        ],
      );
      return Padding(
        padding: EdgeInsets.only(
          left: 20 + padding.left,
          right: 20 + padding.right,
          bottom: 30 + padding.bottom,
        ),
        child: isPortrait
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: info()),
                  const SizedBox(height: 25),
                  progress(),
                  durations(),
                  controls(),
                ],
              )
            : Row(
                spacing: 12,
                children: [
                  Expanded(child: info()),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [progress(), durations(), controls()],
                    ),
                  ),
                ],
              ),
      );
    });
  }
}
