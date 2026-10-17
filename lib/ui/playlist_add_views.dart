part of 'app.dart';

/// A scoped selection task: temporary choices are committed only by Add.
class PlaylistAddScreen extends ConsumerStatefulWidget {
  const PlaylistAddScreen({super.key, required this.playlistId});
  final String playlistId;
  @override
  ConsumerState<PlaylistAddScreen> createState() => _PlaylistAddScreenState();
}

class _PlaylistAddScreenState extends ConsumerState<PlaylistAddScreen> {
  final query = TextEditingController();
  final selected = <String>{};
  bool saving = false;
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  void back() => context.canPop()
      ? context.pop()
      : context.go('/playlist/${widget.playlistId}');

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(libraryProvider);
    final list = p.playlists
        .where((l) => l.id == widget.playlistId)
        .firstOrNull;
    final existing = list?.trackIds.toSet() ?? <String>{};
    final pending = selected
        .where((id) => p.library.containsKey(id) && !existing.contains(id))
        .toList();
    final tracks = p
        .collectionIds('library', p.library.keys)
        .map((id) => p.library[id]!)
        .where((track) => matchesLocal(track, query.text))
        .toList();
    final t = context.tokens;
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        action(
                          Icons.arrow_back,
                          '取消添加歌曲',
                          saving ? null : back,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '添加歌曲',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              if (list != null)
                                Text(
                                  list.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: t.muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        labelButton(
                          '在线搜索',
                          saving || list == null
                              ? null
                              : () => context.push(
                                  '/playlist/${widget.playlistId}/add/search',
                                ),
                          icon: Icons.search,
                        ),
                      ],
                    ),
                  ),
                  if (list != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        key: const ValueKey('playlist-add-query'),
                        controller: query,
                        enabled: !saving,
                        decoration: InputDecoration(
                          hintText: '搜索音乐库',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: action(
                            Icons.close,
                            '清除选歌搜索',
                            () => setState(query.clear),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: list == null
                        ? EmptyView(
                            '歌单已删除',
                            '返回音乐库重新选择。',
                            child: labelButton('返回音乐库', () => context.go('/')),
                          )
                        : tracks.isEmpty
                        ? EmptyView(
                            query.text.trim().isEmpty ? '音乐库还没有歌曲' : '没有匹配的歌曲',
                            '可通过在线搜索添加新歌曲。',
                          )
                        : ListView.builder(
                            key: const PageStorageKey('playlist-add-library'),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: tracks.length,
                            itemBuilder: (_, index) {
                              final track = tracks[index];
                              final added = existing.contains(track.id);
                              final checked = selected.contains(track.id);
                              return Pressable(
                                key: ValueKey('select-add-${track.id}'),
                                label:
                                    '${added
                                        ? '已添加'
                                        : checked
                                        ? '取消选择'
                                        : '选择'} ${track.title}',
                                selected: checked,
                                selectionFill: false,
                                onPressed: added || saving
                                    ? null
                                    : () => setState(() {
                                        checked
                                            ? selected.remove(track.id)
                                            : selected.add(track.id);
                                      }),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 4,
                                ),
                                child: Row(
                                  children: [
                                    Artwork(track),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            track.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            track.artist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: t.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    if (added)
                                      Text(
                                        '已添加',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: t.muted,
                                        ),
                                      )
                                    else
                                      Icon(
                                        checked
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        color: checked ? t.accent : t.muted,
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: Pressable(
                        key: const ValueKey('commit-add-tracks'),
                        label: saving ? '正在添加' : '添加 ${pending.length} 首',
                        color: t.accent,
                        onPressed: saving || list == null || pending.isEmpty
                            ? null
                            : () async {
                                setState(() => saving = true);
                                try {
                                  await report(context, () async {
                                    await p.addLibraryTracks(
                                      widget.playlistId,
                                      pending,
                                    );
                                    if (mounted) back();
                                  });
                                } finally {
                                  if (mounted) setState(() => saving = false);
                                }
                              },
                        child: Center(
                          child: Text(
                            saving ? '正在添加…' : '添加 ${pending.length} 首',
                            style: TextStyle(color: t.onAccent),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PlaylistAddTrackAction extends ConsumerWidget {
  const PlaylistAddTrackAction({
    super.key,
    required this.track,
    required this.playlist,
  });
  final Track track;
  final Playlist playlist;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(libraryProvider);
    final list = p.playlists.where((l) => l.id == playlist.id).firstOrNull;
    final added =
        list?.trackIds.any((id) {
          final stored = p.library[id];
          return id == track.id ||
              (track.cid == 0 &&
                  stored?.bvid == track.bvid &&
                  stored?.part == 1);
        }) ??
        false;
    return action(
      added ? Icons.check : Icons.add,
      '${added ? '已添加' : '添加到歌单'} ${track.title}',
      added || list == null ? null : () => p.addToPlaylist(list, track),
      selected: added,
    );
  }
}
