import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/music.dart';
import 'bilibili.dart';
import 'storage.dart';

class DownloadManager extends ChangeNotifier {
  DownloadManager(this.api, this.db, this.directory, {Dio? dio})
    : _http =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 40),
            ),
          );
  final BilibiliClient api;
  final AppDatabase db;
  final Directory directory;
  final Dio _http;
  final List<DownloadTask> tasks = [];
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
    await _pumpFuture;
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
          notifyListeners();
          // Cover failure is visible but does not invalidate an intact audio file.
          if (pending.track.cover.isNotEmpty) {
            try {
              await _http.download(
                pending.track.cover,
                path.join(directory.path, '${_stem(pending.track)}.cover'),
                cancelToken: _cancel,
                options: Options(
                  headers: {
                    'User-Agent': BilibiliClient.userAgent,
                    'Referer': 'https://www.bilibili.com/',
                  },
                ),
              );
            } on DioException catch (e) {
              if (!CancelToken.isCancel(e)) pending.error = '音频已下载，封面获取失败';
            }
          }
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

  Future<void> saveLyrics(Track t, String text) async {
    await File(
      path.join(directory.path, '${_stem(t)}.lyrics'),
    ).writeAsString(jsonEncode({'lrc': text}));
  }

  Future<String?> lyrics(Track t) async {
    final f = File(path.join(directory.path, '${_stem(t)}.lyrics'));
    return await f.exists()
        ? jsonDecode(await f.readAsString())['lrc'] as String?
        : null;
  }

  File coverFile(Track t) =>
      File(path.join(directory.path, '${_stem(t)}.cover'));
  @override
  void dispose() {
    _closed = true;
    _saveTimer?.cancel();
    _cancel?.cancel();
    super.dispose();
  }
}
