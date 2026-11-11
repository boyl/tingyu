import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/services/covers.dart';

class _Images implements HttpClientAdapter {
  _Images(this.bytes, {this.expectedRequests = 4, this.autoRelease = true});

  final Uint8List bytes;
  final int expectedRequests;
  final bool autoRelease;
  final started = Completer<void>();
  final release = Completer<void>();
  int requests = 0;
  int cancellations = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (++requests == expectedRequests) {
      started.complete();
      if (autoRelease) release.complete();
    }
    final cancelled = cancelFuture?.then<void>((_) {
      cancellations++;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
      );
    });
    await Future.any<void>([release.future, ?cancelled]);
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        'content-length': ['${bytes.length}'],
        'content-type': ['image/png'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _DirectoryProxy implements Directory {
  _DirectoryProxy(this.delegate);

  final Directory delegate;

  @override
  String get path => delegate.path;

  @override
  Future<Directory> create({bool recursive = false}) =>
      delegate.create(recursive: recursive);

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => delegate.list(recursive: recursive, followLinks: followLinks);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Pauses real directory enumeration without changing cache file operations.
class _PausedDirectory extends _DirectoryProxy {
  _PausedDirectory(super.delegate);

  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) async* {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    yield* delegate.list(recursive: recursive, followLinks: followLinks);
  }
}

class _FailingDeleteDirectory extends _DirectoryProxy {
  _FailingDeleteDirectory(super.delegate);

  bool failDelete = true;

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) async* {
    await for (final entry in delegate.list(
      recursive: recursive,
      followLinks: followLinks,
    )) {
      yield entry is File && entry.uri.pathSegments.last == 'old-0.cover'
          ? _FailingDeleteFile(entry, () => failDelete)
          : entry;
    }
  }
}

class _FailingDeleteFile implements File {
  _FailingDeleteFile(this.delegate, this.shouldFail);

  final File delegate;
  final bool Function() shouldFail;

  @override
  String get path => delegate.path;

