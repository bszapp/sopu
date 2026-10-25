/// 双平台试听与移动端后台媒体控制。
library;

import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart' as audio;
import 'package:audio_session/audio_session.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart' show Media, Player;

class AuditionTrack {
  final String url, title, platform, scoreId, cover, author;
  const AuditionTrack({
    required this.url,
    required this.title,
    required this.platform,
    required this.scoreId,
    this.cover = '',
    this.author = '',
  });
  String get platformName => platform == 'tan8' ? '弹琴吧' : '虫虫钢琴';
}

class PlayerState {
  final track = Rxn<AuditionTrack>();
  final playing = false.obs, buffering = false.obs, completed = false.obs;
  final position = Duration.zero.obs, duration = Duration.zero.obs;
  final error = ''.obs;
}

class PlayerService extends GetxService {
  late final Player _player;
  final List<StreamSubscription> _subs = [];
  final state = PlayerState();
  AudioSession? _session;
  _AuditionAudioHandler? _handler;
  bool _resumeAfterInterruption = false;
  bool _disposed = false;
  int _request = 0;
  Future<void> _opening = Future.value();
  static PlayerService get I => Get.find<PlayerService>();
  @override
  void onInit() {
    _player = Player();
    _subs.addAll([
      _player.stream.playing.listen((v) {
        state.playing.value = v;
        _publish();
      }),
      _player.stream.position.listen((v) => state.position.value = v),
      _player.stream.duration.listen((v) {
        state.duration.value = v;
        _publishItem();
      }),
      _player.stream.buffering.listen((v) {
        state.buffering.value = v;
        _publish();
      }),
      _player.stream.completed.listen((v) {
        state.completed.value = v;
        _publish();
      }),
      _player.stream.error.listen((v) {
        if (v.isNotEmpty) {
          state.error.value = v;
          _publish();
        }
      }),
    ]);
    super.onInit();
  }

  Future<void> initializeBackground() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _handler = await audio.AudioService.init(
      builder: () => _AuditionAudioHandler(this),
      config: const audio.AudioServiceConfig(
        androidNotificationChannelId: 'sopu.audition.playback',
        androidNotificationChannelName: '曲谱试听',
        androidNotificationIcon: 'drawable/ic_stat_music',
        androidStopForegroundOnPause: false,
      ),
    );
    final session = await AudioSession.instance;
    _session = session;
    await session.configure(const AudioSessionConfiguration.music());
    _subs.add(session.becomingNoisyEventStream.listen((_) => pause()));
    _subs.add(
      session.interruptionEventStream.listen((event) async {
        if (event.begin) {
          _resumeAfterInterruption = state.playing.value;
          await _player.pause();
        } else {
          final restart =
              _resumeAfterInterruption &&
              event.type != AudioInterruptionType.unknown;
          _resumeAfterInterruption = false;
          if (restart && state.track.value != null) await resume();
        }
      }),
    );
  }

  Future<void> play(AuditionTrack track) {
    final request = ++_request, previous = _opening;
    final operation = () async {
      try {
        await previous;
      } catch (_) {}
      if (request != _request) return;
      final same =
          state.track.value?.url == track.url && state.error.value.isEmpty;
      state.error.value = '';
      state.track.value = track;
      _publishItem();
      try {
        if (!same) {
          state.position.value = Duration.zero;
          state.duration.value = Duration.zero;
          state.completed.value = false;
          state.buffering.value = true;
          _publish();
          await _player.open(Media(track.url), play: false);
        }
        if (request == _request) await _resumeLoaded();
      } catch (e) {
        if (request == _request) {
          state.error.value = '$e';
          state.buffering.value = false;
          _publish();
        }
        rethrow;
      }
    }();
    _opening = operation;
    return operation;
  }

  Future<void> resume() async {
    final track = state.track.value;
    if (track == null) return;
    if (state.error.value.isNotEmpty) {
      await play(track);
      return;
    }
    await _resumeLoaded();
  }

  Future<void> _resumeLoaded() async {
    if (_session != null && !await _session!.setActive(true)) {
      throw StateError('当前无法获得音频播放权限');
    }
    if (state.completed.value) await _player.seek(Duration.zero);
    await _player.play();
    _publish();
  }

  Future<void> pause() async {
    _resumeAfterInterruption = false;
    await _player.pause();
    _publish();
    await _session?.setActive(false);
  }

  Future<void> toggle() => state.error.value.isNotEmpty
      ? resume()
      : state.playing.value
      ? pause()
      : resume();
  Future<void> seekTo(Duration position) async {
    final duration = state.duration.value;
    final target = position < Duration.zero
        ? Duration.zero
        : duration > Duration.zero && position > duration
        ? duration
        : position;
    await _player.seek(target);
    state.position.value = target;
    _publish();
  }

  Future<void> stop() async {
    final request = ++_request;
    _resumeAfterInterruption = false;
    try {
      await _opening;
    } catch (_) {}
    if (request != _request) return;
    await _player.stop();
    state.track.value = null;
    state.playing.value = false;
    state.buffering.value = false;
    state.completed.value = false;
    state.position.value = Duration.zero;
    state.duration.value = Duration.zero;
    state.error.value = '';
    _handler?.mediaItem.add(null);
    _publish();
    await _session?.setActive(false);
  }

  void _publishItem() {
    final track = state.track.value;
    if (track == null) return;
    final art = Uri.tryParse(track.cover);
    _handler?.mediaItem.add(
      audio.MediaItem(
        id: '${track.platform}:${track.scoreId}',
        title: track.title,
        artist: track.author,
        album: track.platformName,
        artUri: art != null && ['http', 'https'].contains(art.scheme)
            ? art
            : null,
        duration: state.duration.value > Duration.zero
            ? state.duration.value
            : null,
        extras: {'platform': track.platform, 'scoreId': track.scoreId},
      ),
    );
  }

  void _publish() {
    final handler = _handler;
    if (handler == null) return;
    final hasTrack = state.track.value != null,
        playing = state.playing.value && !state.completed.value;
    handler.playbackState.add(
      audio.PlaybackState(
        controls: [
          playing ? audio.MediaControl.pause : audio.MediaControl.play,
          audio.MediaControl.stop,
        ],
        systemActions: const {audio.MediaAction.seek},
        androidCompactActionIndices: const [0, 1],
        processingState: !hasTrack
            ? audio.AudioProcessingState.idle
            : state.error.value.isNotEmpty
            ? audio.AudioProcessingState.error
            : state.completed.value
            ? audio.AudioProcessingState.completed
            : state.buffering.value
            ? audio.AudioProcessingState.buffering
            : audio.AudioProcessingState.ready,
        playing: playing,
        updatePosition: state.position.value,
        errorCode: state.error.value.isEmpty ? null : 1,
        errorMessage: state.error.value.isEmpty ? null : state.error.value,
      ),
    );
  }

  Future<void> disposePlayer() async {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subs) {
      await subscription.cancel();
    }
    _subs.clear();
    await _player.dispose();
  }

  @override
  void onClose() {
    unawaited(disposePlayer());
    super.onClose();
  }
}

class _AuditionAudioHandler extends audio.BaseAudioHandler {
  final PlayerService player;
  _AuditionAudioHandler(this.player);
  @override
  Future<void> play() => player.resume();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> seek(Duration position) => player.seekTo(position);
  @override
  Future<void> stop() => player.stop();
}
