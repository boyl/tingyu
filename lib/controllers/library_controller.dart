import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/music.dart';
import '../models/play_order.dart';
import '../services/bilibili.dart';
import '../services/downloads.dart';
import '../services/lyrics.dart';
import '../services/playback.dart';
import '../services/storage.dart';

class LibraryController extends ChangeNotifier {
  LibraryController(
    this.api,
    this.db,
    this.downloads,
    this.playback, {
    LyricsClient? lyricsClient,
  }) : lyricsClient = lyricsClient ?? LyricsClient() {
    playback.onNext = () => unawaited(next());
    playback.onPrevious = () => unawaited(next(-1));
    playback.onCompleted = () => unawaited(next(1, true));
    _subscriptions.add(
      playback.player.positionStream.listen((v) {
        if (!opening &&
            current != null &&
            playback.player.processingState != ProcessingState.idle) {
          position = v;
        }
        if (!_disposed) notifyListeners();
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
  String theme = 'a',
      mode = 'order',
      quality = '',
      error = '',
      searchError = '',
      query = '',
      lyricText = '',
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
  Duration position = Duration.zero;
  Map<String, dynamic>? profile;
  List<LyricLine> get lines => parseLrc(lyricText);
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
    if (s != null) {
      theme = ['a', 'b', 'c'].contains(s['theme']) ? s['theme'] : 'a';
      mode = ['order', 'shuffle', 'repeat'].contains(s['mode'])
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
    await downloads.initialize();
    notifyListeners();
  }

  void _downloadsChanged() => notifyListeners();
  Future<void> save() => db.writeState('library', {
    'libraryOrder': library.keys.toList(),
    'collectionSort': collectionSort,
    'theme': theme,
    'mode': mode,
    'standard': standard,
    'lyricOffset': lyricOffset,
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

  Future<void> setMode(String value) async {
    if (!['order', 'shuffle', 'repeat'].contains(value)) {
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
      await playback.pause();
      await save();
    } else if (playback.player.processingState == ProcessingState.idle ||
        playback.player.processingState == ProcessingState.completed) {
      await play(current!, at: position, advancing: true);
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

  Future<void> _advance(int delta, bool automatic) async {
    final ids = queue.where(library.containsKey).toSet().toList();
    if (ids.isEmpty || (automatic && opening)) return;
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
    queue.remove(t.id);
    final index = queue.indexOf(current?.id ?? '');
    queue.insert(next ? max(0, index + 1) : queue.length, t.id);
    _playOrder.sync(queue);
    if (next) {
      _nextPriority.remove(t.id);
      _nextPriority.insert(0, t.id);
    }
    notifyListeners();
    await save();
  }

  Future<void> toggleLike(Track input) async {
    final t = await remember(input);
    likes.contains(t.id) ? likes.remove(t.id) : likes.add(t.id);
    notifyListeners();
    await save();
  }

  Future<void> addPlaylist(String name, {Track? track}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 30) {
      throw const AppFailure('歌单名称需要 1–30 个字');
    }
    final stored = track == null ? null : await remember(track);
    playlists.add(
      Playlist(
        DateTime.now().microsecondsSinceEpoch.toString(),
        trimmed,
        stored == null ? [] : [stored.id],
      ),
    );
    notifyListeners();
    await save();
  }

  Future<void> addToPlaylist(Playlist l, Track t) async {
    final stored = await remember(t);
    final index = playlists.indexWhere((p) => p.id == l.id);
    if (index < 0) throw const AppFailure('歌单已删除，请重新选择歌单');
    final latest = playlists[index];
    playlists[index] = Playlist(
      latest.id,
      latest.name,
      {...latest.trackIds, stored.id}.toList(),
      description: latest.description,
    );
    notifyListeners();
    await save();
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
    notifyListeners();
    await save();
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
    notifyListeners();
    await save();
  }

  Future<void> moveQueue(int i, int delta) async {
    final j = i + delta;
    if (i < 0 || i >= queue.length || j < 0 || j >= queue.length) return;
    final t = queue.removeAt(i);
    queue.insert(j, t);
    notifyListeners();
    await save();
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
    ++_playEpoch;
    opening = false;
    current = null;
    quality = '';
    parts = [];
    lyricText = '';
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

  Future<void> download(Track t) async {
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
    }
  }

  Future<void> _loadLyrics(Track t) async {
    if (_disposed || current?.id != t.id) return;
    final epoch = ++_lyricEpoch;
    lyricText = '';
    lyricError = '';
    notifyListeners();
    try {
      final cached = await downloads.lyrics(t);
      if (_disposed || epoch != _lyricEpoch || current?.id != t.id) return;
      if (cached != null) {
        lyricText = cached;
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
        lyricError = '歌词服务暂不可用，可通过歌词图标重新匹配或粘贴 LRC';
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
    final synced = candidate['syncedLyrics'] as String?;
    final text = synced != null && synced.trim().isNotEmpty
        ? synced
        : candidate['plainLyrics'] as String? ?? '';
    await downloads.saveLyrics(t, text);
    if (!_disposed && epoch == _lyricEpoch && current?.id == t.id) {
      lyricText = text;
      lyricError = '';
      notifyListeners();
    }
  }

  Future<void> setLyrics(String text, {Track? track, int? offset}) async {
    final target = track ?? current;
    if (target == null || current?.id != target.id) {
      throw const AppFailure('歌曲已切换，请重新打开歌词窗口');
    }
    ++_lyricEpoch;
    await downloads.saveLyrics(target, text);
    if (_disposed || current?.id != target.id) return;
    lyricText = text;
    lyricError = '';
    if (offset != null) lyricOffset = offset;
    await save();
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    try {
      profile = await api.profile();
      error = '';
    } on AppFailure catch (e) {
      error = e.message;
      profile = null;
    }
    notifyListeners();
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
    ++_playEpoch;
    ++_searchEpoch;
    _saveTimer?.cancel();
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    downloads.removeListener(_downloadsChanged);
    super.dispose();
  }
}
