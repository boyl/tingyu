import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../controllers/library_controller.dart';
import '../models/music.dart';
import 'theme.dart';
part 'library_views.dart';
part 'settings_views.dart';

Widget action(
  IconData icon,
  String label,
  FutureOr<void> Function()? call, {
  bool selected = false,
}) => Builder(
  builder: (context) => Tooltip(
    message: label,
    child: Pressable(
      key: ValueKey(label),
      label: label,
      onPressed: call == null ? null : () => report(context, call),
      selected: selected,
      padding: const EdgeInsets.all(10),
      child: Icon(icon),
    ),
  ),
);
Widget labelButton(
  String label,
  FutureOr<void> Function()? call, {
  IconData? icon,
  bool selected = false,
}) => Builder(
  builder: (context) => Pressable(
    key: ValueKey(label),
    onPressed: call == null ? null : () => report(context, call),
    selected: selected,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  ),
);

Future<void> report(
  BuildContext context,
  FutureOr<void> Function() task,
) async {
  try {
    await task();
  } on Exception catch (e) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('操作未完成'),
          content: Text(e is AppFailure ? e.message : '请检查网络或存储空间后重试'),
          actions: [labelButton('知道了', () => Navigator.pop(ctx))],
        ),
      );
    }
  }
}

Future<bool> confirm(BuildContext context, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认操作'),
        content: Text(text),
        actions: [
          labelButton('取消', () => Navigator.pop(ctx, false)),
          labelButton('确认', () => Navigator.pop(ctx, true)),
        ],
      ),
    ) ??
    false;
Future<String?> nameDialog(BuildContext context, {String initial = ''}) =>
    showDialog<String>(context: context, builder: (_) => _NameDialog(initial));

class _NameDialog extends StatefulWidget {
  const _NameDialog(this.initial);
  final String initial;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final edit = TextEditingController(text: widget.initial);
  String? error;
  @override
  void dispose() {
    edit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial.isEmpty ? '新建歌单' : '重命名歌单'),
    content: TextField(
      controller: edit,
      autofocus: true,
      maxLength: 30,
      decoration: InputDecoration(labelText: '歌单名称', errorText: error),
    ),
    actions: [
      labelButton('取消', () => Navigator.pop(context)),
      labelButton('保存', () {
        if (edit.text.trim().isEmpty) {
          setState(() => error = '请输入歌单名称');
          return;
        }
        Navigator.pop(context, edit.text.trim());
      }),
    ],
  );
}

