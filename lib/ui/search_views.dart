part of 'app.dart';

/// Watches the outer page only; horizontal shelves must never request pages.
class DiscoveryPagination extends StatefulWidget {
  const DiscoveryPagination({
    super.key,
    required this.controller,
    required this.child,
  });
  final DiscoveryController? controller;
  final Widget child;
  @override
  State<DiscoveryPagination> createState() => _DiscoveryPaginationState();
}

class _DiscoveryPaginationState extends State<DiscoveryPagination> {
  bool requestedForScroll = false;
  bool scheduled = false;

  bool onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification) requestedForScroll = false;
    final delta = switch (notification) {
      ScrollUpdateNotification() => notification.scrollDelta ?? 0,
      OverscrollNotification() => notification.overscroll,
      _ => 0.0,
    };
    final d = widget.controller;
    if (d == null ||
        delta <= 0 ||
        requestedForScroll ||
        scheduled ||
        !d.initialized ||
        d.loading ||
        d.error.isNotEmpty ||
        d.exhausted ||
        d.needsMoreSearch ||
        d.tracks.isEmpty ||
        notification.metrics.extentAfter >
            notification.metrics.viewportDimension / 2) {
      return false;
    }
    requestedForScroll = true;
    scheduled = true;
    final tag = d.tag;
    final first = d.tracks.first.bvid;
    // Scroll notifications arrive during layout. Defer controller notifications.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (!mounted ||
          widget.controller != d ||
          d.tag != tag ||
          d.tracks.firstOrNull?.bvid != first ||
          d.loading ||
          d.error.isNotEmpty ||
          d.exhausted) {
        return;
      }
      unawaited(d.loadMore());
    });
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: onScroll,
        child: widget.child,
      );
}

class SearchDiscovery extends StatefulWidget {
  const SearchDiscovery(this.p, {super.key});
  final LibraryController p;
  @override
  State<SearchDiscovery> createState() => _SearchDiscoveryState();
}

