// StreamAudioSource is isolated here; just_audio is pinned by pubspec.lock.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/music.dart';

/// 可淘汰的播放文件；不创建 DownloadTask，也不保存远程 URL/请求头。
class PlaybackCache extends ChangeNotifier {
  PlaybackCache(
    this.directory, {
    Dio? dio,
    this.maxBytes = 2 * 1024 * 1024 * 1024,
  }) : http =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 40),
             ),
           );
  final Directory directory;
  final Dio http;
  final int maxBytes;
  final _entries = <String, ({int bytes, String quality})>{};
  final _jobs = <String, _CacheTransfer>{};
  final _pins = <String, int>{};
  final _promoted = <String>{};
  String? _current;
  bool _closed = false;
  int get bytes => _entries.values.fold(0, (sum, e) => sum + e.bytes);
  bool get transferring => _jobs.values.any((job) => !job.finished);
  String key(Track track, bool standard) => sha256
      .convert(utf8.encode('${track.id}:${standard ? 'standard' : 'high'}'))
      .toString();
  File _audio(String key) => File('${directory.path}/$key.m4a');
  File _meta(String key) => File('${directory.path}/$key.json');

  Future<void> initialize() async {
    await directory.create(recursive: true);
    await for (final file in directory.list()) {
      if (file is! File) continue;
      if (file.path.endsWith('.part') || file.path.endsWith('.tmp')) {
        await file.delete();
      } else if (file.path.endsWith('.json')) {
        final name = file.uri.pathSegments.last.replaceFirst('.json', '');
        if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(name)) continue;
        try {
          final data = jsonDecode(await file.readAsString()) as Map;
          final length = data['bytes'] as int;
          if (length > 0 &&
              await _audio(name).exists() &&
              await _audio(name).length() == length) {
            _entries[name] = (
              bytes: length,
              quality: data['quality'] as String,
            );
          } else {
            await _delete(name);
          }
        } on FormatException {
          await _delete(name);
        } on TypeError {
          await _delete(name);
        }
      }
    }
    // A crash between audio rename and metadata commit leaves an untrusted file.
    await for (final file in directory.list()) {
      if (file is File && file.path.endsWith('.m4a')) {
        final name = file.uri.pathSegments.last.replaceFirst('.m4a', '');
        if (!_entries.containsKey(name)) await file.delete();
      }
    }
    await trim();
  }

  Future<String?> availablePath(Track track, {required bool standard}) async {
    final id = key(track, standard), entry = _entries[key(track, standard)];
    if (entry == null) return null;
    final file = _audio(id);
    if (!await file.exists() || await file.length() != entry.bytes) {
      await _delete(id);
      return null;
    }
    await file.setLastModified(DateTime.now());
    return file.path;
  }

  Future<void> activate(Track? track, {bool standard = false}) async {
    _current = track == null ? null : key(track, standard);
    for (final item in _jobs.entries.toList()) {
      if (item.key != _current && (_pins[item.key] ?? 0) == 0) {
        await item.value.cancel();
        _jobs.remove(item.key);
      }
    }
    for (final id in _promoted.toList()) {
      if (!_protected(id)) {
        await _delete(id);
        _promoted.remove(id);
      }
    }
    await trim();
  }

  Future<StreamAudioSource> source(
    Track track,
    AudioStream stream, {
    required bool standard,
  }) async {
    if (_closed) throw StateError('播放缓存已关闭');
    final id = key(track, standard);
    final old = _jobs[id];
    if (old?.error != null) _jobs.remove(id);
    final job = _jobs.putIfAbsent(id, () => _CacheTransfer(this, id, stream));
    await job.start();
    return _CachedAudioSource(job);
  }

  /// 下载请求借用正在播放的同一传输，取消下载不取消仍在播放的缓存。
  Future<bool> copyForDownload(
    Track track,
    File destination, {
    CancelToken? cancelToken,
  }) async {
    final id = key(track, false);
    _pins[id] = (_pins[id] ?? 0) + 1;
    try {
      final job = _jobs[id];
      if (job != null && !job.finished) {
        try {
          await job.start();
        } on Exception {
          if (cancelToken?.isCancelled ?? false) {
            throw cancelToken!.cancelError!;
          }
          return false;
        }
        await Future.any([
          job.done.future,
          if (cancelToken != null)
            cancelToken.whenCancel.then<void>((error) => throw error),
        ]);
      }
      if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
      final file = await availablePath(track, standard: false);
      if (file == null) return false;
      await File(file).copy(destination.path);
      if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
      return true;
    } finally {
      _pins[id] = (_pins[id] ?? 1) - 1;
    }
  }

  Future<void> downloaded(Track track) async {
    final id = key(track, false);
    if (_protected(id)) {
      _promoted.add(id);
    } else {
      await _delete(id);
    }
  }

  bool _protected(String id) =>
      id == _current || (_pins[id] ?? 0) > 0 || (_jobs[id]?.finished == false);
  Future<void> _delete(String id) async {
    for (final file in [_audio(id), _meta(id)]) {
      if (await file.exists()) await file.delete();
    }
    _entries.remove(id);
  }

  Future<void> _maintenance = Future.value();
  Future<void> _exclusive(Future<void> Function() action) {
    final next = _maintenance.then((_) => action());
    _maintenance = next.then<void>(
      (_) {},
      onError: (Object e, StackTrace st) {},
    );
    return next;
  }

  Future<void> trim() => _exclusive(_trim);
  Future<void> _trim() async {
    final candidates = <({String id, DateTime used})>[];
    for (final id in _entries.keys.toList()) {
      if (!_protected(id) && await _audio(id).exists()) {
        candidates.add((id: id, used: await _audio(id).lastModified()));
      }
    }
    candidates.sort((a, b) => a.used.compareTo(b.used));
    for (final entry in candidates) {
      final reserved = _jobs.entries
          .where((e) => !e.value.finished && !_entries.containsKey(e.key))
          .fold(0, (sum, e) => sum + e.value.length);
      if (bytes + reserved <= maxBytes) break;
      if (!_protected(entry.id)) await _delete(entry.id);
    }
    if (!_closed) notifyListeners();
  }

  Future<void> clear() => _exclusive(_clear);
  Future<void> _clear() async {
    for (final id in _entries.keys.toList()) {
      if (!_protected(id)) await _delete(id);
    }
    if (!_closed) notifyListeners();
  }

  Future<void> close() async {
    _closed = true;
    await Future.wait(_jobs.values.map((job) => job.cancel()));
    http.close(force: true);
  }
}

