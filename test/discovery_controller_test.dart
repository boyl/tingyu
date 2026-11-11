import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/controllers/discovery_controller.dart';
import 'package:tingyu/models/music.dart';

Track track(int i, {String? artist, int cid = 0}) => Track(
  bvid: 'BVtest$i',
  cid: cid,
  title: '歌曲$i',
  artist: artist ?? 'UP$i',
  cover: '',
  duration: 60,
);

void main() {
  test(
    'new likes invalidate late results without moving the current batch',
    () async {
      var seeds = <Track>[];
      final response = Completer<List<Track>>();
      var slow = false;
      final queries = <String>[];
      final d = DiscoveryController(
        search: (q, {page = 1}) async {
          queries.add(q);
          if (slow) return response.future;
          return List.generate(16, (i) => track(i + page * 100));
        },
        seeds: () => seeds,
        recent: () => {},
      );
      addTearDown(d.dispose);
      await d.ensureLoaded();
      final before = d.tracks;
      slow = true;
      final loading = d.loadMore();
      seeds = [track(999)];
      response.complete(List.generate(16, (i) => track(i + 9999)));
      await loading;
      expect(d.tracks, before);
      expect(d.moreTracks.any((t) => t.bvid == 'BVtest9999'), false);
      slow = false;
      await d.loadMore();
      expect(queries, contains('歌曲999 音乐'));
    },
  );
  test(
    'filtered pages have bounded requests and an explicit continuation state',
    () async {
      var calls = 0;
      final d = DiscoveryController(
        search: (_, {page = 1}) async {
          calls++;
          return [
            Track(
              bvid: 'BV$page',
              cid: 0,
              title: '唱歌教学',
              artist: 'UP',
              cover: '',
              duration: 60,
            ),
          ];
        },
        seeds: () => [],
        recent: () => {},
      );
      addTearDown(d.dispose);
      await d.selectTag('翻唱');
      expect(calls, 2);
      expect(d.needsMoreSearch, true);
      expect(d.exhausted, false);
      await d.loadMore();
      expect(calls, 4);
    },
  );

  test(
    'uploader-heavy buffer must not prevent fetching diverse next page',
    () async {
      final pages = <int>[];
      final d = DiscoveryController(
        search: (_, {page = 1}) async {
          pages.add(page);
          return page == 1
              ? List.generate(40, (i) => track(i, artist: '同一UP'))
              : List.generate(20, (i) => track(100 + i));
        },
        seeds: () => [],
        recent: () => {},
      );
      addTearDown(d.dispose);
      await d.selectTag('翻唱');
      expect(pages, [1, 2]);
      expect([...d.tracks, ...d.moreTracks].length, 16);
    },
  );

  test(
    'refresh failure with buffered candidates retains the whole current page',
    () async {
      var fail = false;
      final d = DiscoveryController(
        search: (_, {page = 1}) async {
          if (fail) throw const AppFailure('离线');
          return List.generate(20, (i) => track((page - 1) * 20 + i));
        },
        seeds: () => [],
        recent: () => {},
      );
      addTearDown(d.dispose);
      await d.selectTag('翻唱');
      final featured = d.tracks;
      final rows = d.moreTracks;
      fail = true;
      await d.nextBatch();
      expect(d.error, '离线');
      expect(d.tracks, featured);
      expect(d.moreTracks, rows);
      fail = false;
      await d.retry();
      expect(
        [...d.tracks, ...d.moreTracks].any((t) => t.bvid == 'BVtest16'),
        true,
      );
      expect(d.moreTracks.length, 10);
    },
  );
  test(
    'discovery separates six featured and ten rows then appends without duplicates',
    () async {
      var calls = 0;
      final d = DiscoveryController(
        search: (_, {page = 1}) async {
          calls++;
          return List.generate(60, track);
        },
        seeds: () => [],
        recent: () => {},
      );
      addTearDown(d.dispose);
      await d.ensureLoaded();
      expect(d.tracks.map((t) => t.bvid), List.generate(6, (i) => 'BVtest$i'));
      expect(
        d.moreTracks.map((t) => t.bvid),
        List.generate(10, (i) => 'BVtest${i + 6}'),
      );
      await d.loadMore();
      expect(d.tracks.first.bvid, 'BVtest0');
      expect(d.moreTracks.length, 20);
      expect(
        {
          ...d.tracks.map((t) => t.bvid),
          ...d.moreTracks.map((t) => t.bvid),
        }.length,
        26,
      );
      expect(calls, 1);
      await d.nextBatch();
      expect(d.tracks.first.bvid, 'BVtest26');
      expect(d.moreTracks.first.bvid, 'BVtest32');
      expect(d.moreTracks.length, 10);
      expect(calls, 1);
    },
  );

  test(
    'append failure retries append and preserves both sections across tag changes',
    () async {
      final calls = <int>[];
      var fail = false;
      final d = DiscoveryController(
        search: (_, {page = 1}) async {
          calls.add(page);
          if (fail) throw const AppFailure('离线');
          return List.generate(
            page == 1 ? 16 : 10,
            (i) => track((page - 1) * 16 + i),
          );
        },
        seeds: () => [],
        recent: () => {},
      );
      addTearDown(d.dispose);
      await d.selectTag('纯音乐');
      fail = true;
      await d.loadMore();
      expect(d.error, '离线');
      expect(d.tracks.first.bvid, 'BVtest0');
      expect(d.moreTracks.length, 10);
      fail = false;
      await d.retry();
      expect(calls, [1, 2, 2]);
      expect(d.tracks.first.bvid, 'BVtest0');
      expect(d.moreTracks.length, 20);
      await d.selectTag('现场');
      await d.selectTag('纯音乐');
      expect(d.moreTracks.length, 20);
    },
  );

  test(
    'tutorial search results do not displace listening candidates',
    () async {
      final d = DiscoveryController(
        search: (_, {page = 1}) async => [
          const Track(
            bvid: 'BVtutorial',
            cid: 0,
            title: '教你如何唱歌',
            artist: '教程',
            cover: '',
            duration: 60,
          ),
          ...List.generate(6, track),
        ],
        seeds: () => [],
        recent: () => {},
      );
      addTearDown(d.dispose);
      await d.ensureLoaded();
      expect(d.tracks.length, 6);
      expect(d.tracks.any((t) => t.bvid == 'BVtutorial'), false);
    },
  );
  test(
    'uses liked/title clues and generic discovery, caches whole-page batches and BV dedupes',
    () async {
      final calls = <String>[];
      final d = DiscoveryController(
        search: (q, {page = 1}) async {
          calls.add('$q:$page');
          return [...List.generate(40, track), track(0, cid: 12)];
        },
        seeds: () => [track(99)],
        recent: () => {'BVtest0'},
      );
      addTearDown(d.dispose);
      await d.ensureLoaded();
      expect(calls, ['歌曲99 音乐:1', '音乐 现场 翻唱:1']);
      expect(d.tracks.first.bvid, 'BVtest1');
      final shown = {
        ...d.tracks.map((t) => t.bvid),
        ...d.moreTracks.map((t) => t.bvid),
      };
      final callCount = calls.length;
      await d.ensureLoaded();
      expect(calls.length, callCount);
      await d.nextBatch();
      expect(calls.length - callCount, lessThanOrEqualTo(2));
      expect(
        [...d.tracks, ...d.moreTracks].any((t) => shown.contains(t.bvid)),
        false,
      );
      await d.nextBatch();
      expect(d.tracks.map((t) => t.bvid).toSet().length, d.tracks.length);
    },
  );

  test(
    'limits each uploader to two and retains overflow for later batches',
    () async {
      final d = DiscoveryController(
        search: (_, {page = 1}) async =>
            List.generate(8, (i) => track(i, artist: '同一个 UP')),
        seeds: () => [],
        recent: () => {},
      );
      addTearDown(d.dispose);
      await d.ensureLoaded();
      expect(d.tracks.length, 2);
      final before = d.tracks.map((t) => t.bvid).toSet();
      await d.nextBatch();
      expect(d.tracks.length, 2);
      expect(d.tracks.any((t) => before.contains(t.bvid)), false);
    },
  );

  test('failed page retries without discarding current batch', () async {
    var fail = false;
    final calls = <int>[];
    final d = DiscoveryController(
      search: (_, {page = 1}) async {
        calls.add(page);
        if (fail) throw const AppFailure('断网');
        return List.generate(16, (i) => track((page - 1) * 16 + i));
      },
      seeds: () => [],
      recent: () => {},
    );
    addTearDown(d.dispose);
    await d.selectTag('纯音乐');
    final before = d.tracks;
    fail = true;
    await d.nextBatch();
    expect(d.error, '断网');
    expect(d.tracks, before);
    fail = false;
    await d.nextBatch();
    expect(calls, [1, 2, 2]);
    expect(d.error, isEmpty);
    expect(
      [...d.tracks, ...d.moreTracks].any((t) => t.bvid == 'BVtest16'),
      true,
    );
  });

  test(
    'fast tag changes isolate late responses and suppress duplicate loads',
    () async {
      final old = Completer<List<Track>>();
      var calls = 0;
      final d = DiscoveryController(
        search: (q, {page = 1}) async {
          calls++;
          if (q == '轻音乐 音乐') return old.future;
          return List.generate(16, (i) => track(i + 20));
        },
        seeds: () => [],
        recent: () => {},
      );
      addTearDown(d.dispose);
      final pending = d.selectTag('轻音乐');
      await d.nextBatch();
      expect(calls, 1);
      await d.selectTag('现场');
      old.complete(List.generate(16, track));
      await pending;
      expect(d.tag, '现场');
      expect(d.tracks.first.bvid, 'BVtest20');
      await d.selectTag('轻音乐');
      expect(d.tracks.first.bvid, 'BVtest0');
      expect(calls, 2);
    },
  );

  test(
    'empty responses exhaust a tag; disposed requests do not notify',
    () async {
      final empty = DiscoveryController(
        search: (_, {page = 1}) async => [],
        seeds: () => [],
        recent: () => {},
      );
      await empty.selectTag('翻唱');
      expect(empty.exhausted, true);
      expect(empty.loading, false);
      empty.dispose();
      final future = Completer<List<Track>>();
      final d = DiscoveryController(
        search: (_, {page = 1}) => future.future,
        seeds: () => [],
        recent: () => {},
      );
      var notifications = 0;
      d.addListener(() => notifications++);
      final pending = d.ensureLoaded();
      d.dispose();
      future.complete([track(1)]);
      await pending;
      expect(notifications, 1);
    },
  );
}
