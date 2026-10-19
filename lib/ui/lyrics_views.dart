part of 'app.dart';

class LyricsScreen extends ConsumerWidget {
  const LyricsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(libraryProvider), t = context.tokens;
    final track = p.current;
    return DetailAtmosphere(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PlayerHeader(
          onBack: () =>
              context.canPop() ? context.pop() : context.go('/player'),
          transparent: true,
          status: track?.title ?? '歌词',
          onMore: track == null ? null : () => showLyrics(context, p),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TingyuTokens.space * 3,
                ),
                child: Column(
                  children: [
                    Text(
                      lyricSourceLabel(p.lyricSource),
                      style: TextStyle(color: t.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: track == null
                    ? const EmptyView('还没有正在播放的曲目', '开始播放后在这里查看歌词')
                    : p.lines.isEmpty
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(TingyuTokens.space * 3),
                        child: Column(
                          children: [
                            if (p.lyricLoading) const LinearProgressIndicator(),
                            const SizedBox(height: TingyuTokens.space * 4),
                            Text(
                              p.lyricText.isNotEmpty
                                  ? p.lyricText
                                  : p.lyricLoading
                                  ? '正在查找歌词…'
                                  : '暂无歌词',
                              style: TextStyle(
                                color: t.text,
                                fontSize: 20,
                                height: 1.8,
                              ),
                            ),
                            if (p.lyricError.isNotEmpty)
                              Text(
                                p.lyricError,
                                style: TextStyle(color: t.muted),
                              ),
                            labelButton(
                              '匹配或导入歌词',
                              () => showLyrics(context, p),
                            ),
                          ],
                        ),
                      )
                    : RichLyricTimeline(
                        p,
                        key: ValueKey('lyric-timeline-${track.id}'),
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: track == null
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TingyuTokens.space * 3,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [SeekBar(p), transport(context, p)],
                  ),
                ),
              ),
      ),
    );
  }
}

