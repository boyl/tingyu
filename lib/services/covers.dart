import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'bilibili.dart';

/// URL-addressed persistent artwork, shared by all pages and thumbnail sizes.
class CoverCache {
  CoverCache(this.directory, {Dio? dio})
    : _http =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ),
          );
  final Directory directory;
  final Dio _http;
  final _ready = <String, File>{};
  final _inFlight = <String, Future<File?>>{};
  final _failed = <String, DateTime>{};
  final _cancel = CancelToken();
  bool _closed = false;
  int _active = 0;
  final _waiting = <Completer<void>>[];
  Future<void> _acquire() async {
    if (_active < 4) {
      _active++;
      return;
    }
    final ready = Completer<void>();
    _waiting.add(ready);
    await ready.future;
  }

  void _release() {
    if (_waiting.isEmpty) {
      _active--;
    } else {
      _waiting.removeAt(0).complete();
    }
  }

  static const maxBytes = 64 * 1024 * 1024;
  File? peek(String url) => _ready[url];
  File _file(String url) =>
      File('${directory.path}/${sha256.convert(utf8.encode(url))}.cover');

  Future<File?> get(String url) {
    if (_closed || url.isEmpty) return Future.value(null);
    final ready = _ready[url];
    if (ready != null) return Future.value(ready);
    final failure = _failed[url];
    if (failure != null &&
        DateTime.now().difference(failure) < const Duration(minutes: 1)) {
      return Future.value(null);
    }
    return _inFlight.putIfAbsent(url, () => _load(url));
  }

  Future<File?> _load(String url) async {
    final file = _file(url), temp = File('${_file(url).path}.part');
    var acquired = false;
    try {
      await directory.create(recursive: true);
      if (await file.exists() && await file.length() > 0) {
        await file.setLastModified(DateTime.now());
        return _ready[url] = file;
      }
      final uri = Uri.tryParse(url);
      if (uri == null || !['http', 'https'].contains(uri.scheme)) return null;
      await _acquire();
      acquired = true;
      if (_closed) return null;
      await _http.download(
        url,
        temp.path,
        cancelToken: _cancel,
        options: Options(
          headers: {
            'Referer': 'https://www.bilibili.com/',
            'User-Agent': BilibiliClient.userAgent,
          },
        ),
      );
      if (_closed || await temp.length() == 0) return null;
      await temp.rename(file.path);
      _ready[url] = file;
      await _trim(keep: file);
      return file;
    } on DioException {
      _failed[url] = DateTime.now();
      return null;
    } on FileSystemException {
      _failed[url] = DateTime.now();
      return null;
    } finally {
      if (acquired) _release();
      _inFlight.remove(url);
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<void> _trim({required File keep}) async {
    final entries = <(File, FileStat)>[];
    await for (final item in directory.list()) {
      if (item is File && item.path.endsWith('.cover')) {
        entries.add((item, await item.stat()));
      }
    }
    var size = entries.fold<int>(0, (sum, e) => sum + e.$2.size);
    entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final entry in entries) {
      if (size <= maxBytes) break;
      if (entry.$1.path == keep.path) continue;
      await entry.$1.delete();
      size -= entry.$2.size;
      _ready.removeWhere((_, file) => file.path == entry.$1.path);
    }
  }

  Future<void> close() async {
    _closed = true;
    _cancel.cancel();
    await Future.wait(_inFlight.values.toList());
  }
}
