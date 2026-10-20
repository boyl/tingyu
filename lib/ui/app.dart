import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import '../services/storage_usage.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../services/lyrics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:qr_flutter/qr_flutter.dart';
import '../main.dart';
import '../controllers/library_controller.dart';
import '../models/music.dart';
import '../services/media_export.dart';
import '../services/bilibili_link.dart';
import 'theme.dart';
import 'icons.dart';
import 'playing_indicator.dart';
import 'scroll_to_top.dart';
part 'library_views.dart';
part 'home_views.dart';
part 'status_marquee.dart';
part 'volume_views.dart';
part 'settings_views.dart';
part 'playlist_add_views.dart';
part 'downloads_views.dart';
part 'search_views.dart';
part 'lyrics_views.dart';
part 'lyrics_preferences_views.dart';
part 'playback_settings_views.dart';
part 'preferences_views.dart';

String normalizedFolderName(String value) => String.fromCharCodes(
  value.runes.map(
    (r) => r == 0x3000
        ? 0x20
        : r >= 0xff01 && r <= 0xff5e
        ? r - 0xfee0
        : r,
  ),
).toLowerCase().trim();
bool matchesFolderName(String name, String query) {
  final normalized = normalizedFolderName(name);
  return normalizedFolderName(
    query,
  ).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).every(normalized.contains);
}

bool matchesLocal(Track? track, String query) {
  if (track == null) return false;
  final text = '${track.title} ${track.artist} ${track.bvid}'.toLowerCase();
  return query.toLowerCase().trim().split(RegExp(r'\s+')).every(text.contains);
}

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
      selectionFill: false,
      padding: const EdgeInsets.all(10),
      child: SizedBox.square(
        dimension: TingyuTokens.iconSize,
        child: Center(child: TingyuIcon(icon, size: TingyuTokens.iconSize)),
      ),
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
    selectionFill: false,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          TingyuIcon(icon, size: 18),
          const SizedBox(width: 8),
        ],
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

class Artwork extends ConsumerStatefulWidget {
  const Artwork(this.track, {super.key, this.size = 48});
  final Track track;
  final double size;
  @override
  ConsumerState<Artwork> createState() => _ArtworkState();
}

class _ArtworkState extends ConsumerState<Artwork> {
  late Future<File?> image;
  void load() {
    final p = ref.read(libraryProvider);
    image = p.downloads.artworkFile(widget.track);
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant Artwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.cover != widget.track.cover ||
        oldWidget.track.id != widget.track.id) {
      load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.read(libraryProvider);
    final cached = p.downloads.cachedArtwork(widget.track);
    final pixels = (widget.size * MediaQuery.devicePixelRatioOf(context) * 2)
        .ceil()
        .clamp(96, 2048);
    Widget fallback() => ColoredBox(
      color: context.tokens.tint,
      child: Center(
        child: TingyuIcon(
          Icons.graphic_eq,
          size: widget.size / 3,
          color: context.tokens.accent,
        ),
      ),
    );
    Widget render(File? file) => file == null
        ? fallback()
        : Image.file(
            file,
            fit: BoxFit.cover,
            cacheWidth: pixels,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => fallback(),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(TingyuTokens.artworkRadius),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: FutureBuilder<File?>(
          future: image,
          initialData: cached,
          builder: (_, snapshot) => render(snapshot.data),
        ),
      ),
    );
  }
}

class RecordDisc extends StatefulWidget {
  const RecordDisc(
    this.track, {
    super.key,
    required this.size,
    required this.playing,
  });
  final Track track;
  final double size;
  final bool playing;
  @override
  State<RecordDisc> createState() => _RecordDiscState();
}

