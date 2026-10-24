import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'support/fakes.dart';
import 'package:tingyu/models/music.dart';

void main() {
  late TestLibrary f;
  setUp(() async {
    f = await TestLibrary.create();
  });
  tearDown(() async {
    await f.close();
  });

  test(
    'library deletion removes references atomically and retains files after restart',
    () async {
      final p = f.controller;
      await p.enqueue(firstTrack);
      await p.enqueue(secondTrack);
      await p.setLiked(firstTrack, true);
      await p.addPlaylist('保留歌单', track: firstTrack);
      await p.addToPlaylist(p.playlists.single, secondTrack);
      await p.play(firstTrack);
      final file = File('${f.directory.path}/keep.m4a');
      await file.writeAsString('audio');
      await p.removeLibraryTracks({firstTrack.id});
      expect(p.library.keys, [secondTrack.id]);
      expect(p.likes, isEmpty);
      expect(p.history, isNot(contains(firstTrack.id)));
      expect(p.queue, [secondTrack.id]);
      expect(p.current, isNull);
      expect(p.playlists.single.trackIds, [secondTrack.id]);
      expect(await file.exists(), isTrue);
      final directory = f.directory;
      await f.close(deleteData: false);
      f = await TestLibrary.create(dataDirectory: directory);
      expect(f.controller.library.keys, [secondTrack.id]);
      expect(f.controller.playlists.single.trackIds, [secondTrack.id]);
    },
  );

  test(
    'failed delete transaction preserves records references and current playback',
    () async {
      final p = f.controller;
      await p.play(firstTrack);
      await p.setLiked(firstTrack, true);
      await f.db.customStatement(
        "CREATE TRIGGER reject_delete BEFORE DELETE ON tracks BEGIN SELECT RAISE(ABORT, 'fixture'); END",
      );
      await expectLater(
        p.removeLibraryTracks({firstTrack.id}),
        throwsA(anything),
      );
      expect(p.library, contains(firstTrack.id));
      expect(p.likes, contains(firstTrack.id));
      expect(p.current?.id, firstTrack.id);
      expect(
        (await f.db.loadTracks()).map((t) => t.id),
        contains(firstTrack.id),
      );
    },
  );

  test(
    'batch unlike preserves library playlist queue and playing track',
    () async {
      final p = f.controller;
      await p.setLiked(firstTrack, true);
      await p.setLiked(secondTrack, true);
      await p.addPlaylist('保留', track: firstTrack);
      await p.play(firstTrack);
      await p.removeLikes({firstTrack.id, secondTrack.id});
      expect(p.likes, isEmpty);
      expect(p.library.length, 2);
      expect(p.playlists.single.trackIds, [firstTrack.id]);
      expect(p.current?.id, firstTrack.id);
      expect((await f.db.readState('library'))!['likes'], isEmpty);
    },
  );
  test(
    'batch download removal deletes only selected files and retains metadata',
    () async {
      final p = f.controller;
      await p.setLiked(firstTrack, true);
      await p.remember(secondTrack);
      await p.addPlaylist('保留', track: firstTrack);
      for (final track in [firstTrack, secondTrack]) {
        f.downloads.tasks.add(
          DownloadTask(track, status: DownloadStatus.completed),
        );
        for (final ext in ['m4a', 'cover', 'lyrics']) {
          await File(
            '${f.directory.path}/${track.bvid}_${track.cid}.$ext',
          ).writeAsString('fixture');
        }
      }
      await p.removeDownloads({firstTrack.id});
      expect(f.downloads.tasks.single.track.id, secondTrack.id);
      expect(
        await File(
          '${f.directory.path}/${firstTrack.bvid}_${firstTrack.cid}.m4a',
        ).exists(),
        isFalse,
      );
      expect(
        await File(
          '${f.directory.path}/${secondTrack.bvid}_${secondTrack.cid}.m4a',
        ).exists(),
        isTrue,
      );
      expect(p.likes, [firstTrack.id]);
      expect(p.library.length, 2);
      expect(p.playlists.single.trackIds, [firstTrack.id]);
    },
  );

  test('failed download removal remains visible for retry', () async {
    final task = DownloadTask(firstTrack, status: DownloadStatus.completed);
    f.downloads.tasks.add(task);
    await f.db.customStatement(
      "CREATE TRIGGER reject_download_save BEFORE INSERT ON app_state WHEN NEW.key = 'downloads' BEGIN SELECT RAISE(ABORT, 'fixture'); END",
    );
    await expectLater(
      f.controller.removeDownloads({firstTrack.id}),
      throwsA(anything),
    );
    expect(f.downloads.tasks, contains(task));
    await f.db.customStatement('DROP TRIGGER reject_download_save');
    await f.controller.removeDownloads({firstTrack.id});
    expect(f.downloads.tasks, isEmpty);
  });
}
