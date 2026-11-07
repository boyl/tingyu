import 'package:flutter/foundation.dart';
import '../models/music.dart';

typedef DiscoverySearch =
    Future<List<Track>> Function(String query, {int page});

/// Session-only discovery: never mutates manual search, library or playback.
class DiscoveryController extends ChangeNotifier {
  DiscoveryController({
    required this.search,
    required this.seeds,
    required this.recent,
  });
  final DiscoverySearch search;
  final List<Track> Function() seeds;
  final Set<String> Function() recent;
  static const tags = ['全部', '轻音乐', '翻唱', '现场', '纯音乐'];
  final Map<String, _DiscoveryBatch> _batches = {};
  String tag = '全部';
  bool _disposed = false;
  _DiscoveryBatch get _state => _batches.putIfAbsent(tag, _DiscoveryBatch.new);
  List<Track> get tracks =>
      List.unmodifiable(_state.tracks.take(_state.featuredCount));
  List<Track> get moreTracks =>
      List.unmodifiable(_state.tracks.skip(_state.featuredCount));
  bool get loadingMore => _state.loading && _state.appendAttempt;
  bool get loadMoreFailed => _state.appendAttempt && _state.error.isNotEmpty;
  bool get initialized => _state.started;
  bool get loading => _state.loading;
  String get error => _state.error;
  bool get exhausted =>
      _state.sources != null &&
      _state.sources!.every((s) => s.done) &&
      _state.pending.isEmpty;

  Future<void> ensureLoaded() => _state.started ? Future.value() : nextBatch();

  Future<void> selectTag(String value) async {
    if (!tags.contains(value)) throw ArgumentError.value(value, 'tag');
    if (_disposed || tag == value) return;
    tag = value;
    notifyListeners();
    await ensureLoaded();
  }

  List<_DiscoverySource> _sources(String selected) {
    if (selected != '全部') return [_DiscoverySource('$selected 音乐')];
    final queries = <String>{};
    for (final t in seeds()) {
      // Titles are search clues, not reliable artist or genre metadata.
      final title = t.title
          .replaceAll(RegExp(r'【[^】]*】|\[[^\]]*\]'), ' ')
          .trim();
      final phrase = title.split(RegExp(r'[｜|·]')).first.trim();
      if (phrase.isNotEmpty) {
        queries.add('${String.fromCharCodes(phrase.runes.take(32))} 音乐');
      }
      if (queries.length == 2) break;
    }
    return [
      ...queries.map(_DiscoverySource.new),
      _DiscoverySource('音乐 现场 翻唱'),
      _DiscoverySource('轻音乐 纯音乐'),
    ];
  }

  Future<void> nextBatch() => _load(append: false);
  Future<void> loadMore() => _load(append: true);
  Future<void> retry() => _load(append: _state.appendAttempt);

  Future<void> _load({required bool append}) async {
    if (_disposed) return;
    final state = _state;
    if (state.loading) return;
    state.appendAttempt = append;
    final count = append ? 10 : 16;
    state.started = true;
    state.loading = true;
    state.error = '';
    state.sources ??= _sources(tag);
    notifyListeners();
    try {
      for (
        var attempts = 0;
        attempts < 2 && state.pending.length < count;
        attempts++
      ) {
        final available = state.sources!.where((s) => !s.done).toList();
        if (available.isEmpty) break;
        final source = available[state.cursor % available.length];
        final found = await search(source.query, page: source.page);
        if (_disposed) return;
        final fresh = found.where((t) => source.seen.add(t.bvid)).toList();
        source.done = fresh.isEmpty;
        source.page++;
        state.cursor++;
        for (final t in fresh) {
          if (state.seen.add(t.bvid) &&
              !RegExp(r'教程|教学|教你|唱歌技巧|如何.*(?:唱|歌)|歌曲推荐').hasMatch(t.title)) {
            state.pending.add(t);
          }
        }
      }
    } on Exception catch (e) {
      if (_disposed) return;
      state.error = e is AppFailure ? e.message : '推荐加载失败，请重试';
    } finally {
      if (!_disposed) {
        final heard = recent();
        // Stable partition retains relevance order within each group.
        final ranked = [
          ...state.pending.where((t) => !heard.contains(t.bvid)),
          ...state.pending.where((t) => heard.contains(t.bvid)),
        ];
        final picked = <Track>[];
        final uploaders = <String, int>{};
        for (final t in ranked) {
          final uploader = t.artist.trim();
          if (uploader.isNotEmpty && (uploaders[uploader] ?? 0) >= 2) continue;
          picked.add(t);
          uploaders[uploader] = (uploaders[uploader] ?? 0) + 1;
          if (picked.length == count) break;
        }
        // A failed request retains the current page; retry can reuse its partial buffer.
        if (picked.isNotEmpty &&
            (state.error.isEmpty || state.tracks.isEmpty)) {
          if (append) {
            state.tracks = [...state.tracks, ...picked];
          } else {
            state.tracks = picked;
            state.featuredCount = picked.length < 6 ? picked.length : 6;
          }
          final ids = picked.map((t) => t.bvid).toSet();
          state.pending.removeWhere((t) => ids.contains(t.bvid));
        }
        state.loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _DiscoveryBatch {
  bool started = false, loading = false, appendAttempt = false;
  String error = '';
  int cursor = 0, featuredCount = 0;
  List<Track> tracks = [];
  final List<Track> pending = [];
  final Set<String> seen = {};
  List<_DiscoverySource>? sources;
}

class _DiscoverySource {
  _DiscoverySource(this.query);
  final String query;
  int page = 1;
  bool done = false;
  final Set<String> seen = {};
}