class _RecordDiscState extends State<RecordDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController spin = AnimationController(
    vsync: this,
    duration: TingyuTokens.recordTurn,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sync();
  }

  @override
  void didUpdateWidget(covariant RecordDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) sync();
  }

  void sync() {
    final still =
        !widget.playing ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    if (still) {
      spin.stop();
    } else if (!spin.isAnimating) {
      spin.repeat();
    }
  }

  @override
  void dispose() {
    spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: context.tokens.playerShadow.withValues(alpha: .20),
              blurRadius: TingyuTokens.space * 3,
              offset: const Offset(0, TingyuTokens.space),
            ),
          ],
        ),
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned.fill(
                child: CustomPaint(painter: RecordGrooves()),
              ),
              RotationTransition(
                turns: spin,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipOval(
                      child: Artwork(
                        widget.track,
                        size: size * TingyuTokens.recordCoverRatio,
                      ),
                    ),
                  ],
                ),
              ),
              const Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: RecordSheen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RecordSheen extends CustomPainter {
  const RecordSheen();
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), radius = size.shortestSide / 2;
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..addOval(
        Rect.fromCircle(
          center: center,
          radius: radius * TingyuTokens.recordCoverRatio,
        ),
      );
    canvas.save();
    canvas.clipPath(ring);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = SweepGradient(
          colors: [
            TingyuTokens.recordGlint.withValues(alpha: 0),
            TingyuTokens.recordGlint.withValues(alpha: .22),
            TingyuTokens.recordGlint.withValues(alpha: 0),
            TingyuTokens.recordGlint.withValues(alpha: .04),
            TingyuTokens.recordGlint.withValues(alpha: 0),
          ],
          stops: const [0, .18, .29, .68, 1],
        ).createShader(Offset.zero & size),
    );
    canvas.drawCircle(
      center,
      radius - .7,
      Paint()
        ..color = TingyuTokens.recordGlint.withValues(alpha: .30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7,
    );
    canvas.drawCircle(
      center,
      radius * TingyuTokens.recordCoverRatio + .8,
      Paint()
        ..color = TingyuTokens.recordGlint.withValues(alpha: .12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .6,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RecordSheen oldDelegate) => false;
}

class RecordGrooves extends CustomPainter {
  const RecordGrooves();
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), radius = size.shortestSide / 2;
    canvas.drawCircle(center, radius, Paint()..color = TingyuTokens.recordBase);
    final groove = Paint()
      ..color = TingyuTokens.recordGroove.withValues(alpha: .5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .45;
    for (
      double r = radius * TingyuTokens.recordCoverRatio;
      r < radius - 1;
      r += 1.6
    ) {
      canvas.drawCircle(center, r, groove);
    }
  }

  @override
  bool shouldRepaint(covariant RecordGrooves oldDelegate) => false;
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
          TingyuIcon(
            Icons.album_outlined,
            size: 42,
            color: context.tokens.accent,
          ),
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

class BilibiliExternalLink extends StatelessWidget {
  const BilibiliExternalLink({super.key, this.launcher, this.compact = false});
  final bool compact;
  final BilibiliLinkLauncher? launcher;
  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Pressable(
        key: const ValueKey('open-bilibili-external'),
        label: '前往哔哩哔哩，打开外部 App 或浏览器',
        onPressed: () =>
            report(context, (launcher ?? BilibiliLinkLauncher()).open),
        padding: const EdgeInsets.symmetric(horizontal: TingyuTokens.space / 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '前往哔哩哔哩',
              style: TextStyle(color: context.tokens.muted, fontSize: 12),
            ),
            const SizedBox(width: TingyuTokens.space / 2),
            TingyuIcon(Icons.north_east, size: 16, color: context.tokens.muted),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.tokens.surface,
            border: Border.all(color: context.tokens.line),
            borderRadius: BorderRadius.circular(TingyuTokens.radius),
          ),
          child: Pressable(
            key: const ValueKey('open-bilibili-external'),
            label: '前往哔哩哔哩，打开外部 App 或浏览器',
            onPressed: () =>
                report(context, (launcher ?? BilibiliLinkLauncher()).open),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '前往哔哩哔哩',
                  style: TextStyle(
                    color: context.tokens.accentInk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: TingyuTokens.space),
                TingyuIcon(
                  Icons.open_in_new,
                  size: 18,
                  color: context.tokens.accent,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: TingyuTokens.space),
        Text(
          '优先打开 App，未安装时使用浏览器',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: context.tokens.muted),
        ),
      ],
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    required this.page,
    this.playlistId,
    this.downloadSection,
  });
  final String page;
  final String? playlistId, downloadSection;
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

  final pageScroll = ScrollController();
  final localSearch = TextEditingController();
  bool localSearchOpen = false;
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
      localSearch.clear();
      localSearchOpen = false;
    }
  }

  List<String> visibleIds(LibraryController p, Playlist? list) => p
      .collectionIds(
        collectionKey,
        widget.page == 'likes' ? p.likes : list?.trackIds ?? p.library.keys,
      )
      .where((id) => matchesLocal(p.library[id], localSearch.text))
      .toList();
  Timer? debounce;
  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    localSearch.dispose();
    pageScroll.dispose();
    super.dispose();
  }

  Widget localSearchField() => TextField(
    key: const ValueKey('local-search'),
    controller: localSearch,
    decoration: InputDecoration(
      hintText: '搜索当前列表的歌名、UP 主',
      prefixIcon: const TingyuIcon(Icons.search),
      suffixIcon: action(
        Icons.clear_all,
        '清除本地搜索',
        () => setState(localSearch.clear),
      ),
      border: const OutlineInputBorder(),
    ),
    onChanged: (_) => setState(() {}),
  );

  void navigate(String page) {
    FocusManager.instance.primaryFocus?.unfocus();
    final index = ['library', 'search', 'downloads', 'likes'].indexOf(page);
    final shell = StatefulNavigationShell.of(context);
    shell.goBranch(index, initialLocation: shell.widget.currentIndex == index);
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(libraryProvider);
    final desktop = MediaQuery.sizeOf(context).width >= 960;
    final list = p.playlists
        .where((l) => l.id == widget.playlistId)
        .firstOrNull;
    final title = switch (widget.page) {
      'search' => widget.playlistId == null ? '听点新鲜的' : '在线搜索',
      'downloads' => '下载',
      'likes' => '心动收藏',
      'playlist' => list?.name ?? '歌单不存在',
      _ => '随心听',
    };
    if (selecting) selection.retainAll(visibleIds(p, list));
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (widget.page == 'search' && widget.playlistId != null)
              action(
                Icons.arrow_back,
                '返回选歌',
                () => context.canPop()
                    ? context.pop()
                    : context.go('/playlist/${widget.playlistId}/add'),
              )
            else if (widget.page == 'playlist')
              action(Icons.arrow_back, '返回音乐库', () => navigate('library')),
            if (!desktop && widget.page == 'library')
              Tooltip(
                message: '打开设置',
                child: Pressable(
                  key: const ValueKey('打开设置'),
                  label: '打开设置',
                  padding: const EdgeInsets.all(TingyuTokens.space / 2),
                  radius: TingyuTokens.playerRadius,
                  onPressed: () {
                    unawaited(context.push('/settings'));
                  },
                  child: AccountAvatar(
                    profile: p.profile,
                    size: TingyuTokens.avatarSize,
                  ),
                ),
              ),
            if (!desktop && widget.page == 'library')
              const SizedBox(width: TingyuTokens.space),
            Expanded(
              child: Text(
                title,
                textAlign: !desktop && widget.page == 'library'
                    ? TextAlign.right
                    : TextAlign.left,
                style: widget.page == 'library'
                    ? Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(fontSize: 24)
                    : Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (!['search', 'library'].contains(widget.page))
              action(
                Icons.search,
                '搜索本地歌曲',
                () => setState(() {
                  localSearchOpen = !localSearchOpen;
                  if (!localSearchOpen) localSearch.clear();
                }),
              ),
            if (widget.page == 'playlist' && list != null)
              action(
                Icons.more_horiz,
                '歌单更多',
                () => showPlaylistActions(context, p, list),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (localSearchOpen &&
            !['search', 'library'].contains(widget.page)) ...[
          localSearchField(),
          const SizedBox(height: 16),
        ],
        if (p.error.isNotEmpty) errorBox(context, p.error, p.clearError),
        if (widget.page == 'search') ...[
          TextField(
            controller: search,
            decoration: InputDecoration(
              prefixIcon: const TingyuIcon(Icons.search),
              suffixIcon: search.text.isEmpty
                  ? null
                  : action(Icons.clear_all, '清除在线搜索', () {
                      debounce?.cancel();
                      search.clear();
                      unawaited(p.search(''));
                      setState(() {});
                    }),
              hintText: '歌曲、UP 主、BV / AV 号或链接',
            ),
            onChanged: (v) {
              setState(() {});
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
          const Align(
            alignment: Alignment.centerRight,
            child: BilibiliExternalLink(compact: true),
          ),
          if (search.text.isEmpty && widget.playlistId == null)
            SearchDiscovery(
              p,
              onSearch: (value) {
                search.text = value;
                unawaited(p.search(value));
                setState(() {});
              },
            ),
          if (!p.searching &&
              search.text.isNotEmpty &&
              p.results.isEmpty &&
              p.searchError.isEmpty)
            const EmptyView('没有找到相关内容', '换个关键词，或直接粘贴 BV 号。'),
        ],
        if (['library', 'likes', 'playlist'].contains(widget.page)) ...[
          if (widget.page == 'library' && localSearch.text.trim().isEmpty)
            HomeShelves(
              p,
              onCreate: () async {
                final name = await nameDialog(context);
                if (name != null && context.mounted) await p.addPlaylist(name);
              },
            ),
          if (widget.page == 'library')
            Row(
              children: [
                Expanded(
                  child: Text(
                    '歌曲',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                action(
                  Icons.search,
                  '搜索本地歌曲',
                  () => setState(() {
                    localSearchOpen = !localSearchOpen;
                    if (!localSearchOpen) localSearch.clear();
                  }),
                ),
              ],
            ),
          if (localSearchOpen && widget.page == 'library') ...[
            const SizedBox(height: 12),
            localSearchField(),
          ],
          if (list != null) PlaylistSummary(list),
          SizedBox(
            width: double.infinity,
            child: Stack(
              children: [
                Visibility(
                  visible: !selecting,
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  child: LayoutBuilder(
                    builder: (context, constraints) => SizedBox(
                      height:
                          measuredSelectionToolbar(
                            context,
                            constraints.maxWidth,
                            visibleIds(p, list).length,
                            list != null,
                          ).compact
                          ? TingyuTokens.controlSize * 2
                          : TingyuTokens.controlSize,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: CollectionToolbar(
                          ids: visibleIds(p, list),
                          list: list,
                          collectionKey: collectionKey,
                          compact: widget.page == 'library',
                          selecting: false,
                          onSelect: () => setState(() {
                            selecting = true;
                            selection.clear();
                          }),
                        ),
                      ),
                    ),
                  ),
                ),
                if (selecting)
                  Positioned.fill(
                    child: SelectionToolbar(
                      selectedIds: selection
                          .where(visibleIds(p, list).contains)
                          .toList(),
                      totalCount: visibleIds(p, list).length,
                      allSelected:
                          visibleIds(p, list).isNotEmpty &&
                          selection.containsAll(visibleIds(p, list)),
                      list: list,
                      onSelectAll: () => setState(() {
                        final ids = visibleIds(p, list);
                        selection.containsAll(ids)
                            ? selection.clear()
                            : selection.addAll(ids);
                      }),
                      onDone: () => setState(() {
                        selecting = false;
                        selection.clear();
                      }),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
    final collection = ['library', 'likes', 'playlist'].contains(widget.page);
    final rows = widget.page == 'search'
        ? <WidgetBuilder>[
            for (final track in p.results)
              (_) =>
                  TrackRow(track, key: ValueKey(track.id), addToPlaylist: list),
            if (p.results.isNotEmpty && !p.searching)
              (_) => Center(
                child: labelButton(
                  '加载更多',
                  () => p.search(search.text, page: p.searchPage + 1),
                ),
              ),
          ]
        : collection
        ? _libraryRows(p, list)
        : <WidgetBuilder>[];
    final rowSliver = SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) => rows[i](context),
        childCount: rows.length,
      ),
    );
    return PopScope(
      canPop: !selecting && widget.playlistId != null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (selecting) {
          setState(() {
            selecting = false;
            selection.clear();
          });
        } else if (widget.playlistId == null) {
          if (widget.page != 'library') {
            navigate('library');
          } else if (pageScroll.hasClients && pageScroll.offset > 0) {
            if (MediaQuery.disableAnimationsOf(context)) {
              pageScroll.jumpTo(0);
            } else {
              unawaited(
                pageScroll.animateTo(
                  0,
                  duration: TingyuTokens.scrollReturn,
                  curve: Curves.easeOutCubic,
                ),
              );
            }
          } else {
            unawaited(SystemNavigator.pop());
          }
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
          child: BackdropGroup(
            child: Scaffold(
              extendBody: !desktop,
              body: GlassBackdrop(
                p: p,
                child: Builder(
                  builder: (context) => SafeArea(
                    bottom: desktop,
                    child: Column(
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (desktop &&
                                  !(widget.page == 'search' &&
                                      widget.playlistId != null))
                                SizedBox(width: 224, child: sidebar(p)),
                              Expanded(
                                child: widget.page == 'downloads'
                                    ? DownloadsWorkspace(
                                        p,
                                        tasks:
                                            widget.downloadSection == 'tasks',
                                        desktop: desktop,
                                        dockInset: desktop
                                            ? 0
                                            : MediaQuery.paddingOf(
                                                context,
                                              ).bottom,
                                      )
                                    : ScrollToTop(
                                        enabled: widget.playlistId != null,
                                        controller: pageScroll,
                                        builder: (scroll) => CustomScrollView(
                                          controller: scroll,
                                          key: PageStorageKey(
                                            'page-${widget.page}-${widget.playlistId}',
                                          ),
                                          slivers: [
                                            SliverPadding(
                                              padding: EdgeInsets.fromLTRB(
                                                desktop ? 36 : 20,
                                                desktop ? 36 : 20,
                                                desktop
                                                    ? 36
                                                    : widget.page == 'library'
                                                    ? 0
                                                    : 20,
                                                0,
                                              ),
                                              sliver: SliverToBoxAdapter(
                                                child:
                                                    !desktop &&
                                                        widget.page == 'library'
                                                    ? Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          for (final child
                                                              in content
                                                                  .children)
                                                            if (child
                                                                is HomeShelves)
                                                              child
                                                            else
                                                              Padding(
                                                                padding:
                                                                    const EdgeInsets.only(
                                                                      right: 20,
                                                                    ),
                                                                child: child,
                                                              ),
                                                        ],
                                                      )
                                                    : content,
                                              ),
                                            ),
                                            SliverPadding(
                                              padding: EdgeInsets.fromLTRB(
                                                desktop ? 36 : 20,
                                                0,
                                                desktop ? 36 : 20,
                                                TingyuTokens.space * 10 +
                                                    (desktop
                                                        ? 0
                                                        : MediaQuery.paddingOf(
                                                            context,
                                                          ).bottom),
                                              ),
                                              sliver: rowSliver,
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                        if (desktop) RepaintBoundary(child: MiniPlayer(p)),
                      ],
                    ),
                  ),
                ),
              ),
              bottomNavigationBar:
                  desktop ||
                      (widget.page == 'search' && widget.playlistId != null)
                  ? null
                  : SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MiniPlayer(p),
                          CompactNavigation(
                            controller: p,
                            selected: widget.page == 'playlist'
                                ? 'library'
                                : widget.page,
                            onSelect: navigate,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  List<WidgetBuilder> _libraryRows(LibraryController p, Playlist? list) {
    final ids = visibleIds(p, list);
    if (ids.isEmpty && localSearch.text.trim().isNotEmpty) {
      return [
        (_) => EmptyView(
          '没有匹配的歌曲',
          '试试其他歌名或 UP 主。',
          child: labelButton('清除搜索', () => setState(localSearch.clear)),
        ),
      ];
    }
    if (ids.isEmpty) {
      return [
        (_) => EmptyView(
          list == null ? '这里还很安静' : '歌单还没有歌曲',
          '搜索喜欢的声音，开始你的收藏。',
          child: labelButton(
            list == null ? '去搜索' : '添加歌曲',
            () => list == null
                ? navigate('search')
                : context.push('/playlist/${list.id}/add'),
          ),
        ),
      ];
    }
    return ids.where(p.library.containsKey).map((id) {
      // A lazy row can be built while async canonicalization awaits persistence.
      // Keep the immutable track from this collection snapshot until notified.
      final track = p.library[id]!;
      return (BuildContext _) => TrackRow(
        track,
        playlist: list,
        sourceIds: ids,
        selecting: selecting,
        selected: selection.contains(id),
        onSelect: () => setState(() {
          selection.contains(id) ? selection.remove(id) : selection.add(id);
        }),
      );
    }).toList();
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
              TingyuIcon(Icons.graphic_eq),
              SizedBox(width: 12),
              Flexible(
                child: Text(
                  'tingyu',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
                ),
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
                    icon: Icons.featured_play_list_outlined,
                    selected: widget.playlistId == l.id,
                  ),
                )
                .toList(),
          ),
        ),
        Pressable(
          key: const ValueKey('打开设置'),
          label: '设置',
          onPressed: () {
            unawaited(context.push('/settings'));
          },
          child: Row(
            children: [
              AccountAvatar(profile: p.profile, size: TingyuTokens.avatarSize),
              const SizedBox(width: TingyuTokens.space * 1.5),
              const Expanded(child: Text('设置')),
            ],
          ),
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
      labelButton('编辑歌单', () async {
        Navigator.pop(ctx);
        await showDialog<void>(
          context: context,
          builder: (_) => PlaylistEditDialog(list),
        );
      }, icon: Icons.edit_outlined),
      labelButton('添加歌曲', () {
        Navigator.pop(ctx);
        context.push('/playlist/${list.id}/add');
      }, icon: Icons.library_add_outlined),
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
      TingyuIcon(Icons.arrow_downward, size: 14, color: context.tokens.accent),
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
        selectionFill: false,
        onPressed: tracks.isEmpty
            ? null
            : () => report(context, () async {
                if (allDone || active) {
                  context.go(
                    '/downloads?section=${allDone ? 'completed' : 'tasks'}',
                  );
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
            : TingyuIcon(
                allDone
                    ? Icons.check_circle_outline
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
            DownloadStatus.completed => '已下载',
            DownloadStatus.paused => '下载已暂停，点击继续',
            DownloadStatus.failed => '下载失败，点击重试',
            null => '下载',
          };
    Future<void> activate() async {
      if (completed ||
          task?.status == DownloadStatus.downloading ||
          task?.status == DownloadStatus.waiting) {
        context.go('/downloads?section=${completed ? 'completed' : 'tasks'}');
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
      DownloadStatus.completed => Icons.check_circle_outline,
      DownloadStatus.paused => Icons.play_arrow,
      DownloadStatus.failed => Icons.error_outline,
      DownloadStatus.waiting => Icons.schedule,
      _ => Icons.download_outlined,
    };
    return Tooltip(
      message: label,
      child: Pressable(
        key: ValueKey('download-${track.id}'),
        dimWhenDisabled: !completed,
        label: '$label ${track.title}',
        selected: completed,
        selectionFill: false,
        onPressed: preparing || completed
            ? null
            : () => report(context, activate),
        child: transferring
            ? downloadProgress(context, preparing ? null : task?.progress)
            : TingyuIcon(
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
  const TrackRow(
    this.track, {
    super.key,
    this.playlist,
    this.sourceIds,
    this.addToPlaylist,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
  });
  final bool selecting, selected;
  final VoidCallback? onSelect;
  final Playlist? addToPlaylist;
  final Track track;
  final Playlist? playlist;
  final List<String>? sourceIds;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(libraryProvider),
        desktop = MediaQuery.sizeOf(context).width >= 960,
        liked = p.likes.contains(track.id);
    return Container(
      decoration: BoxDecoration(
        color: !selecting && p.current?.id == track.id
            ? context.tokens.tint
            : null,
        borderRadius: BorderRadius.circular(TingyuTokens.radius),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : TingyuTokens.transition,
            width: selecting ? TingyuTokens.controlSize : 0,
            height: TingyuTokens.controlSize,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(),
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: TingyuTokens.controlSize,
              maxWidth: TingyuTokens.controlSize,
              child: ExcludeFocus(
                excluding: !selecting,
                child: ExcludeSemantics(
                  excluding: !selecting,
                  child: action(
                    selected ? Icons.check_box : Icons.check_box_outline_blank,
                    '选择 ${track.title}',
                    onSelect,
                    selected: selected,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Pressable(
              key: ValueKey(
                selecting ? 'select-${track.id}' : 'play-${track.id}',
              ),
              label: selecting ? '选择 ${track.title}' : '播放 ${track.title}',
              selected: selecting && selected,
              selectionFill: false,
              onPressed: selecting
                  ? onSelect
                  : () => sourceIds == null
                        ? p.play(track)
                        : p.playFromCollection(track, sourceIds!),
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
                          style: TextStyle(
                            fontSize: 13,
                            color: context.tokens.text,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
          if (!selecting && !desktop && liked)
            Semantics(
              label: '已喜欢',
              child: TingyuIcon(
                Icons.favorite,
                size: 16,
                color: context.tokens.accent,
              ),
            ),
          if (!selecting && desktop) ...[
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
          if (selecting && p.current?.id == track.id)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TingyuTokens.space,
              ),
              child: PlayingIndicator(
                playing:
                    p.playing &&
                    p.playback.player.processingState == ProcessingState.ready,
              ),
            ),
          if (!selecting && addToPlaylist != null)
            PlaylistAddTrackAction(track: track, playlist: addToPlaylist!)
          else if (!selecting)
            TrackDownloadAction(
              track,
              key: ValueKey('download-action-${track.id}'),
            ),
          if (!selecting)
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
  Playlist? list, {
  bool includeVolume = false,
}) async {
  await showContentActions(
    context,
    (ctx) => SimpleDialog(
      title: Text(
        track.title,
        maxLines: 2,
        style: const TextStyle(fontSize: 17),
      ),
      children: [
        if (includeVolume)
          labelButton('播放音量', () async {
            Navigator.pop(ctx);
            await showPlayerVolume(context, p);
          }, icon: Icons.volume_up),
        labelButton('下一首播放', () async {
          await p.enqueue(track, next: true);
          if (ctx.mounted) Navigator.pop(ctx);
        }, icon: Icons.playlist_play),
        labelButton('加入播放队列', () async {
          await p.enqueue(track);
          if (ctx.mounted) Navigator.pop(ctx);
        }, icon: Icons.add_to_queue),
        labelButton(
          p.likes.contains(track.id) ? '取消喜欢' : '喜欢',
          () async {
            await p.toggleLike(track);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          icon: p.likes.contains(track.id)
              ? Icons.favorite
              : Icons.favorite_border,
          selected: p.likes.contains(track.id),
        ),
        Consumer(
          builder: (context, ref, _) {
            ref.watch(libraryProvider);
            final task = trackDownload(p, track);
            if (task?.status == DownloadStatus.completed) {
              return Padding(
                key: const ValueKey('menu-downloaded'),
                padding: const EdgeInsets.symmetric(
                  horizontal: TingyuTokens.space * 1.5,
                ),
                child: SizedBox(
                  height: TingyuTokens.controlSize,
                  child: Row(
                    children: [
                      TingyuIcon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: context.tokens.text,
                      ),
                      const SizedBox(width: TingyuTokens.space),
                      const Text('已下载'),
                    ],
                  ),
                ),
              );
            }
            return Row(
              children: [
                const SizedBox(width: TingyuTokens.space * 2),
                Expanded(
                  child: Text(
                    task?.status == DownloadStatus.completed ? '已下载' : '下载',
                  ),
                ),
                TrackDownloadAction(track),
                const SizedBox(width: TingyuTokens.space),
              ],
            );
          },
        ),
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
        labelButton('在 B 站打开', () async {
          Navigator.pop(ctx);
          await report(context, () => BilibiliLinkLauncher().openVideo(track));
        }, icon: Icons.open_in_new),
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
    final tokens = context.tokens;
    final overlayContext = context;
    final dockTokens = tokens.copyWith(
      text: tokens.onPlayer,
      muted: tokens.playerMuted,
      accent: tokens.playerButton,
      onAccent: tokens.onPlayerButton,
      tint: tokens.playerTrack,
      line: tokens.playerTrack,
    );
    return Theme(
      data: Theme.of(context).copyWith(extensions: [dockTokens]),
      child: Builder(
        builder: (context) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: AdaptiveGlass(
            p: p,
            navigation: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: Pressable(
                      key: const ValueKey('展开播放器'),
                      label: '展开播放器',
                      onPressed: () {
                        unawaited(context.push('/player'));
                      },
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
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.onPlayer,
                                  ),
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
                                    fontSize: 12,
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
                        children: [
                          transport(context, p, overlayContext: overlayContext),
                          SeekBar(p),
                        ],
                      ),
                    )
                  else
                    Pressable(
                      key: const ValueKey('播放或暂停'),
                      label: '播放或暂停',
                      onPressed: p.opening ? null : () => p.toggle(),

                      radius: 48,
                      child: TingyuIcon(
                        p.playing ? Icons.pause : Icons.play_arrow,
                        color: tokens.onPlayer,
                      ),
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
                    action(
                      Icons.queue_music,
                      '播放队列',
                      () => showQueue(overlayContext),
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

String modeLabel(String mode) => switch (mode) {
  'shuffle' => '随机播放',
  'repeat' => '单曲循环',
  'once' => '播完暂停',
  _ => '列表循环',
};
IconData modeIcon(String mode) => switch (mode) {
  'shuffle' => Icons.shuffle,
  'repeat' => Icons.repeat_one,
  'once' => Icons.pause_circle_outline,
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
        const modes = ['order', 'repeat', 'shuffle', 'once'];
        final task = p.setMode(
          modes[(modes.indexOf(p.mode) + 1) % modes.length],
        );
        p.announceMode(modeLabel(p.mode));
        return task;
      }),
      child: TingyuIcon(modeIcon(p.mode), color: context.tokens.accent),
    ),
  );
}

Widget transport(
  BuildContext context,
  LibraryController p, {
  BuildContext? overlayContext,
}) => Row(
  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
  children: [
    ModeButton(p),
    action(Icons.skip_previous, '上一首', p.opening ? null : () => p.next(-1)),
    Pressable(
      label: p.playing ? '暂停' : '播放',
      key: const ValueKey('toggle-playback'),
      onPressed: p.opening ? null : () => p.toggle(),
      minSize: TingyuTokens.playControlSize,
      radius: TingyuTokens.playControlSize / 2,
      color: context.tokens.playerButton,
      child: TingyuIcon(
        p.playing ? Icons.pause : Icons.play_arrow,
        color: context.tokens.onPlayerButton,
        size: TingyuTokens.space * 4,
      ),
    ),
    action(Icons.skip_next, '下一首', p.opening ? null : () => p.next()),
    action(
      Icons.queue_music,
      '播放队列',
      () => showQueue(overlayContext ?? context),
    ),
  ],
);

class PlayerProgress extends StatefulWidget {
  const PlayerProgress(this.controller, {super.key});
  final LibraryController controller;
  @override
  State<PlayerProgress> createState() => _PlayerProgressState();
}

class _PlayerProgressState extends State<PlayerProgress> {
  var seeking = false;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SeekBar(
        widget.controller,
        onSeeking: (value) {
          if (seeking == value) return;
          setState(() => seeking = value);
        },
      ),
    ],
  );
}

class SeekBar extends StatelessWidget {
  const SeekBar(this.p, {super.key, this.onSeeking});
  final LibraryController p;
  final ValueChanged<bool>? onSeeking;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Duration>(
    valueListenable: p.playhead,
    builder: (context, _, _) => buildProgress(context),
  );

  Widget buildProgress(BuildContext context) {
    final duration =
            p.playback.player.duration ??
            Duration(seconds: p.current?.duration ?? 0),
        max = duration.inMilliseconds.toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Slider(
          value: p.position.inMilliseconds.toDouble().clamp(
            0,
            max > 0 ? max : 1,
          ),
          max: max > 0 ? max : 1,
          onChangeStart: max > 0 ? (_) => onSeeking?.call(true) : null,
          onChangeEnd: max > 0 ? (_) => onSeeking?.call(false) : null,
          onChanged: max > 0
              ? (v) => p.playback.seek(Duration(milliseconds: v.round()))
              : null,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              clock(p.position),
              style: TextStyle(fontSize: 10, color: context.tokens.muted),
            ),
            Text(
              clock(duration),
              style: TextStyle(fontSize: 10, color: context.tokens.muted),
            ),
          ],
        ),
      ],
    );
  }
}

class RecordCarousel extends StatefulWidget {
  const RecordCarousel(this.p, {super.key, required this.size});
  final LibraryController p;
  final double size;
  @override
  State<RecordCarousel> createState() => _RecordCarouselState();
}

class _RecordCarouselState extends State<RecordCarousel> {
  double drag = 0;
  Future<void> change(int delta) async {
    if (!widget.p.opening && widget.p.adjacentTrack(delta) != null) {
      await widget.p.next(delta);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p, size = widget.size;
    final previous = p.adjacentTrack(-1), next = p.adjacentTrack(1);
    return Semantics(
      label: '歌曲封面，左右滑动切歌',
      onIncrease: next == null ? null : () => change(1),
      onDecrease: previous == null ? null : () => change(-1),
      child: GestureDetector(
        key: const ValueKey('record-carousel'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => drag = 0,
        onHorizontalDragUpdate: (details) =>
            setState(() => drag += details.delta.dx),
        onHorizontalDragCancel: () => setState(() => drag = 0),
        onHorizontalDragEnd: (details) {
          final distance = drag;
          setState(() => drag = 0);
          if (distance.abs() >= TingyuTokens.swipeThreshold ||
              details.velocity.pixelsPerSecond.dx.abs() > 400) {
            change(
              (distance == 0 ? details.velocity.pixelsPerSecond.dx : distance) <
                      0
                  ? 1
                  : -1,
            );
          }
        },
        child: LayoutBuilder(
          builder: (context, box) {
            final center = (box.maxWidth - size) / 2;
            final peek = (size * (1 - TingyuTokens.recordPeek) / 2);
            final previousLeft = -size + size * .1 + peek;
            final nextLeft = box.maxWidth - size * .1 - peek;
            final offset = drag.clamp(-size * .2, size * .2);
            Widget record(Track track, double left, bool active) => Positioned(
              key: ValueKey(active ? 'record-current' : 'record-preview-$left'),
              left: left + offset,
              top: TingyuTokens.space,
              child: Opacity(
                opacity: active ? 1 : .6,
                child: Transform.scale(
                  scale: active ? 1 : TingyuTokens.recordPeek,
                  child: RecordDisc(
                    track,
                    size: size,
                    playing: active && p.playing,
                  ),
                ),
              ),
            );
            return ClipRect(
              child: SizedBox(
                height: size + TingyuTokens.space * 2,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (previous != null) record(previous, previousLeft, false),
                    if (next != null) record(next, nextLeft, false),
                    record(p.current!, center, true),
                  ],
                ),
              ),
            );
          },
        ),
      ),
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
    final phoneArtMax = (width * TingyuTokens.recordDiameterRatio).clamp(
      180.0,
      340.0,
    );
    final meta = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: desktop
                          ? 0
                          : MediaQuery.textScalerOf(context).scale(23) * 2.7,
                    ),
                    child: Text(
                      track.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: desktop ? null : 23,
                        height: 1.35,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          track.artist,
                          style: TextStyle(color: context.tokens.muted),
                        ),
                      ),
                    ],
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
    final art = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: RecordDisc(
            track,
            size: desktop ? 360 : phoneArtMax,
            playing: p.playing,
          ),
        ),
        const SizedBox(height: 24),
        meta,
      ],
    );
    final lyrics = desktop
        ? SizedBox(
            height: 280,
            child: p.showPlayerLyrics ? LyricPanel(p) : const SizedBox.shrink(),
          )
        : null;
    final screen = Scaffold(
      backgroundColor: desktop ? null : Colors.transparent,
      appBar: PlayerHeader(
        onBack: goBack,
        status: p.opening
            ? '正在加载…'
            : (desktop
                  ? ''
                  : '正在播放 · ${p.queue.indexOf(track.id) + 1} / ${p.queue.length}'),
        transparent: !desktop,
        onMore: () =>
            showTrackActions(context, p, track, null, includeVolume: true),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      PlaybackTool(p, timer: false),
                      PlaybackTool(p, timer: true),
                    ],
                  ),
                  PlayerProgress(p),
                  transport(context, p),
                  Padding(
                    padding: const EdgeInsets.only(top: TingyuTokens.space / 2),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: TingyuTokens.space * 4,
                      children: [
                        LyricVisibilityControl(p),
                        labelButton('展开歌词 ›', () => context.push('/lyrics')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: desktop
            ? SingleChildScrollView(
                key: const ValueKey('player-content'),
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    if (p.error.isNotEmpty)
                      errorBox(
                        context,
                        p.error,
                        () => p.play(track, at: p.position),
                      ),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: art),
                            const SizedBox(width: 80),
                            Expanded(child: lyrics!),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : LayoutBuilder(
                builder: (context, box) {
                  final lyricExtent = detailLyricExtent(
                    context,
                    p,
                    box.maxWidth - 48,
                  );
                  final lyricHeight = math.max(144.0, lyricExtent + 40);
                  // Budget for the focused line, rather than reserving the whole timeline.
                  final lyricVisible =
                      lyricHeight / 2 +
                      (p.lines.isEmpty
                          ? MediaQuery.textScalerOf(context).scale(16)
                          : lyricExtent / 2 +
                                (p.lyricSource.startsWith('bilibili-')
                                    ? MediaQuery.textScalerOf(context).scale(14)
                                    : 0));
                  Widget recordAndMeta() => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (p.error.isNotEmpty)
                        errorBox(
                          context,
                          p.error,
                          () => p.play(track, at: p.position),
                        ),
                      RecordCarousel(
                        p,
                        size: math.min(
                          phoneArtMax,
                          math.max(
                            100,
                            box.maxHeight -
                                lyricVisible -
                                TingyuTokens.space * 3 -
                                MediaQuery.textScalerOf(context).scale(106),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: meta,
                      ),
                    ],
                  );
                  Widget stableLyrics() => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      height: lyricHeight,
                      child: IgnorePointer(
                        ignoring: !p.showPlayerLyrics,
                        child: ExcludeSemantics(
                          excluding: !p.showPlayerLyrics,
                          child: AnimatedOpacity(
                            opacity: p.showPlayerLyrics ? 1 : 0,
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : TingyuTokens.transition,
                            child: LyricPanel(
                              p,
                              key: ValueKey(
                                'detail-lyrics-${track.id}-${p.lyricText}',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                  return PlayerContentViewport(
                    layoutIdentity:
                        '${track.id}:${track.title}:${p.parts.length}:${p.lyricText}:${p.lyricTranslation}:${p.lyricRomaji}:${p.showLyricTranslation}:${p.showLyricRomaji}:${p.lyricSource}:${box.maxWidth}:${box.maxHeight}:${MediaQuery.textScalerOf(context)}',
                    child: Column(children: [recordAndMeta(), stableLyrics()]),
                  );
                },
              ),
      ),
    );
    return desktop ? screen : DetailAtmosphere(child: screen);
  }
}

/// Start with the whole record visible; constrained content scrolls from the top.
class PlayerContentViewport extends StatefulWidget {
  const PlayerContentViewport({
    super.key,
    required this.child,
    required this.layoutIdentity,
  });
  final Widget child;
  final String layoutIdentity;
  @override
  State<PlayerContentViewport> createState() => _PlayerContentViewportState();
}

class _PlayerContentViewportState extends State<PlayerContentViewport> {
  final scroll = ScrollController();
  String? fitted;
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (fitted != widget.layoutIdentity) {
      fitted = widget.layoutIdentity;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.jumpTo(0);
        }
      });
    }
    return SingleChildScrollView(
      key: const ValueKey('player-content'),
      controller: scroll,
      child: widget.child,
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
    this.transparent = false,
  });
  final bool transparent;
  final VoidCallback onBack;
  final String status;
  final VoidCallback? onMore;
  @override
  Size get preferredSize => const Size.fromHeight(64);
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: transparent ? Colors.transparent : context.tokens.background,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            action(Icons.arrow_back, '返回', onBack),
            const SizedBox(width: 12),
            Expanded(
              child: Consumer(
                builder: (context, ref, _) => ValueListenableBuilder<String?>(
                  valueListenable: ref.watch(libraryProvider).modeNotice,
                  builder: (context, notice, _) => Semantics(
                    liveRegion: notice != null,
                    child: PlayerHeaderStatus(
                      status: notice ?? status,
                      mode: ref.watch(libraryProvider).mode,
                      hold: notice != null,
                    ),
                  ),
                ),
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

class PlayerHeaderStatus extends StatefulWidget {
  const PlayerHeaderStatus({
    super.key,
    required this.status,
    required this.mode,
    required this.hold,
  });
  final String status, mode;
  final bool hold;
  @override
  State<PlayerHeaderStatus> createState() => _PlayerHeaderStatusState();
}

double detailLyricExtent(
  BuildContext context,
  LibraryController p,
  double width,
) {
  double measured(String text, double size, FontWeight weight) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, height: 1.45, fontWeight: weight),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: math.max(1, width));
    final height = painter.height;
    painter.dispose();
    return height;
  }

  var extent = 48.0;
  for (final line in p.lines) {
    final height =
        measured(line.text, 19, FontWeight.w600) +
        TingyuTokens.space * 2 +
        (p.showLyricTranslation && line.translation.isNotEmpty
            ? measured(line.translation, 12, FontWeight.normal)
            : 0) +
        (p.showLyricRomaji && line.romaji.isNotEmpty
            ? measured(line.romaji, 11, FontWeight.normal)
            : 0);
    extent = math.max(extent, height);
  }
  return extent;
}

class LyricPanel extends StatefulWidget {
  const LyricPanel(this.p, {super.key});
  final LibraryController p;
  @override
  State<LyricPanel> createState() => _LyricPanelState();
}

class _LyricPanelState extends State<LyricPanel> {
  final scroll = ScrollController();
  String measuredKey = '';
  double measuredExtent = 48;
  int last = -1;
  int? pending;
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Duration>(
    valueListenable: widget.p.playhead,
    builder: (context, _, _) => LayoutBuilder(
      builder: (context, box) => buildLyrics(context, box.maxWidth),
    ),
  );

  void alignLyric(int index, double extent, {bool retried = false}) {
    final previous = last;
    pending = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients || pending != index) return;
      final metrics = scroll.position;
      if (metrics.viewportDimension == 0 && !retried) {
        alignLyric(index, extent, retried: true);
        return;
      }
      last = index;
      pending = null;
      final target = centeredLyricOffset(
        index: index,
        lineExtent: extent,
        viewport: metrics.viewportDimension,
        maxScroll: metrics.maxScrollExtent,
        padding: math.max(12, (metrics.viewportDimension - extent) / 2),
      );
      if ((metrics.pixels - target).abs() < 1) return;
      final jump =
          previous < 0 ||
          (index - previous).abs() > 1 ||
          MediaQuery.disableAnimationsOf(context);
      if (jump) {
        metrics.jumpTo(target);
      } else {
        unawaited(
          metrics.animateTo(
            target,
            duration: TingyuTokens.scrollReturn,
            curve: Curves.easeOut,
          ),
        );
      }
    });
  }

  Widget buildLyrics(BuildContext context, double width) {
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
    final index = focusedLyricLine(
      lines,
      p.position.inMilliseconds + p.lyricOffset,
    );
    final key =
        '${p.lyricText}:${p.lyricTranslation}:${p.lyricRomaji}:${p.showLyricTranslation}:${p.showLyricRomaji}:$width:${MediaQuery.textScalerOf(context)}';
    if (key != measuredKey) {
      measuredKey = key;
      measuredExtent = detailLyricExtent(context, p, width);
      last = -1;
      pending = null;
    }
    final extent = measuredExtent;
    if (index != last && pending != index) alignLyric(index, extent);
    return Column(
      children: [
        if (p.lyricSource.startsWith('bilibili-'))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              p.lyricSource == 'bilibili-ai-subtitle' ? 'B 站 AI 字幕' : 'B 站字幕',
              style: TextStyle(fontSize: 10, color: context.tokens.muted),
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => ListView.builder(
              controller: scroll,
              itemCount: lines.length,
              itemExtent: extent,
              padding: EdgeInsets.symmetric(
                vertical: math.max(12, (box.maxHeight - extent) / 2),
              ),
              itemBuilder: (ctx, i) {
                final line = lines[i];
                final active = i == index;
                final secondary =
                    active &&
                    ((p.showLyricTranslation && line.translation.isNotEmpty) ||
                        (p.showLyricRomaji && line.romaji.isNotEmpty));
                final style = TextStyle(
                  color: active
                      ? context.tokens.accentInk
                      : context.tokens.muted,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  fontSize: active ? 19 : 14,
                  height: 1.45,
                );
                final main = LyricWordLine(
                  line: line,
                  milliseconds: p.position.inMilliseconds + p.lyricOffset,
                  style: style,
                  sung: context.tokens.accentInk,
                  unsung: context.tokens.muted,
                  animate: active && !MediaQuery.disableAnimationsOf(context),
                  maxLines: null,
                );
                if (!secondary) return Center(child: main);
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      main,
                      if (p.showLyricTranslation && line.translation.isNotEmpty)
                        Text(
                          line.translation,
                          textAlign: TextAlign.center,

                          style: TextStyle(
                            color: context.tokens.muted,
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      if (p.showLyricRomaji && line.romaji.isNotEmpty)
                        Text(
                          line.romaji,
                          textAlign: TextAlign.center,

                          style: TextStyle(
                            color: context.tokens.muted,
                            fontSize: 11,
                            height: 1.45,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> showQueue(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: context.tokens.background,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(TingyuTokens.sheetRadius),
    ),
  ),
  builder: (_) => const QueuePanel(),
);

class QueuePanel extends ConsumerStatefulWidget {
  const QueuePanel({super.key});
  @override
  ConsumerState<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends ConsumerState<QueuePanel> {
  late final ScrollController scroll;
  @override
  void initState() {
    super.initState();
    final p = ref.read(libraryProvider);
    final index = p.queue.indexOf(p.current?.id ?? '');
    scroll = ScrollController(
      initialScrollOffset: (index < 0 ? 0 : index) * rowHeight,
    );
  }

  List<String>? dragOrder;
  String? located;
  bool initialized = false;
  static const rowHeight = 72.0;

  void locate(LibraryController p) {
    final index = p.queue.indexOf(p.current?.id ?? '');
    if (index < 0 || !scroll.hasClients) return;
    final target =
        (index * rowHeight -
                (scroll.position.viewportDimension - rowHeight) / 2)
            .clamp(0.0, scroll.position.maxScrollExtent);
    scroll.jumpTo(target);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(libraryProvider), t = context.tokens;
    if (!initialized || located != p.current?.id) {
      initialized = true;
      located = p.current?.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) locate(ref.read(libraryProvider));
      });
    }
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('播放队列 · ${p.queue.length} 首'),
                        const SizedBox(height: 4),
                        Text(
                          '长按歌曲或拖动手柄排序',
                          style: TextStyle(fontSize: 11, color: t.muted),
                        ),
                      ],
                    ),
                  ),
                  action(
                    Icons.my_location,
                    '定位当前歌曲',
                    p.queue.contains(p.current?.id) ? () => locate(p) : null,
                  ),
                  action(
                    Icons.more_horiz,
                    '队列更多',
                    () => showContentActions(
                      context,
                      (ctx) => SimpleDialog(
                        title: const Text('播放队列'),
                        children: [
                          labelButton('清空', () async {
                            Navigator.pop(ctx);
                            if (await confirm(context, '清空队列并停止播放？')) {
                              await p.clearQueue();
                            }
                          }),
                        ],
                      ),
                    ),
                  ),
                  action(
                    Icons.keyboard_arrow_down,
                    '关闭队列',
                    () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: p.queue.isEmpty
                  ? const EmptyView('队列是空的', '从搜索结果添加下一首声音。')
                  : ScrollToTop(
                      controller: scroll,
                      builder: (controller) => ReorderableListView.builder(
                        key: const ValueKey('queue-list'),
                        scrollController: controller,
                        buildDefaultDragHandles: false,
                        itemExtent: rowHeight,
                        padding: const EdgeInsets.only(
                          bottom: TingyuTokens.space * 10,
                        ),
                        itemCount: p.queue.length,
                        onReorderStart: (_) => dragOrder = List.of(p.queue),
                        onReorderItem: (oldIndex, newIndex) {
                          final snapshot = List<String>.of(
                            dragOrder ?? p.queue,
                          );
                          if (oldIndex < 0 || oldIndex >= snapshot.length) {
                            return;
                          }
                          final id = snapshot.removeAt(oldIndex);
                          final before = newIndex < snapshot.length
                              ? snapshot[newIndex]
                              : null;
                          unawaited(
                            report(context, () => p.reorderQueue(id, before)),
                          );
                        },
                        proxyDecorator: (child, _, animation) => Material(
                          color: t.tint,
                          borderRadius: BorderRadius.circular(
                            TingyuTokens.radius,
                          ),
                          child: child,
                        ),
                        itemBuilder: (context, i) {
                          final track = p.library[p.queue[i]]!,
                              current = track.id == p.current?.id;
                          return ReorderableDelayedDragStartListener(
                            key: ValueKey('queue-row-${track.id}'),
                            index: i,
                            child: ColoredBox(
                              color: current ? t.tint : t.background,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 28,
                                    child: current
                                        ? Center(
                                            child: PlayingIndicator(
                                              playing:
                                                  p.playing &&
                                                  p
                                                          .playback
                                                          .player
                                                          .processingState ==
                                                      ProcessingState.ready,
                                            ),
                                          )
                                        : null,
                                  ),
                                  Expanded(
                                    child: Pressable(
                                      key: ValueKey('queue-track-${track.id}'),
                                      label:
                                          '${current ? '当前歌曲，' : ''}${track.title}',
                                      selected: current,
                                      selectionFill: false,
                                      onPressed: () => report(
                                        context,
                                        () => current
                                            ? p.toggle()
                                            : p.play(track),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: TingyuTokens.space / 2,
                                        vertical: TingyuTokens.space,
                                      ),
                                      child: Row(
                                        children: [
                                          Artwork(track, size: 40),
                                          const SizedBox(
                                            width: TingyuTokens.space * 1.5,
                                          ),
                                          Expanded(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  track.title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: current
                                                        ? t.accent
                                                        : t.text,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                const SizedBox(
                                                  height:
                                                      TingyuTokens.space / 2,
                                                ),
                                                Text(
                                                  track.artist,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: t.muted,
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
                                  action(
                                    Icons.more_horiz,
                                    '队列选项 ${track.id}',
                                    () async {
                                      await showQueueTrackActions(
                                        context,
                                        p,
                                        track.id,
                                      );
                                      if (mounted &&
                                          p.current?.id == track.id) {
                                        locate(p);
                                      }
                                    },
                                  ),
                                  Semantics(
                                    label: '拖动调整 ${track.title}',
                                    customSemanticsActions: {
                                      if (i > 0)
                                        const CustomSemanticsAction(
                                          label: '上移',
                                        ): () =>
                                            unawaited(p.moveQueue(i, -1)),
                                      if (i < p.queue.length - 1)
                                        const CustomSemanticsAction(
                                          label: '下移',
                                        ): () =>
                                            unawaited(p.moveQueue(i, 1)),
                                    },
                                    child: ReorderableDragStartListener(
                                      index: i,
                                      child: SizedBox.square(
                                        key: ValueKey('queue-drag-${track.id}'),
                                        dimension: TingyuTokens.controlSize,
                                        child: Center(
                                          child: TingyuIcon(
                                            Icons.drag_indicator,
                                            color: t.muted,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class DownloadsPanel extends StatelessWidget {
  const DownloadsPanel(
    this.p, {
    super.key,
    this.query = '',
    this.sliver = false,
    this.showTasks = false,
  });
  final bool sliver, showTasks;
  final LibraryController p;
  final String query;
  @override
  Widget build(BuildContext context) {
    final active = p.downloads.incompleteTasks
        .where((d) => matchesLocal(d.track, query))
        .toList();
    final done = p.downloads.completedTasks
        .where((d) => matchesLocal(d.track, query))
        .toList();
    final tasks = showTasks ? active : done;
    if (tasks.isEmpty) {
      final empty = query.trim().isNotEmpty
          ? const EmptyView('没有匹配的歌曲', '试试其他歌名或 UP 主。')
          : showTasks
          ? const EmptyView('没有下载任务', '新任务会显示在这里。')
          : const EmptyView('还没有下载', '点击歌曲或歌单的下载图标。');
      return sliver ? SliverToBoxAdapter(child: empty) : empty;
    }
    final bytes = done.fold<int>(0, (v, d) => v + d.received);
    final children = <WidgetBuilder>[
      if (!showTasks)
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: TingyuTokens.space * 2),
          child: Text(
            '${done.length} 首 · ${(bytes / 1024 / 1024).toStringAsFixed(1)} MB',
            style: TextStyle(color: context.tokens.muted, fontSize: 11),
          ),
        ),
      for (final d in tasks)
        (_) => Container(
          key: ValueKey('download-row-${d.track.id}'),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.tokens.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Pressable(
                  key: ValueKey('play-downloaded-${d.track.id}'),
                  label: '播放已下载歌曲 ${d.track.title}',
                  onPressed: d.status == DownloadStatus.completed
                      ? () => p.playDownloaded(d.track)
                      : () => showDownloadActions(context, p, d),
                  padding: const EdgeInsets.symmetric(
                    vertical: TingyuTokens.space * 1.5,
                  ),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          Artwork(d.track),
                          if (p.current?.id == d.track.id)
                            Positioned(
                              right: TingyuTokens.downloadBadgeInset,
                              bottom: TingyuTokens.downloadBadgeInset,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  TingyuTokens.downloadBadgeRadius,
                                ),
                                child: BackdropFilter(
                                  filter: ui.ImageFilter.blur(
                                    sigmaX: TingyuTokens.glassBlur,
                                    sigmaY: TingyuTokens.glassBlur,
                                  ),
                                  child: Container(
                                    key: ValueKey(
                                      'download-playing-${d.track.id}',
                                    ),
                                    width: TingyuTokens.downloadBadgeSize,
                                    height: TingyuTokens.downloadBadgeSize,
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: context.tokens.downloadBadgeFill,
                                      borderRadius: BorderRadius.circular(
                                        TingyuTokens.downloadBadgeRadius,
                                      ),
                                      border: Border.all(
                                        color: context.tokens.downloadBadgeEdge,
                                        width: .5,
                                      ),
                                    ),
                                    child: PlayingIndicator(
                                      color: TingyuTokens.onArtwork,
                                      playing:
                                          p.playing &&
                                          p.playback.player.processingState ==
                                              ProcessingState.ready,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: TingyuTokens.space * 1.5),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.tokens.text,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: TingyuTokens.space / 2),
                            Text(
                              d.error ??
                                  switch (d.status) {
                                    DownloadStatus.completed => d.track.artist,
                                    DownloadStatus.waiting => '等待下载',
                                    DownloadStatus.downloading =>
                                      '下载中 · ${d.progress == null ? '未知大小' : '${(d.progress! * 100).round()}%'}',
                                    DownloadStatus.failed => '下载失败',
                                    DownloadStatus.paused => '下载已中断，点击重试',
                                  },
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.tokens.muted,
                                fontSize: 12,
                              ),
                            ),
                            if (d.status == DownloadStatus.downloading)
                              LinearProgressIndicator(value: d.progress),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (d.status == DownloadStatus.completed) ...[
                action(
                  Icons.more_horiz,
                  '下载选项 ${d.track.title}',
                  () => showDownloadActions(context, p, d),
                ),
              ] else ...[
                if (d.status == DownloadStatus.downloading ||
                    d.status == DownloadStatus.waiting)
                  action(Icons.pause, '暂停下载', () => p.downloads.pause(d))
                else
                  action(
                    d.status == DownloadStatus.paused
                        ? Icons.play_arrow
                        : Icons.refresh,
                    d.status == DownloadStatus.paused ? '继续下载' : '重试下载',
                    () => p.downloads.retry(d),
                  ),
                action(Icons.delete_outline, '移除下载', () => p.removeDownload(d)),
              ],
            ],
          ),
        ),
    ];
    return sliver
        ? SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => children[i](context),
              childCount: children.length,
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children.map((build) => build(context)).toList(),
          );
  }
}

Future<void> showDownloadActions(
  BuildContext context,
  LibraryController p,
  DownloadTask task,
) => showContentActions(
  context,
  (ctx) => SimpleDialog(
    title: Text(task.track.title),
    children: [
      labelButton('导出歌曲', () async {
        Navigator.pop(ctx);
        await report(context, () => exportTrack(context, p, task));
      }, icon: Icons.ios_share_outlined),
      if ([
        DownloadLyricStatus.missing,
        DownloadLyricStatus.failed,
      ].contains(task.lyricStatus))
        labelButton('补全歌词', () async {
          Navigator.pop(ctx);
          await p.downloads.retryLyrics(task);
        }, icon: Icons.lyrics_outlined),
      labelButton('移除下载', () async {
        Navigator.pop(ctx);
        if (await confirm(context, '删除音频和离线资料？歌单与喜欢记录会保留。')) {
          await p.removeDownload(task);
        }
      }, icon: Icons.delete_outline),
    ],
  ),
);

Future<void> exportTrack(
  BuildContext context,
  LibraryController p,
  DownloadTask task,
) async {
  final audio = await p.downloads.availablePath(task.track);
  if (audio == null) throw const AppFailure('下载文件已丢失，请重新下载');
  final coverFile = p.downloads.coverFile(task.track);
  final cover = await coverFile.exists()
      ? coverFile
      : await p.downloads.covers.get(task.track.cover);
  final document = await p.downloads.lyricDocument(task.track);
  final rawLyrics = document?['lrc'] as String?;
  final offset = document?['offset'] as int? ?? 0;
  final lyrics = rawLyrics == null || rawLyrics.trim().isEmpty
      ? null
      : offset == 0
      ? rawLyrics
      : '[offset:$offset]\n$rawLyrics';
  final exporter = MediaExporter();
  if (!context.mounted) return;
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('正在准备导出'),
          content: LinearProgressIndicator(),
        ),
      ),
    ),
  );
  late PreparedExport prepared;
  try {
    prepared = await exporter.prepare(
      audio: File(audio),
      track: task.track,
      directory: Directory('${p.downloads.directory.path}/exports'),
      cover: cover,
      lyrics: lyrics,
    );
  } finally {
    if (context.mounted) navigator.pop();
  }
  try {
    if (!context.mounted) return;
    final path = await exporter.save(prepared, task.track.title);
    if (path == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('已导出'),
        content: Text(
          'M4A · ${prepared.hasCover ? '封面' : '无封面'} · ${prepared.hasLyrics ? '内嵌歌词' : '未匹配到歌词'}',
        ),
        actions: [labelButton('完成', () => Navigator.pop(ctx))],
      ),
    );
  } finally {
    await prepared.file.parent.delete(recursive: true);
  }
}

Future<void> showAboutTingyu(BuildContext context) => showContentActions(
  context,
  (ctx) => SimpleDialog(
    title: Row(children: [const Expanded(child: Text('关于 tingyu'))]),
    children: [
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Image.asset(
              'assets/branding/ribbon-outline.png',
              width: 64,
              height: 64,
              color: ctx.tokens.accent,
              semanticLabel: 'tingyu 应用图标',
            ),
            const SizedBox(height: 16),
            const Text(
              'tingyu',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text('版本 $tingyuVersion'),
            const SizedBox(height: 24),
            Text(
              '音乐与下载保存在本机\n账号凭据由系统安全存储保护',
              textAlign: TextAlign.center,
              style: TextStyle(color: ctx.tokens.muted, height: 1.8),
            ),
          ],
        ),
      ),
    ],
  ),
);

Future<void> showQueueTrackActions(
  BuildContext context,
  LibraryController p,
  String id,
) => showContentActions(context, (ctx) {
  final i = p.queue.indexOf(id);
  return SimpleDialog(
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          p.library[id]?.title ?? '歌曲操作',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: TingyuTokens.space),
        Text(
          '队列第 ${i + 1} 首',
          style: TextStyle(fontSize: 12, color: ctx.tokens.muted),
        ),
      ],
    ),
    children: [
      labelButton(
        '移至下一首',
        i >= 0 && id != p.current?.id
            ? () async {
                Navigator.pop(ctx);
                final track = p.library[id];
                if (track != null) await p.enqueue(track, next: true);
              }
            : null,
        icon: Icons.playlist_play,
      ),
      labelButton(
        '上移一位',
        i > 0
            ? () async {
                Navigator.pop(ctx);
                final index = p.queue.indexOf(id);
                if (index > 0) await p.moveQueue(index, -1);
              }
            : null,
        icon: Icons.arrow_upward,
      ),
      labelButton(
        '下移一位',
        i >= 0 && i < p.queue.length - 1
            ? () async {
                Navigator.pop(ctx);
                final index = p.queue.indexOf(id);
                if (index >= 0) await p.moveQueue(index, 1);
              }
            : null,
        icon: Icons.arrow_downward,
      ),
      labelButton('从队列移除', () async {
        Navigator.pop(ctx);
        await p.removeQueue(id);
      }, icon: Icons.remove_circle_outline),
    ],
  );
});

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
  const AccountPanel(this.p, {super.key, this.standalone = false});
  final LibraryController p;
  final bool standalone;
  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  String? qr, key;
  String message = '扫码后可以导入你的 B 站收藏夹';
  bool busy = false, polling = false;
  Map<String, dynamic>? selectedFolder;
  final selectedFolders = <int>{};
  final folderSearch = TextEditingController();
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
    folderSearch.dispose();
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
          selectedFolders.clear();
        });
        return;
      }
      final found = await widget.p.api.folders(widget.p.profile!['mid']);
      if (mounted) {
        setState(() {
          folders = found;
          selectedFolder = null;
          selectedFolders.clear();
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
      Playlist? result;
      final chosen = folders
          .where((f) => selectedFolders.contains(f['id']))
          .toList();
      for (final item in chosen.isEmpty ? [folder] : chosen) {
        result = await widget.p.importFolder(item);
        selectedFolders.remove(item['id']);
      }
      if (result == null) return;
      final importedResult = result;
      if (mounted) {
        setState(() {
          imported = importedResult;
          message =
              '已导入 ${importedResult.trackIds.length} 首到「${importedResult.name}」';
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

  Future<void> generate({bool openApp = true}) async {
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
      if (openApp) {
        final opened = await BilibiliLinkLauncher().openLogin(
          Uri.parse(result.url),
        );
        if (!mounted) return;
        setState(
          () => message = opened
              ? '已打开登录链接，请完成 B 站确认；返回后自动检查登录状态'
              : '未能打开登录链接，请使用二维码扫码',
        );
      }
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
    final visibleFolders = folders
        .where((f) => matchesFolderName('${f['title']}', folderSearch.text))
        .toList();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (widget.standalone)
                action(
                  Icons.arrow_back,
                  '返回设置',
                  () => context.canPop()
                      ? context.pop()
                      : context.go('/settings'),
                ),
              const Expanded(
                child: Text(
                  '账号与收藏',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
              if (!widget.standalone)
                action(
                  Icons.keyboard_arrow_down,
                  '关闭账号窗口',
                  () => Navigator.pop(context),
                ),
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
                      '选择收藏夹，导入为本地歌单。',
                      style: TextStyle(color: context.tokens.muted),
                    ),
                    const SizedBox(height: 16),
                    if (!busy && folders.isEmpty) const Text('暂无可导入的收藏夹。'),
                    TextField(
                      controller: folderSearch,
                      decoration: const InputDecoration(hintText: '查找收藏夹'),
                      onChanged: (_) => setState(() {}),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${folderSearch.text.trim().isEmpty ? '我的收藏夹' : '匹配结果'} · ${folders.where((f) => matchesFolderName('${f['title']}', folderSearch.text)).length}',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.tokens.muted,
                            ),
                          ),
                        ),
                        labelButton(
                          '全选',
                          busy
                              ? null
                              : () => setState(() {
                                  final visible = folders.where(
                                    (f) => matchesFolderName(
                                      '${f['title']}',
                                      folderSearch.text,
                                    ),
                                  );
                                  if (visible.every(
                                    (f) => selectedFolders.contains(f['id']),
                                  )) {
                                    selectedFolders.removeAll(
                                      visible.map((f) => f['id'] as int),
                                    );
                                  } else {
                                    selectedFolders.addAll(
                                      visible.map((f) => f['id'] as int),
                                    );
                                  }
                                  selectedFolder = folders
                                      .where(
                                        (f) =>
                                            selectedFolders.contains(f['id']),
                                      )
                                      .firstOrNull;
                                }),
                        ),
                      ],
                    ),
                    for (final folder in folders.where(
                      (f) =>
                          matchesFolderName('${f['title']}', folderSearch.text),
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 0),
                        child: FolderChoice(
                          folder: folder,
                          first:
                              visibleFolders.isNotEmpty &&
                              identical(folder, visibleFolders.first),
                          last:
                              visibleFolders.isNotEmpty &&
                              identical(folder, visibleFolders.last),
                          selected: selectedFolders.contains(folder['id']),
                          onSelect: busy
                              ? null
                              : () => setState(() {
                                  if (!selectedFolders.add(
                                    folder['id'] as int,
                                  )) {
                                    selectedFolders.remove(folder['id']);
                                  }
                                  selectedFolder = folders
                                      .where(
                                        (f) =>
                                            selectedFolders.contains(f['id']),
                                      )
                                      .firstOrNull;
                                  imported = null;
                                  message = '';
                                }),
                        ),
                      ),
                    if (!busy &&
                        folders.isNotEmpty &&
                        !folders.any(
                          (f) => matchesFolderName(
                            '${f['title']}',
                            folderSearch.text,
                          ),
                        ))
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('没有匹配的收藏夹'),
                      ),
                    if (!busy)
                      labelButton('刷新收藏夹', loadProfile, icon: Icons.refresh),
                    labelButton(
                      '退出账号',
                      busy
                          ? null
                          : () async {
                              if (!await confirm(
                                context,
                                '退出账号？本地歌曲、歌单和下载会保留。',
                              )) {
                                return;
                              }
                              await p.logout();
                              if (!mounted) return;
                              setState(() {
                                folders = [];
                                selectedFolder = null;
                                selectedFolders.clear();
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
                      labelButton('使用二维码', () => generate(openApp: false)),
                    if (!busy)
                      labelButton(
                        qr == null ? '登录' : '刷新二维码',
                        () => generate(),
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
                ? Pressable(
                    key: const ValueKey('import-folders'),
                    label: busy
                        ? '正在导入或加载'
                        : selectedFolder == null
                        ? '选择收藏夹'
                        : '导入 ${selectedFolders.length} 个收藏夹',
                    color: busy || selectedFolder == null
                        ? context.tokens.tint
                        : context.tokens.accent,
                    onPressed: busy || selectedFolder == null
                        ? null
                        : importSelected,
                    child: Center(
                      child: Text(
                        busy
                            ? '正在导入或加载…'
                            : selectedFolder == null
                            ? '选择收藏夹'
                            : '导入 ${selectedFolders.length} 个收藏夹',
                        style: TextStyle(
                          color: busy || selectedFolder == null
                              ? context.tokens.muted
                              : context.tokens.onAccent,
                        ),
                      ),
                    ),
                  )
                : labelButton('查看已导入歌单', () {
                    final router = GoRouter.of(context), id = imported!.id;
                    Navigator.pop(context);
                    router.go('/playlist/$id');
                  }, icon: Icons.featured_play_list_outlined),
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
    this.first = false,
    this.last = false,
  });
  final bool first, last;
  final Map<String, dynamic> folder;
  final bool selected;
  final VoidCallback? onSelect;
  @override
  Widget build(BuildContext context) => SelectionSurface(
    first: first,
    last: last,
    child: Pressable(
      key: ValueKey('folder-${folder['id']}'),
      selectionFill: false,
      selected: selected,
      onPressed: onSelect,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.tokens.tint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(child: TingyuIcon(Icons.folder_outlined)),
          ),
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
          const SizedBox(width: 12),
          TingyuIcon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? context.tokens.accent : context.tokens.muted,
          ),
        ],
      ),
    ),
  );
}

Future<void> showLyrics(BuildContext context, LibraryController p) async {
  final track = p.current;
  if (track == null) return;
  final section = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    backgroundColor: context.tokens.surface,
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '歌词',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            for (final entry in [
              ('display', '显示与排版'),
              ('match', '匹配歌词'),
              ('edit', '编辑歌词'),
              ('offset', '时间偏移'),
            ])
              labelButton(entry.$2, () => Navigator.pop(ctx, entry.$1)),
          ],
        ),
      ),
    ),
  );
  if (section == null || !context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => LyricsPreferencesPage(p, track, section: section),
    ),
  );
}

/// Persistent, fixed-width destinations avoid layout movement while switching.
class CompactNavigation extends StatelessWidget {
  const CompactNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
    this.controller,
  });
  final LibraryController? controller;
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
    Widget surface(Widget child) => controller == null
        ? GlassSurface(child: child)
        : AdaptiveGlass(p: controller!, navigation: true, child: child);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: surface(
        Padding(
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
                        selectionFill: false,
                        onPressed: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          onSelect(item.$1);
                        },
                        radius: 28,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 10,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TingyuIcon(
                              selected == item.$1
                                  ? switch (item.$1) {
                                      'library' => Icons.library_music,
                                      'downloads' => Icons.download_rounded,
                                      'likes' => Icons.favorite_rounded,
                                      _ => item.$2,
                                    }
                                  : item.$2,
                              size: 24,
                              color: selected == item.$1 ? t.accent : t.muted,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.$3,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: selected == item.$1
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: selected == item.$1 ? t.text : t.muted,
                              ),
                            ),
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

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.profile, this.size = 48});
  final Map<String, dynamic>? profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final raw = profile?['face'];
    final url = raw is String ? raw.trim() : '';
    final uri = Uri.tryParse(url.startsWith('//') ? 'https:$url' : url);
    final valid =
        uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
    final fallback = ColoredBox(
      color: context.tokens.tint,
      child: Center(
        child: TingyuIcon(
          Icons.person_rounded,
          color: context.tokens.accent,
          size: size * .6,
        ),
      ),
    );
    return ExcludeSemantics(
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: valid
              ? Image.network(
                  uri.toString(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : fallback,
                )
              : fallback,
        ),
      ),
    );
  }
}
