part of 'app.dart';

Future<void> showContentActions(BuildContext context, WidgetBuilder builder) {
  if (MediaQuery.sizeOf(context).width >= 960) {
    return showDialog<void>(context: context, builder: builder);
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.tokens.surface,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * .85,
      ),
      child: Builder(
        builder: (ctx) {
          final content = builder(ctx);
          if (content is! SimpleDialog) return content;
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.tokens.line,
                        borderRadius: BorderRadius.circular(
                          TingyuTokens.radius,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (content.title != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 16),
                      child: DefaultTextStyle(
                        style: Theme.of(ctx).textTheme.titleMedium!,
                        child: content.title!,
                      ),
                    ),
                  ...?content.children,
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class PlaylistSummary extends ConsumerWidget {
  const PlaylistSummary(this.list, {super.key});
  final Playlist list;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(libraryProvider);
    final tracks = list.trackIds.map((id) => p.library[id]).whereType<Track>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          if (tracks.isNotEmpty)
            Artwork(tracks.first, size: 88)
          else
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: context.tokens.tint,
                borderRadius: BorderRadius.circular(TingyuTokens.radius),
              ),
              child: Icon(
                Icons.library_music_outlined,
                size: 32,
                color: context.tokens.accent,
              ),
            ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${tracks.length} 首歌曲',
                  style: TextStyle(color: context.tokens.muted),
                ),
                if (list.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    list.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.tokens.muted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CollectionToolbar extends ConsumerWidget {
  const CollectionToolbar({
    super.key,
    required this.ids,
    this.list,
    required this.collectionKey,
    required this.selecting,
    required this.onSelect,
  });
  final List<String> ids;
  final Playlist? list;
  final String collectionKey;
  final bool selecting;
  final VoidCallback onSelect;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(libraryProvider);
    if (selecting) return const SizedBox.shrink();
    return Row(
      children: [
        action(
          Icons.play_arrow,
          '播放全部',
          ids.isEmpty ? null : () => p.playCollection(ids),
        ),
        Expanded(
          child: Text(
            list == null ? '${ids.length} 首歌曲' : '',
            style: TextStyle(color: context.tokens.muted, fontSize: 12),
          ),
        ),
        if (list != null) PlaylistDownloadAction(list!),
        action(
          Icons.swap_vert,
          '歌曲排序',
          ids.isEmpty
              ? null
              : () => showContentActions(
                  context,
                  (ctx) => SimpleDialog(
                    title: const Text('歌曲排序'),
                    children: [
                      for (final option in [
                        ('default', '默认顺序', Icons.drag_handle),
                        ('recent', '最近添加', Icons.schedule),
                        ('title', '歌曲名称', Icons.sort_by_alpha),
                        ('artist', 'UP 主', Icons.person_outline),
                      ])
                        Pressable(
                          key: ValueKey('sort-${option.$1}'),
                          onPressed: () async {
                            await p.setCollectionSort(collectionKey, option.$1);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          child: Row(
                            children: [
                              Icon(option.$3),
                              const SizedBox(width: 16),
                              Expanded(child: Text(option.$2)),
                              if ((p.collectionSort[collectionKey] ??
                                      'default') ==
                                  option.$1)
                                Icon(Icons.check, color: context.tokens.accent),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        action(Icons.checklist, '批量选择', ids.isEmpty ? null : onSelect),
      ],
    );
  }
}

class SelectionTrackRow extends StatelessWidget {
  const SelectionTrackRow(
    this.track, {
    super.key,
    required this.selected,
    required this.onPressed,
  });
  final Track track;
  final bool selected;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Pressable(
    key: ValueKey('select-${track.id}'),
    label: '选择 ${track.title}',
    selected: selected,
    onPressed: onPressed,
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(
          selected ? Icons.check_box : Icons.check_box_outline_blank,
          color: selected ? context.tokens.accent : context.tokens.muted,
        ),
        const SizedBox(width: 12),
        Artwork(track),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.tokens.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class SelectionBar extends ConsumerWidget {
  const SelectionBar({
    super.key,
    required this.ids,
    this.list,
    required this.onDone,
  });
  final List<String> ids;
  final Playlist? list;
  final VoidCallback onDone;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(libraryProvider);
    return Container(
      decoration: BoxDecoration(
        color: context.tokens.surface,
        border: Border(top: BorderSide(color: context.tokens.line)),
      ),
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          action(
            Icons.playlist_add,
            '批量加入歌单',
            ids.isEmpty
                ? null
                : () => showContentActions(
                    context,
                    (ctx) => SimpleDialog(
                      title: const Text('添加至歌单'),
                      children: [
                        for (final target in p.playlists)
                          labelButton(target.name, () async {
                            for (final id in ids) {
                              final track = p.library[id];
                              if (track != null) {
                                await p.addToPlaylist(target, track);
                              }
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                            onDone();
                          }),
                        labelButton('新建歌单', () async {
                          Navigator.pop(ctx);
                          final name = await nameDialog(context);
                          if (name == null) return;
                          await p.addPlaylist(name);
                          final target = p.playlists.last;
                          for (final id in ids) {
                            final track = p.library[id];
                            if (track != null) {
                              await p.addToPlaylist(target, track);
                            }
                          }
                          onDone();
                        }, icon: Icons.playlist_add),
                      ],
                    ),
                  ),
          ),
          action(
            Icons.download_outlined,
            '批量下载',
            ids.isEmpty
                ? null
                : () async {
                    for (final id in ids) {
                      final track = p.library[id];
                      if (track != null) await p.download(track);
                    }
                    onDone();
                  },
          ),
          if (list != null)
            action(
              Icons.remove_circle_outline,
              '批量移出歌单',
              ids.isEmpty
                  ? null
                  : () async {
                      if (await confirm(
                        context,
                        '从歌单移除所选 ${ids.length} 首歌？已下载文件会保留。',
                      )) {
                        await p.removeFromPlaylist(list!, ids.toSet());
                        onDone();
                      }
                    },
            ),
        ],
      ),
    );
  }
}

class PlaylistEditDialog extends ConsumerStatefulWidget {
  const PlaylistEditDialog(this.list, {super.key});
  final Playlist list;
  @override
  ConsumerState<PlaylistEditDialog> createState() => _PlaylistEditDialogState();
}

class _PlaylistEditDialogState extends ConsumerState<PlaylistEditDialog> {
  late final name = TextEditingController(text: widget.list.name);
  late final description = TextEditingController(text: widget.list.description);
  String? error;
  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('编辑歌单'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('playlist-name'),
            controller: name,
            autofocus: true,
            maxLength: 30,
            decoration: InputDecoration(labelText: '名称', errorText: error),
          ),
          TextField(
            key: const ValueKey('playlist-description'),
            controller: description,
            maxLength: 160,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: '简介（可选）'),
          ),
        ],
      ),
    ),
    actions: [
      labelButton('取消', () => Navigator.pop(context)),
      labelButton('保存', () async {
        if (name.text.trim().isEmpty) {
          setState(() => error = '请输入歌单名称');
          return;
        }
        await ref
            .read(libraryProvider)
            .editPlaylist(
              widget.list,
              name: name.text,
              description: description.text,
            );
        if (context.mounted) Navigator.pop(context);
      }),
    ],
  );
}
