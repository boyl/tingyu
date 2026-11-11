import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
  Future<void> _maintenance = Future.value();
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
  // Bilibili search and view endpoints can return different CDN shards and
  // schemes for the same immutable image. Keep variants and other hosts distinct.
  static String _key(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        !RegExp(r'^i[0-9]+\.hdslb\.com$').hasMatch(uri.host) ||
        !uri.path.startsWith('/bfs/')) {
      return url;
    }
    return uri.replace(scheme: 'https', host: 'i0.hdslb.com').toString();
  }

  File? peek(String url) => _ready[_key(url)];
  File _file(String url) =>
      File('${directory.path}/${sha256.convert(utf8.encode(url))}.cover');

  Future<File?> get(String url) {
    if (_closed || url.isEmpty) return Future.value(null);
    final key = _key(url);
    final ready = _ready[key];
    if (ready != null) return Future.value(ready);
    final failure = _failed[url];
    if (failure != null &&
        DateTime.now().difference(failure) < const Duration(minutes: 1)) {
      return Future.value(null);
    }
    return _inFlight.putIfAbsent(key, () => _load(url, key));
  }

  Future<File?> _load(String url, String key) async {
    final file = _file(key), temp = File('${_file(key).path}.part');
    var acquired = false;
    try {
      await directory.create(recursive: true);
      for (final cached in [file, if (url != key) _file(url)]) {
        if (await cached.exists() && await cached.length() > 0) {
          await cached.setLastModified(DateTime.now());
          return _ready[key] = cached;
        }
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
      _ready[key] = file;
      await _scheduleTrim(keep: file);
      return file;
    } on DioException {
      _failed[url] = DateTime.now();
      return null;
    } on FileSystemException {
      _failed[url] = DateTime.now();
      return null;
    } finally {
      if (acquired) _release();
      _inFlight.remove(key);
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<void> _scheduleTrim({required File keep}) =>
      _maintenance = _maintenance.then((_) async {
        // 清理串行执行，避免并发任务重复删除同一旧文件。
        // 维护失败不应覆盖已经成功落盘的图片结果。
        try {
          await _trim(keep: keep);
        } on FileSystemException catch (error) {
          debugPrint('封面缓存清理失败：${error.message} (${error.osError?.errorCode})');
        }
      });

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
