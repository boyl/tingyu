import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/music.dart';
import '../models/appearance.dart';
import '../models/play_order.dart';
import '../services/bilibili.dart';
import '../services/downloads.dart';
import '../services/lyrics.dart';
import '../services/playback.dart';
import '../services/storage.dart';
import '../services/sleep_timer.dart';

class LibraryController extends ChangeNotifier {
  LibraryController(
    this.api,
    this.db,
    this.downloads,
    this.playback, {
    LyricsClient? lyricsClient,
  }) : lyricsClient = lyricsClient ?? LyricsClient(subtitleClient: api) {
    playback.onNext = () => unawaited(next());
    playback.onPrevious = () => unawaited(next(-1));
    playback.onCompleted = () => unawaited(_completed());
    sleepTimer.onExpire = _expireTimer;
    sleepTimer.addListener(_timerChanged);
    playback.onSpeedChange = setSpeed;
    _subscriptions.add(
      playback.player.positionStream.listen((v) {
        if (!opening &&
            current != null &&
            playback.player.processingState != ProcessingState.idle) {
          position = v;
        }
      }),
    );
    _subscriptions.add(
      playback.player.playerStateStream.listen((_) {
        if (!_disposed) notifyListeners();
      }),
    );
    _subscriptions.add(
      playback.player.volumeStream.listen((_) {
        if (!_disposed) notifyListeners();
      }),
    );
    _subscriptions.add(
      playback.player.errorStream.listen((e) {
        if (_disposed || opening) return;
        if (_waitingForTrack != null) {
          _waitingForTrack = null;
          error = '播放失败，定时已结束';
          unawaited(playback.pause());
          notifyListeners();
          return;
        }
        if (!_refreshing && current != null) {
          _refreshing = true;
          unawaited(_recover());
        } else {
          error = '播放失败，请重试或选择其他曲目';
          notifyListeners();
        }
      }),
    );
    _saveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(save()),
    );
    downloads.addListener(_downloadsChanged);
  }
  final BilibiliClient api;
  final AppDatabase db;
  final DownloadManager downloads;
  final PlaybackHandler playback;
  final LyricsClient lyricsClient;
  final Map<String, Track> library = {};
  final Map<String, Track> _resolved = {};
  final List<Playlist> playlists = [];
  final Map<String, String> collectionSort = {};
  final List<String> queue = [], likes = [], history = [];
  final SleepTimer sleepTimer = SleepTimer();
  String? _waitingForTrack;
  bool get waitingForTrack => _waitingForTrack != null;
  double speed = 1;
  bool showPlayerLyrics = true;
  bool glassAutomatic = true;
  final autoGlassOpacity = ValueNotifier<double>(.26);
  double navigationOpacity = .26, playerOpacity = .26;
  void _timerChanged() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _expireTimer(bool finishTrack) async {
    if (_disposed) return;
    if (finishTrack &&
        playing &&
        current != null &&
        !opening &&
        playback.player.processingState != ProcessingState.completed) {
      _waitingForTrack = current!.id;
      notifyListeners();
      return;
    }
    ++_playEpoch;
    opening = false;
    await playback.pause();
    notifyListeners();
    await save();
  }

  Future<void> _completed() async {
    if (_disposed || opening) return;
    if (mode == 'once' || _waitingForTrack != null) {
      _waitingForTrack = null;
      await playback.pause();
      notifyListeners();
      await save();
    } else {
      await next(1, true);
    }
  }

  Future<void> setSleepTimer(Duration? duration, {bool? finishTrack}) {
    _waitingForTrack = null;
    if (duration == null) {
      if (finishTrack != null) sleepTimer.finishTrack = finishTrack;
      sleepTimer.cancel();
    } else {
      sleepTimer.start(
        duration,
        finishTrack: finishTrack ?? sleepTimer.finishTrack,
      );
    }
    notifyListeners();
    return save();
  }

  Future<void> setVolume(double value) async {
    if (!value.isFinite || value < 0 || value > 1) {
      throw const AppFailure('音量范围为 0–100%');
    }
    await playback.player.setVolume(value);
    await save();
  }

  Future<void> setSpeed(double value) async {
    if (!value.isFinite || value < .5 || value > 2) {
      throw const AppFailure('倍速范围为 0.5–2×');
    }
    final rounded = (value * 20).round() / 20;
    await playback.player.setSpeed(rounded);
    speed = rounded;
    notifyListeners();
    await save();
  }

  Future<void> setPlayerLyrics(bool value) async {
    showPlayerLyrics = value;
    notifyListeners();
    await save();
  }

  void announceMode(String name) {
    _modeNoticeTimer?.cancel();
    modeNotice.value = name;
    _modeNoticeTimer = Timer(const Duration(milliseconds: 1800), () {
      modeNotice.value = null;
    });
  }

  Future<void> setLyricCentered(bool value) async {
    lyricCentered = value;
    notifyListeners();
    await save();
  }

  Future<void> setGlass({
    bool? automatic,
    double? navigation,
    double? player,
  }) async {
    if (automatic != null) {
      glassAutomatic = automatic;
      if (automatic) {
        navigationOpacity = .26;
        playerOpacity = .26;
        autoGlassOpacity.value = .26;
      }
    }
    if (navigation != null) navigationOpacity = navigation.clamp(0.0, 1.0);
    if (player != null) playerOpacity = player.clamp(0.0, 1.0);
    notifyListeners();
    await save();
  }

  final PlayOrder _playOrder = PlayOrder();
  final List<String> _nextPriority = [];
  Future<void>? _advancing;
  Future<void>? _sourceWork;
  Future<void> _withPlayer(Future<void> Function() work) async {
    final previous = _sourceWork;
    final done = Completer<void>();
    _sourceWork = done.future;
    try {
      if (previous != null) await previous;
      await work();
    } finally {
      done.complete();
      if (identical(_sourceWork, done.future)) _sourceWork = null;
    }
  }

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _saveTimer;
  String theme = defaultTheme,
      mode = 'order',
      quality = '',
      error = '',
      searchError = '',
      query = '',
      lyricText = '',
      lyricSource = '',
      lyricError = '';
  bool standard = false,
      searching = false,
      opening = false,
      _refreshing = false;
  int _searchEpoch = 0, _playEpoch = 0, _lyricEpoch = 0, lyricOffset = 0;
  int searchPage = 1, searchAttemptPage = 1;
  bool _disposed = false;
  Track? current;
  List<Track> results = [], parts = [];
  final playhead = ValueNotifier<Duration>(Duration.zero);
  Duration get position => playhead.value;
  set position(Duration value) => playhead.value = value;
  Map<String, dynamic>? profile;
  String lyricTranslation = '', lyricRomaji = '';
  bool lyricLoading = false,
      showLyricWords = true,
      showLyricTranslation = true,
      showLyricRomaji = true;
  int lyricSize = 1;
  double lyricFontSize = 24;
  bool lyricCentered = false;
  final modeNotice = ValueNotifier<String?>(null);
  Timer? _modeNoticeTimer;
  String? _parsedLyricKey;
  List<LyricLine> _parsedLines = [];
  List<LyricLine> get lines {
    final key = jsonEncode([lyricText, lyricTranslation, lyricRomaji]);
    if (key != _parsedLyricKey) {
      _parsedLyricKey = key;
      _parsedLines = parseRichLyrics(
        lyricText,
        translation: lyricTranslation,
        romaji: lyricRomaji,
      );
    }
    return _parsedLines;
  }

  bool get playing => playback.player.playing;
  Future<void> initialize() async {
    await api.initialize();
    for (final t in await db.loadTracks()) {
      library[t.id] = t;
    }
    for (final track in library.values) {
      if (track.cid > 0 && track.part == 1) {
        _resolved['${track.bvid}:0'] = track;
      }
    }
    final s = await db.readState('library');
    double volume = 1;
    if (s != null) {
      theme = supportedThemes.contains(s['theme']) ? s['theme'] : defaultTheme;
      mode = ['order', 'shuffle', 'repeat', 'once'].contains(s['mode'])
          ? s['mode']
          : 'order';
      final ordered = <String, Track>{
        for (final id in List<String>.from(s['libraryOrder'] ?? []))
          if (library.containsKey(id)) id: library[id]!,
        ...library,
      };
      library
        ..clear()
        ..addAll(ordered);
      collectionSort.addAll(
        Map<String, String>.from(s['collectionSort'] ?? {}),
      );
      standard = s['standard'] ?? false;
      final storedVolume = (s['volume'] as num?)?.toDouble() ?? 1;
      volume = storedVolume.isFinite ? storedVolume.clamp(0.0, 1.0) : 1;
      sleepTimer.finishTrack = s['sleepFinishTrack'] as bool? ?? false;
      final storedSpeed = (s['speed'] as num?)?.toDouble() ?? 1;
      speed = storedSpeed.isFinite ? storedSpeed.clamp(.5, 2) : 1;
      showPlayerLyrics = s['showPlayerLyrics'] as bool? ?? true;
      glassAutomatic = s['glassAutomatic'] as bool? ?? true;
      navigationOpacity = ((s['navigationOpacity'] as num?)?.toDouble() ?? .26)
          .clamp(0.0, 1.0);
      playerOpacity = ((s['playerOpacity'] as num?)?.toDouble() ?? .26).clamp(
        0.0,
        1.0,
      );
      showLyricWords = s['showLyricWords'] as bool? ?? true;
      showLyricTranslation = s['showLyricTranslation'] as bool? ?? true;
      showLyricRomaji = s['showLyricRomaji'] as bool? ?? true;
      lyricCentered = s['lyricCentered'] as bool? ?? false;
      lyricSize = (s['lyricSize'] as int? ?? 1).clamp(0, 2);
      final storedFont = (s['lyricFontSize'] as num?)?.toDouble();
      lyricFontSize = storedFont != null && storedFont.isFinite
          ? storedFont.clamp(16, 32)
          : [20.0, 24.0, 28.0][lyricSize];
      lyricOffset = s['lyricOffset'] ?? 0;
      queue.addAll(
        List<String>.from(s['queue'] ?? []).where(library.containsKey),
      );
      likes.addAll(
        List<String>.from(s['likes'] ?? []).where(library.containsKey),
      );
      history.addAll(
        List<String>.from(s['history'] ?? []).where(library.containsKey),
      );
      playlists.addAll(
        (s['playlists'] as List? ?? []).map(
          (j) => Playlist.fromJson(Map<String, dynamic>.from(j)),
        ),
      );
      current = library[s['current']];
      _playOrder.restore(
        Map<String, dynamic>.from(s['playOrder'] ?? {}),
        queue,
        current?.id,
      );
      _nextPriority.addAll(
        List<String>.from(s['nextPriority'] ?? []).where(queue.contains),
      );
      position = Duration(milliseconds: s['position'] ?? 0);
    }
    await playback.player.setVolume(volume);
    await playback.player.setSpeed(speed);
    await downloads.initialize();
    if (api.hasSession) unawaited(refreshProfile(silent: true));
    notifyListeners();
  }

  String? _loadingDownloadedLyrics;
  void _downloadsChanged() {
    final track = current;
    if (!_disposed &&
        track != null &&
        lyricText.isEmpty &&
        _loadingDownloadedLyrics != track.id &&
        downloads.tasks.any(
          (d) =>
              d.track.id == track.id &&
              d.lyricStatus == DownloadLyricStatus.available,
        )) {
      _loadingDownloadedLyrics = track.id;
      unawaited(
        _loadLyrics(track).whenComplete(() {
          if (_loadingDownloadedLyrics == track.id) {
            _loadingDownloadedLyrics = null;
          }
        }),
      );
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> save() => db.writeState('library', {
    'libraryOrder': library.keys.toList(),
    'collectionSort': collectionSort,
    'theme': theme,
    'mode': mode,
    'standard': standard,
    'lyricOffset': lyricOffset,
    'showLyricWords': showLyricWords,
    'showLyricTranslation': showLyricTranslation,
    'showLyricRomaji': showLyricRomaji,
    'lyricSize': lyricSize,
    'lyricFontSize': lyricFontSize,
    'lyricCentered': lyricCentered,
    'speed': speed,
    'volume': playback.player.volume,
    'sleepFinishTrack': sleepTimer.finishTrack,
    'showPlayerLyrics': showPlayerLyrics,
    'glassAutomatic': glassAutomatic,
    'navigationOpacity': navigationOpacity,
    'playerOpacity': playerOpacity,
    'queue': queue,
    'playOrder': _playOrder.toJson(),
    'nextPriority': _nextPriority,
    'likes': likes,
    'history': history,
    'playlists': playlists.map((l) => l.toJson()).toList(),
    'current': current?.id,
    'position': position.inMilliseconds,
  });
  void showError(String message) {
    error = message;
    notifyListeners();
  }

  void clearError() {
    error = '';
    notifyListeners();
  }

  Future<void> setLyricDisplay({
    bool? words,
    bool? translation,
    bool? romaji,
    int? size,
    double? fontSize,
  }) async {
    if (words != null) showLyricWords = words;
    if (translation != null) showLyricTranslation = translation;
    if (romaji != null) showLyricRomaji = romaji;
    if (size != null) {
      lyricSize = size.clamp(0, 2);
      lyricFontSize = [20.0, 24.0, 28.0][lyricSize];
    }
    if (fontSize != null) {
      if (!fontSize.isFinite) throw const AppFailure('字号无效');
      lyricFontSize = fontSize.clamp(16, 32).roundToDouble();
      lyricSize = ((lyricFontSize - 20) / 4).round().clamp(0, 2);
    }
    notifyListeners();
    await save();
  }

  Future<void> setMode(String value) async {
    if (!['order', 'shuffle', 'repeat', 'once'].contains(value)) {
      throw const AppFailure('不支持的播放模式');
    }
    if (value != mode) _playOrder.reset(queue, current?.id);
    mode = value;
    notifyListeners();
    await save();
  }

  Future<void> setStandard(bool value) async {
    standard = value;
    notifyListeners();
    await save();
  }

  Future<void> setTheme(String value) async {
    if (!supportedThemes.contains(value)) return;
    theme = value;
    notifyListeners();
    await save();
  }

  Future<void> search(String value, {int page = 1}) async {
    if (query.trim() != value.trim()) results = [];
    query = value;
    searchAttemptPage = page;
    searchError = '';
    final epoch = ++_searchEpoch;
    if (value.trim().isEmpty) {
      results = [];
      searchPage = 1;
      searching = false;
      notifyListeners();
      return;
    }
    searching = true;
    notifyListeners();
    try {
      final found = await api.search(value, page: page);
      if (epoch == _searchEpoch) {
        results = {
          for (final t in page == 1 ? found : [...results, ...found]) t.id: t,
        }.values.toList();
        searchPage = page;
      }
    } on Exception catch (e) {
      if (epoch == _searchEpoch) {
        searchError = e is AppFailure ? e.message : '搜索失败，请重试';
      }
    } finally {
      if (epoch == _searchEpoch) {
        searching = false;
        notifyListeners();
      }
    }
  }

  Future<Track> canonical(Track t) async {
    if (t.cid != 0) return t;
    final known = _resolved[t.id];
    if (known != null && !library.containsKey(t.id)) return known;
    final resolved = known == null ? await api.details(t.bvid) : [known];
    if (resolved.isEmpty) throw const AppFailure('视频没有可播放分 P');
    final real = resolved.first;
    _resolved[t.id] = real;
    try {
      await db.transaction(() async {
        await db.saveTrack(real);
        await db.deleteTrack(t.id);
      });
    } on Exception {
      _resolved.remove(t.id);
      rethrow;
    }
    _playOrder.alias(t.id, real.id);
    final priority = _nextPriority
        .map((id) => id == t.id ? real.id : id)
        .toSet()
        .toList();
    _nextPriority
      ..clear()
      ..addAll(priority);
    // Read the latest state after I/O, preserving concurrent additions and position.
    final ordered = <String, Track>{
      for (final entry in library.entries)
        (entry.key == t.id ? real.id : entry.key):
            entry.key == t.id || entry.key == real.id ? real : entry.value,
    };
    ordered.putIfAbsent(real.id, () => real);
    library
      ..clear()
      ..addAll(ordered);
    for (final list in [queue, likes, history]) {
      final mapped = list
          .map((id) => id == t.id ? real.id : id)
          .toSet()
          .toList();
      list
        ..clear()
        ..addAll(mapped);
    }
    for (var i = 0; i < playlists.length; i++) {
      final l = playlists[i];
      playlists[i] = Playlist(
        l.id,
        l.name,
        l.trackIds.map((id) => id == t.id ? real.id : id).toSet().toList(),
        description: l.description,
      );
    }
    if (current?.id == t.id) current = real;
    await save();
    return real;
  }

  Future<Track> remember(Track input) async {
    final t = _resolved[input.id] ?? input;
    library[t.id] = t;
    await db.saveTrack(t);
    return _resolved[t.id] ?? t;
  }

  Future<void> play(
    Track input, {
    Duration at = Duration.zero,
    bool advancing = false,
  }) async {
    if (_waitingForTrack != null) {
      _waitingForTrack = null;
      await playback.pause();
      notifyListeners();
      return;
    }
    final epoch = ++_playEpoch;
    opening = true;
    error = '';
    _refreshing = false;
    notifyListeners();
    try {
      final t = await canonical(input);
      if (epoch != _playEpoch) return;
      final file = await downloads.availablePath(t);
      final source = file == null
          ? await api.resolve(t, standard: standard)
          : null;
      if (epoch != _playEpoch) return;
      await _withPlayer(() async {
        if (epoch != _playEpoch || _disposed) return;
        await playback.pause();
        if (epoch != _playEpoch || _disposed) return;
        await playback.open(t, file: file, source: source, position: at);
        await playback.player.setSpeed(speed);
      });
      if (epoch != _playEpoch) return;
      current = t;
      position = at;
      quality = file != null ? '离线文件' : source!.quality;
      await remember(t);
      if (_disposed || epoch != _playEpoch) return;
      if (!queue.contains(t.id)) queue.add(t.id);
      _nextPriority.remove(t.id);
      if (!advancing) {
        _playOrder.reset(queue, t.id);
      } else if (mode == 'shuffle') {
        _playOrder.arrive(t.id);
      }
      history.remove(t.id);
      history.insert(0, t.id);
      if (history.length > 50) history.removeLast();
      unawaited(_startPlayback());
      await save();
      if (_disposed || epoch != _playEpoch) return;
      unawaited(_loadLyrics(t));
      // Resolve multi-P metadata independently after local playback has started.
      unawaited(_loadParts(t));
    } on Exception catch (e) {
      if (epoch == _playEpoch) {
        error = e is AppFailure
            ? e.message
            : e is PlayerException
            ? '音频无法播放，请重新解析或下载后重试'
            : '播放请求失败，请检查连接后重试';
      }
    } finally {
      if (epoch == _playEpoch) {
        opening = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadParts(Track t) async {
    try {
      final list = await api.details(t.bvid);
      if (!_disposed && current?.bvid == t.bvid) {
        parts = list;
        notifyListeners();
      }
    } on Exception {
      if (!_disposed && current?.bvid == t.bvid) {
        parts = [t];
        notifyListeners();
      }
    }
  }

  Future<void> _recover() async {
    final t = current;
    if (t == null) return;
    final at = position;
    final epoch = _playEpoch;
    try {
      final src = await api.resolve(t, standard: standard);
      if (_disposed || epoch != _playEpoch || current?.id != t.id) return;
      await _withPlayer(() async {
        if (_disposed || epoch != _playEpoch || current?.id != t.id) return;
        await playback.open(t, source: src, position: at);
      });
      if (_disposed || epoch != _playEpoch || current?.id != t.id) return;
      unawaited(_startPlayback());
    } on Exception {
      if (_disposed || epoch != _playEpoch || current?.id != t.id) return;
      error = '音频地址刷新失败，请点击重试';
      await playback.pause();
      notifyListeners();
    }
  }

  Future<void> _startPlayback() async {
    final id = current?.id;
    try {
      await playback.play();
    } on Exception {
      if (!_disposed && current?.id == id) {
        error = '播放未能继续，请重新打开曲目';
        notifyListeners();
      }
    }
  }

  Future<void> removeDownload(DownloadTask task) async {
    if (current?.id == task.track.id && quality == '离线文件') {
      await playback.pause();
      await playback.player.stop();
      quality = '';
    }
    await downloads.remove(task);
    notifyListeners();
  }

  Future<void> toggle() async {
    if (current == null) {
      if (queue.isNotEmpty) await play(library[queue.first]!);
      return;
    }
    if (playing) {
      _waitingForTrack = null;
      await playback.pause();
      await save();
    } else if (playback.player.processingState == ProcessingState.idle ||
        playback.player.processingState == ProcessingState.completed) {
      await play(
        current!,
        at: playback.player.processingState == ProcessingState.completed
            ? Duration.zero
            : position,
        advancing: true,
      );
    } else {
      try {
        unawaited(_startPlayback());
      } on PlayerException {
        error = '无法继续播放，请重新打开曲目';
        notifyListeners();
      }
    }
  }

  Future<void> next([int delta = 1, bool automatic = false]) {
    if (_disposed) return Future.value();
    // UI, notification and completion can arrive together; only one transition runs.
    if (_advancing != null) return _advancing!;
    final task = _advance(delta, automatic);
    _advancing = task;
    return task.whenComplete(() {
      if (identical(_advancing, task)) _advancing = null;
    });
  }

  Track? adjacentTrack(int delta) {
    final ids = queue.where(library.containsKey).toSet().toList();
    if (ids.length < 2) return null;
    String? id;
    final priority = _nextPriority.where(ids.contains);
    if (delta > 0 && priority.isNotEmpty) {
      id = priority.first;
    } else if (mode == 'shuffle') {
      id = _playOrder.peek(ids, current?.id, previous: delta < 0);
    } else {
      final index = ids.indexOf(current?.id ?? '');
      id =
          ids[index < 0
              ? (delta < 0 ? ids.length - 1 : 0)
              : (index + delta) % ids.length];
    }
    return id == current?.id ? null : library[id];
  }

  Future<void> _advance(int delta, bool automatic) async {
    final ids = queue.where(library.containsKey).toSet().toList();
    if (ids.isEmpty || (automatic && opening)) return;
    if (!automatic && _waitingForTrack != null) {
      _waitingForTrack = null;
      await playback.pause();
      notifyListeners();
      return;
    }
    if (automatic && mode == 'once') {
      await _completed();
      return;
    }
    String id;
    if (automatic &&
        mode == 'repeat' &&
        current != null &&
        ids.contains(current!.id)) {
      id = current!.id;
    } else if (delta > 0 && _nextPriority.isNotEmpty) {
      id = _nextPriority.removeAt(0);
      if (!ids.contains(id)) return _advance(delta, automatic);
      if (mode == 'shuffle') {
        _playOrder.prioritize(id);
        id = _playOrder.next(ids, current?.id)!;
      }
    } else if (mode == 'shuffle') {
      id = _playOrder.next(ids, current?.id, previous: delta < 0)!;
    } else {
      final index = ids.indexOf(current?.id ?? '');
      id =
          ids[index < 0
              ? (delta < 0 ? ids.length - 1 : 0)
              : (index + delta) % ids.length];
    }
    await play(library[id]!, advancing: true);
    if (_disposed) return;
    final expected = _resolved[id]?.id ?? id;
    if (current?.id != expected) _playOrder.failed(expected, current?.id);
    await save();
  }

  Future<void> playFromCollection(Track track, List<String> source) async {
    library.putIfAbsent(track.id, () => track);
    final ids = source.where(library.containsKey).toSet().toList();
    if (!ids.contains(track.id)) ids.add(track.id);
    queue
      ..clear()
      ..addAll(ids);
    _nextPriority.clear();
    _playOrder.reset(queue, track.id);
    notifyListeners();
    await play(track);
  }

  Future<void> enqueue(Track input, {bool next = false}) async {
    final t = await remember(input);
    if (next && current?.id == t.id) return;
    if (!next && queue.contains(t.id)) return;
    await _changeQueue(() {
      queue.remove(t.id);
      final index = queue.indexOf(current?.id ?? '');
      queue.insert(next ? max(0, index + 1) : queue.length, t.id);
      if (next) {
        _nextPriority.remove(t.id);
        _nextPriority.insert(0, t.id);
      }
    });
  }

  final Map<String, int> _likeRevisions = {};
  final Set<String> _likeBusy = {};
  int likeRevision(String id) => _likeRevisions[id] ?? 0;

  Future<void> toggleLike(Track input) =>
      setLiked(input, !likes.contains(input.id));

  Future<void> setLiked(Track input, bool liked, {int? restoreIndex}) async {
    if (!_likeBusy.add(input.id)) return;
    final before = likes.indexOf(input.id);
    try {
      final t = await remember(input);
      if (likes.contains(t.id) == liked) return;
      likes.remove(t.id);
      if (liked) {
        likes.insert(
          (restoreIndex ?? likes.length).clamp(0, likes.length),
          t.id,
        );
      }
      _likeRevisions[t.id] = likeRevision(t.id) + 1;
      notifyListeners();
      try {
        await save();
      } catch (_) {
        likes.remove(t.id);
        if (before >= 0) likes.insert(before.clamp(0, likes.length), t.id);
        _likeRevisions[t.id] = likeRevision(t.id) + 1;
        if (!_disposed) notifyListeners();
        rethrow;
      }
    } finally {
      _likeBusy.remove(input.id);
    }
  }

  Future<void> addPlaylist(String name, {Track? track}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 30) {
      throw const AppFailure('歌单名称需要 1–30 个字');
    }
    final stored = track == null ? null : await remember(track);
    final created = Playlist(
      DateTime.now().microsecondsSinceEpoch.toString(),
      trimmed,
      stored == null ? [] : [stored.id],
    );
    playlists.add(created);
    notifyListeners();
    try {
      await save();
    } catch (_) {
      playlists.remove(created);
      if (!_disposed) notifyListeners();
      rethrow;
    }
  }

  Future<void> addToPlaylist(Playlist l, Track t) async {
    final stored = await remember(t);
    await addLibraryTracks(l.id, [stored.id]);
  }

  Future<void> addLibraryTracks(String playlistId, Iterable<String> ids) async {
    final index = playlists.indexWhere((list) => list.id == playlistId);
    if (index < 0) throw const AppFailure('歌单已删除，请返回音乐库');
    final selected = ids.toSet();
    if (selected.any((id) => !library.containsKey(id))) {
      throw const AppFailure('部分歌曲已移除，请重新选择');
    }
    final previous = playlists[index];
    final updated = Playlist(
      previous.id,
      previous.name,
      {...previous.trackIds, ...selected}.toList(),
      description: previous.description,
    );
    playlists[index] = updated;
    try {
      await save();
    } on Exception {
      final currentIndex = playlists.indexWhere(
        (list) => list.id == playlistId,
      );
      if (currentIndex >= 0 && identical(playlists[currentIndex], updated)) {
        playlists[currentIndex] = previous;
      }
      rethrow;
    }
    notifyListeners();
  }

  Future<void> restorePlaylistTrack(
    String playlistId,
    String trackId,
    int position,
  ) async {
    final i = playlists.indexWhere((x) => x.id == playlistId);
    if (i < 0) throw const AppFailure('歌单已删除，无法撤销');
    final before = playlists[i];
    if (before.trackIds.contains(trackId)) return;
    final ids = before.trackIds.toList()
      ..insert(position.clamp(0, before.trackIds.length), trackId);
    playlists[i] = Playlist(
      before.id,
      before.name,
      ids,
      description: before.description,
    );
    notifyListeners();
    try {
      await save();
    } catch (_) {
      playlists[i] = before;
      if (!_disposed) notifyListeners();
      rethrow;
    }
  }

  Future<void> editPlaylist(
    Playlist l, {
    String? name,
    String? description,
    String? remove,
    bool delete = false,
  }) async {
    final i = playlists.indexWhere((v) => v.id == l.id);
    if (i < 0) throw const AppFailure('歌单已删除，请返回音乐库');
    final latest = playlists[i];
    if (delete) {
      playlists.removeAt(i);
    } else {
      final trimmed = (name ?? latest.name).trim();
      if (trimmed.isEmpty || trimmed.length > 30) {
        throw const AppFailure('歌单名称需要 1–30 个字');
      }
      if ((description ?? latest.description).trim().length > 160) {
        throw const AppFailure('歌单简介不能超过 160 个字');
      }
      playlists[i] = Playlist(
        l.id,
        trimmed,
        latest.trackIds.where((id) => id != remove).toList(),
        description: (description ?? latest.description).trim(),
      );
    }
    final updated = delete ? null : playlists[i];
    try {
      await save();
    } on Exception {
      final at = playlists.indexWhere((x) => x.id == latest.id);
      if (delete && at < 0) {
        playlists.insert(i.clamp(0, playlists.length), latest);
      } else if (!delete && at >= 0 && identical(playlists[at], updated)) {
        playlists[at] = latest;
      }
      if (!_disposed) notifyListeners();
      rethrow;
    }
    if (!_disposed) notifyListeners();
  }

  List<String> collectionIds(String key, Iterable<String> source) {
    final ids = source.where(library.containsKey).toList();
    final sort = collectionSort[key] ?? 'default';
    if (sort == 'recent') return ids.reversed.toList();
    if (sort == 'title' || sort == 'artist') {
      final original = {for (var i = 0; i < ids.length; i++) ids[i]: i};
      ids.sort((a, b) {
        final ta = library[a]!, tb = library[b]!;
        final order = (sort == 'title' ? ta.title : ta.artist).compareTo(
          sort == 'title' ? tb.title : tb.artist,
        );
        return order == 0 ? original[a]!.compareTo(original[b]!) : order;
      });
    }
    return ids;
  }

  Future<void> setCollectionSort(String key, String value) async {
    if (!['default', 'recent', 'title', 'artist'].contains(value)) return;
    collectionSort[key] = value;
    notifyListeners();
    await save();
  }

  Future<void> playCollection(List<String> ids) async {
    final valid = ids.where(library.containsKey).toSet().toList();
    if (valid.isEmpty) return;
    await playFromCollection(library[valid.first]!, valid);
  }

  Future<void> removeFromPlaylist(Playlist list, Set<String> ids) async {
    final i = playlists.indexWhere((p) => p.id == list.id);
    if (i < 0) throw const AppFailure('歌单已删除，请返回音乐库');
    final latest = playlists[i];
    playlists[i] = Playlist(
      latest.id,
      latest.name,
      latest.trackIds.where((id) => !ids.contains(id)).toList(),
      description: latest.description,
    );
    final updated = playlists[i];
    try {
      await save();
    } on Exception {
      final at = playlists.indexWhere((x) => x.id == latest.id);
      if (at >= 0 && identical(playlists[at], updated)) playlists[at] = latest;
      if (!_disposed) notifyListeners();
      rethrow;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> reorderQueue(String id, String? beforeId) async {
    if (!queue.contains(id) ||
        id == beforeId ||
        (beforeId != null && !queue.contains(beforeId))) {
      return;
    }
    await _changeQueue(() {
      queue.remove(id);
      queue.insert(
        beforeId == null ? queue.length : queue.indexOf(beforeId),
        id,
      );
    });
  }

  Future<void> moveQueue(int i, int delta) async {
    final j = i + delta;
    if (i < 0 || i >= queue.length || j < 0 || j >= queue.length) return;
    await _changeQueue(() {
      final t = queue.removeAt(i);
      queue.insert(j, t);
    });
  }

  Future<void> _changeQueue(VoidCallback change) async {
    final before = queue.toList(), priority = _nextPriority.toList();
    final order = _playOrder.toJson(), currentId = current?.id;
    change();
    _playOrder.sync(queue);
    final after = queue.toList(), afterPriority = _nextPriority.toList();
    notifyListeners();
    try {
      await save();
    } catch (_) {
      if (listEquals(queue, after) &&
          listEquals(_nextPriority, afterPriority) &&
          current?.id == currentId) {
        queue
          ..clear()
          ..addAll(before);
        _nextPriority
          ..clear()
          ..addAll(priority);
        _playOrder.restore(order, queue, currentId);
        if (!_disposed) notifyListeners();
      }
      rethrow;
    }
  }

  Future<Future<void> Function()> removeQueueUndoable(String id) async {
    final before = queue.toList(), priority = _nextPriority.toList();
    final order = _playOrder.toJson();
    try {
      await removeQueue(id);
    } catch (_) {
      queue
        ..clear()
        ..addAll(before);
      _nextPriority
        ..clear()
        ..addAll(priority);
      _playOrder.restore(order, queue, current?.id);
      if (!_disposed) notifyListeners();
      rethrow;
    }
    final after = queue.toList(), afterCurrent = current?.id;
    final afterPriority = _nextPriority.toList(),
        afterOrder = _playOrder.toJson();
    var used = false;
    return () async {
      if (used) return;
      if (!listEquals(queue, after) || current?.id != afterCurrent) {
        throw const AppFailure('队列已变化，无法撤销这次移除');
      }
      queue
        ..clear()
        ..addAll(before);
      _nextPriority
        ..clear()
        ..addAll(priority);
      _playOrder.restore(order, queue, current?.id);
      notifyListeners();
      try {
        await save();
        used = true;
      } catch (_) {
        queue
          ..clear()
          ..addAll(after);
        _nextPriority
          ..clear()
          ..addAll(afterPriority);
        _playOrder.restore(afterOrder, queue, current?.id);
        if (!_disposed) notifyListeners();
        rethrow;
      }
    };
  }

  Future<void> removeQueue(String id) async {
    queue.remove(id);
    _nextPriority.remove(id);
    _playOrder.sync(queue);
    if (current?.id == id) await _clearPlayback();
    notifyListeners();
    await save();
  }

  Future<void> _clearPlayback() async {
    _waitingForTrack = null;
    ++_playEpoch;
    opening = false;
    current = null;
    quality = '';
    parts = [];
    lyricText = '';
    lyricSource = '';
    lyricOffset = 0;
    lyricError = '';
    position = Duration.zero;
    await _withPlayer(() async {
      await playback.pause();
      await playback.player.stop();
    });
  }

  Future<void> clearQueue() async {
    queue.clear();
    _nextPriority.clear();
    _playOrder.reset(queue, null);
    await _clearPlayback();
    notifyListeners();
    await save();
  }

  Future<void> playDownloaded(Track track) async {
    final tracks = downloads.tasks
        .where((task) => task.status == DownloadStatus.completed)
        .map((task) => task.track)
        .toList();
    for (final item in tracks) {
      await remember(item);
    }
    await playFromCollection(track, tracks.map((item) => item.id).toList());
  }

  Future<void> download(Track t, {bool propagateFailure = false}) async {
    try {
      final track = await canonical(t);
      final existing = downloads.tasks
          .where((task) => task.track.id == track.id)
          .firstOrNull;
      if (existing?.status == DownloadStatus.failed ||
          existing?.status == DownloadStatus.paused) {
        await downloads.retry(existing!);
      } else {
        await downloads.enqueue(track);
      }
      notifyListeners();
    } on Exception catch (e) {
      error = e is AppFailure ? e.message : '无法添加下载任务，请重试';
      notifyListeners();
      if (propagateFailure) rethrow;
    }
  }

  Future<void> _loadLyrics(Track t) async {
    if (_disposed || current?.id != t.id) return;
    final epoch = ++_lyricEpoch;
    lyricText = '';
    lyricTranslation = lyricRomaji = lyricSource = '';
    lyricOffset = 0;
    lyricError = '';
    lyricLoading = true;
    notifyListeners();
    try {
      final document = await downloads.lyricDocument(t);
      final cached = document?['lrc'] as String?;
      if (_disposed || epoch != _lyricEpoch || current?.id != t.id) return;
      if (cached != null) {
        lyricText = cached;
        lyricTranslation = document?['translation'] as String? ?? '';
        lyricRomaji = document?['romaji'] as String? ?? '';
        lyricSource = document?['source'] as String? ?? 'manual';
        lyricOffset = document?['offset'] as int? ?? 0;
        notifyListeners();
        return;
      }
      final found = await lyricsClient.match(
        t,
        isCurrent: () =>
            !_disposed && epoch == _lyricEpoch && current?.id == t.id,
      );
      if (_disposed || epoch != _lyricEpoch || current?.id != t.id) return;
      if (found != null) {
        await chooseLyrics(found, t, expectedEpoch: epoch);
      }
    } on Exception {
      if (!_disposed && epoch == _lyricEpoch && current?.id == t.id) {
        lyricError = '歌词服务暂不可用，可重新匹配或导入 LRC / SPL';
        notifyListeners();
      }
    } finally {
      if (!_disposed && epoch == _lyricEpoch && current?.id == t.id) {
        lyricLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> chooseLyrics(
    Map<String, dynamic> candidate,
    Track t, {
    int? expectedEpoch,
  }) async {
    if (_disposed ||
        current?.id != t.id ||
        (expectedEpoch != null && expectedEpoch != _lyricEpoch)) {
      return;
    }
    final epoch = expectedEpoch ?? ++_lyricEpoch;
    candidate = await lyricsClient.resolveCandidate(candidate);
    if (_disposed || current?.id != t.id || epoch != _lyricEpoch) return;
    final synced = candidate['syncedLyrics'] as String?;
    final text = synced != null && synced.trim().isNotEmpty
        ? synced
        : candidate['plainLyrics'] as String? ?? '';
    await downloads.saveLyrics(
      t,
      text,
      source: candidate['source'] as String? ?? 'lrclib',
      translation: candidate['translation'] as String? ?? '',
      romaji: candidate['romaji'] as String? ?? '',
    );
    if (!_disposed && epoch == _lyricEpoch && current?.id == t.id) {
      lyricText = text;
      lyricTranslation = candidate['translation'] as String? ?? '';
      lyricRomaji = candidate['romaji'] as String? ?? '';
      lyricLoading = false;
      lyricSource = candidate['source'] as String? ?? 'lrclib';
      lyricOffset = 0;
      lyricError = '';
      notifyListeners();
    }
  }

  Future<void> setLyrics(
    String text, {
    Track? track,
    int? offset,
    String translation = '',
    String romaji = '',
  }) async {
    final target = track ?? current;
    if (target == null || current?.id != target.id) {
      throw const AppFailure('歌曲已切换，请重新打开歌词窗口');
    }
    final epoch = ++_lyricEpoch;
    await downloads.saveLyrics(
      target,
      text,
      offset: offset ?? lyricOffset,
      translation: translation,
      romaji: romaji,
    );
    if (_disposed || current?.id != target.id || epoch != _lyricEpoch) return;
    lyricText = text;
    lyricTranslation = translation;
    lyricRomaji = romaji;
    lyricLoading = false;
    lyricSource = 'manual';
    lyricError = '';
    if (offset != null) lyricOffset = offset;
    await save();
    notifyListeners();
  }

  Future<void> refreshProfile({bool silent = false}) async {
    try {
      final found = await api.profile();
      if (_disposed) return;
      profile = found;
      if (!silent) error = '';
    } on AppFailure catch (e) {
      if (_disposed) return;
      if (!silent) {
        error = e.message;
        profile = null;
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<Playlist> importFolder(Map<String, dynamic> folder) async {
    final found = await api.importFolder(folder['id']);
    final stored = <Track>[];
    for (final t in found) {
      stored.add(await remember(t));
    }
    final playlist = Playlist(
      'bili-${folder['id']}-${DateTime.now().millisecondsSinceEpoch}',
      folder['title'],
      stored.map((t) => t.id).toSet().toList(),
    );
    playlists.add(playlist);
    notifyListeners();
    await save();
    return playlist;
  }

  Future<void> logout() async {
    await api.logout();
    profile = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    lyricsClient.cancelRequests();
    ++_playEpoch;
    ++_searchEpoch;
    _saveTimer?.cancel();
    _modeNoticeTimer?.cancel();
    modeNotice.dispose();
    sleepTimer.removeListener(_timerChanged);
    sleepTimer.dispose();
    playback.onSpeedChange = null;
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    downloads.removeListener(_downloadsChanged);
    autoGlassOpacity.dispose();
    playhead.dispose();
    super.dispose();
  }
}
