import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/discovery_policy.dart';
import '../models/music.dart';

typedef DiscoverySearch =
    Future<List<Track>> Function(String query, {int page});

/// Session-only discovery: never mutates manual search, library or playback.
class DiscoveryController extends ChangeNotifier {
  DiscoveryController({
    required this.search,
    required this.seeds,
    required this.recent,
    this.history,
    DiscoveryPreferences? preferences,
    Random? random,
  }) : preferences = preferences ?? DiscoveryPreferences(),
       random = random ?? Random();
  final DiscoveryPreferences preferences;
  final Random random;
  final List<Track> Function()? history;
  String _signature() =>
      '${preferences.revision}:${seeds().map((t) => t.bvid).join(',')}:${history?.call().map((t) => t.bvid).join(',')}';
  void preferencesChanged() {
    if (!_disposed) notifyListeners();
  }

  final DiscoverySearch search;
  final List<Track> Function() seeds;
  final Set<String> Function() recent;
  static const tags = ['全部', '轻音乐', '翻唱', '现场', '纯音乐'];
  final Map<String, _DiscoveryBatch> _batches = {};
  String tag = '全部';
  bool _disposed = false;
  _DiscoveryBatch get _state => _batches.putIfAbsent(tag, _DiscoveryBatch.new);
  List<Track> get tracks => List.unmodifiable(
    _state.tracks
        .take(_state.featuredCount)
        .where((t) => !preferences.blocked.contains(t.bvid)),
  );
  List<Track> get moreTracks => List.unmodifiable(
    _state.tracks
        .skip(_state.featuredCount)
        .where((t) => !preferences.blocked.contains(t.bvid)),
  );
  bool get loadingMore => _state.loading && _state.appendAttempt;
  bool get loadMoreFailed => _state.appendAttempt && _state.error.isNotEmpty;
  bool get initialized => _state.started;
  bool get loading => _state.loading;
  String get error => _state.error;
  bool get exhausted =>
      _state.signature == _signature() &&
      _state.sources != null &&
      _state.sources!.every((s) => s.done) &&
      _pick(_state, 1).isEmpty;

  Future<void> ensureLoaded() => _state.started ? Future.value() : nextBatch();

  Future<void> selectTag(String value) async {
    if (!tags.contains(value)) throw ArgumentError.value(value, 'tag');
    if (_disposed || tag == value) return;
    tag = value;
    notifyListeners();
    await ensureLoaded();
  }

  bool get needsMoreSearch => _state.needsMoreSearch;
  void _updateSources(_DiscoveryBatch state) {
    final signature = _signature();
    if (state.sources != null && state.signature == signature) return;
    final previous = {
      for (final s in state.sources ?? <_DiscoverySource>[]) s.query: s,
    };
    state.sources =
        DiscoveryPolicy.queries(
              tag,
              seeds(),
              history?.call() ?? [],
              preferences,
              random,
            )
            .map(
              (q) =>
                  (previous[q.text] ?? _DiscoverySource(q.text, q.weight))
                    ..weight = q.weight,
            )
            .toList();
    state.pending.removeWhere((c) => c.interest);
    state.signature = signature;
  }

  bool _needsSupply(_DiscoveryBatch state, int count) {
    final picked = _pick(state, count);
    if (picked.length < count) return true;
    final interest = (count * .7).round();
    return (picked.where((c) => c.interest).length < interest &&
            state.sources!.any((s) => s.weight > 0 && !s.done)) ||
        (picked.where((c) => !c.interest).length < count - interest &&
            state.sources!.any((s) => s.weight == 0 && !s.done) &&
            state.sources!.any((s) => s.weight > 0));
  }

  List<DiscoveryCandidate> _pick(_DiscoveryBatch state, int count) =>
      DiscoveryPolicy.pick(state.pending, count, preferences, recent());

  Future<void> nextBatch() {
    if (!_state.loading && ++_state.rounds % 3 == 0) _state.signature = '';
    return _load(append: false);
  }

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
    _updateSources(state);
    state.needsMoreSearch = false;
    final signature = state.signature;
    var stale = false;
    notifyListeners();
    try {
      for (
        var attempts = 0;
        attempts < 2 && _needsSupply(state, count);
        attempts++
      ) {
        final available = state.sources!.where((s) => !s.done).toList();
        if (available.isEmpty) break;
        final interests = available.where((s) => s.weight > 0).toList();
        final general = available.where((s) => s.weight == 0).toList();
        final ready = _pick(state, count);
        final wantsInterest =
            interests.isNotEmpty &&
            (ready.where((c) => c.interest).length < (count * .7).round()) &&
            (attempts == 0 || state.cursor.isEven || general.isEmpty);
        final pool = wantsInterest && interests.isNotEmpty
            ? interests
            : general.isNotEmpty
            ? general
            : interests;
        final source =
            pool[(interests.isEmpty ? state.cursor : state.cursor ~/ 2) %
                pool.length];
        final found = await search(source.query, page: source.page);
        if (_disposed) return;
        if (_signature() != signature) {
          stale = true;
          break;
        }
        final fresh = found.where((t) => source.seen.add(t.bvid)).toList();
        source.done = fresh.isEmpty;
        source.page++;
        state.cursor++;
        for (final (index, t) in fresh.indexed) {
          if (state.seen.add(t.bvid) &&
              DiscoveryPolicy.allowed(t) &&
              !preferences.blocked.contains(t.bvid)) {
            state.pending.add(
              DiscoveryCandidate(
                t,
                rank: (source.page - 2) * 20 + index,
                interest: source.weight > 0,
                weight: source.weight,
              ),
            );
          }
        }
        if (state.pending.length > 200) {
          final retained = _pick(state, 200);
          final tail = state.pending.where((c) => !retained.contains(c));
          state.pending = [...retained, ...tail].take(200).toList();
        }
      }
    } on Exception catch (e) {
      if (_disposed) return;
      state.error = e is AppFailure ? e.message : '推荐加载失败，请重试';
    } finally {
      if (!_disposed && !stale) {
        final candidates = _pick(state, count);
        final picked = candidates.map((c) => c.track).toList();
        state.needsMoreSearch =
            picked.isEmpty && !state.sources!.every((s) => s.done);
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
          state.pending.removeWhere((t) => ids.contains(t.track.bvid));
        }
        state.loading = false;
        notifyListeners();
      } else if (!_disposed) {
        state.loading = false;
        state.needsMoreSearch = true;
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
  bool started = false,
      loading = false,
      appendAttempt = false,
      needsMoreSearch = false;
  String signature = '';
  String error = '';
  int cursor = 0, featuredCount = 0, rounds = 0;
  List<Track> tracks = [];
  List<DiscoveryCandidate> pending = [];
  final Set<String> seen = {};
  List<_DiscoverySource>? sources;
}

class _DiscoverySource {
  _DiscoverySource(this.query, this.weight);
  double weight;
  final String query;
  int page = 1;
  bool done = false;
  final Set<String> seen = {};
}
