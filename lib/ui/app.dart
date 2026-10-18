import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
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
part 'settings_views.dart';
part 'playlist_add_views.dart';
part 'downloads_views.dart';
part 'search_views.dart';

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
    final label = size * .62;
    final hole = size * .075;
    return RepaintBoundary(
      child: RotationTransition(
        turns: spin,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: TingyuTokens.vinyl,
                  border: Border.all(
                    color: TingyuTokens.onArtwork.withValues(alpha: .16),
                  ),
                ),
              ),
              ClipOval(
                child: SizedBox(
                  width: label,
                  height: label,
                  child: Artwork(widget.track, size: label),
                ),
              ),
              Container(
                width: size * .86,
                height: size * .86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: TingyuTokens.onArtwork.withValues(alpha: .2),
                    width: size * .01,
                  ),
                ),
              ),
              Container(
                width: hole,
                height: hole,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.tokens.background,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (selecting)
              action(
                Icons.arrow_back,
                '退出多选',
                () => setState(() {
                  selecting = false;
                  selection.clear();
                }),
              )
            else if (widget.page == 'search' && widget.playlistId != null)
              action(
                Icons.arrow_back,
                '返回选歌',
                () => context.canPop()
                    ? context.pop()
                    : context.go('/playlist/${widget.playlistId}/add'),
              )
            else if (widget.page == 'playlist')
              action(Icons.arrow_back, '返回音乐库', () => navigate('library')),
            if (!desktop && !selecting && widget.page == 'library')
              Tooltip(
                message: '打开设置',
                child: Pressable(
                  key: const ValueKey('打开设置'),
                  label: '打开设置',
                  padding: const EdgeInsets.all(TingyuTokens.space / 2),
                  radius: TingyuTokens.playerRadius,
                  onPressed: () => context.push('/settings'),
                  child: AccountAvatar(
                    profile: p.profile,
                    size: TingyuTokens.avatarSize,
                  ),
                ),
              ),
            if (!desktop && !selecting && widget.page == 'library')
              const SizedBox(width: TingyuTokens.space),
            Expanded(
              child: Text(
                selecting ? '已选 ${selection.length} 首' : title,
                textAlign: !desktop && !selecting && widget.page == 'library'
                    ? TextAlign.right
                    : TextAlign.left,
                style: widget.page == 'library'
                    ? Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(fontSize: 24)
                    : Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (!selecting && !['search', 'library'].contains(widget.page))
              action(
                Icons.search,
                '搜索本地歌曲',
                () => setState(() {
                  localSearchOpen = !localSearchOpen;
                  if (!localSearchOpen) localSearch.clear();
                }),
              ),
            if (selecting)
              labelButton(
                '全选',
                () => setState(() {
                  final ids = visibleIds(p, list);
                  if (selection.containsAll(ids)) {
                    selection.clear();
                  } else {
                    selection.addAll(ids);
                  }
                }),
              )
            else if (widget.page == 'playlist' && list != null)
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
          if (!selecting && widget.page == 'library')
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
          CollectionToolbar(
            ids: visibleIds(p, list),
            list: list,
            collectionKey: collectionKey,
            compact: widget.page == 'library',
            selecting: selecting,
            onSelect: () => setState(() {
              selecting = true;
              selection.clear();
            }),
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
      canPop: !selecting && widget.page != 'playlist',
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (selecting) {
          setState(() {
            selecting = false;
            selection.clear();
          });
        } else if (widget.page == 'playlist') {
          navigate('library');
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
              body: Builder(
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
                                      tasks: widget.downloadSection == 'tasks',
                                      desktop: desktop,
                                      dockInset: desktop
                                          ? 0
                                          : MediaQuery.paddingOf(
                                              context,
                                            ).bottom,
                                    )
                                  : ScrollToTop(
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
                                                            in content.children)
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
                      if (desktop && selecting)
                        SelectionBar(
                          ids: selection.where(p.library.containsKey).toList(),
                          list: list,
                          onDone: () => setState(() {
                            selecting = false;
                            selection.clear();
                          }),
                        )
                      else if (desktop)
                        RepaintBoundary(child: MiniPlayer(p)),
                    ],
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
                          if (selecting)
                            SelectionBar(
                              ids: selection
                                  .where(p.library.containsKey)
                                  .toList(),
                              list: list,
                              onDone: () => setState(() {
                                selecting = false;
                                selection.clear();
                              }),
                            )
                          else
                            MiniPlayer(p),
                          CompactNavigation(
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
      return (BuildContext _) => selecting
          ? SelectionTrackRow(
              track,
              selected: selection.contains(id),
              onPressed: () => setState(() {
                selection.contains(id)
                    ? selection.remove(id)
                    : selection.add(id);
              }),
            )
          : TrackRow(track, playlist: list, sourceIds: ids);
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
              Text(
                '听屿',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
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
          onPressed: () => context.push('/settings'),
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
            DownloadStatus.completed => '已下载，点击查看',
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
        label: '$label ${track.title}',
        selected: completed,
        selectionFill: false,
        onPressed: preparing ? null : () => report(context, activate),
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
  });
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
        color: p.current?.id == track.id ? context.tokens.tint : null,
        borderRadius: BorderRadius.circular(TingyuTokens.radius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Pressable(
              key: ValueKey('play-${track.id}'),
              label: '播放 ${track.title}',
              onPressed: () => sourceIds == null
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
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          track.artist,
                          maxLines: 1,
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
          if (!desktop && liked)
            Semantics(
              label: '已喜欢',
              child: TingyuIcon(
                Icons.favorite,
                size: 16,
                color: context.tokens.accent,
              ),
            ),
          if (desktop) ...[
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
          if (addToPlaylist != null)
            PlaylistAddTrackAction(track: track, playlist: addToPlaylist!)
          else
            TrackDownloadAction(
              track,
              key: ValueKey('download-action-${track.id}'),
            ),
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
  Playlist? list,
) async {
  await showContentActions(
    context,
    (ctx) => SimpleDialog(
      title: Text(
        track.title,
        maxLines: 2,
        style: const TextStyle(fontSize: 17),
      ),
      children: [
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
        labelButton(
          '在 B 站打开',
          () => launchUrl(
            Uri.parse('https://www.bilibili.com/video/${track.bvid}'),
          ),
          icon: Icons.open_in_new,
        ),
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
          child: GlassSurface(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: Pressable(
                      key: const ValueKey('展开播放器'),
                      label: '展开播放器',
                      onPressed: () => context.push('/player'),
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
  _ => '列表循环',
};
IconData modeIcon(String mode) => switch (mode) {
  'shuffle' => Icons.shuffle,
  'repeat' => Icons.repeat_one,
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
        const modes = ['order', 'repeat', 'shuffle'];
        return p.setMode(modes[(modes.indexOf(p.mode) + 1) % modes.length]);
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

class SeekBar extends StatelessWidget {
  const SeekBar(this.p, {super.key});
  final LibraryController p;
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
    return Row(
      children: [
        Text(
          clock(p.position),
          style: TextStyle(fontSize: 10, color: context.tokens.muted),
        ),
        Expanded(
          child: Slider(
            value: p.position.inMilliseconds.toDouble().clamp(
              0,
              max > 0 ? max : 1,
            ),
            max: max > 0 ? max : 1,
            onChanged: max > 0
                ? (v) => p.playback.seek(Duration(milliseconds: v.round()))
                : null,
          ),
        ),
        Text(
          clock(duration),
          style: TextStyle(fontSize: 10, color: context.tokens.muted),
        ),
      ],
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
    final phoneArtMax = (width - 64).clamp(180.0, 340.0);
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
                  Text(
                    track.title,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    track.artist,
                    style: TextStyle(color: context.tokens.muted),
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
        ? SizedBox(height: 280, child: LyricPanel(p))
        : null;
    return Scaffold(
      appBar: PlayerHeader(
        onBack: goBack,
        status: p.opening ? '正在加载…' : '',
        onMore: () => showTrackActions(context, p, track, null),
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
                  SeekBar(p),
                  transport(context, p),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      TrackDownloadAction(
                        track,
                        key: ValueKey('download-action-${track.id}'),
                      ),
                      action(
                        Icons.lyrics_outlined,
                        '歌词',
                        () => showLyrics(context, p),
                      ),
                    ],
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
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    key: const ValueKey('player-content'),
                    child: SizedBox(
                      height: constraints.maxHeight,
                      width: constraints.maxWidth,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (p.error.isNotEmpty)
                              errorBox(
                                context,
                                p.error,
                                () => p.play(track, at: p.position),
                              ),
                            Expanded(
                              child: Column(
                                children: [
                                  Expanded(
                                    child: LayoutBuilder(
                                      builder: (context, box) {
                                        final side = box.maxHeight.clamp(
                                          0.0,
                                          phoneArtMax,
                                        );
                                return Center(
                                  child: side < 48
                                      ? const SizedBox.shrink()
                                      : RecordDisc(
                                          track,
                                          size: side,
                                          playing: p.playing,
                                        ),
                                );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  meta,
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(height: 112, child: LyricPanel(p)),
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
}

/// Navigation stays outside the scrollable content, including empty playback.
class PlayerHeader extends StatelessWidget implements PreferredSizeWidget {
  const PlayerHeader({
    super.key,
    required this.onBack,
    required this.status,
    this.onMore,
  });
  final VoidCallback onBack;
  final String status;
  final VoidCallback? onMore;
  @override
  Size get preferredSize => const Size.fromHeight(64);
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.tokens.background,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            action(Icons.arrow_back, '返回', onBack),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: context.tokens.muted),
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

class LyricPanel extends StatefulWidget {
  const LyricPanel(this.p, {super.key});
  final LibraryController p;
  @override
  State<LyricPanel> createState() => _LyricPanelState();
}

class _LyricPanelState extends State<LyricPanel> {
  final scroll = ScrollController();
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
    builder: (context, _, _) => buildLyrics(context),
  );

  void alignLyric(int index, {bool retried = false}) {
    final previous = last;
    pending = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients || pending != index) return;
      final metrics = scroll.position;
      if (metrics.viewportDimension == 0 && !retried) {
        alignLyric(index, retried: true);
        return;
      }
      last = index;
      final target = centeredLyricOffset(
        index: index,
        viewport: metrics.viewportDimension,
        maxScroll: metrics.maxScrollExtent,
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
            duration: TingyuTokens.transition,
            curve: Curves.easeOut,
          ),
        );
      }
    });
  }

  Widget buildLyrics(BuildContext context) {
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
    if (index != last) alignLyric(index);
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
          child: ListView.builder(
            controller: scroll,
            itemCount: lines.length,
            itemExtent: 64,
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemBuilder: (ctx, i) => Center(
              child: Text(
                lines[i].text,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: i == index
                      ? context.tokens.accent
                      : context.tokens.muted,
                  fontWeight: i == index ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 16,
                ),
              ),
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
                  Expanded(child: Text('播放队列 · ${p.queue.length} 首')),
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
                        onReorderItem: (oldIndex, newIndex) {
                          unawaited(p.moveQueue(oldIndex, newIndex - oldIndex));
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
                          return ColoredBox(
                            key: ValueKey('queue-row-${track.id}'),
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
                                      () =>
                                          current ? p.toggle() : p.play(track),
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
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: current
                                                      ? t.accent
                                                      : t.text,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(
                                                height: TingyuTokens.space / 2,
                                              ),
                                              Text(
                                                track.artist,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
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
                                    if (mounted && p.current?.id == track.id) {
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
                          );
                        },
                      ),
                    ),
            ),
            if (p.current != null)
              Padding(
                padding: const EdgeInsets.all(TingyuTokens.space * 1.5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.playerSurface,
                    borderRadius: BorderRadius.circular(
                      TingyuTokens.collectionRadius,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(TingyuTokens.space),
                    child: Row(
                      children: [
                        Artwork(p.current!, size: 40),
                        const SizedBox(width: TingyuTokens.space * 1.5),
                        Expanded(
                          child: Text(
                            p.current!.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: t.onPlayer, fontSize: 13),
                          ),
                        ),
                        Pressable(
                          key: const ValueKey('queue-toggle'),
                          label: p.playing ? '暂停队列播放' : '继续队列播放',
                          onPressed: () => p.toggle(),
                          child: TingyuIcon(
                            p.playing ? Icons.pause : Icons.play_arrow,
                            color: t.onPlayer,
                          ),
                        ),
                      ],
                    ),
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
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: context.tokens.background,
                                  shape: BoxShape.circle,
                                ),
                                child: PlayingIndicator(
                                  playing:
                                      p.playing &&
                                      p.playback.player.processingState ==
                                          ProcessingState.ready,
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
                Tooltip(
                  message: '已下载，可离线播放',
                  child: TingyuIcon(
                    Icons.check_circle_outline,
                    size: 20,
                    color: context.tokens.accent,
                  ),
                ),
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

Future<void> showAboutTingyu(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.tokens.background,
      builder: (ctx) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(TingyuTokens.space * 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    action(
                      Icons.keyboard_arrow_down,
                      '关闭',
                      () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ctx.tokens.tint,
                    borderRadius: BorderRadius.circular(
                      TingyuTokens.collectionRadius,
                    ),
                  ),
                  child: TingyuIcon(
                    Icons.graphic_eq,
                    size: 36,
                    color: ctx.tokens.accent,
                  ),
                ),
                const SizedBox(height: TingyuTokens.space * 2),
                Text('听屿', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: TingyuTokens.space),
                Text(
                  '版本 $tingyuVersion',
                  style: TextStyle(color: ctx.tokens.muted, fontSize: 12),
                ),
                const SizedBox(height: TingyuTokens.space * 3),
                Text(
                  '歌单与下载保存在本机，账号凭据由系统安全存储。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ctx.tokens.muted, height: 1.7),
                ),
                const SizedBox(height: TingyuTokens.space * 3),
                Pressable(
                  key: const ValueKey('about-dismiss'),
                  label: '知道了',
                  color: ctx.tokens.tint,
                  onPressed: () => Navigator.pop(ctx),
                  child: Center(
                    child: Text(
                      '知道了',
                      style: TextStyle(
                        color: ctx.tokens.accentInk,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
  const AccountPanel(this.p, {super.key});
  final LibraryController p;
  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  String? qr, key;
  String message = '扫码后可以导入你的 B 站收藏夹';
  bool busy = false, polling = false;
  Map<String, dynamic>? selectedFolder;
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
        });
        return;
      }
      final found = await widget.p.api.folders(widget.p.profile!['mid']);
      if (mounted) {
        setState(() {
          folders = found;
          selectedFolder = null;
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
      final result = await widget.p.importFolder(folder);
      if (mounted) {
        setState(() {
          imported = result;
          message = '已导入 ${result.trackIds.length} 首到「${result.name}」';
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

  Future<void> generate() async {
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '连接你的收藏',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
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
                      '选择一个收藏夹，导入为本地歌单。',
                      style: TextStyle(color: context.tokens.muted),
                    ),
                    const SizedBox(height: 16),
                    if (!busy && folders.isEmpty) const Text('暂无可导入的收藏夹。'),
                    for (final folder in folders)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: FolderChoice(
                          folder: folder,
                          selected: selectedFolder?['id'] == folder['id'],
                          onSelect: busy
                              ? null
                              : () => setState(() {
                                  selectedFolder = folder;
                                  imported = null;
                                  message = '';
                                }),
                        ),
                      ),
                    if (!busy)
                      labelButton('刷新收藏夹', loadProfile, icon: Icons.refresh),
                    labelButton(
                      '退出账号',
                      busy
                          ? null
                          : () async {
                              await p.logout();
                              if (!mounted) return;
                              setState(() {
                                folders = [];
                                selectedFolder = null;
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
                      labelButton(
                        qr == null ? '生成登录二维码' : '刷新二维码',
                        generate,
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
                ? labelButton(
                    busy
                        ? '正在导入或加载…'
                        : selectedFolder == null
                        ? '请先选择收藏夹'
                        : '导入所选收藏夹',
                    busy || selectedFolder == null ? null : importSelected,
                    icon: Icons.playlist_add,
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
  });
  final Map<String, dynamic> folder;
  final bool selected;
  final VoidCallback? onSelect;
  @override
  Widget build(BuildContext context) => Pressable(
    key: ValueKey('folder-${folder['id']}'),
    selected: selected,
    onPressed: onSelect,
    child: Row(
      children: [
        TingyuIcon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
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
      ],
    ),
  );
}

Future<void> showLyrics(BuildContext context, LibraryController p) async {
  final track = p.current;
  if (track == null) return;
  if (MediaQuery.sizeOf(context).width >= 960) {
    await showDialog<void>(
      context: context,
      builder: (_) => _LyricsDialog(p, track),
    );
  } else {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: _LyricsDialog(p, track),
      ),
    );
  }
}

class _LyricsDialog extends StatefulWidget {
  const _LyricsDialog(this.controller, this.track);
  final LibraryController controller;
  final Track track;
  @override
  State<_LyricsDialog> createState() => _LyricsDialogState();
}

class _LyricsDialogState extends State<_LyricsDialog> {
  LibraryController get p => widget.controller;
  Track get track => widget.track;
  late final edit = TextEditingController(text: track.title);
  late final lrc = TextEditingController(text: p.lyricText);
  late int offset = p.lyricOffset;
  List<Map<String, dynamic>> candidates = [];
  String? error;
  bool busy = false;
  @override
  void dispose() {
    edit.dispose();
    lrc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TingyuFormPanel(
    title: const Text('匹配歌词'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: edit,
              decoration: const InputDecoration(labelText: '歌名 / 歌手'),
            ),
            labelButton(
              '搜索歌词',
              busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        final found = await p.lyricsClient.search(edit.text);
                        if (mounted) {
                          setState(() {
                            candidates = found;
                            error = found.isEmpty ? '未找到歌词，可粘贴 LRC 文本' : null;
                          });
                        }
                      } on AppFailure catch (e) {
                        if (mounted) setState(() => error = e.message);
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
            ),
            if (error != null) Text(error!),
            for (final c in candidates.take(10))
              labelButton('${c['trackName']} · ${c['artistName']}', () async {
                if (p.current?.id != track.id) {
                  throw const AppFailure('歌曲已切换，请重新打开歌词窗口');
                }
                await p.chooseLyrics(c, track);
                if (context.mounted) Navigator.pop(context);
              }),
            TextField(
              controller: lrc,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '粘贴歌词',
                hintText: '支持 LRC 或纯文本歌词',
              ),
            ),
            const SizedBox(height: TingyuTokens.space * 2),
            Row(
              children: [
                const Expanded(child: Text('时间偏移')),
                action(
                  Icons.remove,
                  '歌词提前 0.1 秒',
                  offset > -5000 ? () => setState(() => offset -= 100) : null,
                ),
                Text('${(offset / 1000).toStringAsFixed(1)} 秒'),
                action(
                  Icons.add,
                  '歌词延后 0.1 秒',
                  offset < 5000 ? () => setState(() => offset += 100) : null,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: [
      labelButton('取消', () => Navigator.pop(context)),
      Pressable(
        label: '保存歌词',
        key: const ValueKey('保存歌词'),
        color: context.tokens.accent,
        onPressed: () => report(context, () async {
          await p.setLyrics(lrc.text, track: track, offset: offset);
          await p.save();
          if (context.mounted) Navigator.pop(context);
        }),
        child: Text('保存歌词', style: TextStyle(color: context.tokens.onAccent)),
      ),
    ],
  );
}

/// Persistent, fixed-width destinations avoid layout movement while switching.
class CompactNavigation extends StatelessWidget {
  const CompactNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
  });
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: GlassSurface(
        child: Padding(
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
