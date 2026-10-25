part of 'app.dart';

/// A scoped selection task: temporary choices are committed only by Add.
class PlaylistAddScreen extends ConsumerStatefulWidget {
  const PlaylistAddScreen({
    super.key,
    required this.playlistId,
    this.desktop = false,
  });
  final String playlistId;
  final bool desktop;
  @override
  ConsumerState<PlaylistAddScreen> createState() => _PlaylistAddScreenState();
}

class _PlaylistAddScreenState extends ConsumerState<PlaylistAddScreen> {
  final localQuery = TextEditingController();
  final onlineQuery = TextEditingController();
  TextEditingController get query => online ? onlineQuery : localQuery;
  bool online = false, searching = false, hasMore = true;
  int searchPage = 1, searchAttempt = 1, searchEpoch = 0;
  String? searchError;
  List<Track> results = [];
  final candidates = <String, Track>{};
  Timer? debounce;

  Future<void> searchOnline({int page = 1}) async {
    final text = onlineQuery.text.trim();
    final epoch = ++searchEpoch;
    setState(() {
      if (page == 1) {
        results = [];
        hasMore = true;
      }
      searchError = null;
      searching = text.isNotEmpty;
      searchAttempt = page;
    });
    if (text.isEmpty) return;
    try {
      final found = await ref
          .read(libraryProvider)
          .api
          .search(text, page: page);
      if (!mounted || epoch != searchEpoch) return;
      setState(() {
        final existing = results.map((t) => t.id).toSet();
        hasMore =
            found.isNotEmpty &&
            (page == 1 || found.any((t) => !existing.contains(t.id)));
        results = {
          for (final t in [...results, ...found]) t.id: t,
        }.values.toList();
        candidates.addEntries(found.map((t) => MapEntry(t.id, t)));
        searchPage = page;
      });
    } on Exception catch (error) {
      if (mounted && epoch == searchEpoch) {
        setState(() {
          searchError = error is AppFailure ? error.message : '搜索失败，请重试';
        });
      }
    } finally {
      if (mounted && epoch == searchEpoch) setState(() => searching = false);
    }
  }

  final selected = <String>{};
  bool saving = false;
  @override
  void dispose() {
    debounce?.cancel();
    localQuery.dispose();
    onlineQuery.dispose();
    super.dispose();
  }

  void back() => widget.desktop
      ? Navigator.pop(context)
      : context.canPop()
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
        .where(
          (id) =>
              (p.library.containsKey(id) || candidates.containsKey(id)) &&
              !existing.contains(id),
        )
        .toList();
    final tracks = online
        ? results
        : p
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
                          widget.desktop ? Icons.clear : Icons.arrow_back,
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
                        if (!widget.desktop)
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
                  if (widget.desktop)
                    Row(
                      children: [
                        for (final source in [(false, '音乐库'), (true, '在线搜索')])
                          Expanded(
                            child: labelButton(
                              source.$2,
                              saving
                                  ? null
                                  : () => setState(() => online = source.$1),
                              selected: online == source.$1,
                            ),
                          ),
                      ],
                    ),
                  if (list != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        key: const ValueKey('playlist-add-query'),
                        controller: query,
                        enabled: !saving,
                        decoration: InputDecoration(
                          hintText: online ? '歌曲、UP 主、BV / AV 号或链接' : '搜索音乐库',
                          prefixIcon: const TingyuIcon(Icons.search),
                          suffixIcon: action(
                            Icons.clear_all,
                            '清除选歌搜索',
                            saving || query.text.isEmpty
                                ? null
                                : () {
                                    setState(query.clear);
                                    if (online) {
                                      debounce?.cancel();
                                      unawaited(searchOnline());
                                    }
                                  },
                          ),
                        ),
                        onChanged: (_) {
                          setState(() {});
                          if (online) {
                            debounce?.cancel();
                            // Invalidate in-flight results as soon as the query changes.
                            ++searchEpoch;
                            setState(() {
                              results = [];
                              searching = query.text.trim().isNotEmpty;
                              searchError = null;
                            });
                            debounce = Timer(
                              const Duration(milliseconds: 450),
                              searchOnline,
                            );
                          }
                        },
                        onSubmitted: online
                            ? (_) {
                                debounce?.cancel();
                                unawaited(searchOnline());
                              }
                            : null,
                      ),
                    ),
                  if (online && searching) const LinearProgressIndicator(),
                  if (online && searchError != null)
                    errorBox(
                      context,
                      searchError!,
                      () => searchOnline(page: searchAttempt),
                    ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: list == null
                        ? EmptyView(
                            '歌单已删除',
                            '返回音乐库重新选择。',
                            child: labelButton('返回音乐库', () => context.go('/')),
                          )
                        : online && tracks.isEmpty
                        ? searching
                              ? const Center(child: Text('正在搜索…'))
                              : searchError != null
                              ? const SizedBox.shrink()
                              : EmptyView(
                                  query.text.trim().isEmpty
                                      ? '搜索歌曲'
                                      : '没有找到相关内容',
                                  '搜索关键词，或粘贴 BV 号。',
                                )
                        : tracks.isEmpty
                        ? EmptyView(
                            query.text.trim().isEmpty ? '音乐库还没有歌曲' : '没有匹配的歌曲',
                            '可通过在线搜索添加新歌曲。',
                          )
                        : ListView.builder(
                            key: const PageStorageKey('playlist-add-library'),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: tracks.length + (online ? 1 : 0),
                            itemBuilder: (_, index) {
                              if (index == tracks.length) {
                                return hasMore
                                    ? labelButton(
                                        '加载更多',
                                        searching
                                            ? null
                                            : () => searchOnline(
                                                page: searchPage + 1,
                                              ),
                                      )
                                    : const Center(child: Text('已显示全部结果'));
                              }
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
                                      TingyuIcon(
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
                                    for (final id in pending) {
                                      if (!p.library.containsKey(id)) {
                                        await p.remember(candidates[id]!);
                                      }
                                    }
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
