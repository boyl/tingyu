// ignore_for_file: experimental_member_use
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/services/playback_cache.dart';
import 'package:tingyu/services/downloads.dart';
import 'package:tingyu/services/storage_usage.dart';
import 'support/fakes.dart';

void main() {
  late Directory root;
  late PlaybackCache cache;
  late HttpServer server;
  late AudioStream remote;
  int requests = 0;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('tingyu-cache-test-');
    cache = PlaybackCache(
      Directory('${root.path}/playback-cache'),
      maxBytes: 12000,
    );
    await cache.initialize();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requests = 0;
    server.listen((request) async {
      requests++;
      final range = request.headers.value('range');
      int from = 0, end = 7999;
      if (range != null) {
        final parts = range.substring(6).split('-');
        from = int.parse(parts[0]);
        end = int.parse(parts[1]);
        request.response.statusCode = 206;
        request.response.headers.set('content-range', 'bytes $from-$end/8000');
      }
      request.response.contentLength = end - from + 1;
      request.response.headers.contentType = ContentType('audio', 'mp4');
      try {
        for (var offset = from; offset <= end; offset += 1000) {
          final count = (end - offset + 1).clamp(0, 1000);
          request.response.add(List.generate(count, (i) => (offset + i) % 251));
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await request.response.close();
      } on Exception {
        /* client cancellation is expected */
      }
    });
    remote = AudioStream(
      'http://127.0.0.1:${server.port}/song?secret=never-persist',
      {},
      'high',
    );
  });
  tearDown(() async {
    await cache.close();
    cache.dispose();
    await server.close(force: true);
    await root.delete(recursive: true);
  });
  Future<void> fill(Track track) async {
    await cache.activate(track);
    final source = await cache.source(track, remote, standard: false);
    final response = await source.request();
    final data = await response.stream.expand((x) => x).toList();
    expect(data.length, 8000);
    while (cache.transferring) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('播放与并发下载共享一次传输，重启复用且不保存签名 URL', () async {
    await cache.activate(firstTrack);
    final source = await cache.source(firstTrack, remote, standard: false);
    final playback = await source.request();
    final copied = File('${root.path}/download.m4a');
    final copy = cache.copyForDownload(firstTrack, copied);
    expect(
      await playback.stream.expand((x) => x).toList(),
      List.generate(8000, (i) => i % 251),
    );
    expect(await copy, isTrue);
    expect(requests, 1);
    expect(await copied.length(), 8000);
    final metadata = await cache.directory
        .list()
        .where((x) => x.path.endsWith('.json'))
        .cast<File>()
        .first;
    expect(await metadata.readAsString(), isNot(contains('secret')));
    final restored = PlaybackCache(cache.directory);
    await restored.initialize();
    expect(
      await restored.availablePath(firstTrack, standard: false),
      isNotNull,
    );
    expect(await restored.availablePath(firstTrack, standard: true), isNull);
    await restored.close();
    restored.dispose();
  });
  test('清理保护播放文件，下载转存后释放缓存且不删除下载', () async {
    await fill(firstTrack);
    await cache.clear();
    expect(cache.bytes, 8000);
    final dest = File('${root.path}/download.m4a');
    expect(await cache.copyForDownload(firstTrack, dest), true);
    await cache.downloaded(firstTrack);
    expect(cache.bytes, 8000);
    await cache.activate(null);
    expect(cache.bytes, 0);
    expect(await dest.length(), 8000);
  });
  test('LRU 限额和存储分类；临时清理不删除完整缓存', () async {
    await fill(firstTrack);
    await fill(secondTrack);
    expect(cache.bytes, 8000);
    expect(await cache.availablePath(firstTrack, standard: false), isNull);
    await File('${cache.directory.path}/orphan.part').writeAsBytes([1, 2]);
    final usage = await StorageUsage.scan(root);
    expect(usage.bytes['播放缓存'], greaterThanOrEqualTo(8000));
    expect(usage.bytes['已下载音频'], 0);
    expect(usage.bytes['临时文件'], 2);
    await usage.clearTemporary(root, transferActive: false);
    expect(await cache.availablePath(secondTrack, standard: false), isNotNull);
  });
  test('提前关闭取消传输，不发布部分文件，启动清除残留', () async {
    await cache.activate(firstTrack);
    await cache.source(firstTrack, remote, standard: false);
    await cache.close();
    expect(await cache.availablePath(firstTrack, standard: false), isNull);
    expect(cache.bytes, 0);
    await File('${cache.directory.path}/incomplete.part').writeAsBytes([1]);
    final restored = PlaybackCache(cache.directory);
    await restored.initialize();
    expect(
      await File('${cache.directory.path}/incomplete.part').exists(),
      false,
    );
    await restored.close();
    restored.dispose();
  });
  test('下载管理器在离线状态复用缓存，持久保存为下载任务', () async {
    final f = await TestLibrary.create();
    final manager = DownloadManager(
      f.api,
      f.db,
      Directory('${root.path}/downloads'),
      cache: cache,
      lyricsClient: FixtureLyrics(),
    );
    await manager.initialize();
    try {
      await fill(firstTrack);
      f.api.offline = true;
      await manager.enqueue(firstTrack);
      for (
        var i = 0;
        i < 200 && manager.tasks.single.status != DownloadStatus.completed;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(manager.tasks.single.status, DownloadStatus.completed);
      expect(await manager.availablePath(firstTrack), isNotNull);
      expect(requests, 1);
      final stored = await f.db.readState('downloads');
      expect(stored, isNotNull);
    } finally {
      await manager.prepareForExit();
      manager.dispose();
      await f.close();
    }
  });

  test('取消转存保留播放传输，转存路径失败不损坏缓存', () async {
    await cache.activate(firstTrack);
    await cache.source(firstTrack, remote, standard: false);
    final token = CancelToken();
    final copy = cache.copyForDownload(
      firstTrack,
      File('${root.path}/cancelled.m4a'),
      cancelToken: token,
    );
    final assertion = expectLater(copy, throwsA(isA<DioException>()));
    token.cancel();
    await assertion;
    while (cache.transferring) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(await cache.availablePath(firstTrack, standard: false), isNotNull);
    await expectLater(
      cache.copyForDownload(firstTrack, File(root.path)),
      throwsA(isA<FileSystemException>()),
    );
    expect(await cache.availablePath(firstTrack, standard: false), isNotNull);
    expect(requests, 1);
  });
  test('截断响应不提交完整缓存', () async {
    final broken = PlaybackCache(
      Directory('${root.path}/broken'),
      dio: Dio()..httpClientAdapter = TruncatedResponse(),
    );
    await broken.initialize();
    try {
      final source = await broken.source(firstTrack, remote, standard: false);
      final response = await source.request();
      await expectLater(
        response.stream.drain<void>(),
        throwsA(isA<AppFailure>()),
      );
      while (broken.transferring) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(await broken.availablePath(firstTrack, standard: false), isNull);
    } finally {
      await broken.close();
      broken.dispose();
    }
  });
  test('尾部 Range 立即读取且主传输可完整保存', () async {
    await cache.activate(firstTrack);
    final source = await cache.source(firstTrack, remote, standard: false);
    final tail = await source.request(7000, 8000);
    expect(
      await tail.stream.expand((x) => x).toList(),
      List.generate(1000, (i) => (7000 + i) % 251),
    );
    while (cache.transferring) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(await cache.availablePath(firstTrack, standard: false), isNotNull);
  });
}

class TruncatedResponse implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromBytes(
    [1, 2, 3],
    200,
    headers: {
      'content-length': ['10'],
    },
  );
  @override
  void close({bool force = false}) {}
}
