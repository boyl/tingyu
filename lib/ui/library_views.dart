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
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
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
                borderRadius: BorderRadius.circular(TingyuTokens.artworkRadius),
              ),
              child: TingyuIcon(
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
    this.compact = false,
  });
  final List<String> ids;
  final Playlist? list;
  final String collectionKey;
  final bool selecting;
  final bool compact;
  final VoidCallback onSelect;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(libraryProvider);
    if (selecting) return const SizedBox.shrink();
    if (compact) {
      return Row(
        children: [
          Expanded(
            child: Pressable(
              key: const ValueKey('播放全部'),
              label: '播放全部',
              selectionFill: false,
              padding: EdgeInsets.zero,
              onPressed: ids.isEmpty
                  ? null
                  : () => report(context, () => p.playCollection(ids)),
              child: Row(
                children: [
                  TingyuIcon(Icons.play_arrow, color: context.tokens.accent),
                  const SizedBox(width: TingyuTokens.space),
                  Text(
                    '播放全部',
                    style: TextStyle(color: context.tokens.accentInk),
                  ),
                  const SizedBox(width: TingyuTokens.space),
                  Flexible(
                    child: Text(
                      '${ids.length} 首',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.tokens.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          action(
            Icons.swap_vert,
            '歌曲排序',
            ids.isEmpty
                ? null
                : () => showCollectionSort(context, p, collectionKey),
          ),
          action(Icons.checklist, '批量选择', ids.isEmpty ? null : onSelect),
        ],
      );
    }

    final leading = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: TingyuTokens.space,
      runSpacing: TingyuTokens.space,
      children: [
        Pressable(
          key: const ValueKey('播放全部'),
          label: '播放全部',
          onPressed: ids.isEmpty
              ? null
              : () => report(context, () => p.playCollection(ids)),
          color: context.tokens.accent,
          radius: TingyuTokens.playerRadius,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TingyuIcon(Icons.play_arrow, color: context.tokens.onAccent),
              const SizedBox(width: TingyuTokens.space),
              Text('播放全部', style: TextStyle(color: context.tokens.onAccent)),
            ],
          ),
        ),
        if (list == null)
          Text(
            '${ids.length} 首歌曲',
            style: TextStyle(color: context.tokens.muted, fontSize: 12),
          ),
        if (list != null) PlaylistDownloadAction(list!),
      ],
    );
    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        action(
          Icons.swap_vert,
          '歌曲排序',
          ids.isEmpty
              ? null
              : () => showCollectionSort(context, p, collectionKey),
        ),
        action(Icons.checklist, '批量选择', ids.isEmpty ? null : onSelect),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (selectionToolbarCompact(context, constraints.maxWidth)) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: TingyuTokens.controlSize,
                child: Align(alignment: Alignment.centerLeft, child: leading),
              ),
              SizedBox(
                height: TingyuTokens.controlSize,
                child: Align(alignment: Alignment.centerRight, child: trailing),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: leading),
            const SizedBox(width: TingyuTokens.space),
            trailing,
          ],
        );
      },
    );
  }
}

Future<void> showCollectionSort(
  BuildContext context,
  LibraryController p,
  String collectionKey,
) => showContentActions(
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
              TingyuIcon(option.$3),
              const SizedBox(width: 16),
              Expanded(child: Text(option.$2)),
              if ((p.collectionSort[collectionKey] ?? 'default') == option.$1)
                TingyuIcon(Icons.check, color: context.tokens.accent),
            ],
          ),
        ),
    ],
  ),
);

class SelectionSurface extends StatelessWidget {
  const SelectionSurface({
    super.key,
    required this.child,
    required this.first,
    required this.last,
  });
  final Widget child;
  final bool first, last;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.tokens.tint.withValues(alpha: .45),
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(first ? TingyuTokens.detailRadius : 0),
        bottom: Radius.circular(last ? TingyuTokens.detailRadius : 0),
      ),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        if (!last)
          Padding(
            padding: const EdgeInsets.only(
              left: TingyuTokens.space * 7,
              right: TingyuTokens.space * 2,
            ),
            child: Divider(
              height: 1,
              thickness: .5,
              color: context.tokens.line,
            ),
          ),
      ],
    ),
  );
}