class Artwork extends ConsumerWidget {
  const Artwork(this.track, {super.key, this.size = 48});
  final Track track;
  final double size;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.read(libraryProvider), file = p.downloads.coverFile(track);
    Widget fallback() => ColoredBox(
      color: context.tokens.tint,
      child: Center(
        child: Icon(
          Icons.graphic_eq,
          size: size / 3,
          color: context.tokens.accent,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(TingyuTokens.radius),
      child: SizedBox(
        width: size,
        height: size,
        child: file.existsSync()
            ? Image.file(
                file,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback(),
              )
            : track.cover.isEmpty
            ? fallback()
            : Image.network(
                track.cover,
                fit: BoxFit.cover,
                headers: const {'Referer': 'https://www.bilibili.com/'},
                errorBuilder: (_, _, _) => fallback(),
              ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView(this.title, this.description, {super.key, this.child});
  final String title, description;
  final Widget? child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.album_outlined, size: 42, color: context.tokens.accent),
          const SizedBox(height: 20),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.tokens.muted, height: 1.8),
          ),
          if (child != null) ...[const SizedBox(height: 16), child!],
        ],
      ),
    ),
  );
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.page, this.playlistId});
  final String page;
  final String? playlistId;
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late final TextEditingController search;
  @override
  void initState() {
    super.initState();
    search = TextEditingController(text: ref.read(libraryProvider).query);
  }

  bool selecting = false;
  final Set<String> selection = {};
  String get collectionKey => widget.playlistId ?? widget.page;
  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page ||
        oldWidget.playlistId != widget.playlistId) {
      selecting = false;
      selection.clear();
    }
  }

  List<String> visibleIds(LibraryController p, Playlist? list) =>
      p.collectionIds(
        collectionKey,
        widget.page == 'likes' ? p.likes : list?.trackIds ?? p.library.keys,
      );
  Timer? debounce;
  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  void navigate(String page) {
    FocusManager.instance.primaryFocus?.unfocus();
    context.go(page == 'library' ? '/' : '/$page');
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(libraryProvider), t = context.tokens;
    final desktop = MediaQuery.sizeOf(context).width >= 960;
    final list = p.playlists
        .where((l) => l.id == widget.playlistId)
        .firstOrNull;
    final title = switch (widget.page) {
      'search' => '搜索',
      'downloads' => '下载',
      'likes' => '我喜欢的',
      'settings' => '设置',
      'playlist' => list?.name ?? '歌单不存在',
      _ => '音乐库',
    };
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (selecting)
              action(
                Icons.close,
                '退出多选',
                () => setState(() {
                  selecting = false;
                  selection.clear();
                }),
              )
            else if (widget.page == 'playlist')
              action(Icons.arrow_back, '返回音乐库', () => navigate('library'))
            else if (!desktop && widget.page == 'library')
              action(
                Icons.settings_outlined,
                '打开设置',
                () => context.push('/settings'),
              ),
            Expanded(
              child: Text(
                selecting ? '已选 ${selection.length} 首' : title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (selecting)
              labelButton(
                '全选',
                () => setState(() {
                  final ids = visibleIds(p, list);
                  if (selection.containsAll(ids)) {
                    selection.clear();
                  } else {
                    selection.addAll(ids);
                  }
                }),
              )
            else if (widget.page == 'library')
              action(Icons.playlist_add, '新建歌单', () async {
                final name = await nameDialog(context);
                if (name != null && context.mounted) await p.addPlaylist(name);
              })
            else if (list != null)
              action(
                Icons.more_horiz,
                '歌单更多',
                () => showPlaylistActions(context, p, list),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (p.error.isNotEmpty) errorBox(context, p.error, p.clearError),
        if (widget.page == 'search') ...[
          TextField(
            controller: search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '歌曲、UP 主、BV / AV 号或链接',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 450), () {
                unawaited(p.search(v));
              });
            },
            onSubmitted: (v) => p.search(v),
          ),
          const SizedBox(height: 20),
          if (p.searching) const Center(child: CircularProgressIndicator()),
          if (p.searchError.isNotEmpty)
            errorBox(
              context,
              p.searchError,
              () => p.search(search.text, page: p.searchAttemptPage),
            ),
          if (search.text.isEmpty)
            EmptyView(
              '从一首歌开始',
              '搜索 B 站视频，或粘贴视频链接。\n音乐内容来自 B 站，登录后可导入收藏夹。',
              child: labelButton(
                '打开 B 站',
                () => launchUrl(Uri.parse('https://www.bilibili.com/')),
              ),
            ),
          if (!p.searching &&
              search.text.isNotEmpty &&
              p.results.isEmpty &&
              p.searchError.isEmpty)
            const EmptyView('没有找到相关内容', '换个关键词，或直接粘贴 BV 号。'),
          for (final track in p.results) TrackRow(track),
          if (p.results.isNotEmpty && !p.searching)
            Center(
              child: labelButton(
                '加载更多',
                () => p.search(search.text, page: p.searchPage + 1),
              ),
            ),
        ],
        if (widget.page == 'downloads') DownloadsPanel(p),
        if (['library', 'likes', 'playlist'].contains(widget.page)) ...[
          if (widget.page == 'library') ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...p.playlists.map(
                  (l) => labelButton(
                    l.name,
                    () => context.go('/playlist/${l.id}'),
                    icon: Icons.library_music_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (p.history.isNotEmpty) ...[
              const Text(
                '最近播放',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: desktop ? 220 : 200,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: p.history.take(8).length,
                  separatorBuilder: (_, _) => const SizedBox(width: 20),
                  itemBuilder: (ctx, i) {
                    final track = p.library[p.history[i]]!;
                    return Pressable(
                      onPressed: () => p.play(track),
                      padding: EdgeInsets.zero,
                      child: SizedBox(
                        width: desktop ? 160 : 140,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Artwork(track, size: desktop ? 160 : 140),
                            const SizedBox(height: 10),
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              track.artist,
                              style: TextStyle(fontSize: 11, color: t.muted),
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
          ],
          if (list != null) PlaylistSummary(list),
          CollectionToolbar(
            ids: visibleIds(p, list),
            list: list,
            collectionKey: collectionKey,
            selecting: selecting,
            onSelect: () => setState(() {
              selecting = true;
              selection.clear();
            }),
          ),
          const SizedBox(height: 12),
          ..._libraryRows(p, list),
        ],
      ],
    );
    return PopScope(
      canPop: !selecting && widget.page != 'playlist',
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (selecting) {
          setState(() {
            selecting = false;
            selection.clear();
          });
        } else if (widget.page == 'playlist') {
          navigate('library');
        }
      },
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        child: Actions(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                final focusContext =
                    FocusManager.instance.primaryFocus?.context;
                if (focusContext
                        ?.findAncestorWidgetOfExactType<EditableText>() ==
                    null) {
                  unawaited(p.toggle());
                }
                return null;
              },
            ),
          },
          child: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (desktop) SizedBox(width: 224, child: sidebar(p)),
                        Expanded(
                          child: SingleChildScrollView(
                            key: PageStorageKey(
                              'page-${widget.page}-${widget.playlistId}',
                            ),
                            padding: EdgeInsets.all(desktop ? 36 : 20),
                            child: content,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selecting)
                    SelectionBar(
                      ids: selection.where(p.library.containsKey).toList(),
                      list: list,
                      onDone: () => setState(() {
                        selecting = false;
                        selection.clear();
                      }),
                    )
                  else
                    MiniPlayer(p),
                ],
              ),
            ),
            bottomNavigationBar: desktop
                ? null
                : CompactNavigation(
                    selected: widget.page == 'playlist'
                        ? 'library'
                        : widget.page,
                    onSelect: navigate,
                  ),
          ),
        ),
      ),
    );
  }

  List<Widget> _libraryRows(LibraryController p, Playlist? list) {
    final ids = visibleIds(p, list);
    if (ids.isEmpty) {
      return [
        EmptyView(
          list == null ? '这里还很安静' : '歌单还没有歌曲',
          '去搜索喜欢的声音，加入你的音乐收藏。',
          child: labelButton(
            list == null ? '去搜索' : '添加歌曲',
            () => navigate('search'),
          ),
        ),
      ];
    }
    return ids
        .where(p.library.containsKey)
        .map(
          (id) => selecting
              ? SelectionTrackRow(
                  p.library[id]!,
                  selected: selection.contains(id),
                  onPressed: () => setState(() {
                    selection.contains(id)
                        ? selection.remove(id)
                        : selection.add(id);
                  }),
                )
              : TrackRow(p.library[id]!, playlist: list),
        )
        .toList();
  }

  Widget sidebar(LibraryController p) => Container(
    color: context.tokens.sidebar,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24, horizontal: 12),
          child: Row(
            children: [
              Icon(Icons.graphic_eq),
              SizedBox(width: 12),
              Text(
                '听屿',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        for (final item in [
          ('search', Icons.search, '搜索'),
          ('library', Icons.library_music_outlined, '音乐库'),
          ('downloads', Icons.download_outlined, '下载'),
          ('likes', Icons.favorite_border, '我喜欢的'),
        ])
          labelButton(
            item.$3,
            () => navigate(item.$1),
            icon: item.$2,
            selected: widget.page == item.$1,
          ),
        const Divider(height: 32),
        Expanded(
          child: ListView(
            children: p.playlists
                .map(
                  (l) => labelButton(
                    l.name,
                    () => context.go('/playlist/${l.id}'),
                    icon: Icons.queue_music,
                    selected: widget.playlistId == l.id,
                  ),
                )
                .toList(),
          ),
        ),
        labelButton(
          '设置',
          () => context.push('/settings'),
          icon: Icons.settings_outlined,
          selected: widget.page == 'settings',
        ),
      ],
    ),
  );
}

