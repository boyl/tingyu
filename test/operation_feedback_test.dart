import 'package:flutter_test/flutter_test.dart';
import 'support/fakes.dart';

void main() {
  late TestLibrary f;
  setUp(() async {
    f = await TestLibrary.create();
  });
  tearDown(() async {
    await f.close();
  });

  test(
    'failed like persistence restores membership and original order',
    () async {
      final p = f.controller;
      await p.toggleLike(firstTrack);
      await p.toggleLike(secondTrack);
      final before = p.likes.toList();
      await f.db.customStatement('DROP TABLE app_state');
      try {
        await expectLater(p.setLiked(firstTrack, false), throwsException);
        expect(p.likes, before);
      } finally {
        await f.db.customStatement(
          'CREATE TABLE app_state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
      }
      await p.setLiked(firstTrack, false);
      final revision = p.likeRevision(firstTrack.id);
      await p.setLiked(firstTrack, true, restoreIndex: 0);
      expect(p.likes, before);
      expect(p.likeRevision(firstTrack.id), greaterThan(revision));
    },
  );

  test(
    'queue removal undo restores order and next priority without reopening audio',
    () async {
      final p = f.controller;
      await p.play(firstTrack);
      await p.enqueue(secondTrack, next: true);
      final before = p.queue.toList();
      final opened = f.playback.opened.toList();
      final undo = await p.removeQueueUndoable(secondTrack.id);
      expect(p.queue.contains(secondTrack.id), isFalse);
      await undo();
      expect(p.queue, before);
      expect(p.adjacentTrack(1)?.id, secondTrack.id);
      expect(f.playback.opened, opened);
      await undo();
      expect(p.queue, before);
    },
  );

  test('old queue undo cannot overwrite newer edits', () async {
    final p = f.controller;
    await p.play(firstTrack);
    await p.enqueue(secondTrack);
    final undo = await p.removeQueueUndoable(secondTrack.id);
    await p.enqueue(secondTrack);
    final current = p.queue.toList();
    await expectLater(undo(), throwsException);
    expect(p.queue, current);
  });

  test(
    'failed add-to-playlist does not masquerade as an existing member',
    () async {
      final p = f.controller;
      await p.remember(secondTrack);
      await p.addPlaylist('歌单', track: firstTrack);
      await f.db.customStatement('DROP TABLE app_state');
      try {
        await expectLater(
          p.addToPlaylist(p.playlists.single, secondTrack),
          throwsException,
        );
        expect(p.playlists.single.trackIds, [firstTrack.id]);
      } finally {
        await f.db.customStatement(
          'CREATE TABLE app_state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
      }
    },
  );
  test('failed queue move restores order and next priority', () async {
    final p = f.controller;
    await p.play(firstTrack);
    await p.enqueue(secondTrack, next: true);
    final before = p.queue.toList();
    await f.db.customStatement('DROP TABLE app_state');
    try {
      await expectLater(p.moveQueue(1, -1), throwsException);
      expect(p.queue, before);
      expect(p.adjacentTrack(1)?.id, secondTrack.id);
    } finally {
      await f.db.customStatement(
        'CREATE TABLE app_state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
    }
  });

  test('failed playlist creation leaves no phantom playlist', () async {
    final p = f.controller;
    await f.db.customStatement('DROP TABLE app_state');
    try {
      await expectLater(p.addPlaylist('新歌单'), throwsException);
      expect(p.playlists, isEmpty);
    } finally {
      await f.db.customStatement(
        'CREATE TABLE app_state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
    }
  });
  test(
    'failed queue undo restores the removed state including next priority',
    () async {
      final p = f.controller;
      await p.play(firstTrack);
      await p.enqueue(secondTrack, next: true);
      final undo = await p.removeQueueUndoable(secondTrack.id);
      final after = p.queue.toList();
      await f.db.customStatement('DROP TABLE app_state');
      try {
        await expectLater(undo(), throwsException);
        expect(p.queue, after);
      } finally {
        await f.db.customStatement(
          'CREATE TABLE app_state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
      }
      await p.save();
      final state = await f.db.readState('library');
      expect(state!['nextPriority'], isEmpty);
      await undo();
      expect(p.queue, [firstTrack.id, secondTrack.id]);
      expect(p.adjacentTrack(1)?.id, secondTrack.id);
    },
  );
}
