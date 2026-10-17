import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/music.dart';
import 'bilibili.dart';
import 'storage.dart';
import 'covers.dart';
import 'lyrics.dart';
import 'media_export.dart';

class DownloadManager extends ChangeNotifier {
  DownloadManager(
    this.api,
    this.db,
    this.directory, {
    Dio? dio,
    LyricsClient? lyricsClient,
  }) : lyricsClient = lyricsClient ?? LyricsClient(subtitleClient: api),
       _http =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 40),
             ),
           ) {
    covers = CoverCache(Directory('${directory.path}/covers'), dio: _http);
  }
  late final CoverCache covers;
  final LyricsClient lyricsClient;
  final BilibiliClient api;
  final AppDatabase db;
  final Directory directory;
  final Dio _http;
  final List<DownloadTask> tasks = [];
  final _coverJobs = <DownloadTask, Future<void>>{};
  final _coverWrites = <DownloadTask, Future<File>>{};
  final _lyricQueue = <DownloadTask>[];
  final _lyricRevisions = <String, int>{};
  final _lyricWrites = <String, Future<void>>{};
  Future<void>? _lyricPumpFuture;
  bool _lyricRunning = false;
  DownloadTask? _lyricActive;
  bool _running = false, _closed = false;
  Future<void>? _pumpFuture;
  CancelToken? _cancel;
  DownloadTask? _active;
  Completer<void>? _activeDone;
  Timer? _saveTimer;
  Future<void> initialize() async {
    await directory.create(recursive: true);
    final j = await db.readState('downloads');
    for (final raw in j?['tasks'] as List? ?? []) {
      final t = DownloadTask.fromJson(Map<String, dynamic>.from(raw));
      if (t.status == DownloadStatus.completed) {
        final file = File(t.filePath ?? '');
        if (!await file.exists() || (await file.length()) != t.received) {
          t.status = DownloadStatus.failed;
          t.error = '下载文件已丢失或不完整，请重新下载';
          t.filePath = null;
        }
      } else if (t.status == DownloadStatus.downloading) {
        t.status = DownloadStatus.paused;
        t.error = '上次下载中断，点击重试重新下载';
      }
      tasks.add(t);
    }
    notifyListeners();
    _startPump();
    for (final task in tasks) {
      if (task.status == DownloadStatus.completed &&
          [
            DownloadLyricStatus.waiting,
            DownloadLyricStatus.fetching,
          ].contains(task.lyricStatus)) {
        _queueLyrics(task);
      }
    }
  }

  String? localPath(Track t) {
    for (final d in tasks) {
      if (d.track.id == t.id && d.status == DownloadStatus.completed) {
        return d.filePath;
      }
    }
    return null;
  }

  Future<String?> availablePath(Track track) async {
    final task = tasks
        .where(
          (t) => t.track.id == track.id && t.status == DownloadStatus.completed,
        )
        .firstOrNull;
    if (task == null) return null;
    final file = File(task.filePath ?? '');
    if (await file.exists() && await file.length() == task.received) {
      return file.path;
    }
    task.status = DownloadStatus.failed;
    task.filePath = null;
    task.error = '下载文件已丢失或不完整，请重新下载';
    await _save();
    notifyListeners();
    return null;
  }

  Future<void> pause(DownloadTask task) async {
    if (task.status != DownloadStatus.downloading &&
        task.status != DownloadStatus.waiting) {
      return;
    }
    task.status = DownloadStatus.paused;
    task.error = '下载已暂停，可继续下载';
    if (_active == task) {
      final done = _activeDone?.future;
      _cancel?.cancel();
      await done;
    }
    await _save();
    notifyListeners();
  }

  Future<void> enqueue(Track track) async {
    if (tasks.any((t) => t.track.id == track.id)) return;
    tasks.add(DownloadTask(track));
    await _save();
    notifyListeners();
    _startPump();
  }

  Future<void> retry(DownloadTask t) async {
    if (t.status == DownloadStatus.completed ||
        t.status == DownloadStatus.downloading) {
      return;
    }
    t.status = DownloadStatus.waiting;
    t.error = null;
    t.received = 0;
    t.total = 0;
    await _save();
    notifyListeners();
    _startPump();
  }

  Future<void> remove(DownloadTask t) async {
    tasks.remove(t);
    _lyricQueue.remove(t);
    _lyricRevisions[t.track.id] = (_lyricRevisions[t.track.id] ?? 0) + 1;
    await _lyricWrites[t.track.id];
    await _coverWrites[t];
    if (_active == t) {
      final done = _activeDone?.future;
      _cancel?.cancel();
      await done;
    }
    final stem = path.join(directory.path, _stem(t.track));
    for (final ext in ['.m4a', '.part', '.cover', '.lyrics']) {
      final f = File('$stem$ext');
      if (await f.exists()) await f.delete();
    }
    await _save();
    notifyListeners();
  }

  String _stem(Track t) => '${t.bvid}_${t.cid}';
  Future<void> _save() => db.writeState('downloads', {
    'tasks': tasks.map((t) => t.toJson()).toList(),
  });
  void _startPump() {
    if (_running || _closed) return;
    _pumpFuture = _pump();
  }

  Future<void> prepareForExit() async {
    _closed = true;
    _saveTimer?.cancel();
    _saveTimer = null;
    _cancel?.cancel();
    lyricsClient.cancelRequests();
    await _pumpFuture;
    await _lyricPumpFuture;
    await covers.close();
    await Future.wait(_coverJobs.values.toList());
    await _save();
  }

  Future<void> _pump() async {
    if (_running || _closed) return;
    _running = true;
    try {
      while (!_closed) {
        final pending = tasks
            .where((t) => t.status == DownloadStatus.waiting)
            .firstOrNull;
        if (pending == null) break;
        _active = pending;
        final done = _activeDone = Completer<void>();
        _cancel = CancelToken();
        pending.status = DownloadStatus.downloading;
        pending.error = null;
        notifyListeners();
        final temp = File(
          path.join(directory.path, '${_stem(pending.track)}.part'),
        );
        try {
          final stream = await api.resolve(pending.track, cancelToken: _cancel);
          if (_cancel!.isCancelled) continue;
          // Restart incomplete resources rather than append bytes from expired URLs.
          final response = await _http.download(
            stream.url,
            temp.path,
            options: Options(headers: stream.headers),
            cancelToken: _cancel,
            onReceiveProgress: (count, total) {
              if (_closed) return;
              pending.received = count;
              pending.total = total;
              _saveTimer ??= Timer(const Duration(seconds: 1), () {
                _saveTimer = null;
                unawaited(_save());
              });
              notifyListeners();
            },
          );
          final bytes = await temp.length();
          final expected = int.tryParse(
            response.headers.value('content-length') ?? '',
          );
          if (bytes == 0 || (expected != null && bytes != expected)) {
            throw const AppFailure('下载文件不完整，请重试');
          }
          if (!tasks.contains(pending)) continue;
          final file = await temp.rename(
            path.join(directory.path, '${_stem(pending.track)}.m4a'),
          );
          pending.filePath = file.path;
          pending.received = bytes;
          pending.total = bytes;
          pending.status = DownloadStatus.completed;
          _queueLyrics(pending);
          notifyListeners();
          if (pending.track.cover.isNotEmpty) _queueCover(pending);
          await db.saveTrack(pending.track);
        } on DioException catch (e) {
          if (tasks.contains(pending)) {
            pending.status = e.type == DioExceptionType.cancel
                ? DownloadStatus.paused
                : DownloadStatus.failed;
            pending.error = e.type == DioExceptionType.cancel
                ? '下载已暂停'
                : '下载连接失败，请重试';
          }
        } on AppFailure catch (e) {
          pending.status = DownloadStatus.failed;
          pending.error = e.message;
        } on FileSystemException {
          pending.status = DownloadStatus.failed;
          pending.error = '无法写入下载目录，请检查可用空间';
        } finally {
          try {
            if (await temp.exists()) await temp.delete();
            await _save();
            if (!_closed) notifyListeners();
          } finally {
            if (!done.isCompleted) done.complete();
          }
        }
      }
    } finally {
      _running = false;
      _active = null;
      _cancel = null;
    }
  }

  void _queueCover(DownloadTask task) {
    if (_closed || _coverJobs.containsKey(task)) return;
    final job = _attachCover(task);
    _coverJobs[task] = job;
    unawaited(job.whenComplete(() => _coverJobs.remove(task)));
  }

  Future<void> _attachCover(DownloadTask task) async {
    try {
      final cover = await covers.get(task.track.cover);
      if (!tasks.contains(task) || _closed) return;
      if (cover == null) {
        task.error = '音频已下载，封面获取失败';
      } else {
        final write = cover.copy(
          path.join(directory.path, '${_stem(task.track)}.cover'),
        );
        _coverWrites[task] = write;
        try {
          await write;
        } finally {
          if (identical(_coverWrites[task], write)) _coverWrites.remove(task);
        }
      }
    } on FileSystemException {
      if (tasks.contains(task) && !_closed) task.error = '音频已下载，封面保存失败';
    } finally {
      if (tasks.contains(task)) await _save();
      if (!_closed) notifyListeners();
    }
  }

  Future<void> retryLyrics(DownloadTask task) async {
    if (_closed ||
        !tasks.contains(task) ||
        task.status != DownloadStatus.completed ||
        _lyricActive == task) {
      return;
    }
    task.lyricStatus = DownloadLyricStatus.waiting;
    _queueLyrics(task);
    await _save();
    if (!_closed) notifyListeners();
  }

  void _queueLyrics(DownloadTask task) {
    if (_closed || _lyricQueue.contains(task) || _lyricActive == task) return;
    _lyricQueue.add(task);
    if (!_lyricRunning) _lyricPumpFuture = _runLyrics();
  }

  Future<void> _runLyrics() async {
    _lyricRunning = true;
    try {
      while (!_closed && _lyricQueue.isNotEmpty) {
        final task = _lyricActive = _lyricQueue.removeAt(0);
        if (!tasks.contains(task)) continue;
        final revision = _lyricRevisions[task.track.id] ?? 0;
        bool valid() =>
            !_closed &&
            tasks.contains(task) &&
            (_lyricRevisions[task.track.id] ?? 0) == revision;
        task.lyricStatus = DownloadLyricStatus.fetching;
        notifyListeners();
        try {
          String? cached;
          try {
            cached = await lyrics(task.track);
          } on FormatException {
            cached = null;
          }
          if (!valid()) continue;
          if (cached != null && cached.trim().isNotEmpty) {
            task.lyricStatus = DownloadLyricStatus.available;
          } else {
            final embedded = task.filePath == null
                ? null
                : await MediaExporter.embeddedLyrics(File(task.filePath!));
            if (!valid()) continue;
            final candidate = embedded != null
                ? <String, dynamic>{
                    'syncedLyrics': embedded,
                    'source': 'embedded',
                  }
                : await lyricsClient.match(task.track, isCurrent: valid);
            if (!valid()) continue;
            final synced = candidate?['syncedLyrics'] as String?;
            final text = synced != null && synced.trim().isNotEmpty
                ? synced
                : candidate?['plainLyrics'] as String?;
            if (text == null || text.trim().isEmpty) {
              task.lyricStatus = DownloadLyricStatus.missing;
            } else {
              await _writeLyrics(
                task.track,
                text,
                expectedRevision: revision,
                allowed: () => !_closed && tasks.contains(task),
                source: candidate?['source'] as String? ?? 'lrclib',
              );
              if (valid()) task.lyricStatus = DownloadLyricStatus.available;
            }
          }
        } on AppFailure {
          if (valid()) task.lyricStatus = DownloadLyricStatus.failed;
        } on FileSystemException {
          if (valid()) task.lyricStatus = DownloadLyricStatus.failed;
        } finally {
          if (_closed && task.lyricStatus == DownloadLyricStatus.fetching) {
            task.lyricStatus = DownloadLyricStatus.waiting;
          }
          if (tasks.contains(task)) await _save();
          if (!_closed) notifyListeners();
          _lyricActive = null;
        }
      }
    } finally {
      _lyricRunning = false;
      _lyricActive = null;
    }
  }

  Future<void> saveLyrics(
    Track t,
    String text, {
    String source = 'manual',
    int offset = 0,
  }) async {
    _lyricRevisions[t.id] = (_lyricRevisions[t.id] ?? 0) + 1;
    await _writeLyrics(t, text, source: source, offset: offset);
    for (final task in tasks.where((task) => task.track.id == t.id)) {
      task.lyricStatus = text.trim().isEmpty
          ? DownloadLyricStatus.missing
          : DownloadLyricStatus.available;
    }
    if (!_closed) notifyListeners();
  }

  Future<void> _writeLyrics(
    Track t,
    String text, {
    int? expectedRevision,
    bool Function()? allowed,
    String source = 'manual',
    int offset = 0,
  }) async {
    final previous = _lyricWrites[t.id];
    final done = Completer<void>();
    _lyricWrites[t.id] = done.future;
    try {
      if (previous != null) await previous;
      if (allowed?.call() == false ||
          (expectedRevision != null &&
              (_lyricRevisions[t.id] ?? 0) != expectedRevision)) {
        return;
      }
      final file = File(path.join(directory.path, '${_stem(t)}.lyrics'));
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({'lrc': text, 'source': source, 'offset': offset}),
        flush: true,
      );
      await temp.rename(file.path);
    } finally {
      done.complete();
      if (identical(_lyricWrites[t.id], done.future)) _lyricWrites.remove(t.id);
    }
  }

  Future<Map<String, dynamic>?> lyricDocument(Track t) async {
    final file = File(path.join(directory.path, '${_stem(t)}.lyrics'));
    return await file.exists()
        ? Map<String, dynamic>.from(jsonDecode(await file.readAsString()))
        : null;
  }

  Future<String?> lyrics(Track t) async =>
      (await lyricDocument(t))?['lrc'] as String?;

  File coverFile(Track t) =>
      File(path.join(directory.path, '${_stem(t)}.cover'));
  @override
  void dispose() {
    _closed = true;
    lyricsClient.cancelRequests();
    _saveTimer?.cancel();
    _cancel?.cancel();
    unawaited(covers.close());
    super.dispose();
  }
}
