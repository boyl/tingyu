import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:drift/native.dart';
import 'package:just_audio/just_audio.dart';
import 'package:tingyu/controllers/library_controller.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/services/bilibili.dart';
import 'package:tingyu/services/downloads.dart';
import 'package:tingyu/services/lyrics.dart';
import 'package:tingyu/services/playback.dart';
import 'package:tingyu/services/storage.dart';

const firstTrack = Track(
  bvid: 'BV1xx411c7mD',
  cid: 101,
  title: '第一首声音',
  artist: '测试 UP',
  cover: '',
  duration: 30,
);
const secondTrack = Track(
  bvid: 'BV17x411w7KC',
  cid: 202,
  title: '第二首声音',
  artist: '测试 UP',
  cover: '',
  duration: 40,
);

class MemoryCredentials implements CredentialStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class FixtureApi extends BilibiliClient {
  FixtureApi() : super(MemoryCredentials());
  bool offline = false;
  int qrCode = 86101, qrRequests = 0;
  bool loggedIn = false;
  @override
  bool get hasSession => loggedIn;
  @override
  Future<({String url, String key})> createQr() async {
    qrRequests++;
    return (url: 'https://example.test/qr/$qrRequests', key: '$qrRequests');
  }

  @override
  Future<int> pollQr(String key) async {
    if (qrCode == 0) loggedIn = true;
    return qrCode;
  }

  @override
  Future<Map<String, dynamic>> profile() async {
    if (!loggedIn) throw const AppFailure('登录已过期，请重新扫码');
    return {'mid': 1, 'uname': '测试账号'};
  }

  @override
  Future<List<Map<String, dynamic>>> folders(int mid) async => folderResults;
  List<Map<String, dynamic>> folderResults = [];
  @override
  Future<void> logout() async {
    loggedIn = false;
  }

  Future<AudioStream> Function(
    Track, {
    bool standard,
    CancelToken? cancelToken,
  })?
  resolveAnswer;
  Future<List<Track>> Function(String, int)? searchAnswer;
  final Map<String, Completer<List<Track>>> searches = {};
  @override
  Future<List<Track>> search(String text, {int page = 1}) async {
    if (searchAnswer != null) return searchAnswer!(text, page);
    if (searches.containsKey(text)) return searches[text]!.future;
    if (offline || text == '失败') throw const AppFailure('测试网络断开，请重试');
    return text == '空' ? [] : [firstTrack, secondTrack];
  }

  @override
  Future<List<Track>> details(String bvid) async {
    if (offline) throw const AppFailure('网络断开');
    return [bvid == firstTrack.bvid ? firstTrack : secondTrack];
  }

  @override
  Future<AudioStream> resolve(
    Track track, {
    bool standard = false,
    CancelToken? cancelToken,
  }) async {
    if (resolveAnswer != null) {
      return resolveAnswer!(
        track,
        standard: standard,
        cancelToken: cancelToken,
      );
    }
    if (offline) throw const AppFailure('测试网络断开，请重试');
    return AudioStream('https://example.test/${track.cid}', {}, '测试音质');
  }
}

class FixtureLyrics extends LyricsClient {
  Future<List<Map<String, dynamic>>> Function(String)? answer;
  @override
  Future<List<Map<String, dynamic>>> search(
    String query, {
    CancelToken? cancelToken,
  }) async => answer == null ? [] : answer!(query);
}

class FakePlayer implements AudioPlayer {
  final positions = StreamController<Duration>.broadcast();
  final states = StreamController<PlayerState>.broadcast();
  final errors = StreamController<PlayerException>.broadcast();
  final volumes = StreamController<double>.broadcast();
  double gain = 1;
  double playbackSpeed = 1;
  @override
  double get speed => playbackSpeed;
  @override
  Future<void> setSpeed(double value) async {
    playbackSpeed = value;
  }

  @override
  Stream<double> get volumeStream => volumes.stream;
  @override
  Future<void> setVolume(double value) async {
    gain = value;
    volumes.add(value);
  }

  bool active = false;
  ProcessingState state = ProcessingState.idle;
  Duration at = Duration.zero;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<PlayerException> get errorStream => errors.stream;
  @override
  bool get playing => active;
  @override
  ProcessingState get processingState => state;
  @override
  Duration get position => at;
  @override
  Duration? get duration => const Duration(seconds: 30);
  @override
  double get volume => gain;
  @override
  Future<void> play() async {
    active = true;
    state = ProcessingState.ready;
    states.add(PlayerState(active, state));
  }

  @override
  Future<void> pause() async {
    active = false;
    states.add(PlayerState(active, state));
  }

  @override
  Future<void> seek(Duration? value, {int? index}) async {
    at = value ?? Duration.zero;
    positions.add(at);
  }

  @override
  Future<void> stop() async {
    active = false;
    state = ProcessingState.idle;
    at = Duration.zero;
    positions.add(at);
    states.add(PlayerState(active, state));
  }

  @override
  Future<void> dispose() async {
    await positions.close();
    await states.close();
    await errors.close();
    await volumes.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePlayback extends BaseAudioHandler implements PlaybackHandler {
  @override
  final FakePlayer player = FakePlayer();
  @override
  void Function()? onNext, onPrevious, onCompleted;
  @override
  Future<void> Function(double)? onSpeedChange;
  final List<String> opened = [];
  Future<void> Function(Track)? openAnswer;
  @override
  Future<void> open(
    Track track, {
    String? file,
    AudioStream? source,
    Duration position = Duration.zero,
  }) async {
    final answer = openAnswer;
    if (answer != null) await answer(track);
    opened.add(track.id);
    player.state = ProcessingState.ready;
    await player.seek(position);
  }

  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> seek(Duration position) => player.seek(position);
  @override
  Future<void> close() => player.dispose();
}

class TestLibrary {
  TestLibrary._(
    this.directory,
    this.db,
    this.api,
    this.downloads,
    this.playback,
    this.controller,
  );
  final Directory directory;
  final AppDatabase db;
  final FixtureApi api;
  final DownloadManager downloads;
  final FakePlayback playback;
  final LibraryController controller;
  static Future<TestLibrary> create({Directory? dataDirectory}) async {
    final directory =
        dataDirectory ??
        await Directory.systemTemp.createTemp('tingyu-interactions-');
    final db = AppDatabase(
      NativeDatabase(File('${directory.path}/library.sqlite')),
    );
    final api = FixtureApi(), playback = FakePlayback();
    final downloads = DownloadManager(
      api,
      db,
      directory,
      lyricsClient: FixtureLyrics(),
    );
    final controller = LibraryController(
      api,
      db,
      downloads,
      playback,
      lyricsClient: FixtureLyrics(),
    );
    await controller.initialize();
    return TestLibrary._(directory, db, api, downloads, playback, controller);
  }

  Future<void> close({
    bool deleteData = true,
    bool disposeController = true,
  }) async {
    if (disposeController) controller.dispose();
    await downloads.prepareForExit();
    downloads.dispose();
    await playback.close();
    await db.close();
    if (deleteData) await directory.delete(recursive: true);
  }
}