Widget errorBox(BuildContext context, String message, VoidCallback retry) =>
    Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.tokens.tint,
        borderRadius: BorderRadius.circular(TingyuTokens.radius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: context.tokens.danger, fontSize: 12),
            ),
          ),
          action(Icons.refresh, '重试或关闭提示', retry),
        ],
      ),
    );

Future<void> showPlaylistActions(
  BuildContext context,
  LibraryController p,
  Playlist list,
) => showContentActions(
  context,
  (ctx) => SimpleDialog(
    title: Text(list.name),
    children: [
      labelButton('编辑名称与简介', () async {
        Navigator.pop(ctx);
        await showDialog<void>(
          context: context,
          builder: (_) => PlaylistEditDialog(list),
        );
      }, icon: Icons.edit_outlined),
      labelButton('添加歌曲', () {
        Navigator.pop(ctx);
        context.go('/search');
      }, icon: Icons.playlist_add),
      labelButton('下载全部', () async {
        Navigator.pop(ctx);
        for (final id in list.trackIds) {
          final track = p.library[id];
          if (track != null) await p.download(track);
        }
      }, icon: Icons.download_outlined),
      labelButton('删除歌单', () async {
        Navigator.pop(ctx);
        if (await confirm(context, '删除歌单？已下载音频和喜欢记录会保留。')) {
          await p.editPlaylist(list, delete: true);
          if (context.mounted) context.go('/');
        }
      }, icon: Icons.delete_outline),
    ],
  ),
);

Widget downloadProgress(BuildContext context, double? progress) => SizedBox(
  width: 24,
  height: 24,
  child: Stack(
    alignment: Alignment.center,
    children: [
      SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          value: progress,
          color: context.tokens.accent,
        ),
      ),
      Icon(Icons.arrow_downward, size: 14, color: context.tokens.accent),
    ],
  ),
);

class PlaylistDownloadAction extends ConsumerWidget {
  const PlaylistDownloadAction(this.list, {super.key});
  final Playlist list;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(libraryProvider);
    final tracks = list.trackIds
        .map((id) => p.library[id])
        .whereType<Track>()
        .toList();
    final tasks = tracks.map((track) => trackDownload(p, track)).toList();
    final completed = tasks
        .where((task) => task?.status == DownloadStatus.completed)
        .length;
    final active = tasks.any(
      (task) =>
          task?.status == DownloadStatus.downloading ||
          task?.status == DownloadStatus.waiting,
    );
    final progress = tracks.isEmpty
        ? 0.0
        : tasks.fold<double>(
                0,
                (value, task) =>
                    value +
                    (task?.status == DownloadStatus.completed
                        ? 1
                        : task?.progress ?? 0),
              ) /
              tracks.length;
    final failed = tasks.any((task) => task?.status == DownloadStatus.failed);
    final allDone = tracks.isNotEmpty && completed == tracks.length;
    final label = allDone
        ? '已全部下载，点击查看'
        : active
        ? '正在下载歌单 $completed/${tracks.length}，点击查看'
        : failed
        ? '部分下载失败，点击重试'
        : '下载全部';
    return Tooltip(
      message: label,
      child: Pressable(
        key: const ValueKey('下载全部'),
        label: label,
        selected: allDone,
        onPressed: tracks.isEmpty
            ? null
            : () => report(context, () async {
                if (allDone || active) {
                  context.go('/downloads');
                  return;
                }
                for (final track in tracks) {
                  final task = trackDownload(p, track);
                  if (task == null) {
                    await p.download(track);
                  } else if (task.status == DownloadStatus.failed ||
                      task.status == DownloadStatus.paused) {
                    await p.downloads.retry(task);
                  }
                }
              }),
        child: active
            ? downloadProgress(context, progress)
            : Icon(
                allDone
                    ? Icons.download_done
                    : failed
                    ? Icons.error_outline
                    : Icons.download_outlined,
                color: failed
                    ? context.tokens.danger
                    : allDone
                    ? context.tokens.accent
                    : context.tokens.text,
              ),
      ),
    );
  }
}

DownloadTask? trackDownload(LibraryController p, Track track) => p
    .downloads
    .tasks
    .where(
      (task) =>
          task.track.id == track.id ||
          (track.cid == 0 &&
              task.track.bvid == track.bvid &&
              task.track.part == 1),
    )
    .firstOrNull;

/// One icon communicates transfer state across search, library and player.
class TrackDownloadAction extends ConsumerStatefulWidget {
  const TrackDownloadAction(this.track, {super.key});
  final Track track;
  @override
  ConsumerState<TrackDownloadAction> createState() =>
      _TrackDownloadActionState();
}