class _CacheTransfer {
  _CacheTransfer(this.owner, this.id, this.source);
  final PlaybackCache owner;
  final String id;
  final AudioStream source;
  final cancelToken = CancelToken();
  final done = Completer<void>();
  final _headers = Completer<void>();
  Completer<void> _changed = Completer<void>();
  int received = 0, length = 0;
  String contentType = 'audio/mp4';
  bool finished = false;
  Object? error;
  Future<void>? _running;
  File get temp => File('${owner.directory.path}/$id.part');
  void _signal() {
    final previous = _changed;
    _changed = Completer<void>();
    previous.complete();
  }

  Future<void> start() {
    _running ??= _fetch();
    return _headers.future;
  }

  Future<void> _fetch() async {
    RandomAccessFile? output;
    try {
      final response = await owner.http.get<ResponseBody>(
        source.url,
        options: Options(
          responseType: ResponseType.stream,
          headers: source.headers,
        ),
        cancelToken: cancelToken,
      );
      final body = response.data!;
      length =
          int.tryParse(response.headers.value('content-length') ?? '') ?? 0;
      if (response.statusCode != 200 ||
          length <= 0 ||
          length > owner.maxBytes) {
        await body.stream.listen(null).cancel();
        throw const AppFailure('该音频暂不支持缓存');
      }
      await owner.trim();
      contentType = response.headers.value('content-type') ?? 'audio/mp4';
      output = await temp.open(mode: FileMode.write);
      _headers.complete();
      await for (final chunk in body.stream) {
        if (cancelToken.isCancelled) throw cancelToken.cancelError!;
        await output.writeFrom(chunk);
        received += chunk.length;
        if (received > length) throw const AppFailure('缓存音频长度不匹配');
        _signal();
      }
      if (received != length) throw const AppFailure('缓存音频不完整');
      await output.flush();
      await output.close();
      output = null;
      await temp.rename(owner._audio(id).path);
      final metadata = File('${owner._meta(id).path}.tmp');
      await metadata.writeAsString(
        jsonEncode({'bytes': length, 'quality': source.quality}),
        flush: true,
      );
      await metadata.rename(owner._meta(id).path);
      owner._entries[id] = (bytes: length, quality: source.quality);
    } on Object catch (failure) {
      error = failure;
      if (!_headers.isCompleted) _headers.completeError(failure);
    } finally {
      try {
        await output?.close();
        if (await temp.exists()) await temp.delete();
      } on FileSystemException catch (failure) {
        error ??= failure;
      } finally {
        finished = true;
        _signal();
        done.complete();
      }
      try {
        await owner.trim();
      } on FileSystemException catch (failure) {
        error ??= failure;
      }
    }
  }

  Future<void> cancel() async {
    if (_running == null) return;
    if (!finished) cancelToken.cancel('播放缓存已停止');
    await done.future;
  }

  Stream<List<int>> read(int start, int end) async* {
    // Opening the handle before awaiting more data keeps it valid across rename.
    RandomAccessFile input;
    try {
      input = await (finished ? owner._audio(id) : temp).open();
    } on FileSystemException {
      // The committed file replaces .part atomically during this open.
      if (error != null) throw error!;
      input = await owner._audio(id).open();
    }
    try {
      var offset = start;
      while (offset < end) {
        if (error != null) throw error!;
        final change = _changed.future;
        if (offset >= received) {
          if (finished) throw const AppFailure('缓存音频不完整');
          await change;
          continue;
        }
        final count = math.min(64 * 1024, math.min(received, end) - offset);
        await input.setPosition(offset);
        final bytes = await input.read(count);
        if (bytes.isEmpty) throw const AppFailure('缓存音频读取失败');
        offset += bytes.length;
        yield bytes;
      }
    } finally {
      await input.close();
    }
  }
}

class _CachedAudioSource extends StreamAudioSource {
  _CachedAudioSource(this.job);
  final _CacheTransfer job;
  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    await job.start();
    final from = start ?? 0, until = end ?? job.length;
    if (from < 0 || until > job.length || from >= until) {
      throw const AppFailure('音频范围无效');
    }
    if (from > job.received && !job.finished) {
      final response = await job.owner.http.get<ResponseBody>(
        job.source.url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {...job.source.headers, 'Range': 'bytes=$from-${until - 1}'},
        ),
        cancelToken: job.cancelToken,
      );
      if (response.statusCode != 206 ||
          response.headers.value('content-range') !=
              'bytes $from-${until - 1}/${job.length}') {
        await response.data!.stream.listen(null).cancel();
        throw const AppFailure('音频范围响应无效');
      }
      return StreamAudioResponse(
        sourceLength: job.length,
        contentLength: until - from,
        offset: from,
        contentType: job.contentType,
        stream: response.data!.stream,
      );
    }
    return StreamAudioResponse(
      sourceLength: job.length,
      contentLength: until - from,
      offset: from,
      contentType: job.contentType,
      stream: job.read(from, until),
    );
  }
}