class _SearchDiscoveryState extends State<SearchDiscovery> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.p.discovery.ensureLoaded());
    });
  }

  Track knownTrack(Track candidate) => widget.p.library.values.firstWhere(
    (t) => t.bvid == candidate.bvid && t.part == candidate.part,
    orElse: () => candidate,
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.p, widget.p.discovery]),
    builder: (context, _) {
      final d = widget.p.discovery;
      final t = context.tokens;
      final loading = !d.initialized || d.loading;
      final placeholder = loading && d.tracks.isEmpty;
      // Keep presentation identity tied to the search result. Playback resolves
      // its provisional CID, which must not unmount an already decoded cover.
      final candidates = d.tracks, moreCandidates = d.moreTracks;
      final tracks = candidates.map(knownTrack).toList();
      final moreTracks = moreCandidates.map(knownTrack).toList();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: TingyuTokens.space * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '为你发现',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Pressable(
                  key: const ValueKey('discovery-refresh'),
                  label: '换一批推荐',
                  onPressed: loading || d.exhausted ? null : d.nextBatch,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: TingyuTokens.iconSize,
                        child: loading && !d.loadingMore
                            ? const CircularProgressIndicator(
                                strokeWidth: 2,
                                semanticsLabel: '正在加载推荐',
                              )
                            : const TingyuIcon(
                                Icons.refresh,
                                size: TingyuTokens.iconSize,
                              ),
                      ),
                      const SizedBox(width: TingyuTokens.space),
                      const Text('换一批'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: TingyuTokens.space),
            SingleChildScrollView(
              key: const PageStorageKey('discovery-tags'),
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final tag in DiscoveryController.tags)
                    Padding(
                      padding: const EdgeInsets.only(right: TingyuTokens.space),
                      child: Builder(
                        builder: (tagContext) => Pressable(
                          key: ValueKey('discovery-tag-$tag'),
                          label: '探索$tag',
                          selected: d.tag == tag,
                          onPressed: () {
                            Scrollable.of(tagContext).position.ensureVisible(
                              tagContext.findRenderObject()!,
                              alignment: .5,
                            );
                            d.selectTag(tag);
                          },
                          child: Text(tag, maxLines: 1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: TingyuTokens.space * 2),
            if (widget.p.discoverySaveError.isNotEmpty)
              errorBox(
                context,
                widget.p.discoverySaveError,
                widget.p.saveDiscovery,
              ),
            if (d.needsMoreSearch) labelButton('暂未找到更多，继续查找', d.loadMore),
            if (d.error.isNotEmpty && !d.loadMoreFailed)
              errorBox(context, d.error, d.retry),
            if (d.tracks.isEmpty && !loading && d.error.isEmpty)
              const EmptyView('暂时没有推荐内容', '试试其他标签，或搜索想听的歌曲。'),
            if (placeholder || tracks.isNotEmpty)
              LayoutBuilder(
                builder: (context, constraints) {
                  final card = shelfCardWidth(
                    constraints.maxWidth,
                  ).clamp(100.0, 184.0);
                  final scale = MediaQuery.textScalerOf(context);
                  const titleStyle = TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  );
                  final artistStyle = Theme.of(
                    context,
                  ).textTheme.bodySmall!.copyWith(color: t.muted);
                  double lineHeight(
                    String text,
                    TextStyle style,
                    double width,
                  ) {
                    final painter = TextPainter(
                      text: TextSpan(
                        text: text,
                        style: DefaultTextStyle.of(context).style.merge(style),
                      ),
                      textDirection: Directionality.of(context),
                      textScaler: scale,
                      locale: Localizations.maybeLocaleOf(context),
                      textHeightBehavior: DefaultTextStyle.of(
                        context,
                      ).textHeightBehavior,
                      maxLines: 1,
                      ellipsis: '…',
                    )..layout(maxWidth: width);
                    final height = painter.height.ceilToDouble();
                    painter.dispose();
                    return height;
                  }

                  // Native fallback fonts can exceed fontSize × height. Measure
                  // the same text/style as rendering instead of guessing pixels.
                  final titleHeight = tracks.fold(
                    lineHeight('推荐', titleStyle, card - TingyuTokens.space / 2),
                    (height, track) => math.max(
                      height,
                      lineHeight(
                        track.title,
                        titleStyle,
                        card - TingyuTokens.space / 2,
                      ),
                    ),
                  );
                  final artistHeight = tracks.fold(
                    48.0,
                    (height, track) => math.max(
                      height,
                      lineHeight(track.artist, artistStyle, card - 48),
                    ),
                  );
                  return SizedBox(
                    key: const ValueKey('discovery-shelf'),
                    height:
                        card + TingyuTokens.space + titleHeight + artistHeight,
                    child: ListView.separated(
                      key: PageStorageKey(
                        'discovery-shelf-${d.tag}-${tracks.isEmpty ? "loading" : tracks.first.bvid}',
                      ),
                      scrollDirection: Axis.horizontal,
                      itemCount: placeholder ? 3 : tracks.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: TingyuTokens.space * 1.5),
                      itemBuilder: (context, index) {
                        if (placeholder) {
                          return Semantics(
                            label: index == 0 ? '正在加载推荐' : null,
                            child: ExcludeSemantics(
                              child: SizedBox(
                                key: ValueKey('discovery-placeholder-$index'),
                                width: card,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                        TingyuTokens.artworkRadius,
                                      ),
                                      child: SizedBox.square(
                                        dimension:
                                            card - TingyuTokens.space / 2,
                                        child: ColoredBox(color: t.tint),
                                      ),
                                    ),
                                    const SizedBox(height: TingyuTokens.space),
                                    SizedBox(
                                      width: card * .75,
                                      height: scale.scale(14),
                                      child: ColoredBox(color: t.tint),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                        final track = tracks[index];
                        return DiscoveryExposure(
                          track: track,
                          onExposed: widget.p.recordDiscoveryExposure,
                          child: SizedBox(
                            key: ValueKey(
                              'discovery-card-${candidates[index].id}',
                            ),
                            width: card,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Stack(
                                  children: [
                                    Pressable(
                                      key: ValueKey(
                                        'discovery-play-${candidates[index].id}',
                                      ),
                                      label: '播放${track.title}',
                                      padding: EdgeInsets.zero,
                                      radius: TingyuTokens.artworkRadius,
                                      onPressed: () => report(
                                        context,
                                        () => widget.p.play(track),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Artwork(
                                            track,
                                            size: card - TingyuTokens.space / 2,
                                          ),
                                          const SizedBox(
                                            height: TingyuTokens.space,
                                          ),
                                          Text(
                                            track.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: titleStyle,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Positioned(
                                      top: 0,
                                      right: TingyuTokens.space / 2,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: t.surface,
                                          borderRadius: BorderRadius.circular(
                                            TingyuTokens.radius,
                                          ),
                                        ),
                                        child: action(
                                          Icons.more_horiz,
                                          '推荐歌曲操作${track.title}',
                                          () => showTrackActions(
                                            context,
                                            widget.p,
                                            track,
                                            null,
                                            discovery: true,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        track.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: artistStyle,
                                      ),
                                    ),
                                    action(
                                      widget.p.likes.contains(track.id)
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      widget.p.likes.contains(track.id)
                                          ? '取消喜欢${track.title}'
                                          : '喜欢${track.title}',
                                      () => widget.p.toggleLike(track),
                                      selected: widget.p.likes.contains(
                                        track.id,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            if (moreTracks.isNotEmpty) ...[
              const SizedBox(height: TingyuTokens.space * 3),
              Text('继续发现', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: TingyuTokens.space),
              for (final (index, track) in moreTracks.indexed)
                DiscoveryExposure(
                  track: track,
                  onExposed: widget.p.recordDiscoveryExposure,
                  child: TrackRow(
                    track,
                    discovery: true,
                    key: ValueKey('discovery-more-${moreCandidates[index].id}'),
                    presentationId: moreCandidates[index].id,
                  ),
                ),
            ],
            if (d.loadMoreFailed) errorBox(context, d.error, d.retry),
            if (tracks.isNotEmpty && !d.exhausted && !d.loadMoreFailed)
              SizedBox(
                height: TingyuTokens.space * 6,
                child: Center(
                  child: d.loadingMore
                      ? const SizedBox.square(
                          key: ValueKey('discovery-loading-more'),
                          dimension: TingyuTokens.iconSize,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            semanticsLabel: '正在加载更多推荐',
                          ),
                        )
                      : null,
                ),
              ),
            if (d.exhausted && d.tracks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: TingyuTokens.space * 2),
                child: Text(
                  '暂时没有更多推荐，试试其他标签。',
                  style: TextStyle(color: t.muted),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// Measures actual clipping by both the horizontal shelf and outer viewport.
class DiscoveryExposure extends StatefulWidget {
  const DiscoveryExposure({
    super.key,
    required this.track,
    required this.onExposed,
    required this.child,
  });
  final Track track;
  final ValueChanged<Track> onExposed;
  final Widget child;
  @override
  State<DiscoveryExposure> createState() => _DiscoveryExposureState();
}

class _DiscoveryExposureState extends State<DiscoveryExposure> {
  Timer? timer;
  Duration visibleFor = Duration.zero;
  String? recorded;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(milliseconds: 250), (_) => check());
  }

  @override
  void didUpdateWidget(covariant DiscoveryExposure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.bvid != widget.track.bvid) {
      recorded = null;
      visibleFor = Duration.zero;
    }
  }

  void check() {
    if (!mounted || recorded == widget.track.bvid) return;
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return;
    var visible = Offset.zero & MediaQuery.sizeOf(context);
    context.visitAncestorElements((element) {
      final ancestor = element.renderObject;
      if (ancestor is RenderAbstractViewport) {
        final box = ancestor as RenderBox;
        if (box.hasSize) {
          visible = visible.intersect(
            box.localToGlobal(Offset.zero) & box.size,
          );
        }
      }
      return true;
    });
    final rect = render.localToGlobal(Offset.zero) & render.size;
    final intersection = visible.intersect(rect);
    final active =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    final enough =
        active &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        !intersection.isEmpty &&
        rect.width * rect.height > 0 &&
        intersection.width * intersection.height >=
            rect.width * rect.height / 2;
    if (!enough) {
      visibleFor = Duration.zero;
      return;
    }
    visibleFor += const Duration(milliseconds: 250);
    if (visibleFor >= const Duration(seconds: 1)) {
      recorded = widget.track.bvid;
      widget.onExposed(widget.track);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