class SelectionTrackRow extends StatelessWidget {
  const SelectionTrackRow(
    this.track, {
    super.key,
    required this.selected,
    required this.onPressed,
    this.first = false,
    this.last = false,
  });
  final bool first, last;
  final Track track;
  final bool selected;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SelectionSurface(
    first: first,
    last: last,
    child: Pressable(
      key: ValueKey('select-${track.id}'),
      selectionFill: false,
      label: '选择 ${track.title}',
      selected: selected,
      onPressed: onPressed,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Row(
        children: [
          TingyuIcon(
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
    ),
  );
}

bool selectionToolbarCompact(BuildContext context, double width) =>
    width < 320 || MediaQuery.textScalerOf(context).scale(12) > 15;

({double countWidth, bool compact}) measuredSelectionToolbar(
  BuildContext context,
  double width,
  int total,
  bool hasList,
) {
  final style = DefaultTextStyle.of(
    context,
  ).style.merge(const TextStyle(fontSize: 12));
  double measure(String value) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  final digits = total.toString().length;
  final widest = List.generate(10, (i) => measure('$i')).reduce(math.max);
  final countWidth = (measure('已选  首') + widest * digits).ceilToDouble();
  final requiredWidth =
      countWidth + TingyuTokens.controlSize * (hasList ? 5 : 4) + 1;
  return (
    countWidth: countWidth,
    compact: selectionToolbarCompact(context, width) || width < requiredWidth,
  );
}

class SelectionToolbar extends StatelessWidget {
  const SelectionToolbar({
    super.key,
    required this.selectedIds,
    required this.allSelected,
    required this.totalCount,
    this.list,
    required this.onSelectAll,
    required this.onDone,
  });
  final List<String> selectedIds;
  final bool allSelected;
  final int totalCount;
  final Playlist? list;
  final VoidCallback onSelectAll, onDone;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final layout = measuredSelectionToolbar(
        context,
        constraints.maxWidth,
        totalCount,
        list != null,
      );
      final countWidth = layout.countWidth, compact = layout.compact;
      Widget count() => Text(
        '已选 ${selectedIds.length} 首',
        maxLines: 1,
        style: TextStyle(color: context.tokens.accentInk, fontSize: 12),
      );
      Widget all() => Pressable(
        key: const ValueKey('全选'),
        label: '全选',
        selected: allSelected,
        selectionFill: false,
        padding: const EdgeInsets.symmetric(horizontal: TingyuTokens.space),
        onPressed: onSelectAll,
        child: const Center(child: Text('全选', style: TextStyle(fontSize: 13))),
      );
      Widget done() => Pressable(
        key: const ValueKey('退出多选'),
        label: '退出多选',
        selectionFill: false,
        onPressed: onDone,
        padding: const EdgeInsets.symmetric(horizontal: TingyuTokens.space),
        child: Center(
          child: Text(
            '完成',
            style: TextStyle(color: context.tokens.accentInk, fontSize: 13),
          ),
        ),
      );
      Widget actions() => SelectionBar(
        inline: true,
        ids: selectedIds,
        list: list,
        onDone: onDone,
      );
      if (compact) {
        return Column(
          children: [
            SizedBox(
              height: TingyuTokens.controlSize,
              child: Row(
                children: [
                  Expanded(child: count()),
                  all(),
                  done(),
                ],
              ),
            ),
            SizedBox(
              height: TingyuTokens.controlSize,
              child: Align(alignment: Alignment.centerLeft, child: actions()),
            ),
          ],
        );
      }
      return Row(
        children: [
          SizedBox(width: countWidth, child: count()),
          all(),
          Expanded(child: actions()),
          Container(
            width: 1,
            height: TingyuTokens.space * 3,
            color: context.tokens.line,
          ),
          done(),
        ],
      );
    },
  );
}

class SelectionBar extends ConsumerWidget {
  const SelectionBar({
    super.key,
    required this.ids,
    this.list,
    required this.onDone,
    this.inline = false,
  });
  final bool inline;
  final List<String> ids;
  final Playlist? list;
  final VoidCallback onDone;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(libraryProvider);
    return Container(
      decoration: BoxDecoration(
        color: inline ? Colors.transparent : context.tokens.surface,
        border: inline
            ? null
            : Border(top: BorderSide(color: context.tokens.line)),
      ),
      padding: inline ? EdgeInsets.zero : const EdgeInsets.all(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
              Icons.more_horiz,
              '批量更多',
              ids.isEmpty
                  ? null
                  : () => showContentActions(
                      context,
                      (ctx) => SimpleDialog(
                        children: [
                          labelButton('批量移出歌单', () async {
                            Navigator.pop(ctx);
                            if (await confirm(
                              context,
                              '从歌单移除所选 ${ids.length} 首歌？已下载文件会保留。',
                            )) {
                              await p.removeFromPlaylist(list!, ids.toSet());
                              onDone();
                            }
                          }, icon: Icons.remove_circle_outline),
                        ],
                      ),
                    ),
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
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '简介（可选）',
              alignLabelWithHint: true,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
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

/// The same form hierarchy on phones and desktop, without a stock phone dialog.
class TingyuFormPanel extends StatelessWidget {
  const TingyuFormPanel({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });
  final Widget title, content;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 960) {
      return AlertDialog(title: title, content: content, actions: actions);
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight:
            (MediaQuery.sizeOf(context).height * .85 -
                    MediaQuery.viewInsetsOf(context).bottom)
                .clamp(160.0, double.infinity),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(TingyuTokens.space * 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: TingyuTokens.space * 5,
                  height: TingyuTokens.space / 2,
                  decoration: BoxDecoration(
                    color: context.tokens.line,
                    borderRadius: BorderRadius.circular(TingyuTokens.space),
                  ),
                ),
              ),
              const SizedBox(height: TingyuTokens.space * 3),
              DefaultTextStyle(
                style: Theme.of(context).textTheme.titleMedium!,
                child: title,
              ),
              const SizedBox(height: TingyuTokens.space * 3),
              Flexible(child: content),
              const SizedBox(height: TingyuTokens.space * 2),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: TingyuTokens.space,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