class _TrackDownloadActionState extends ConsumerState<TrackDownloadAction> {
  bool preparing = false;
  @override
  Widget build(BuildContext context) {
    final p = ref.watch(libraryProvider), track = widget.track;
    final task = trackDownload(p, track);
    final completed = task?.status == DownloadStatus.completed;
    final transferring =
        preparing || task?.status == DownloadStatus.downloading;
    final label = preparing
        ? '准备下载'
        : switch (task?.status) {
            DownloadStatus.waiting => '等待下载，点击查看',
            DownloadStatus.downloading =>
              '下载中${task!.total > 0 ? ' ${(task.progress! * 100).round()}%' : ''}，点击查看',
            DownloadStatus.completed => '已下载，点击查看',
            DownloadStatus.paused => '下载已暂停，点击继续',
            DownloadStatus.failed => '下载失败，点击重试',
            null => '下载',
          };
    Future<void> activate() async {
      if (completed ||
          task?.status == DownloadStatus.downloading ||
          task?.status == DownloadStatus.waiting) {
        context.go('/downloads');
        return;
      }
      setState(() => preparing = true);
      try {
        if (task != null) {
          await p.downloads.retry(task);
        } else {
          await p.download(track);
        }
      } finally {
        if (mounted) setState(() => preparing = false);
      }
    }

    final icon = switch (task?.status) {
      DownloadStatus.completed => Icons.download_done,
      DownloadStatus.paused => Icons.pause_circle_outline,
      DownloadStatus.failed => Icons.error_outline,
      DownloadStatus.waiting => Icons.schedule,
      _ => Icons.download_outlined,
    };
    return Tooltip(
      message: label,
      child: Pressable(
        key: ValueKey('download-${track.id}'),
        label: '$label ${track.title}',
        selected: completed,
        onPressed: preparing ? null : () => report(context, activate),
        child: transferring
            ? downloadProgress(context, preparing ? null : task?.progress)
            : Icon(
                icon,
                color: task?.status == DownloadStatus.failed
                    ? context.tokens.danger
                    : completed
                    ? context.tokens.accent
                    : context.tokens.text,
              ),
      ),
    );
  }
}

