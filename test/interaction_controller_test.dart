import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/models/music.dart';
import 'support/fakes.dart';

void main() {
  late TestLibrary fixture;
  setUp(() async {
    fixture = await TestLibrary.create();
  });
  tearDown(() async {
    await fixture.close();
  });
  test(
    'collection sort persists independently and batch removal retains library likes and files',
    () async {
      final p = fixture.controller;
      await p.remember(firstTrack);
      await p.remember(secondTrack);
      await p.addPlaylist('测试', track: firstTrack);
      await p.addToPlaylist(p.playlists.single, secondTrack);
      final list = p.playlists.single;
      await p.editPlaylist(list, description: '夜晚听的歌');
      expect(Playlist.fromJson(list.toJson()).description, isEmpty);
      expect(
        Playlist.fromJson(p.playlists.single.toJson()).description,
        '夜晚听的歌',
      );
      await p.setCollectionSort(list.id, 'recent');
      expect(p.collectionIds(list.id, list.trackIds), [
        secondTrack.id,
        firstTrack.id,
      ]);
      await p.play(firstTrack);
      expect(p.collectionIds(list.id, list.trackIds), [
        secondTrack.id,
        firstTrack.id,
      ]);
      expect(p.collectionIds('library', p.library.keys), [
        firstTrack.id,
        secondTrack.id,
      ]);
      expect(
        (await p.db.readState('library'))!['collectionSort'][list.id],
        'recent',
      );
      await p.toggleLike(firstTrack);
      await p.removeFromPlaylist(list, {firstTrack.id, secondTrack.id});
      expect(p.playlists.single.trackIds, isEmpty);
      expect(p.playlists.single.description, '夜晚听的歌');
      expect(p.library.length, 2);
      expect(p.likes, contains(firstTrack.id));
      expect(p.current!.id, firstTrack.id);
      expect(p.playing, isTrue);
    },
  );
  test(
    '51-track collection replaces a stale two-track queue and survives shuffle resume',
    () async {
      final p = fixture.controller;
      await p.enqueue(firstTrack);
      await p.enqueue(secondTrack);
      final tracks = List.generate(
        51,
        (i) => Track(
          bvid: 'BVfixture$i',
          cid: 1000 + i,
          title: '曲目$i',
          artist: 'UP',
          cover: '',
          duration: 30,
        ),
      );
      for (final t in tracks) {
        await p.remember(t);
      }
      await p.setMode('shuffle');
      await p.playFromCollection(tracks[20], tracks.map((t) => t.id).toList());
      expect(p.queue.length, 51);
      expect(p.current!.id, tracks[20].id);
      final seen = {p.current!.id};
      for (var i = 0; i < 25; i++) {
        await p.next();
        expect(seen.add(p.current!.id), isTrue);
      }
      await p.save();
      final directory = fixture.directory;
      await fixture.close(deleteData: false);
      fixture = await TestLibrary.create(dataDirectory: directory);
      final restored = fixture.controller;
      expect(restored.playing, isFalse);
      await restored.toggle();
      for (var i = 0; i < 25; i++) {
        await restored.next();
        expect(seen.add(restored.current!.id), isTrue);
      }
      expect(seen.length, 51);
    },
  );
  test(
    'shuffle previous retraces, play-next takes precedence and duplicate enqueue stays put',
    () async {
      final p = fixture.controller;
      await p.playFromCollection(firstTrack, [firstTrack.id]);
      await p.enqueue(secondTrack);
      final before = List.of(p.queue);
      await p.enqueue(firstTrack);
      expect(p.queue, before);
      await p.setMode('shuffle');
      await p.next();
      expect(p.current!.id, secondTrack.id);
      await p.next(-1);
      expect(p.current!.id, firstTrack.id);
      await p.next();
      expect(p.current!.id, secondTrack.id);
      await p.enqueue(firstTrack, next: true);
      await p.next();
      expect(p.current!.id, firstTrack.id);
      await p.clearQueue();
      await p.next();
      expect(p.current, isNull);
    },
  );
  test('rapid next and completion requests produce one transition', () async {
    final p = fixture.controller;
    await p.enqueue(firstTrack);
    await p.enqueue(secondTrack);
    await p.play(firstTrack);
    final entered = Completer<void>(), release = Completer<AudioStream>();
    fixture.api.resolveAnswer = (track, {bool standard = false, cancelToken}) {
      entered.complete();
      return release.future;
    };
    final a = p.next();
    await entered.future;
    final b = p.next();
    p.playback.onCompleted?.call();
    release.complete(
      const AudioStream('https://example.test/second', {}, 'test'),
    );
    await Future.wait([a, b]);
    expect(p.current!.id, secondTrack.id);
  });
  test(
    'clearing while a native source is opening cannot resurrect playback',
    () async {
      final p = fixture.controller;
      final entered = Completer<void>(), release = Completer<void>();
      fixture.playback.openAnswer = (_) async {
        entered.complete();
        await release.future;
      };
      final request = p.play(firstTrack);
      await entered.future;
      final clear = p.clearQueue();
      release.complete();
      await Future.wait([request, clear]);
      expect(p.current, isNull);
      expect(p.queue, isEmpty);
      expect(p.playing, isFalse);
    },
  );
  test(
    'a later selected track wins even if the previous native open is slow',
    () async {
      final p = fixture.controller;
      final entered = Completer<void>(), release = Completer<void>();
      fixture.playback.openAnswer = (t) async {
        if (t.id == firstTrack.id) {
          entered.complete();
          await release.future;
        }
      };
      final first = p.play(firstTrack);
      await entered.future;
      final last = p.play(secondTrack);
      release.complete();
      await Future.wait([first, last]);
      expect(p.current!.id, secondTrack.id);
      expect(fixture.playback.opened.last, secondTrack.id);
    },
  );
  test(
    'a new collection selected during clear is retained, not cleared by a late stop',
    () async {
      final p = fixture.controller;
      final entered = Completer<void>(), release = Completer<void>();
      fixture.playback.openAnswer = (t) async {
        if (t.id == firstTrack.id) {
          entered.complete();
          await release.future;
        }
      };
      final old = p.play(firstTrack);
      await entered.future;
      final clear = p.clearQueue();
      final fresh = p.playFromCollection(secondTrack, [secondTrack.id]);
      release.complete();
      await Future.wait([old, clear, fresh]);
      expect(p.queue, [secondTrack.id]);
      expect(p.current!.id, secondTrack.id);
      expect(p.playing, isTrue);
    },
  );
  test(
    'failed shuffle target does not enter actual playback history',
    () async {
      final p = fixture.controller;
      const third = Track(
        bvid: 'BVthird',
        cid: 3,
        title: 'third',
        artist: '',
        cover: '',
        duration: 30,
      );
      await p.remember(firstTrack);
      await p.remember(secondTrack);
      await p.remember(third);
      await p.playFromCollection(firstTrack, [
        firstTrack.id,
        secondTrack.id,
        third.id,
      ]);
      await p.setMode('shuffle');
      await p.enqueue(secondTrack, next: true);
      fixture.api.resolveAnswer =
          (t, {bool standard = false, cancelToken}) async {
            if (t.id == secondTrack.id) throw const AppFailure('失效曲目');
            return const AudioStream('https://example.test/valid', {}, 'test');
          };
      await p.next();
      expect(p.current!.id, firstTrack.id);
      expect(p.error, '失效曲目');
      await p.next();
      expect(p.current!.id, third.id);
      await p.next(-1);
      expect(p.current!.id, firstTrack.id);
    },
  );
  test(
    'switching mode during a pending next does not reselect the arriving track',
    () async {
      final p = fixture.controller;
      const third = Track(
        bvid: 'BVthird',
        cid: 3,
        title: 'third',
        artist: '',
        cover: '',
        duration: 30,
      );
      await p.remember(firstTrack);
      await p.remember(secondTrack);
      await p.remember(third);
      await p.playFromCollection(firstTrack, [
        firstTrack.id,
        secondTrack.id,
        third.id,
      ]);
      final entered = Completer<void>(), release = Completer<AudioStream>();
      fixture.api.resolveAnswer = (_, {bool standard = false, cancelToken}) {
        entered.complete();
        return release.future;
      };
      final pending = p.next();
      await entered.future;
      await p.setMode('shuffle');
      release.complete(
        const AudioStream('https://example.test/next', {}, 'test'),
      );
      await pending;
      fixture.api.resolveAnswer = null;
      await p.next();
      expect(p.current!.id, third.id);
    },
  );
  test(
    'disposing during a pending system next discards the late transition safely',
    () async {
      final extra = await TestLibrary.create();
      final p = extra.controller;
      try {
        await p.enqueue(firstTrack);
        await p.enqueue(secondTrack);
        await p.play(firstTrack);
        final entered = Completer<void>(), release = Completer<AudioStream>();
        extra.api.resolveAnswer = (_, {bool standard = false, cancelToken}) {
          entered.complete();
          return release.future;
        };
        final pending = p.next();
        await entered.future;
        p.dispose();
        release.complete(
          const AudioStream('https://example.test/late', {}, 'test'),
        );
        await pending;
        await p.next();
        expect(extra.playback.opened.last, firstTrack.id);
      } finally {
        await extra.close(disposeController: false);
      }
    },
  );
  test('manual next advances even when single-repeat is selected', () async {
    final p = fixture.controller;
    await p.enqueue(firstTrack);
    await p.enqueue(secondTrack);
    await p.play(firstTrack);
    await p.setMode('repeat');
    await p.next();
    expect(p.current!.id, secondTrack.id);
  });
  test(
    'automatic completion repeats one track or wraps the list according to the visible mode',
    () async {
      final p = fixture.controller;
      await p.enqueue(firstTrack);
      await p.enqueue(secondTrack);
      await p.play(secondTrack);
      await p.setMode('repeat');
      await p.next(1, true);
      expect(p.current!.id, secondTrack.id);
      await p.setMode('order');
      await p.next(1, true);
      expect(p.current!.id, firstTrack.id);
    },
  );
  test('clearing queue cannot resume the removed current track', () async {
    final p = fixture.controller;
    await p.play(firstTrack);
    await p.clearQueue();
    await p.toggle();
    expect(p.queue, isEmpty);
    expect(p.playing, isFalse);
    expect(p.current, isNull);
  });
  test(
    'stale playlist and queue actions give recoverable failures, never range errors',
    () async {
      final p = fixture.controller;
      await expectLater(
        p.addToPlaylist(const Playlist('gone', '已删除', []), firstTrack),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        p.editPlaylist(const Playlist('gone', '已删除', []), name: '重命名'),
        throwsA(isA<AppFailure>()),
      );
      await p.moveQueue(-1, 1);
      expect(p.queue, isEmpty);
    },
  );
  test(
    'canonical resolution merges references instead of duplicating an existing queue item',
    () async {
      final p = fixture.controller;
      const placeholder = Track(
        bvid: 'BV1xx411c7mD',
        cid: 0,
        title: '占位',
        artist: '',
        cover: '',
        duration: 0,
      );
      await p.enqueue(firstTrack);
      await p.enqueue(placeholder);
      await p.toggleLike(placeholder);
      await p.canonical(placeholder);
      expect(p.queue, [firstTrack.id]);
      expect(p.likes, [firstTrack.id]);
    },
  );
  test(
    'playing imported placeholders preserves library order before and after restart',
    () async {
      final p = fixture.controller;
      const placeholder = Track(
        bvid: 'BV1xx411c7mD',
        cid: 0,
        title: '导入曲目',
        artist: '',
        cover: '',
        duration: 30,
      );
      await p.remember(placeholder);
      await p.remember(secondTrack);
      await p.play(placeholder);
      expect(p.library.keys, [firstTrack.id, secondTrack.id]);
      await p.save();
      final directory = fixture.directory;
      await fixture.close(deleteData: false);
      fixture = await TestLibrary.create(dataDirectory: directory);
      expect(fixture.controller.library.keys, [firstTrack.id, secondTrack.id]);
      expect(fixture.controller.current!.id, firstTrack.id);
      expect(fixture.controller.playing, isFalse);
    },
  );
  test('an older search result never replaces a newer query', () async {
    final p = fixture.controller;
    fixture.api.searches['旧'] = Completer<List<Track>>();
    final old = p.search('旧');
    await p.search('新');
    fixture.api.searches['旧']!.complete([firstTrack]);
    await old;
    expect(p.query, '新');
    expect(p.results.length, 2);
  });
  test(
    'late automatic lyric matching cannot overwrite a manual lyric choice',
    () async {
      final p = fixture.controller;
      final found = Completer<List<Map<String, dynamic>>>();
      final started = Completer<void>();
      (p.lyricsClient as FixtureLyrics).answer = (_) {
        started.complete();
        return found.future;
      };
      await p.play(firstTrack);
      await started.future;
      await p.setLyrics('[00:00.00]手动歌词');
      found.complete([
        {'syncedLyrics': '[00:00.00]迟到的自动歌词'},
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(p.lyricText, '[00:00.00]手动歌词');
      expect(await p.downloads.lyrics(firstTrack), '[00:00.00]手动歌词');
    },
  );
}
