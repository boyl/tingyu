import 'dart:io';
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_service_win/audio_service_win.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import '../models/music.dart';

class PlaybackHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer player = AudioPlayer(useProxyForRequestHeaders: false);
  void Function()? onNext, onPrevious, onCompleted;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  PlaybackHandler() {
    _subscriptions.add(
      player.playbackEventStream.listen((event) {
        playbackState.add(
          PlaybackState(
            controls: [
              MediaControl.skipToPrevious,
              player.playing ? MediaControl.pause : MediaControl.play,
              MediaControl.skipToNext,
            ],
            systemActions: const {MediaAction.seek},
            androidCompactActionIndices: const [0, 1, 2],
            processingState: switch (player.processingState) {
              ProcessingState.idle => AudioProcessingState.idle,
              ProcessingState.loading => AudioProcessingState.loading,
              ProcessingState.buffering => AudioProcessingState.buffering,
              ProcessingState.ready => AudioProcessingState.ready,
              ProcessingState.completed => AudioProcessingState.completed,
            },
            playing: player.playing,
            updatePosition: player.position,
            bufferedPosition: player.bufferedPosition,
            speed: player.speed,
          ),
        );
      }),
    );
    _subscriptions.add(
      player.processingStateStream.listen((s) {
        if (s == ProcessingState.completed) onCompleted?.call();
      }),
    );
  }
  static Future<PlaybackHandler> initialize() async {
    if (Platform.isWindows) {
      JustAudioMediaKit.ensureInitialized(windows: true, linux: false);
      AudioServiceWin.registerWith();
    }
    if (!Platform.isWindows) {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    }
    return AudioService.init(
      builder: () => PlaybackHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'app.tingyu.playback',
        androidNotificationChannelName: '听屿音乐播放',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  }

  Future<void> open(
    Track t, {
    String? file,
    AudioStream? source,
    Duration position = Duration.zero,
  }) async {
    mediaItem.add(
      MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artist,
        duration: Duration(seconds: t.duration),
        artUri: t.cover.isEmpty ? null : Uri.tryParse(t.cover),
      ),
    );
    if (file != null) {
      await player.setFilePath(file, initialPosition: position);
    } else {
      await player.setUrl(
        source!.url,
        headers: source.headers,
        initialPosition: position,
      );
    }
  }

  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> seek(Duration position) => player.seek(position);
  @override
  Future<void> skipToNext() async => onNext?.call();
  @override
  Future<void> skipToPrevious() async => onPrevious?.call();
  Future<void> close() async {
    onNext = null;
    onPrevious = null;
    onCompleted = null;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    await player.dispose();
  }

  @override
  Future<void> stop() async {
    await player.stop();
    await super.stop();
  }
}
