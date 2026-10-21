part of 'app.dart';

/// Per-route feedback. A finished asynchronous action cannot touch a disposed route.
class OperationFeedback extends ChangeNotifier {
  bool busy = false, failed = false, _closed = false;
  String message = '';
  Future<void> Function()? retry;
  void progress(String value) {
    if (_closed) return;
    message = value;
    notifyListeners();
  }

  void update(VoidCallback change) {
    if (_closed || busy) return;
    change();
    message = '';
    failed = false;
    retry = null;
    notifyListeners();
  }

  Future<bool> run(Future<void> Function() task, String success) async {
    if (busy || _closed) return false;
    busy = true;
    failed = false;
    message = '正在处理…';
    retry = null;
    notifyListeners();
    try {
      await task();
      if (!_closed) {
        message = success;
        failed = false;
      }
      return true;
    } on Exception catch (e) {
      if (!_closed) {
        failed = true;
        message = e is AppFailure ? e.message : '操作未完成，请重试';
        retry = () async {
          await run(task, success);
        };
      }
      return false;
    } finally {
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  Widget status(BuildContext context) => SizedBox(
    height: TingyuTokens.controlSize,
    child: Semantics(
      liveRegion: message.isNotEmpty,
      child: Row(
        children: [
          if (busy) ...[
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            const SizedBox(width: TingyuTokens.space),
          ],
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              style: TextStyle(
                fontSize: 12,
                color: failed ? context.tokens.danger : context.tokens.muted,
              ),
            ),
          ),
          if (failed && retry != null) labelButton('重试', retry),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}

void offerUndo(
  BuildContext context,
  String message,
  Future<void> Function() undo,
) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: '撤销',
        onPressed: () => unawaited(report(context, undo)),
      ),
    ),
  );
}

/// One shared icon slot for every download state in the song menu.
class TrackMenuDownload extends ConsumerWidget {
  const TrackMenuDownload(this.track, {super.key, required this.feedback});
  final Track track;
  final OperationFeedback feedback;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(libraryProvider);
    final task = trackDownload(p, track);
    final done = task?.status == DownloadStatus.completed;
    final transferring =
        task?.status == DownloadStatus.downloading ||
        task?.status == DownloadStatus.waiting;
    final label = switch (task?.status) {
      DownloadStatus.completed => '已下载',
      DownloadStatus.downloading =>
        '下载中${task!.progress == null ? '' : ' ${(task.progress! * 100).round()}%'}',
      DownloadStatus.waiting => '等待下载',
      DownloadStatus.paused => '继续下载',
      DownloadStatus.failed => '重试下载',
      _ => '下载',
    };
    return Pressable(
      key: done
          ? const ValueKey('menu-downloaded')
          : ValueKey('download-${track.id}'),
      label: label,
      dimWhenDisabled: false,
      selectionFill: false,
      onPressed: done || transferring || feedback.busy
          ? null
          : () => feedback.run(() async {
              if (task != null) {
                await p.downloads.retry(task);
              } else {
                await p.download(track, propagateFailure: true);
              }
            }, '已加入下载任务'),
      child: Row(
        children: [
          if (task?.status == DownloadStatus.downloading)
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                value: task!.progress,
                strokeWidth: 1.5,
              ),
            )
          else
            TingyuIcon(
              done
                  ? Icons.check_circle_outline
                  : task?.status == DownloadStatus.paused
                  ? Icons.play_arrow
                  : task?.status == DownloadStatus.failed
                  ? Icons.refresh
                  : task?.status == DownloadStatus.waiting
                  ? Icons.schedule
                  : Icons.download_outlined,
              size: 18,
              color: context.tokens.text,
            ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

Future<void> showBatchTransfer(
  BuildContext context,
  LibraryController p,
  List<String> source,
  VoidCallback onDone, {
  bool download = false,
}) async {
  final session = OperationFeedback();
  final ids = source.toSet().toList();
  final pending = <String, List<String>>{};
  bool completed = false;
  Future<void> process(Playlist? target) async {
    final key = target?.id ?? 'downloads';
    final work = pending[key] ?? ids;
    final failures = <String>[];
    var success = 0, existing = 0;
    final ok = await session.run(() async {
      for (final id in work) {
        final track = p.library[id];
        if (track == null) {
          failures.add(id);
          continue;
        }
        try {
          if (target == null) {
            if (trackDownload(p, track) != null) {
              existing++;
            } else {
              await p.download(track, propagateFailure: true);
              success++;
            }
          } else {
            final latest = p.playlists
                .where((x) => x.id == target.id)
                .firstOrNull;
            if (latest == null) throw const AppFailure('歌单已删除');
            if (latest.trackIds.contains(id)) {
              existing++;
            } else {
              await p.addToPlaylist(latest, track);
              success++;
            }
          }
        } on Exception {
          failures.add(id);
        }
        session.progress(
          '已处理 ${success + existing + failures.length} / ${work.length}',
        );
      }
      pending[key] = failures;
      if (failures.isNotEmpty) {
        throw AppFailure(
          '成功 $success 首，已有 $existing 首，失败 ${failures.length} 首；重试仅处理失败项',
        );
      }
    }, '处理完成');
    if (ok) {
      completed = true;
      session.progress(
        '${download ? '已加入下载任务' : '已添加'} $success 首，已有 $existing 首',
      );
    }
  }

  try {
    if (download) unawaited(process(null));
    await showContentActions(
      context,
      (ctx) => SimpleDialog(
        title: Text(download ? '批量下载' : '添加至歌单'),
        children: [
          session.status(ctx),
          if (!download) ...[
            for (final target in p.playlists)
              labelButton(
                target.name,
                session.busy ? null : () => process(target),
                icon: Icons.playlist_add,
              ),
            labelButton(
              '新建歌单',
              session.busy
                  ? null
                  : () async {
                      final name = await nameDialog(ctx);
                      if (name == null) return;
                      final created = await session.run(
                        () => p.addPlaylist(name),
                        '已新建歌单',
                      );
                      if (created) await process(p.playlists.last);
                    },
              icon: Icons.add,
            ),
          ],
          labelButton(
            '完成',
            session.busy
                ? null
                : () {
                    Navigator.pop(ctx);
                    if (completed) onDone();
                  },
          ),
        ],
      ),
      listenable: Listenable.merge([p, session]),
    );
  } finally {
    session.dispose();
  }
}
