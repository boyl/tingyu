import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/models/discovery_policy.dart';
import 'package:tingyu/models/discovery_listening.dart';
import 'package:tingyu/models/music.dart';

Track t(int n, {String? title, String? artist, int duration = 180}) => Track(
  bvid: 'BV$n',
  cid: 0,
  title: title ?? '歌曲名称$n',
  artist: artist ?? 'UP$n',
  cover: '',
  duration: duration,
);
void main() {
  test('new skips do not extend an old positive signal past thirty days', () {
    var now = DateTime(2026, 1, 1);
    final prefs = DiscoveryPreferences(clock: () => now);
    prefs.listen('BV1', positive: true);
    now = now.add(const Duration(days: 29));
    prefs.listen('BV1', positive: false);
    now = now.add(const Duration(days: 2));
    expect(prefs.positive('BV1'), false);
  });

  test(
    'bounded interests cover likes and history; tag constrains both pools',
    () {
      final prefs = DiscoveryPreferences();
      final q = DiscoveryPolicy.queries(
        '翻唱',
        List.generate(50, t),
        List.generate(50, (i) => t(i + 100)),
        prefs,
        Random(4),
      );
      expect(q.where((q) => q.interest).length, 6);
      expect(q.every((q) => q.text.contains('翻唱')), true);
      expect(q.any((q) => q.weight == 3), true);
      expect(q.any((q) => q.weight == 1), true);
      expect(q.last.text, '翻唱 音乐');
      expect(DiscoveryPolicy.queries('全部', [], [], prefs, Random(1)).length, 2);
      expect(DiscoveryPolicy.phrase('【现场】歌曲名｜歌手'), '【现场】歌曲名');
    },
  );
  test('70/30 pools with stable ordering, author limits and fallback', () {
    final candidates = List.generate(
      30,
      (i) => DiscoveryCandidate(t(i), interest: i < 20, weight: i < 20 ? 3 : 0),
    );
    final picks = DiscoveryPolicy.pick(
      candidates,
      10,
      DiscoveryPreferences(),
      {},
    );
    expect(picks.length, 10);
    expect(picks.where((c) => c.interest).length, 7);
    expect(
      DiscoveryPolicy.pick(
        candidates.take(20).toList(),
        16,
        DiscoveryPreferences(),
        {},
      ).length,
      16,
    );
    final oneAuthor = List.generate(
      40,
      (i) => DiscoveryCandidate(t(i, artist: 'same')),
    );
    expect(
      DiscoveryPolicy.pick(oneAuthor, 16, DiscoveryPreferences(), {}).length,
      2,
    );
  });
  test(
    'exposure, title duplicates, recent listens and repeated skips lower scores',
    () {
      final prefs = DiscoveryPreferences(clock: () => DateTime(2026, 11, 11));
      prefs.expose(t(1));
      prefs.listen('BV2', positive: false);
      prefs.listen('BV2', positive: false);
      final picked = DiscoveryPolicy.pick(
        List.generate(6, (i) => DiscoveryCandidate(t(i))),
        6,
        prefs,
        {'BV0'},
      );
      expect(picked.first.track.bvid, 'BV3');
      prefs.blocked.add('BV3');
      expect(
        DiscoveryPolicy.pick(
          picked,
          6,
          prefs,
          {},
        ).any((c) => c.track.bvid == 'BV3'),
        false,
      );
      expect(DiscoveryPolicy.allowed(t(1, title: '歌曲推荐合集')), true);
      expect(DiscoveryPolicy.allowed(t(2, title: '教你唱歌')), false);
      expect(DiscoveryPolicy.allowed(t(3, title: '晚会唱什么歌能闪耀全场？')), false);
      expect(DiscoveryPolicy.allowed(t(4, title: '比赛还不知道选什么歌？')), false);
      expect(DiscoveryPolicy.allowed(t(5, title: '跨年晚会歌曲合集')), true);
      expect(
        DiscoveryPolicy.titleKey('歌曲名 现场'),
        isNot(DiscoveryPolicy.titleKey('歌曲名 翻唱')),
      );
    },
  );
  test('restart retains exposure and blocking, expires bounded evidence', () {
    var now = DateTime(2026, 11, 11);
    final prefs = DiscoveryPreferences(clock: () => now);
    for (var i = 0; i < 1005; i++) {
      prefs.expose(t(i));
    }
    expect(prefs.exposures.length, 1000);
    prefs.listen('BV1', positive: true);
    prefs.blocked.add('BV2');
    final restored = DiscoveryPreferences(clock: () => now)
      ..restore(prefs.toJson());
    expect(restored.exposures.length, 1000);
    expect(restored.blocked, {'BV2'});
    now = now.add(const Duration(days: 8));
    restored.prune();
    expect(restored.exposures, isEmpty);
    expect(restored.positive('BV1'), true);
    now = now.add(const Duration(days: 23));
    restored.prune();
    expect(restored.behavior, isEmpty);
    expect(restored.blocked, {'BV2'});
    restored.clear();
    expect(restored.blocked, isEmpty);
  });
  test(
    'listening ignores seek, pause, buffering and failures; threshold once',
    () {
      final meter = DiscoveryListening()..start('BV1');
      var now = DateTime(2026, 11, 11);
      void tick(int position, {bool active = true}) {
        now = now.add(const Duration(seconds: 1));
        meter.sample(Duration(seconds: position), now, active: active);
      }

      tick(0);
      tick(1);
      tick(100);
      tick(101, active: false);
      tick(102);
      expect(meter.seconds, 1);
      for (var i = 103; i <= 132; i++) {
        tick(i);
      }
      expect(meter.qualifies(60), true);
      meter.rewarded = true;
      expect(meter.qualifies(60), false);
      meter.start('BV2');
      tick(0);
      tick(1);
      expect(meter.earlySkip, true);
      meter.failed = true;
      expect(meter.earlySkip, false);
    },
  );
}
