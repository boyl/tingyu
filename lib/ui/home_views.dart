part of 'app.dart';

/// Width is derived from the actual viewport: two complete cards and a peek.
double shelfCardWidth(double width) =>
    (width - TingyuTokens.space * 3) / TingyuTokens.shelfVisibleCards;

class HomeShelves extends StatelessWidget {
  const HomeShelves(this.p, {super.key, required this.onCreate});
  final LibraryController p;
  final Future<void> Function() onCreate;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final card = shelfCardWidth(width).clamp(100.0, 184.0);
      final scale = MediaQuery.textScalerOf(context);
      final history = p.history
          .map((id) => p.library[id])
          .whereType<Track>()
          .take(8)
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (history.isNotEmpty) ...[
            Text('继续收听', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: TingyuTokens.space * 2),
            SizedBox(
              height:
                  (width * .9).clamp(240.0, 480.0) / TingyuTokens.heroRatio +
                  scale.scale(16) * 1.4 +
                  scale.scale(12) * 1.4 +
                  TingyuTokens.space * 3,
              child: ListView.separated(
                key: const ValueKey('continue-shelf'),
                scrollDirection: Axis.horizontal,
                itemCount: history.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: TingyuTokens.space * 1.5),
                itemBuilder: (_, i) => SizedBox(
                  width: (width * .9).clamp(240.0, 480.0),
                  child: Pressable(
                    key: ValueKey('continue-${history[i].id}'),
                    label: '继续收听 ${history[i].title}',
                    padding: EdgeInsets.zero,
                    onPressed: () => p.playFromCollection(
                      history[i],
                      p.collectionIds('library', p.library.keys),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          history[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.tokens.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          history[i].artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.tokens.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: TingyuTokens.space * 1.5),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              TingyuTokens.artworkRadius,
                            ),
                            child: SizedBox.expand(
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: Artwork(history[i], size: 400),
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
            const SizedBox(height: TingyuTokens.space * 3),
          ],
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Pressable(
                    key: const ValueKey('all-playlists'),
                    label: '查看全部歌单',
                    padding: EdgeInsets.zero,
                    onPressed: () => context.push('/playlists'),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '我的歌单',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(width: TingyuTokens.space),
                        const TingyuIcon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              ),
              action(Icons.add, '新建歌单', onCreate),
            ],
          ),
          if (p.playlists.isNotEmpty) ...[
            const SizedBox(height: TingyuTokens.space),
            SizedBox(
              height:
                  card +
                  scale.scale(14) * 1.4 +
                  scale.scale(12) * 1.4 +
                  TingyuTokens.space * 2,
              child: ListView.separated(
                key: const ValueKey('playlist-shelf'),
                scrollDirection: Axis.horizontal,
                itemCount: p.playlists.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: TingyuTokens.space * 1.5),
                itemBuilder: (_, i) {
                  final list = p.playlists[i],
                      covers = list.trackIds
                          .map((id) => p.library[id])
                          .whereType<Track>();
                  return SizedBox(
                    width: card,
                    child: Pressable(
                      key: ValueKey(list.name),
                      label: '打开歌单 ${list.name}',
                      padding: EdgeInsets.zero,
                      onPressed: () => context.go('/playlist/${list.id}'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (covers.isNotEmpty)
                            Artwork(covers.first, size: card - 4)
                          else
                            Container(
                              width: card - 4,
                              height: card - 4,
                              decoration: BoxDecoration(
                                color: context.tokens.tint,
                                borderRadius: BorderRadius.circular(
                                  TingyuTokens.artworkRadius,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: TingyuIcon(
                                Icons.library_music_outlined,
                                color: context.tokens.accent,
                                size: 40,
                              ),
                            ),
                          const SizedBox(height: TingyuTokens.space),
                          Text(
                            list.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${list.trackIds.length} 首',
                            style: TextStyle(
                              color: context.tokens.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: TingyuTokens.space * 3),
          ],
        ],
      );
    },
  );
}

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(libraryProvider);
    Future<void> create() async {
      final name = await nameDialog(context);
      if (name != null && context.mounted) await p.addPlaylist(name);
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 608),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(TingyuTokens.space),
                  child: Row(
                    children: [
                      action(
                        Icons.arrow_back,
                        '返回音乐库',
                        () =>
                            context.canPop() ? context.pop() : context.go('/'),
                      ),
                      const SizedBox(width: TingyuTokens.space),
                      Expanded(
                        child: Text(
                          '我的歌单',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      action(Icons.add, '新建歌单', create),
                    ],
                  ),
                ),
                Expanded(
                  child: p.playlists.isEmpty
                      ? Center(
                          child: EmptyView(
                            '还没有歌单',
                            '创建歌单，整理喜欢的声音',
                            child: labelButton('新建歌单', create, icon: Icons.add),
                          ),
                        )
                      : ListView.separated(
                          key: const PageStorageKey('all-playlists-list'),
                          padding: const EdgeInsets.all(TingyuTokens.space * 2),
                          itemCount: p.playlists.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: TingyuTokens.space * 2),
                          itemBuilder: (context, index) {
                            final list = p.playlists[index];
                            final cover = list.trackIds
                                .map((id) => p.library[id])
                                .whereType<Track>()
                                .firstOrNull;
                            return Pressable(
                              key: ValueKey('playlist-list-${list.id}'),
                              label:
                                  '打开歌单 ${list.name}，${list.trackIds.length} 首',
                              padding: EdgeInsets.zero,
                              onPressed: () => context.push(
                                '/playlist/${list.id}',
                                extra: 'playlists',
                              ),
                              child: Row(
                                children: [
                                  if (cover != null)
                                    Artwork(cover, size: 64)
                                  else
                                    Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        color: context.tokens.tint,
                                        borderRadius: BorderRadius.circular(
                                          TingyuTokens.artworkRadius,
                                        ),
                                      ),
                                      child: TingyuIcon(
                                        Icons.library_music_outlined,
                                        color: context.tokens.accent,
                                      ),
                                    ),
                                  const SizedBox(width: TingyuTokens.space * 2),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          list.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleSmall,
                                        ),
                                        Text(
                                          '${list.trackIds.length} 首',
                                          style: TextStyle(
                                            color: context.tokens.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: TingyuTokens.space),
                                  const TingyuIcon(Icons.chevron_right),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