  @override
  Future<FileStat> stat() => delegate.stat();

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    if (shouldFail()) {
      throw const FileSystemException('forced cover trim failure');
    }
    return delegate.delete(recursive: recursive);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnavailableImages implements HttpClientAdapter {
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      message: 'fixture connection failure',
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<List<File>> _fillOldCache(Directory directory) async {
  final files = <File>[];
  for (var i = 0; i < 32; i++) {
    final file = File('${directory.path}/old-$i.cover');
    final handle = await file.open(mode: FileMode.write);
    try {
      await handle.truncate(2 * 1024 * 1024);
    } finally {
      await handle.close();
    }
    await file.setLastModified(DateTime(2020).add(Duration(seconds: i)));
    files.add(file);
  }
  return files;
}

Future<int> _cacheBytes(Directory directory) async {
  var bytes = 0;
  await for (final entry in directory.list()) {
    if (entry is File && entry.path.endsWith('.cover')) {
      bytes += await entry.length();
    }
  }
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'concurrent trimming returns every successfully downloaded cover',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tingyu-cover-trim-',
      );
      final bytes = await File('assets/tray.png').readAsBytes();
      final images = _Images(bytes);
      final cache = CoverCache(
        directory,
        dio: Dio()..httpClientAdapter = images,
      );
      try {
        final oldFiles = await _fillOldCache(directory);
        final urls = List.generate(4, (i) => 'https://images.test/$i.png');
        final results = await Future.wait(urls.map(cache.get));

        expect(
          results,
          everyElement(isNotNull),
          reason: 'Trimming must not hide a cover already downloaded to disk',
        );
        for (var i = 0; i < urls.length; i++) {
          final file = results[i]!;
          expect(await file.exists(), isTrue);
          expect(await file.readAsBytes(), orderedEquals(bytes));
          expect(cache.peek(urls[i])?.path, file.path);
          final codec = await ui.instantiateImageCodec(
            await file.readAsBytes(),
          );
          try {
            final frame = await codec.getNextFrame();
            expect(frame.image.width, greaterThan(0));
            expect(frame.image.height, greaterThan(0));
            frame.image.dispose();
          } finally {
            codec.dispose();
          }
        }
        expect(await oldFiles.first.exists(), isFalse);
        expect(
          await _cacheBytes(directory),
          lessThanOrEqualTo(CoverCache.maxBytes),
        );

        final repeated = await Future.wait(urls.map(cache.get));
        expect(
          repeated.map((file) => file!.path),
          results.map((file) => file!.path),
        );
        expect(images.requests, 4);
      } finally {
        await cache.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'maintenance failure keeps the cover and allows later cleanup',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tingyu-cover-trim-error-',
      );
      final faulty = _FailingDeleteDirectory(directory);
      final images = _Images(
        await File('assets/tray.png').readAsBytes(),
        expectedRequests: 1,
      );
      final cache = CoverCache(faulty, dio: Dio()..httpClientAdapter = images);
      final messages = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) messages.add(message);
      };
      try {
        final oldFiles = await _fillOldCache(directory);
        const firstUrl = 'https://images.test/first.png';
        final first = await cache.get(firstUrl);
        expect(first, isNotNull);
        expect(await first!.readAsBytes(), orderedEquals(images.bytes));
        expect(cache.peek(firstUrl)?.path, first.path);
        expect(
          messages.any(
            (message) => message.contains('forced cover trim failure'),
          ),
          isTrue,
        );
        expect(await oldFiles.first.exists(), isTrue);

        faulty.failDelete = false;
        final second = await cache.get('https://images.test/second.png');
        expect(second, isNotNull);
        expect(await second!.readAsBytes(), orderedEquals(images.bytes));
        expect(await first.exists(), isTrue);
        expect(await oldFiles.first.exists(), isFalse);
        expect(
          await _cacheBytes(directory),
          lessThanOrEqualTo(CoverCache.maxBytes),
        );
        expect(images.requests, 2);
      } finally {
        debugPrint = previousDebugPrint;
        await cache.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('network failure still returns null without caching a cover', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tingyu-cover-network-error-',
    );
    final images = _UnavailableImages();
    final cache = CoverCache(directory, dio: Dio()..httpClientAdapter = images);
    try {
      const url = 'https://images.test/unavailable.png';
      expect(await cache.get(url), isNull);
      expect(cache.peek(url), isNull);
      expect(await directory.list().toList(), isEmpty);
      expect(await cache.get(url), isNull);
      expect(images.requests, 1);
    } finally {
      await cache.close();
      await directory.delete(recursive: true);
    }
  });

  test('close cancels and settles transfers already started', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tingyu-cover-close-',
    );
    final images = _Images(
      await File('assets/tray.png').readAsBytes(),
      autoRelease: false,
    );
    final cache = CoverCache(directory, dio: Dio()..httpClientAdapter = images);
    try {
      final pending = Future.wait(
        List.generate(4, (i) => cache.get('https://images.test/$i.png')),
      );
      await images.started.future;
      await cache.close();
      expect(await pending, everyElement(isNull));
      expect(images.cancellations, 4);
      expect(await directory.list().toList(), isEmpty);
      expect(await cache.get('https://images.test/after-close.png'), isNull);
      expect(images.requests, 4);
    } finally {
      if (!images.release.isCompleted) images.release.complete();
      await cache.close();
      await directory.delete(recursive: true);
    }
  });

  test('close waits for maintenance already started', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tingyu-cover-close-trim-',
    );
    final paused = _PausedDirectory(directory);
    final images = _Images(
      await File('assets/tray.png').readAsBytes(),
      expectedRequests: 1,
    );
    final cache = CoverCache(paused, dio: Dio()..httpClientAdapter = images);
    try {
      final pending = cache.get('https://images.test/cover.png');
      await paused.entered.future;
      var closed = false;
      final closing = cache.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      paused.release.complete();
      final result = await pending;
      await closing;
      expect(result, isNotNull);
      expect(await result!.readAsBytes(), orderedEquals(images.bytes));
      expect(closed, isTrue);
      expect(images.requests, 1);
    } finally {
      if (!paused.release.isCompleted) paused.release.complete();
      await cache.close();
      await directory.delete(recursive: true);
    }
  });
}
