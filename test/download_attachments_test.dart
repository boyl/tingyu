import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/services/covers.dart';
import 'package:tingyu/services/downloads.dart';
import 'package:tingyu/services/lyrics.dart';
import 'package:tingyu/services/storage.dart';
import 'support/fakes.dart';

class Transfer implements HttpClientAdapter {
  Transfer(this.answer);
  final FutureOr<List<int>> Function(RequestOptions) answer;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = await answer(options);
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        'content-length': ['${bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class MatchLyrics extends LyricsClient {
  Future<Map<String, dynamic>?> Function(Track)? answer;
  @override
  Future<Map<String, dynamic>?> match(
    Track track, {
    bool Function()? isCurrent,
  }) async => answer == null ? null : answer!(track);
}

Future<void> until(bool Function() check) async {
  for (var i = 0; i < 200 && !check(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(check(), isTrue);
}

void main() {
  test(
    'artwork shares one transfer across pages/sizes, survives restart and limits concurrency',
    () async {
      final dir = await Directory.systemTemp.createTemp('tingyu-covers-');
      var requests = 0, active = 0, peak = 0;
      final dio = Dio()
        ..httpClientAdapter = Transfer((options) async {
          requests++;
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          active--;
          return File('assets/tray.png').readAsBytesSync();
        });
      final cache = CoverCache(dir, dio: dio);
      final hits = await Future.wait(
        List.generate(20, (_) => cache.get('https://images.test/a.png')),
      );
      expect(requests, 1);
      expect(hits.map((f) => f!.path).toSet().length, 1);
      expect(cache.peek('https://images.test/a.png'), isNotNull);
      await cache.close();
      final reopened = CoverCache(dir, dio: dio);
      expect(await reopened.get('https://images.test/a.png'), isNotNull);
      expect(requests, 1);
      await Future.wait(
        List.generate(12, (i) => reopened.get('https://images.test/$i.png')),
      );
      expect(peak, lessThanOrEqualTo(4));
      await reopened.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'removing downloaded audio never waits for a slow shared cover request',
    () async {
      final dir = await Directory.systemTemp.createTemp('tingyu-cover-remove-');
      final db = AppDatabase(NativeDatabase.memory());
      final pending = Completer<List<int>>();
      var started = false;
      const track = Track(
        bvid: 'BVcover',
        cid: 901,
        title: '封面测试',
        artist: 'UP',
        cover: 'https://images.test/slow.png',
        duration: 30,
      );
      final manager = DownloadManager(
        FixtureApi(),
        db,
        dir,
        dio: Dio()
          ..httpClientAdapter = Transfer((request) {
            if (request.uri.host == 'images.test') {
              started = true;
              return pending.future;
            }
            return [1, 2, 3, 4];
          }),
        lyricsClient: MatchLyrics(),
      );
      await manager.initialize();
      await manager.enqueue(track);
      await until(
        () =>
            started && manager.tasks.single.status == DownloadStatus.completed,
      );
      await manager
          .remove(manager.tasks.single)
          .timeout(const Duration(seconds: 1));
      expect(manager.tasks, isEmpty);
      pending.complete(File('assets/tray.png').readAsBytesSync());
      await manager.prepareForExit();
      expect(await manager.coverFile(track).exists(), isFalse);
      manager.dispose();
      await db.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'audio queue continues while lyrics wait; manual lyrics beat late automatic results',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'tingyu-lyrics-download-',
      );
      final db = AppDatabase(NativeDatabase.memory());
      final result = Completer<Map<String, dynamic>?>();
      final client = MatchLyrics()
        ..answer = (track) async =>
            track.id == firstTrack.id ? result.future : null;
      final manager = DownloadManager(
        FixtureApi(),
        db,
        dir,
        dio: Dio()..httpClientAdapter = Transfer((_) => [1, 2, 3, 4]),
        lyricsClient: client,
      );
      await manager.initialize();
      await manager.enqueue(firstTrack);
      await manager.enqueue(secondTrack);
      await until(
        () => manager.tasks.every((d) => d.status == DownloadStatus.completed),
      );
      expect(manager.tasks.first.lyricStatus, DownloadLyricStatus.fetching);
      await manager.saveLyrics(firstTrack, '[00:01]手动');
      result.complete({'syncedLyrics': '[00:01]自动'});
      await until(
        () => manager.tasks.last.lyricStatus == DownloadLyricStatus.missing,
      );
      expect(await manager.lyrics(firstTrack), '[00:01]手动');
      expect(manager.tasks.first.lyricStatus, DownloadLyricStatus.available);
      client.answer = (_) async => {'plainLyrics': '补全的歌词'};
      await manager.retryLyrics(manager.tasks.last);
      await until(
        () => manager.tasks.last.lyricStatus == DownloadLyricStatus.available,
      );
      expect(await manager.lyrics(secondTrack), '补全的歌词');
      await manager.prepareForExit();
      manager.dispose();
      await db.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'missing, failed and removed lyric jobs never fail or resurrect audio',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'tingyu-lyrics-remove-',
      );
      final db = AppDatabase(NativeDatabase.memory());
      final client = MatchLyrics()
        ..answer = (_) async => throw const AppFailure('歌词服务失败');
      final manager = DownloadManager(
        FixtureApi(),
        db,
        dir,
        dio: Dio()..httpClientAdapter = Transfer((_) => [1, 2, 3, 4]),
        lyricsClient: client,
      );
      await manager.initialize();
      await manager.enqueue(firstTrack);
      await until(
        () => manager.tasks.single.lyricStatus == DownloadLyricStatus.failed,
      );
      expect(manager.tasks.single.status, DownloadStatus.completed);
      final pending = Completer<Map<String, dynamic>?>();
      client.answer = (_) => pending.future;
      await manager.retryLyrics(manager.tasks.single);
      await until(
        () => manager.tasks.single.lyricStatus == DownloadLyricStatus.fetching,
      );
      await manager.remove(manager.tasks.single);
      pending.complete({'syncedLyrics': '[00:01]太迟'});
      await manager.prepareForExit();
      expect(manager.tasks, isEmpty);
      expect(await manager.lyrics(firstTrack), isNull);
      manager.dispose();
      await db.close();
      await dir.delete(recursive: true);
    },
  );
}