class TrackRow extends ConsumerWidget {
  const TrackRow(this.track, {super.key, this.playlist});
  final Track track;
  final Playlist? playlist;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(libraryProvider),
        desktop = MediaQuery.sizeOf(context).width >= 960,
        liked = p.likes.contains(track.id);
    return Container(
      decoration: BoxDecoration(
        color: p.current?.id == track.id ? context.tokens.tint : null,
        borderRadius: BorderRadius.circular(TingyuTokens.radius),
        border: Border(bottom: BorderSide(color: context.tokens.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Pressable(
              key: ValueKey('play-${track.id}'),
              label: '播放 ${track.title}',
              onPressed: () => p.play(track),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Row(
                children: [
                  Artwork(track),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          track.artist,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.tokens.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!desktop && liked)
            Semantics(
              label: '已喜欢',
              child: Icon(
                Icons.favorite,
                size: 16,
                color: context.tokens.accent,
              ),
            ),
          if (desktop) ...[
            Text(
              clock(Duration(seconds: track.duration)),
              style: TextStyle(fontSize: 11, color: context.tokens.muted),
            ),
            const SizedBox(width: 12),
            action(
              liked ? Icons.favorite : Icons.favorite_border,
              '喜欢 ${track.title}',
              () => p.toggleLike(track),
              selected: liked,
            ),
          ],
          TrackDownloadAction(
            track,
            key: ValueKey('download-action-${track.id}'),
          ),
          action(
            Icons.more_horiz,
            '更多 ${track.title}',
            () => showTrackActions(context, p, track, playlist),
          ),
        ],
      ),
    );
  }
}

Future<void> showTrackActions(
  BuildContext context,
  LibraryController p,
  Track track,
  Playlist? list,
) async {
  await showContentActions(
    context,
    (ctx) => SimpleDialog(
      title: Text(
        track.title,
        maxLines: 2,
        style: const TextStyle(fontSize: 17),
      ),
      children: [
        labelButton('下一首播放', () async {
          await p.enqueue(track, next: true);
          if (ctx.mounted) Navigator.pop(ctx);
        }, icon: Icons.playlist_play),
        labelButton('加入队列', () async {
          await p.enqueue(track);
          if (ctx.mounted) Navigator.pop(ctx);
        }, icon: Icons.queue_music),
        labelButton(p.likes.contains(track.id) ? '取消喜欢' : '喜欢', () async {
          await p.toggleLike(track);
          if (ctx.mounted) Navigator.pop(ctx);
        }, icon: Icons.favorite_border),
        labelButton('加入歌单', () async {
          Navigator.pop(ctx);
          await showAddPlaylist(context, p, track);
        }, icon: Icons.playlist_add),
        if (list != null)
          labelButton('移出歌单', () async {
            Navigator.pop(ctx);
            if (await confirm(context, '从歌单移除这首歌？已下载文件会保留。')) {
              await p.editPlaylist(list, remove: track.id);
            }
          }, icon: Icons.remove_circle_outline),
        labelButton(
          '在 B 站打开',
          () => launchUrl(
            Uri.parse('https://www.bilibili.com/video/${track.bvid}'),
          ),
          icon: Icons.open_in_new,
        ),
      ],
    ),
  );
}

Future<void> showAddPlaylist(
  BuildContext context,
  LibraryController p,
  Track track,
) async => showDialog<void>(
  context: context,
  builder: (ctx) => SimpleDialog(
    title: const Text('添加至歌单'),
    children: [
      ...p.playlists.map(
        (l) => labelButton(l.name, () async {
          await p.addToPlaylist(l, track);
          if (ctx.mounted) Navigator.pop(ctx);
        }),
      ),
      labelButton('新建歌单', () async {
        Navigator.pop(ctx);
        final name = await nameDialog(context);
        if (name != null && context.mounted) {
          await report(context, () => p.addPlaylist(name, track: track));
        }
      }, icon: Icons.add),
    ],
  ),
);

class MiniPlayer extends StatelessWidget {
  const MiniPlayer(this.p, {super.key});
  final LibraryController p;
  @override
  Widget build(BuildContext context) {
    final t = p.current;
    if (t == null) return const SizedBox.shrink();
    final desktop = MediaQuery.sizeOf(context).width >= 960;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: context.tokens.surface,
        border: Border(top: BorderSide(color: context.tokens.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Pressable(
              key: const ValueKey('展开播放器'),
              label: '展开播放器',
              onPressed: () => context.push('/player'),
              padding: EdgeInsets.zero,
              child: Row(
                children: [
                  Artwork(t),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          p.opening
                              ? '正在解析…'
                              : p.quality.isEmpty
                              ? '点击继续播放'
                              : t.artist,
                          maxLines: 1,
                          style: TextStyle(
                            color: context.tokens.muted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (desktop)
            Expanded(
              flex: 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [transport(context, p), SeekBar(p)],
              ),
            )
          else
            action(
              p.playing ? Icons.pause : Icons.play_arrow,
              '播放或暂停',
              p.opening ? null : () => p.toggle(),
            ),
          if (desktop)
            SizedBox(
              width: 120,
              child: Slider(
                value: p.playback.player.volume,
                onChanged: (v) => p.playback.player.setVolume(v),
              ),
            ),
          if (!desktop)
            action(Icons.queue_music, '播放队列', () => showQueue(context)),
        ],
      ),
    );
  }
}

String modeLabel(String mode) => switch (mode) {
  'shuffle' => '随机播放',
  'repeat' => '单曲循环',
  _ => '列表循环',
};
IconData modeIcon(String mode) => switch (mode) {
  'shuffle' => Icons.shuffle,
  'repeat' => Icons.repeat_one,
  _ => Icons.repeat,
};

class ModeButton extends StatelessWidget {
  const ModeButton(this.p, {super.key});
  final LibraryController p;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: '${modeLabel(p.mode)}，点击切换',
    child: Pressable(
      key: const ValueKey('cycle-mode'),
      label: '播放模式：${modeLabel(p.mode)}，点击切换',
      onPressed: () => report(context, () {
        const modes = ['order', 'repeat', 'shuffle'];
        return p.setMode(modes[(modes.indexOf(p.mode) + 1) % modes.length]);
      }),
      child: Icon(modeIcon(p.mode), color: context.tokens.accent),
    ),
  );
}

Widget transport(BuildContext context, LibraryController p) => Row(
  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
  children: [
    ModeButton(p),
    action(Icons.skip_previous, '上一首', p.opening ? null : () => p.next(-1)),
    Pressable(
      label: p.playing ? '暂停' : '播放',
      key: const ValueKey('toggle-playback'),
      onPressed: p.opening ? null : () => p.toggle(),
      minSize: 56,
      color: context.tokens.accent,
      child: Icon(
        p.playing ? Icons.pause : Icons.play_arrow,
        color: context.tokens.onAccent,
      ),
    ),
    action(Icons.skip_next, '下一首', p.opening ? null : () => p.next()),
    action(Icons.queue_music, '播放队列', () => showQueue(context)),
  ],
);

class SeekBar extends StatelessWidget {
  const SeekBar(this.p, {super.key});
  final LibraryController p;
  @override
  Widget build(BuildContext context) {
    final duration =
            p.playback.player.duration ??
            Duration(seconds: p.current?.duration ?? 0),
        max = duration.inMilliseconds.toDouble();
    return Row(
      children: [
        Text(
          clock(p.position),
          style: TextStyle(fontSize: 10, color: context.tokens.muted),
        ),
        Expanded(
          child: Slider(
            value: p.position.inMilliseconds.toDouble().clamp(
              0,
              max > 0 ? max : 1,
            ),
            max: max > 0 ? max : 1,
            onChanged: max > 0
                ? (v) => p.playback.seek(Duration(milliseconds: v.round()))
                : null,
          ),
        ),
        Text(
          clock(duration),
          style: TextStyle(fontSize: 10, color: context.tokens.muted),
        ),
      ],
    );
  }
}

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(libraryProvider), track = p.current;
    void goBack() => context.canPop() ? context.pop() : context.go('/');
    if (track == null) {
      return Scaffold(
        appBar: PlayerHeader(onBack: goBack, status: ''),
        body: EmptyView(
          '还没有正在播放的曲目',
          '搜索一首歌开始聆听',
          child: labelButton('返回音乐库', () => context.go('/')),
        ),
      );
    }
    final width = MediaQuery.sizeOf(context).width, desktop = width >= 960;
    final art = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Artwork(
            track,
            size: desktop ? 360 : (width - 64).clamp(180, 340),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    track.artist,
                    style: TextStyle(color: context.tokens.muted),
                  ),
                ],
              ),
            ),
            action(
              p.likes.contains(track.id)
                  ? Icons.favorite
                  : Icons.favorite_border,
              '喜欢当前歌曲',
              () => p.toggleLike(track),
              selected: p.likes.contains(track.id),
            ),
          ],
        ),
        if (p.parts.length > 1)
          DropdownButton<String>(
            isExpanded: true,
            value: p.parts.any((t) => t.id == track.id) ? track.id : null,
            hint: const Text('选择分 P'),
            items: p.parts
                .map(
                  (t) => DropdownMenuItem(
                    value: t.id,
                    child: Text(
                      'P${t.part} · ${t.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (id) {
              final part = p.parts.firstWhere((t) => t.id == id);
              p.play(part);
            },
          ),
      ],
    );
    final lyrics = SizedBox(height: desktop ? 280 : 150, child: LyricPanel(p));
    return Scaffold(
      appBar: PlayerHeader(
        onBack: goBack,
        status: p.opening ? '正在加载…' : '',
        onMore: () => showTrackActions(context, p, track, null),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SeekBar(p),
                  transport(context, p),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      TrackDownloadAction(
                        track,
                        key: ValueKey('download-action-${track.id}'),
                      ),
                      action(
                        Icons.lyrics_outlined,
                        '歌词',
                        () => showLyrics(context, p),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          key: const ValueKey('player-content'),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              if (p.error.isNotEmpty)
                errorBox(context, p.error, () => p.play(track, at: p.position)),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: desktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: art),
                            const SizedBox(width: 80),
                            Expanded(child: lyrics),
                          ],
                        )
                      : Column(
                          children: [art, const SizedBox(height: 16), lyrics],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Navigation stays outside the scrollable content, including empty playback.
class PlayerHeader extends StatelessWidget implements PreferredSizeWidget {
  const PlayerHeader({
    super.key,
    required this.onBack,
    required this.status,
    this.onMore,
  });
  final VoidCallback onBack;
  final String status;
  final VoidCallback? onMore;
  @override
  Size get preferredSize => const Size.fromHeight(64);
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.tokens.background,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            action(Icons.arrow_back, '返回', onBack),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: context.tokens.muted),
              ),
            ),
            const SizedBox(width: 12),
            if (onMore != null)
              action(Icons.more_horiz, '歌曲操作', onMore)
            else
              const SizedBox(width: 48),
          ],
        ),
      ),
    ),
  );
}

