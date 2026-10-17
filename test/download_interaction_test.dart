import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/services/downloads.dart';
import 'support/fakes.dart';

class TransferApi extends FixtureApi {
  late String url;
  @override
  Future<AudioStream> resolve(
    Track track, {
    bool standard = false,
    CancelToken? cancelToken,
  }) async => AudioStream(url, {}, '本地测试音频');
}

Future<void> until(bool Function() check) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!check()) {
    if (DateTime.now().isAfter(deadline)) fail('等待下载状态超时');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test(
    'completed downloads sort by finish time and persist without mutating task order',
    () async {
      final fixture = await TestLibrary.create();
      DownloadManager? restored;
      try {
        final older = DateTime.utc(2026, 10, 16, 10);
        final newer = older.add(const Duration(hours: 1));
        final oldFile = await File(
          '${fixture.directory.path}/old.m4a',
        ).writeAsBytes([1]);
        final newFile = await File(
          '${fixture.directory.path}/new.m4a',
        ).writeAsBytes([2]);
        final old = DownloadTask(
          firstTrack,
          status: DownloadStatus.completed,
          lyricStatus: DownloadLyricStatus.missing,
          received: 1,
          filePath: oldFile.path,
          completedAt: older,
        );
        final recent = DownloadTask(
          secondTrack,
          status: DownloadStatus.completed,
          lyricStatus: DownloadLyricStatus.missing,
          received: 1,
          filePath: newFile.path,
          completedAt: newer,
        );
        final paused = DownloadTask(firstTrack, status: DownloadStatus.paused);
        fixture.downloads.tasks.addAll([old, recent, paused]);
        expect(fixture.downloads.completedTasks, [recent, old]);
        expect(fixture.downloads.incompleteTasks, [paused]);
        expect(fixture.downloads.tasks, [old, recent, paused]);
        expect(DownloadTask.fromJson(recent.toJson()).completedAt, newer);
        await fixture.downloads.prepareForExit();
        restored = DownloadManager(
          fixture.api,
          fixture.db,
          fixture.directory,
          lyricsClient: FixtureLyrics(),
        );
        await restored.initialize();
        expect(restored.completedTasks.map((d) => d.track.id), [
          secondTrack.id,
          firstTrack.id,
        ]);
        expect(restored.completedTasks.map((d) => d.completedAt), [
          newer,
          older,
        ]);
        expect(restored.incompleteTasks.single.status, DownloadStatus.paused);
      } finally {
        await restored?.prepareForExit();
        restored?.dispose();
        await fixture.close();
      }
    },
  );

  test(
    'cancel active transfer, retry, invalidate missing file and remove without orphan files',
    () async {
      final fixture = await TestLibrary.create();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var slow = true;
      final responseStarted = Completer<void>();
      server.listen((request) async {
        try {
          request.response.contentLength = 32768;
          request.response.add(List<int>.filled(1024, 1));
          await request.response.flush();
          if (!responseStarted.isCompleted) responseStarted.complete();
          if (slow) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
          request.response.add(List<int>.filled(31744, 2));
          await request.response.close();
        } on IOException {
          /* Client cancellation is expected. */
        }
      });
      final api = fixture.api;
      // Keep the real DownloadManager and Dio; inject only stream resolution.
      api.http.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.next(options),
        ),
      );
      final transferApi = TransferApi()
        ..url = 'http://127.0.0.1:${server.port}/audio';
      final manager = fixture.downloads;
      // FixtureApi exposes a deterministic resolver for this service boundary.
      api.resolveAnswer = transferApi.resolve;
      try {
        await manager.enqueue(firstTrack);
        await responseStarted.future;
        final task = manager.tasks.single;
        await manager.pause(task);
        expect(task.status, DownloadStatus.paused);
        expect(
          fixture.directory.listSync().whereType<File>().where(
            (f) => f.path.endsWith('.part'),
          ),
          isEmpty,
        );
        slow = false;
        await manager.retry(task);
        await until(() => task.status == DownloadStatus.completed);
        expect(task.completedAt, isNotNull);
        expect(task.completedAt!.isUtc, isTrue);
        final firstCompletion = task.completedAt!;
        final local = await manager.availablePath(firstTrack);
        expect(local, isNotNull);
        expect(await File(local!).length(), 32768);
        await File(local).delete();
        expect(await manager.availablePath(firstTrack), isNull);
        expect(task.status, DownloadStatus.failed);
        await manager.retry(task);
        await until(() => task.status == DownloadStatus.completed);
        expect(task.completedAt!.isBefore(firstCompletion), isFalse);
        await manager.remove(task);
        expect(manager.tasks, isEmpty);
        expect(
          fixture.directory.listSync().whereType<File>().where(
            (f) => f.path.endsWith('.m4a') || f.path.endsWith('.part'),
          ),
          isEmpty,
        );
      } finally {
        await server.close(force: true);
        await fixture.close();
      }
    },
  );

  test(
    'remove while transfer is active waits for cancellation and retains library records',
    () async {
      final fixture = await TestLibrary.create();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final started = Completer<void>();
      server.listen((request) async {
        try {
          request.response.contentLength = 4096;
          request.response.add([1, 2]);
          await request.response.flush();
          started.complete();
          await Future<void>.delayed(const Duration(milliseconds: 500));
          await request.response.close();
        } on IOException {
          /* Cancellation closes the connection. */
        }
      });
      fixture.api.resolveAnswer =
          (track, {bool standard = false, CancelToken? cancelToken}) async =>
              AudioStream('http://127.0.0.1:${server.port}/audio', {}, '测试');
      try {
        await fixture.controller.remember(firstTrack);
        await fixture.controller.toggleLike(firstTrack);
        await fixture.controller.download(firstTrack);
        await started.future;
        await fixture.controller.removeDownload(fixture.downloads.tasks.single);
        expect(fixture.downloads.tasks, isEmpty);
        expect(fixture.controller.library, contains(firstTrack.id));
        expect(fixture.controller.likes, contains(firstTrack.id));
        expect(
          fixture.directory.listSync().whereType<File>().where(
            (f) => f.path.endsWith('.part'),
          ),
          isEmpty,
        );
      } finally {
        await server.close(force: true);
        await fixture.close();
      }
    },
  );
}
