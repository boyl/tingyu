import 'dart:math';
import 'music.dart';

/// Local recommendation evidence. No network or UI dependencies.
class DiscoveryPreferences {
  DiscoveryPreferences({DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final DateTime Function() clock;
  final Map<String, Map<String, dynamic>> exposures = {}, behavior = {};
  final Set<String> blocked = {};
  int revision = 0;

  void restore(Map<String, dynamic>? value) {
    if (value == null) return;
    if (value['version'] != 1) throw const FormatException('不支持的推荐偏好版本');
    exposures.clear();
    behavior.clear();
    blocked.clear();
    for (final pair in [('exposures', exposures), ('behavior', behavior)]) {
      final map = value[pair.$1] as Map? ?? {};
      for (final entry in map.entries) {
        pair.$2[entry.key as String] = Map<String, dynamic>.from(
          entry.value as Map,
        );
      }
    }
    blocked.addAll((value['blocked'] as List? ?? []).cast<String>());
    prune();
    revision++;
  }

  void prune() {
    for (final pair in [(exposures, 7), (behavior, 30)]) {
      final cutoff = clock()
          .subtract(Duration(days: pair.$2))
          .millisecondsSinceEpoch;
      pair.$1.removeWhere((_, v) => (v['time'] as num? ?? 0) < cutoff);
      final keys = pair.$1.keys.toList()
        ..sort(
          (a, b) => (pair.$1[b]!['time'] as num).compareTo(
            pair.$1[a]!['time'] as num,
          ),
        );
      for (final key in keys.skip(1000)) {
        pair.$1.remove(key);
      }
    }
  }

  Map<String, dynamic> toJson() {
    prune();
    return {
      'version': 1,
      'exposures': exposures,
      'behavior': behavior,
      'blocked': blocked.toList(),
    };
  }

  void expose(Track t) {
    exposures[t.bvid] = {
      'time': clock().millisecondsSinceEpoch,
      'artist': t.artist.trim(),
      'title': DiscoveryPolicy.titleKey(t.title),
    };
    prune();
  }

  bool positive(String bv) =>
      (behavior[bv]?['positiveAt'] as num? ?? 0) >=
      clock().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
  bool earlySkipped(String bv) {
    final times = (behavior[bv]?['skips'] as List? ?? []).cast<int>();
    return times
            .where(
              (t) =>
                  t >=
                  clock()
                      .subtract(const Duration(days: 7))
                      .millisecondsSinceEpoch,
            )
            .length >=
        2;
  }

  void listen(String bv, {required bool positive}) {
    final now = clock();
    final entry = behavior.putIfAbsent(bv, () => {});
    entry['time'] = now.millisecondsSinceEpoch;
    if (positive) {
      final day = '${now.year}-${now.month}-${now.day}';
      if (entry['positive'] == day) return;
      entry['positive'] = day;
      entry['positiveAt'] = now.millisecondsSinceEpoch;
    } else {
      final cutoff = now
          .subtract(const Duration(days: 7))
          .millisecondsSinceEpoch;
      entry['skips'] = [
        ...(entry['skips'] as List? ?? []).cast<int>().where(
          (t) => t >= cutoff,
        ),
        now.millisecondsSinceEpoch,
      ].takeLast(10);
    }
    revision++;
    prune();
  }

  void clear() {
    exposures.clear();
    behavior.clear();
    blocked.clear();
    revision++;
  }
}

extension on List<int> {
  List<int> takeLast(int n) => skip(length > n ? length - n : 0).toList();
}

class DiscoveryCandidate {
  DiscoveryCandidate(
    this.track, {
    this.rank = 0,
    this.interest = false,
    this.weight = 0,
  });
  final Track track;
  final int rank;
  final bool interest;
  final double weight;
}

class DiscoveryQuery {
  DiscoveryQuery(this.text, {this.weight = 0});
  final String text;
  final double weight;
  bool get interest => weight > 0;
}

class DiscoveryPolicy {
  static String phrase(String title) => title
      .replaceAll(RegExp(r'【(?:高音质|无损|完整版|强烈推荐)】|\[(?:高音质|无损|完整版)\]'), ' ')
      .split(RegExp(r'[｜|]'))
      .first
      .trim();
  static String titleKey(String title) =>
      title.toLowerCase().replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '');
  static bool allowed(Track t) => !RegExp(
    r'教程|教学|教你|唱歌技巧|如何.*(?:唱|歌)|(?:歌曲|音乐|乐理|唱法).*(?:解析|讲解)|(?:解析|讲解).*(?:歌曲|乐理|唱法)|(?:比赛|晚会|年会).*(?:选什么歌|唱什么歌|不知道.*(?:选|唱))|练习歌曲推荐|歌曲推荐.*(?:技巧|练习)|(?:选歌|歌曲选择).*(?:建议|攻略)',
  ).hasMatch(t.title);

  static List<DiscoveryQuery> queries(
    String tag,
    List<Track> likes,
    List<Track> history,
    DiscoveryPreferences prefs,
    Random random,
  ) {
    prefs.prune();
    final pool = <String, (Track, double)>{};
    for (final t in history.take(50)) {
      if (!prefs.blocked.contains(t.bvid)) {
        pool[t.bvid] = (t, prefs.positive(t.bvid) ? 2 : 1);
      }
    }
    for (final t in likes.take(50)) {
      if (!prefs.blocked.contains(t.bvid)) pool[t.bvid] = (t, 3);
    }
    final recency = <String, double>{
      for (final (i, t) in history.take(50).indexed) t.bvid: 1 / (1 + i / 50),
      for (final (i, t) in likes.take(50).indexed) t.bvid: 1 / (1 + i / 50),
    };
    final weighted =
        pool.values
            .map(
              (v) => (
                v,
                -log(max(random.nextDouble(), 0.000001)) /
                    (v.$2 * recency[v.$1.bvid]!),
              ),
            )
            .toList()
          ..sort((a, b) => a.$2.compareTo(b.$2));
    final result = <String, DiscoveryQuery>{};
    void add((Track, double) v) {
      final raw = phrase(v.$1.title);
      if (titleKey(raw).runes.length < 2) return;
      final p = String.fromCharCodes(raw.runes.take(32));
      final q = '$p ${tag == '全部' ? '音乐' : tag}';
      result.putIfAbsent(q, () => DiscoveryQuery(q, weight: v.$2));
    }

    // Keep both sources represented when they provide distinct clues.
    final likedIds = likes.map((t) => t.bvid).toSet();
    for (final liked in [true, false]) {
      final candidates = weighted.where(
        (v) => likedIds.contains(v.$1.$1.bvid) == liked,
      );
      if (candidates.isNotEmpty) add(candidates.first.$1);
    }
    for (final v in weighted) {
      if (result.length >= 6) break;
      add(v.$1);
    }
    return [
      ...result.values,
      if (tag == '全部') ...[
        DiscoveryQuery('音乐 现场 翻唱'),
        DiscoveryQuery('轻音乐 纯音乐'),
      ] else
        DiscoveryQuery('$tag 音乐'),
    ];
  }

  static List<DiscoveryCandidate> pick(
    List<DiscoveryCandidate> pending,
    int count,
    DiscoveryPreferences prefs,
    Set<String> recent,
  ) {
    prefs.prune();
    final exposures = prefs.exposures.values.toList()
      ..sort((a, b) => (b['time'] as num).compareTo(a['time'] as num));
    final authors = <String, int>{};
    for (final e in exposures.take(30)) {
      final name = e['artist'] as String;
      authors[name] = (authors[name] ?? 0) + 1;
    }
    final exposedTitles = exposures.map((e) => e['title']).toSet();
    final firstTitles = <String, DiscoveryCandidate>{};
    for (final c in pending) {
      final key = titleKey(c.track.title);
      if (key.runes.length >= 4) firstTitles.putIfAbsent(key, () => c);
    }
    double score(DiscoveryCandidate c) {
      final t = c.track, key = titleKey(c.track.title);
      return 3 * (1 - min(c.rank, 19) / 19) +
          c.weight -
          (recent.contains(t.bvid) ? 2 : 0) -
          (prefs.exposures.containsKey(t.bvid) ? 3 : 0) -
          (prefs.earlySkipped(t.bvid) ? 2 : 0) -
          ((authors[t.artist.trim()] ?? 0) >= 2 ? 2 : 0) -
          (key.runes.length >= 4 &&
                  (exposedTitles.contains(key) || firstTitles[key] != c)
              ? 2
              : 0) -
          (t.duration > 0 && t.duration < 45 ? 1 : 0);
    }

    final scores = {for (final c in pending) c: score(c)};
    final ordered =
        pending.indexed
            .where((v) => !prefs.blocked.contains(v.$2.track.bvid))
            .toList()
          ..sort((a, b) {
            final cmp = scores[b.$2]!.compareTo(scores[a.$2]!);
            return cmp == 0 ? a.$1.compareTo(b.$1) : cmp;
          });
    final picked = <DiscoveryCandidate>[], used = <String, int>{};
    bool add(DiscoveryCandidate c) {
      final name = c.track.artist.trim();
      if (picked.contains(c) || (name.isNotEmpty && (used[name] ?? 0) >= 2)) {
        return false;
      }
      picked.add(c);
      used[name] = (used[name] ?? 0) + 1;
      return true;
    }

    final interestCount = (count * .7).round();
    for (final pool in [
      (true, interestCount),
      (false, count - interestCount),
    ]) {
      if (pool.$2 == 0) continue;
      var n = 0;
      for (final v in ordered) {
        if (v.$2.interest == pool.$1 && add(v.$2)) {
          if (++n == pool.$2) break;
        }
      }
    }
    for (final v in ordered) {
      if (picked.length >= count) break;
      add(v.$2);
    }
    picked.sort((a, b) {
      final cmp = scores[b]!.compareTo(scores[a]!);
      return cmp == 0 ? pending.indexOf(a).compareTo(pending.indexOf(b)) : cmp;
    });
    // Spread authors through the featured shelf without changing batch membership.
    final featured = <DiscoveryCandidate>[], seen = <String>{};
    for (final c in picked) {
      if (featured.length == 6) break;
      if (c.track.artist.isEmpty || seen.add(c.track.artist.trim())) {
        featured.add(c);
      }
    }
    return [...featured, ...picked.where((c) => !featured.contains(c))];
  }
}
