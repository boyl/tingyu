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