class LyricPanel extends StatefulWidget {
  const LyricPanel(this.p, {super.key});
  final LibraryController p;
  @override
  State<LyricPanel> createState() => _LyricPanelState();
}

class _LyricPanelState extends State<LyricPanel> {
  final scroll = ScrollController();
  int last = -1;
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p, lines = p.lines;
    if (lines.isEmpty) {
      return Center(
        child: Tooltip(
          message: p.lyricError,
          child: Text(
            p.lyricText.isEmpty
                ? (p.lyricError.isEmpty ? '暂无歌词' : '歌词暂不可用')
                : p.lyricText,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.tokens.muted, height: 2),
          ),
        ),
      );
    }
    var index = lines.lastIndexWhere(
      (l) => l.time.inMilliseconds <= p.position.inMilliseconds + p.lyricOffset,
    );
    if (index < 0) index = 0;
    if (index != last) {
      last = index;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          final target = (index * 64.0)
              .clamp(0.0, scroll.position.maxScrollExtent)
              .toDouble();
          if (MediaQuery.disableAnimationsOf(context)) {
            scroll.jumpTo(target);
          } else {
            unawaited(
              scroll.animateTo(
                target,
                duration: TingyuTokens.transition,
                curve: Curves.easeOut,
              ),
            );
          }
        }
      });
    }
    return ListView.builder(
      controller: scroll,
      itemCount: lines.length,
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemBuilder: (ctx, i) => SizedBox(
        height: 64,
        child: Center(
          child: Text(
            lines[i].text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: i == index ? context.tokens.accent : context.tokens.muted,
              fontWeight: i == index ? FontWeight.w600 : FontWeight.w400,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showQueue(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.tokens.surface,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final p = ref.watch(libraryProvider);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * .7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(child: Text('播放队列 · ${p.queue.length} 首')),
                      labelButton('清空', () async {
                        if (await confirm(ctx, '清空队列并停止播放？')) {
                          await p.clearQueue();
                        }
                      }),
                      action(Icons.close, '关闭队列', () => Navigator.pop(ctx)),
                    ],
                  ),
                ),
                Expanded(
                  child: p.queue.isEmpty
                      ? const EmptyView('队列是空的', '从搜索结果添加下一首声音。')
                      : ListView.builder(
                          itemCount: p.queue.length,
                          itemBuilder: (ctx, i) {
                            final track = p.library[p.queue[i]]!;
                            return Row(
                              children: [
                                Expanded(
                                  child: Pressable(
                                    onPressed: () => p.play(track),
                                    child: Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                action(
                                  Icons.arrow_upward,
                                  '上移第 ${i + 1} 首',
                                  i == 0 ? null : () => p.moveQueue(i, -1),
                                ),
                                action(
                                  Icons.arrow_downward,
                                  '下移第 ${i + 1} 首',
                                  i == p.queue.length - 1
                                      ? null
                                      : () => p.moveQueue(i, 1),
                                ),
                                action(
                                  Icons.close,
                                  '移除第 ${i + 1} 首',
                                  () => p.removeQueue(track.id),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class DownloadsPanel extends StatelessWidget {
  const DownloadsPanel(this.p, {super.key});
  final LibraryController p;
  @override
  Widget build(BuildContext context) {
    if (p.downloads.tasks.isEmpty) {
      return const EmptyView('还没有下载', '点击歌曲或歌单的下载图标。');
    }
    final completed = p.downloads.tasks
            .where((d) => d.status == DownloadStatus.completed)
            .length,
        bytes = p.downloads.tasks
            .where((d) => d.status == DownloadStatus.completed)
            .fold<int>(0, (v, d) => v + d.received);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$completed 首已下载 · ${(bytes / 1024 / 1024).toStringAsFixed(1)} MB',
        ),
        const SizedBox(height: 20),
        for (final d in p.downloads.tasks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Artwork(d.track),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        d.error ??
                            switch (d.status) {
                              DownloadStatus.waiting => '等待下载',
                              DownloadStatus.downloading =>
                                '下载中 · ${d.progress == null ? '未知大小' : '${(d.progress! * 100).round()}%'}',
                              DownloadStatus.completed => '已下载 · 可离线播放',
                              DownloadStatus.failed => '下载失败',
                              DownloadStatus.paused => '下载已中断，点击重试',
                            },
                        style: TextStyle(
                          fontSize: 11,
                          color: context.tokens.muted,
                        ),
                      ),
                      if (d.status == DownloadStatus.downloading)
                        LinearProgressIndicator(value: d.progress),
                    ],
                  ),
                ),
                if (d.status == DownloadStatus.completed)
                  action(Icons.play_arrow, '播放已下载歌曲', () => p.play(d.track))
                else if (d.status == DownloadStatus.downloading ||
                    d.status == DownloadStatus.waiting)
                  action(Icons.pause, '暂停下载', () => p.downloads.pause(d))
                else if ([
                  DownloadStatus.failed,
                  DownloadStatus.paused,
                ].contains(d.status))
                  action(Icons.refresh, '重试下载', () => p.downloads.retry(d)),
                action(
                  d.status == DownloadStatus.completed
                      ? Icons.delete_outline
                      : Icons.close,
                  '移除下载',
                  () async {
                    if (d.status != DownloadStatus.completed ||
                        await confirm(context, '删除音频和离线资料？歌单与喜欢记录会保留。')) {
                      if (context.mounted) {
                        await report(context, () => p.removeDownload(d));
                      }
                    }
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

void showAboutTingyu(BuildContext context) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('听屿'),
    content: const Text('听屿 $tingyuVersion\n\n歌单与下载保存在本机，账号凭据保存在系统安全存储。'),
    actions: [labelButton('关闭', () => Navigator.pop(ctx))],
  ),
);

Future<void> showAccount(BuildContext context, LibraryController p) async {
  final size = MediaQuery.sizeOf(context);
  if (size.width < 960) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.tokens.surface,
      builder: (_) =>
          SizedBox(height: size.height * .92, child: AccountPanel(p)),
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 460,
          height: (size.height - 64).clamp(280, 680).toDouble(),
          child: AccountPanel(p),
        ),
      ),
    );
  }
}

class AccountPanel extends StatefulWidget {
  const AccountPanel(this.p, {super.key});
  final LibraryController p;
  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  String? qr, key;
  String message = '扫码后可以导入你的 B 站收藏夹';
  bool busy = false, polling = false;
  Map<String, dynamic>? selectedFolder;
  Playlist? imported;
  Timer? timer;
  List<Map<String, dynamic>> folders = [];
  @override
  void initState() {
    super.initState();
    if (widget.p.api.hasSession || widget.p.profile != null) {
      unawaited(loadProfile());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> loadProfile() async {
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await widget.p.refreshProfile();
      if (!mounted) return;
      if (widget.p.profile == null) {
        setState(() {
          message = widget.p.error;
          folders = [];
          selectedFolder = null;
        });
        return;
      }
      final found = await widget.p.api.folders(widget.p.profile!['mid']);
      if (mounted) {
        setState(() {
          folders = found;
          selectedFolder = null;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => message = e is AppFailure ? e.message : '收藏夹加载失败，请重试');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> importSelected() async {
    final folder = selectedFolder;
    if (folder == null || busy) return;
    setState(() {
      busy = true;
      message = '正在导入，请稍候…';
      imported = null;
    });
    try {
      final result = await widget.p.importFolder(folder);
      if (mounted) {
        setState(() {
          imported = result;
          message = '已导入 ${result.trackIds.length} 首到「${result.name}」';
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => message = e is AppFailure ? e.message : '导入失败，请重试');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> generate() async {
    timer?.cancel();
    setState(() => busy = true);
    try {
      final result = await widget.p.api.createQr();
      if (!mounted) return;
      setState(() {
        qr = result.url;
        key = result.key;
        message = '请使用哔哩哔哩 App 扫码确认';
        busy = false;
      });
      timer = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (busy || polling || !mounted) return;
        polling = true;
        try {
          final code = await widget.p.api.pollQr(key!);
          if (!mounted) return;
          if (code == 0) {
            timer?.cancel();
            setState(() => qr = null);
            await loadProfile();
          } else if (code == 86038) {
            timer?.cancel();
            setState(() => message = '二维码已过期，请刷新');
          } else if (code == 86090) {
            setState(() => message = '已扫码，请在 B 站 App 确认');
          }
        } on Exception catch (e) {
          timer?.cancel();
          if (mounted) {
            setState(
              () => message = e is AppFailure ? e.message : '登录请求失败，请刷新重试',
            );
          }
        } finally {
          polling = false;
        }
      });
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          message = e is AppFailure ? e.message : '无法生成二维码，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '连接你的收藏',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
              action(Icons.close, '关闭账号窗口', () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey('account-content'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (p.profile != null) ...[
                    Text(
                      '${p.profile!['uname']}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '选择一个收藏夹，导入为本地歌单。',
                      style: TextStyle(color: context.tokens.muted),
                    ),
                    const SizedBox(height: 16),
                    if (!busy && folders.isEmpty) const Text('暂无可导入的收藏夹。'),
                    for (final folder in folders)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: FolderChoice(
                          folder: folder,
                          selected: selectedFolder?['id'] == folder['id'],
                          onSelect: busy
                              ? null
                              : () => setState(() {
                                  selectedFolder = folder;
                                  imported = null;
                                  message = '';
                                }),
                        ),
                      ),
                    if (!busy)
                      labelButton('刷新收藏夹', loadProfile, icon: Icons.refresh),
                    labelButton(
                      '退出账号',
                      busy
                          ? null
                          : () async {
                              await p.logout();
                              if (!mounted) return;
                              setState(() {
                                folders = [];
                                selectedFolder = null;
                                imported = null;
                                message = '扫码后可以导入你的 B 站收藏夹';
                              });
                            },
                      icon: Icons.logout,
                    ),
                  ] else ...[
                    if (qr != null)
                      Center(
                        child: ColoredBox(
                          color: Colors.white,
                          child: QrImageView(data: qr!, size: 210),
                        ),
                      ),
                    if (!busy)
                      labelButton(
                        qr == null ? '生成登录二维码' : '刷新二维码',
                        generate,
                        icon: Icons.qr_code,
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (busy) const LinearProgressIndicator(minHeight: 3),
          if (message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  style: TextStyle(color: context.tokens.muted, height: 1.5),
                ),
              ),
            ),
          if (p.profile != null)
            imported == null
                ? labelButton(
                    busy
                        ? '正在导入或加载…'
                        : selectedFolder == null
                        ? '请先选择收藏夹'
                        : '导入所选收藏夹',
                    busy || selectedFolder == null ? null : importSelected,
                    icon: Icons.playlist_add,
                  )
                : labelButton('查看已导入歌单', () {
                    final router = GoRouter.of(context), id = imported!.id;
                    Navigator.pop(context);
                    router.go('/playlist/$id');
                  }, icon: Icons.queue_music),
        ],
      ),
    );
  }
}

class FolderChoice extends StatelessWidget {
  const FolderChoice({
    super.key,
    required this.folder,
    required this.selected,
    required this.onSelect,
  });
  final Map<String, dynamic> folder;
  final bool selected;
  final VoidCallback? onSelect;
  @override
  Widget build(BuildContext context) => Pressable(
    key: ValueKey('folder-${folder['id']}'),
    selected: selected,
    onPressed: onSelect,
    child: Row(
      children: [
        Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${folder['title']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${folder['media_count'] ?? 0} 个视频',
                style: TextStyle(fontSize: 12, color: context.tokens.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Future<void> showLyrics(BuildContext context, LibraryController p) async {
  final track = p.current;
  if (track == null) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _LyricsDialog(p, track),
  );
}

class _LyricsDialog extends StatefulWidget {
  const _LyricsDialog(this.controller, this.track);
  final LibraryController controller;
  final Track track;
  @override
  State<_LyricsDialog> createState() => _LyricsDialogState();
}

class _LyricsDialogState extends State<_LyricsDialog> {
  LibraryController get p => widget.controller;
  Track get track => widget.track;
  late final edit = TextEditingController(text: track.title);
  late final lrc = TextEditingController(text: p.lyricText);
  late int offset = p.lyricOffset;
  List<Map<String, dynamic>> candidates = [];
  String? error;
  bool busy = false;
  @override
  void dispose() {
    edit.dispose();
    lrc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('匹配歌词'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: edit,
              decoration: const InputDecoration(labelText: '歌名 / 歌手'),
            ),
            labelButton(
              '搜索歌词',
              busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        final found = await p.lyricsClient.search(edit.text);
                        if (mounted) {
                          setState(() {
                            candidates = found;
                            error = found.isEmpty ? '未找到歌词，可粘贴 LRC 文本' : null;
                          });
                        }
                      } on AppFailure catch (e) {
                        if (mounted) setState(() => error = e.message);
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
            ),
            if (error != null) Text(error!),
            for (final c in candidates.take(10))
              labelButton('${c['trackName']} · ${c['artistName']}', () async {
                if (p.current?.id != track.id) {
                  throw const AppFailure('歌曲已切换，请重新打开歌词窗口');
                }
                await p.chooseLyrics(c, track);
                if (context.mounted) Navigator.pop(context);
              }),
            TextField(
              controller: lrc,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(labelText: '或粘贴 LRC / 纯文本歌词'),
            ),
            Text('时间偏移 ${(offset / 1000).toStringAsFixed(1)} 秒'),
            Slider(
              value: offset.toDouble(),
              min: -5000,
              max: 5000,
              divisions: 20,
              onChanged: (v) => setState(() => offset = v.round()),
            ),
          ],
        ),
      ),
    ),
    actions: [
      labelButton('取消', () => Navigator.pop(context)),
      labelButton('保存歌词', () async {
        await p.setLyrics(lrc.text, track: track, offset: offset);
        await p.save();
        if (context.mounted) Navigator.pop(context);
      }),
    ],
  );
}

/// Persistent, fixed-width destinations avoid layout movement while switching.
class CompactNavigation extends StatelessWidget {
  const CompactNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
  });
  final String selected;
  final ValueChanged<String> onSelect;
  static const destinations = [
    ('library', Icons.library_music_outlined, '音乐库'),
    ('search', Icons.search, '搜索'),
    ('downloads', Icons.download_outlined, '下载'),
    ('likes', Icons.favorite_border, '喜欢'),
  ];
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              for (final item in destinations)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Semantics(
                      selected: selected == item.$1,
                      child: Pressable(
                        key: ValueKey('tab-${item.$1}'),
                        label: item.$3,
                        selected: selected == item.$1,
                        onPressed: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          onSelect(item.$1);
                        },
                        radius: 28,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(item.$2, size: 20),
                            const SizedBox(width: 4),
                            Text(item.$3, style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