/// Active line can reveal one word at a time. Plain lines stay a single
/// [Text] so existing player tests can read `Text.data`.
class LyricWordLine extends StatelessWidget {
  const LyricWordLine({
    super.key,
    required this.line,
    required this.milliseconds,
    required this.style,
    required this.sung,
    required this.unsung,
    required this.animate,
    this.maxLines = 2,
    this.textAlign = TextAlign.center,
  });
  final LyricLine line;
  final int milliseconds;
  final TextStyle style;
  final Color sung, unsung;
  final bool animate;
  final int? maxLines;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    if (!animate || line.words.isEmpty) {
      return Text(
        line.text,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      );
    }
    final words = [
      for (final word in line.words)
        if (word.text.isNotEmpty)
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) {
              final split = word.progress(milliseconds);
              return LinearGradient(
                colors: [sung, sung, unsung, unsung],
                stops: [0, split, split, 1],
              ).createShader(bounds);
            },
            child: Text(word.text, style: style.copyWith(color: sung)),
          ),
    ];
    if (maxLines == null) {
      return Wrap(
        alignment: textAlign == TextAlign.center
            ? WrapAlignment.center
            : WrapAlignment.start,
        children: words,
      );
    }
    return Text.rich(
      TextSpan(children: [for (final word in words) WidgetSpan(child: word)]),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class RichLyricTimeline extends StatefulWidget {
  const RichLyricTimeline(this.p, {super.key});
  final LibraryController p;
  @override
  State<RichLyricTimeline> createState() => _RichLyricTimelineState();
}

class _RichLyricTimelineState extends State<RichLyricTimeline> {
  final scroll = ScrollController();
  bool browsing = false;
  int focused = -1;
  String layoutKey = '';
  List<double> measuredHeights = const [];
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void follow(
    int index,
    List<double> heights,
    double viewport, {
    bool force = false,
  }) {
    if (browsing && !force) return;
    final immediate =
        force ||
        focused < 0 ||
        (focused - index).abs() > 1 ||
        MediaQuery.disableAnimationsOf(context);
    focused = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients || (browsing && !force)) return;
      final padding = viewport / 2;
      final offset =
          (padding +
                  heights
                      .take(index)
                      .fold<double>(0, (sum, height) => sum + height) +
                  heights[index] / 2 -
                  viewport / 2)
              .clamp(0.0, scroll.position.maxScrollExtent);
      if (immediate) {
        scroll.jumpTo(offset);
      } else {
        unawaited(
          scroll.animateTo(
            offset,
            duration: TingyuTokens.scrollReturn,
            curve: Curves.easeOutCubic,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => ValueListenableBuilder<Duration>(
      valueListenable: widget.p.playhead,
      builder: (context, position, _) {
        final p = widget.p, t = context.tokens, lines = p.lines;
        if (lines.isEmpty) return const SizedBox.shrink();
        final font = p.lyricFontSize;
        final width = (box.maxWidth - TingyuTokens.space * 6).clamp(
          1.0,
          double.infinity,
        );
        double measured(
          String text,
          double size, {
          FontWeight weight = FontWeight.normal,
        }) {
          final painter = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(fontSize: size, height: 1.6, fontWeight: weight),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: width);
          final height = painter.height;
          painter.dispose();
          return height;
        }

        final milliseconds = position.inMilliseconds + p.lyricOffset;
        final index = focusedLyricLine(lines, milliseconds);
        final key =
            '${p.lyricText}:${p.lyricTranslation}:${p.lyricRomaji}:${p.showLyricTranslation}:${p.showLyricRomaji}:${p.lyricSize}:${box.maxWidth}:${box.maxHeight}:${MediaQuery.textScalerOf(context).scale(font)}';
        if (layoutKey != key) {
          layoutKey = key;
          focused = -1;
          measuredHeights = [
            for (final line in lines)
              if (line.text.isEmpty)
                0.0
              else
                // Pressable paints a 2px border inside the box.
                4 +
                    TingyuTokens.space * 4 +
                    measured(line.text, font, weight: FontWeight.w600) +
                    (p.showLyricTranslation && line.translation.isNotEmpty
                        ? measured(line.translation, 14) + TingyuTokens.space
                        : 0) +
                    (p.showLyricRomaji && line.romaji.isNotEmpty
                        ? measured(line.romaji, 13) + TingyuTokens.space
                        : 0),
          ];
        }
        final heights = measuredHeights;
        if (index != focused) follow(index, heights, box.maxHeight);
        return Stack(
          children: [
            NotificationListener<ScrollStartNotification>(
              onNotification: (event) {
                if (event.dragDetails != null && !browsing) {
                  setState(() => browsing = true);
                }
                return false;
              },
              child: ListView.builder(
                key: const ValueKey('full-lyrics-list'),
                controller: scroll,
                padding: EdgeInsets.symmetric(
                  vertical: box.maxHeight / 2,
                  horizontal: TingyuTokens.space * 3,
                ),
                itemCount: lines.length,
                itemBuilder: (context, i) {
                  final line = lines[i], active = i == index;
                  if (line.text.isEmpty) return const SizedBox.shrink();
                  final style = TextStyle(
                    fontSize: font,
                    height: 1.6,
                    fontWeight: FontWeight.w600,
                    color: active ? t.accentInk : t.muted,
                  );
                  return SizedBox(
                    height: heights[i],
                    child: Pressable(
                      key: ValueKey('lyric-line-$i'),
                      label: '跳转到 ${clock(line.time)}，${line.text}',
                      onPressed: line.text.isEmpty
                          ? null
                          : () async {
                              final at =
                                  line.time.inMilliseconds - p.lyricOffset;
                              await p.playback.seek(
                                Duration(milliseconds: at < 0 ? 0 : at),
                              );
                              p.position = Duration(
                                milliseconds: at < 0 ? 0 : at,
                              );
                              if (mounted) {
                                setState(() {
                                  browsing = false;
                                  focused = -1;
                                });
                              }
                            },
                      padding: const EdgeInsets.symmetric(
                        vertical: TingyuTokens.space * 2,
                      ),
                      child: Align(
                        alignment: p.lyricCentered
                            ? Alignment.center
                            : Alignment.centerLeft,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: p.lyricCentered
                              ? CrossAxisAlignment.center
                              : CrossAxisAlignment.start,
                          children: [
                            LyricWordLine(
                              line: line,
                              milliseconds: milliseconds,
                              style: style,
                              sung: t.accentInk,
                              unsung: t.muted,
                              animate:
                                  p.showLyricWords &&
                                  active &&
                                  !MediaQuery.disableAnimationsOf(context),
                              maxLines: null,
                              textAlign: p.lyricCentered
                                  ? TextAlign.center
                                  : TextAlign.start,
                            ),
                            if (p.showLyricTranslation &&
                                line.translation.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: TingyuTokens.space,
                                ),
                                child: Text(
                                  line.translation,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.6,
                                    color: active ? t.text : t.muted,
                                  ),
                                ),
                              ),
                            if (p.showLyricRomaji && line.romaji.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: TingyuTokens.space,
                                ),
                                child: Text(
                                  line.romaji,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.6,
                                    color: t.muted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (browsing)
              Positioned(
                right: TingyuTokens.space * 2,
                bottom: TingyuTokens.space * 2,
                child: GlassSurface(
                  child: labelButton('回到当前歌词', () {
                    setState(() => browsing = false);
                    follow(index, heights, box.maxHeight, force: true);
                  }, icon: Icons.my_location),
                ),
              ),
          ],
        );
      },
    ),
  );
}
