import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/music.dart';
import '../services/bilibili.dart';
import '../services/downloads.dart';
import '../services/lyrics.dart';
import '../services/playback.dart';
import '../services/storage.dart';

class LibraryController extends ChangeNotifier {
  LibraryController(this.api, this.db, this.downloads, this.playback) {
    playback.onNext = () => unawaited(next());
    playback.onPrevious = () => unawaited(next(-1));
    playback.onCompleted = () => unawaited(next());
    _subscriptions.add(
      playback.player.positionStream.listen((v) {
        position = v;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      playback.player.playerStateStream.listen((_) {
        notifyListeners();
      }),
    );
    _subscriptions.add(
      playback.player.errorStream.listen((e) {
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
  final lyricsClient = LyricsClient();
  final Map<String, Track> library = {};
  final List<Playlist> playlists = [];
  final List<String> queue = [], likes = [], history = [];
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _saveTimer;
  String theme = 'a',
      mode = 'order',
      quality = '',
      error = '',
      searchError = '',
      query = '',
      lyricText = '';
  bool standard = false,
      searching = false,
      opening = false,
      _refreshing = false;
  int _searchEpoch = 0, _playEpoch = 0, lyricOffset = 0;
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
    final s = await db.readState('library');
    if (s != null) {
      theme = ['a', 'b', 'c'].contains(s['theme']) ? s['theme'] : 'a';
      mode = s['mode'] ?? 'order';
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
      position = Duration(milliseconds: s['position'] ?? 0);
    }
    await downloads.initialize();
    notifyListeners();
  }

  void _downloadsChanged() => notifyListeners();
  Future<void> save() => db.writeState('library', {
    'theme': theme,
    'mode': mode,
    'standard': standard,
    'lyricOffset': lyricOffset,
    'queue': queue,
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
    query = value;
    searchError = '';
    final epoch = ++_searchEpoch;
    if (value.trim().isEmpty) {
      results = [];
      searching = false;
      notifyListeners();
      return;
    }
    searching = true;
    notifyListeners();
    try {
      final found = await api.search(value, page: page);
      if (epoch == _searchEpoch) {
        results = page == 1 ? found : [...results, ...found];
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
    final resolved = await api.details(t.bvid);
    if (resolved.isEmpty) throw const AppFailure('视频没有可播放分 P');
    final real = resolved.first;
    // Resolve placeholder CID references atomically in the controller.
    for (final list in [queue, likes, history]) {
      for (var i = 0; i < list.length; i++) {
        if (list[i] == t.id) list[i] = real.id;
      }
    }
    for (var i = 0; i < playlists.length; i++) {
      final l = playlists[i];
      playlists[i] = Playlist(
        l.id,
        l.name,
        l.trackIds.map((id) => id == t.id ? real.id : id).toSet().toList(),
      );
    }
    library.remove(t.id);
    await db.deleteTrack(t.id);
    await remember(real);
    return real;
  }

  Future<void> remember(Track t) async {
    library[t.id] = t;
    await db.saveTrack(t);
  }

  Future<void> play(Track input, {Duration at = Duration.zero}) async {
    final epoch = ++_playEpoch;
    opening = true;
    error = '';
    _refreshing = false;
    notifyListeners();
    try {
      final t = await canonical(input);
      if (epoch != _playEpoch) return;
      final file = downloads.localPath(t);
      final source = file == null
          ? await api.resolve(t, standard: standard)
          : null;
      if (epoch != _playEpoch) return;
      await playback.pause();
      await playback.open(t, file: file, source: source, position: at);
      if (epoch != _playEpoch) return;
      current = t;
      quality = file != null ? '离线文件' : source!.quality;
      await remember(t);
      if (!queue.contains(t.id)) queue.add(t.id);
      history.remove(t.id);
      history.insert(0, t.id);
      if (history.length > 50) history.removeLast();
      unawaited(playback.play());
      await save();
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
      if (current?.bvid == t.bvid) {
        parts = list;
        notifyListeners();
      }
    } on Exception {
      if (current?.bvid == t.bvid) {
        parts = [t];
        notifyListeners();
      }
    }
  }

  Future<void> _recover() async {
    final t = current;
    if (t == null) return;
    final at = position;
    try {
      final src = await api.resolve(t, standard: standard);
      if (current?.id != t.id) return;
      await playback.open(t, source: src, position: at);
      unawaited(playback.play());
    } on Exception {
      error = '音频地址刷新失败，请点击重试';
      await playback.pause();
      notifyListeners();
    }
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
      await play(current!, at: position);
    } else {
      try {
        unawaited(playback.play());
      } on PlayerException {
        error = '无法继续播放，请重新打开曲目';
        notifyListeners();
      }
    }
  }

  Future<void> next([int delta = 1]) async {
    if (queue.isEmpty) return;
    var index = queue.indexOf(current?.id ?? '');
    if (mode == 'shuffle' && queue.length > 1) {
      final others = queue.where((id) => id != current?.id).toList();
      await play(library[others[Random().nextInt(others.length)]]!);
      return;
    }
    if (mode != 'repeat' || current == null) {
      index = (index + delta) % queue.length;
    }
    await play(library[queue[index < 0 ? 0 : index]]!);
  }

  Future<void> enqueue(Track t, {bool next = false}) async {
    await remember(t);
    queue.remove(t.id);
    final index = queue.indexOf(current?.id ?? '');
    queue.insert(next ? max(0, index + 1) : queue.length, t.id);
    notifyListeners();
    await save();
  }

  Future<void> toggleLike(Track t) async {
    await remember(t);
    likes.contains(t.id) ? likes.remove(t.id) : likes.add(t.id);
    notifyListeners();
    await save();
  }

  Future<void> addPlaylist(String name, {Track? track}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 30) {
      throw const AppFailure('歌单名称需要 1–30 个字');
    }
    if (track != null) await remember(track);
    playlists.add(
      Playlist(
        DateTime.now().microsecondsSinceEpoch.toString(),
        trimmed,
        track == null ? [] : [track.id],
      ),
    );
    notifyListeners();
    await save();
  }

  Future<void> addToPlaylist(Playlist l, Track t) async {
    await remember(t);
    final index = playlists.indexWhere((p) => p.id == l.id);
    playlists[index] = Playlist(l.id, l.name, {...l.trackIds, t.id}.toList());
    notifyListeners();
    await save();
  }

  Future<void> editPlaylist(
    Playlist l, {
    String? name,
    String? remove,
    bool delete = false,
  }) async {
    final i = playlists.indexWhere((v) => v.id == l.id);
    if (delete) {
      playlists.removeAt(i);
    } else {
      final trimmed = (name ?? l.name).trim();
      if (trimmed.isEmpty || trimmed.length > 30) {
        throw const AppFailure('歌单名称需要 1–30 个字');
      }
      playlists[i] = Playlist(
        l.id,
        trimmed,
        l.trackIds.where((id) => id != remove).toList(),
      );
    }
    notifyListeners();
    await save();
  }

  Future<void> moveQueue(int i, int delta) async {
    final j = i + delta;
    if (j < 0 || j >= queue.length) return;
    final t = queue.removeAt(i);
    queue.insert(j, t);
    notifyListeners();
    await save();
  }

  Future<void> removeQueue(String id) async {
    queue.remove(id);
    if (current?.id == id) await playback.pause();
    notifyListeners();
    await save();
  }

  Future<void> clearQueue() async {
    await playback.pause();
    queue.clear();
    notifyListeners();
    await save();
  }

  Future<void> download(Track t) async {
    try {
      await downloads.enqueue(await canonical(t));
      notifyListeners();
    } on Exception catch (e) {
      error = e is AppFailure ? e.message : '无法添加下载任务，请重试';
      notifyListeners();
    }
  }

  Future<void> _loadLyrics(Track t) async {
    lyricText = '';
    notifyListeners();
    try {
      final cached = await downloads.lyrics(t);
      if (current?.id != t.id) return;
      if (cached != null) {
        lyricText = cached;
        notifyListeners();
        return;
      }
      final found = await lyricsClient.search(lyricsClient.clean(t.title));
      if (current?.id != t.id) return;
      if (found.isNotEmpty) await chooseLyrics(found.first, t);
    } on Exception {
      if (current?.id == t.id) {
        lyricText = '歌词暂时不可用，可点击“歌词”重新匹配或粘贴 LRC';
        notifyListeners();
      }
    }
  }

  Future<void> chooseLyrics(Map<String, dynamic> candidate, Track t) async {
    lyricText = candidate['syncedLyrics'] ?? candidate['plainLyrics'] ?? '';
    await downloads.saveLyrics(t, lyricText);
    notifyListeners();
  }

  Future<void> setLyrics(String text) async {
    if (current == null) return;
    lyricText = text;
    await downloads.saveLyrics(current!, text);
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    try {
      profile = await api.profile();
    } on AppFailure catch (e) {
      error = e.message;
      profile = null;
    }
    notifyListeners();
  }

  Future<void> importFolder(Map<String, dynamic> folder) async {
    final found = await api.importFolder(folder['id']);
    for (final t in found) {
      await remember(t);
    }
    playlists.add(
      Playlist(
        'bili-${folder['id']}-${DateTime.now().millisecondsSinceEpoch}',
        folder['title'],
        found.map((t) => t.id).toList(),
      ),
    );
    notifyListeners();
    await save();
  }

  Future<void> logout() async {
    await api.logout();
    profile = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    downloads.removeListener(_downloadsChanged);
    super.dispose();
  }
}
