part of 'app.dart';

/// Entry points are real search queries; suggestions only use the local library.
class SearchDiscovery extends StatelessWidget {
  const SearchDiscovery(this.p, {super.key, required this.onSearch});
  final LibraryController p;
  final void Function(String) onSearch;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final suggestions = <String>{
      ...p.history,
      ...p.library.keys,
    }.map((id) => p.library[id]).whereType<Track>().take(3).toList();
    const topics = [
      ('夜晚放空', '晚风', '给夜色一点回响', Icons.nights_stay_outlined),
      ('日落漫游', '日落', '收集傍晚的温柔', Icons.wb_twilight),
      ('安静片刻', '轻音乐', '让思绪慢下来', Icons.waves),
      ('心动旋律', '情歌', '把喜欢再听一遍', Icons.favorite_border),
    ];
    return Padding(
      padding: const EdgeInsets.only(
        top: TingyuTokens.space,
        bottom: TingyuTokens.space * 3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('此刻想听', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: TingyuTokens.space * 2),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720 ? 4 : 2;
              final width =
                  (constraints.maxWidth -
                      TingyuTokens.space * 1.5 * (columns - 1)) /
                  columns;
              return Wrap(
                spacing: TingyuTokens.space * 1.5,
                runSpacing: TingyuTokens.space * 1.5,
                children: [
                  for (var i = 0; i < topics.length; i++)
                    SizedBox(
                      width: width,
                      child: Pressable(
                        key: ValueKey('search-topic-$i'),
                        label: '搜索${topics[i].$1}',
                        onPressed: () => onSearch(topics[i].$2),
                        padding: EdgeInsets.zero,
                        radius: TingyuTokens.artworkRadius,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            TingyuTokens.artworkRadius,
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: DiscoveryArtwork(i),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(
                                  TingyuTokens.space * 2,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TingyuIcon(
                                        Icons.north_east,
                                        size: TingyuTokens.space * 2,
                                        color: TingyuTokens.onArtwork,
                                      ),
                                    ),
                                    const SizedBox(
                                      height: TingyuTokens.space * 2,
                                    ),
                                    Text(
                                      topics[i].$1,
                                      style: const TextStyle(
                                        color: TingyuTokens.onArtwork,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(
                                      height: TingyuTokens.space / 2,
                                    ),
                                    Text(
                                      topics[i].$3,
                                      style: const TextStyle(
                                        color: TingyuTokens.onArtwork,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: TingyuTokens.space * 4),
            Text('换个声音听听', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: TingyuTokens.space),
            for (final track in suggestions)
              Pressable(
                key: ValueKey('search-suggestion-${track.id}'),
                label: '播放${track.title}',
                onPressed: () => p.playFromCollection(
                  track,
                  suggestions.map((t) => t.id).toList(),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: TingyuTokens.space,
                ),
                child: Row(
                  children: [
                    Artwork(track),
                    const SizedBox(width: TingyuTokens.space * 1.5),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: TingyuTokens.space / 2),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: t.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    TingyuIcon(
                      Icons.play_arrow_rounded,
                      color: t.muted,
                      size: TingyuTokens.iconSize,
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class DiscoveryArtwork extends CustomPainter {
  const DiscoveryArtwork(this.index);
  final int index;
  @override
  void paint(Canvas canvas, Size size) {
    final colors = TingyuTokens.discoveryPalettes[index];
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ).createShader(rect),
    );
    canvas.drawCircle(
      Offset(size.width * .62, size.height * .23),
      size.shortestSide * .065,
      Paint()..color = TingyuTokens.onArtwork.withValues(alpha: .65),
    );
    final hill = Path()
      ..moveTo(0, size.height * .68)
      ..quadraticBezierTo(
        size.width * .5,
        size.height * .5,
        size.width,
        size.height * .57,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(hill, Paint()..color = colors.last.withValues(alpha: .75));
    // Darkened lower area keeps the actual category labels readable.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.last.withValues(alpha: .05),
            colors.last.withValues(alpha: .8),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant DiscoveryArtwork oldDelegate) =>
      oldDelegate.index != index;
}
