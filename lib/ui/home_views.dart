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
                child: Text(
                  '我的歌单',
                  style: Theme.of(context).textTheme.titleMedium,
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
