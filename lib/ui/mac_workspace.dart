part of 'app.dart';

/// Mac presentation only. All durable state and effects belong to LibraryController.
class MacWorkspace extends StatelessWidget {
  const MacWorkspace({super.key, this.initialPage = 'auto'});
  final String initialPage;
  @override
  Widget build(BuildContext context) => PressableStyle(
    desktop: true,
    child: _MacWorkspaceBody(initialPage: initialPage),
  );
}

class _MacWorkspaceBody extends ConsumerStatefulWidget {
  const _MacWorkspaceBody({required this.initialPage});
  final String initialPage;
  @override
  ConsumerState<_MacWorkspaceBody> createState() => _MacWorkspaceState();
}

class _MacCollectionState {
  final query = TextEditingController();
  final scroll = ScrollController();
  final selected = <String>{};
  bool selecting = false;
  void dispose() {
    query.dispose();
    scroll.dispose();
  }
}

class _MacWorkspaceState extends ConsumerState<_MacWorkspaceBody>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      closeOverlay(commit: false);
    }
  }

  late String page = widget.initialPage == 'auto'
      ? (p.history.any(p.library.containsKey) ? 'recent' : 'songs')
      : widget.initialPage == 'library'
      ? 'songs'
      : widget.initialPage;
  final history = <String>[];
  final states = <String, _MacCollectionState>{};
  final search = TextEditingController();
  final searchFocus = FocusNode();
  final localFocus = FocusNode();
  final optionsMinutes = TextEditingController();
  final queueScroll = ScrollController();
  final downloadsMemory = DownloadsViewMemory();
  String? overlay;
  SleepTimerDraft? timerDraft;
  Timer? debounce;
  _MacCollectionState get collection =>
      states.putIfAbsent(page, _MacCollectionState.new);
  LibraryController get p => ref.read(libraryProvider);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    debounce?.cancel();
    search.dispose();
    searchFocus.dispose();
    localFocus.dispose();
    optionsMinutes.dispose();
    queueScroll.dispose();
    downloadsMemory.dispose();
    for (final state in states.values) {
      state.dispose();
    }
    super.dispose();
  }

  void navigate(String next, {bool back = false}) {
    closeOverlay();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      if (back) {
        if (history.isNotEmpty) page = history.removeLast();
      } else if (page != next) {
        if (next == 'details') {
          history.add(page);
        } else {
          history.clear();
        }
        page = next;
      }
    });
  }

  void closeOverlay({bool commit = true}) {
    final draft = timerDraft;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (commit &&
        draft != null &&
        draft.changed &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed)) {
      unawaited(
        report(
          context,
          () => p.setSleepTimer(
            draft.minutes == null ? null : Duration(minutes: draft.minutes!),
            finishTrack: draft.finish,
          ),
        ),
      );
    }
    timerDraft = null;
    if (overlay != null && mounted) setState(() => overlay = null);
  }

  void toggleOverlay(String value) {
    final closing = overlay == value;
    closeOverlay();
    if (closing) return;
    if (value == 'options') {
      timerDraft = SleepTimerDraft(p);
      optionsMinutes.text = timerDraft!.minutes?.toString() ?? '';
    }
    setState(() => overlay = value);
  }

  Future<void> createPlaylist() async {
    final name = await nameDialog(context);
    if (name != null && mounted) {
      await report(context, () => p.addPlaylist(name));
    }
  }

  Future<void> openAccount() => panel(
    '账号与收藏夹',
    (_) => AccountPanel(
      p,
      pollWhileInactive: true,
      desktop: true,
      onOpenPlaylist: (list) => navigate(list.id),
    ),
    selfContained: true,
    width: TingyuTokens.macAccountWidth,
  );

  Future<void> openSettings() => panel(
    '设置',
    (_) => MacSettingsPanel(p),
    selfContained: true,
    width: TingyuTokens.macSettingsWidth,
  );

  Future<void> panel(
    String title,
    WidgetBuilder builder, {
    bool selfContained = false,
    double? width,
  }) async {
    closeOverlay();
    await showDialog<void>(
      context: context,
      builder: (ctx) => PressableStyle(
        desktop: true,
        child: Dialog(
          backgroundColor: ctx.tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              selfContained
                  ? TingyuTokens.macAccountRadius
                  : TingyuTokens.detailRadius,
            ),
          ),
          child: SizedBox(
            width: selfContained
                ? null
                : width ?? TingyuTokens.macCover + TingyuTokens.macPadding * 6,
            height: selfContained ? null : MediaQuery.sizeOf(ctx).height * .8,
            child: selfContained
                ? ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: width ?? TingyuTokens.macAccountWidth,
                      maxHeight: math.min(
                        MediaQuery.sizeOf(ctx).height * .8,
                        TingyuTokens.macAccountHeight,
                      ),
                    ),
                    child: ListenableBuilder(
                      listenable: p,
                      builder: (context, _) => builder(context),
                    ),
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(TingyuTokens.space * 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: Theme.of(ctx).textTheme.titleLarge,
                              ),
                            ),
                            action(
                              Icons.clear,
                              '关闭$title',
                              () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(
                            TingyuTokens.macPadding,
                          ),
                          child: ListenableBuilder(
                            listenable: p,
                            builder: (context, _) => builder(context),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  String title(LibraryController p) => switch (page) {
    'songs' => '歌曲',
    'search' => '搜索',
    'likes' => '喜欢',
    'recent' => '最近播放',
    'downloads' => '下载',
    'playlists' => '我的歌单',
    'details' => '歌曲详情',
    _ => playlist(p)?.name ?? '歌单不存在',
  };
  Playlist? playlist(LibraryController p) =>
      p.playlists.where((x) => x.id == page).firstOrNull;
  List<String> ids(LibraryController p) =>
      (page == 'recent'
              ? p.history.where(p.library.containsKey).toList()
              : p.collectionIds(
                  page,
                  page == 'likes'
                      ? p.likes
                      : playlist(p)?.trackIds ?? p.library.keys,
                ))
          .where((id) => matchesLocal(p.library[id], collection.query.text))
          .toList();
  @override
  Widget build(BuildContext context) {
    final p = ref.watch(libraryProvider), t = context.tokens;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: TingyuTokens.macSliderTrack,
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: TingyuTokens.macSliderThumb,
        ),
        overlayShape: const RoundSliderOverlayShape(
          overlayRadius: TingyuTokens.macSliderOverlay,
        ),
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (overlay != null) closeOverlay();
          },
          const SingleActivator(LogicalKeyboardKey.comma, meta: true): () =>
              openSettings(),
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
            if (page == 'search') {
              searchFocus.requestFocus();
            } else if ([
              'library',
              'details',
              'playlists',
              'downloads',
            ].contains(page)) {
              navigate('search');
              searchFocus.requestFocus();
            } else {
              localFocus.requestFocus();
            }
          },
          const SingleActivator(LogicalKeyboardKey.space): () {
            final focus = FocusManager.instance.primaryFocus?.context;
            if (focus?.findAncestorWidgetOfExactType<EditableText>() == null &&
                focus?.widget is! EditableText) {
              if (p.current != null && !p.opening) {
                unawaited(report(context, p.toggle));
              }
            }
          },
        },
        child: Scaffold(
          backgroundColor: t.background,
          body: Row(
            children: [
              SizedBox(
                width: MediaQuery.sizeOf(context).width < TingyuTokens.macWide
                    ? TingyuTokens.macSidebarCompact
                    : TingyuTokens.macSidebar,
                child: sidebar(p),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final compact = box.maxWidth < TingyuTokens.macCompact;
                    const dock = TingyuTokens.macDock;
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Column(
                            children: [
                              if (page == 'details')
                                SizedBox(
                                  height: TingyuTokens.macHeader,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: TingyuTokens.space * 2,
                                    ),
                                    child: Row(
                                      children: [
                                        action(
                                          Icons.arrow_back,
                                          '返回来源',
                                          history.isEmpty
                                              ? null
                                              : () => navigate('', back: true),
                                        ),
                                        const SizedBox(
                                          width: TingyuTokens.space,
                                        ),
                                        Text(
                                          title(p),
                                          style: TextStyle(color: t.muted),
                                        ),
                                        const Spacer(),
                                      ],
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    bottom: dock + TingyuTokens.space * 3,
                                  ),
                                  child: KeyedSubtree(
                                    key: ValueKey('mac-page-$page'),
                                    child: SizedBox.expand(
                                      key: const ValueKey('mac-main-content'),
                                      child: content(p),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (overlay != null) ...[
                          Positioned.fill(
                            child: GestureDetector(
                              key: const ValueKey('mac-overlay-dismiss'),
                              behavior: HitTestBehavior.opaque,
                              onTap: closeOverlay,
                              child: const SizedBox.expand(),
                            ),
                          ),
                          Positioned(
                            right: TingyuTokens.space * 2,
                            bottom: dock + TingyuTokens.space * 2,
                            width: math.min(
                              TingyuTokens.macQueueWidth,
                              box.maxWidth - TingyuTokens.macPadding,
                            ),
                            height: math.min(
                              overlay == 'volume'
                                  ? TingyuTokens.macVolumeHeight
                                  : overlay == 'options'
                                  ? TingyuTokens.macOptionsHeight
                                  : TingyuTokens.macQueueHeight,
                              box.maxHeight - dock - TingyuTokens.macPadding,
                            ),
                            child: overlaySurface(p),
                          ),
                        ],
                        Positioned(
                          left: TingyuTokens.space * 2,
                          bottom: dock + TingyuTokens.space * 3,
                          child: IgnorePointer(
                            child: ValueListenableBuilder<String?>(
                              valueListenable: p.modeNotice,
                              builder: (context, notice, _) => notice == null
                                  ? const SizedBox.shrink()
                                  : Semantics(
                                      liveRegion: true,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: t.surface,
                                          border: Border.all(color: t.line),
                                          borderRadius: BorderRadius.circular(
                                            TingyuTokens.radius,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(
                                            TingyuTokens.space * 1.5,
                                          ),
                                          child: Text(notice),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        Positioned(
                          key: const ValueKey('mac-dock-position'),
                          left: TingyuTokens.space * 2,
                          right: TingyuTokens.space * 2,
                          bottom: TingyuTokens.space,
                          height: dock,
                          child: MacPlaybackBar(
                            p,
                            compact: compact,
                            onDetails: () => navigate('details'),
                            onQueue: () => toggleOverlay('queue'),
                            onVolume: () => toggleOverlay('volume'),
                            onOptions: () => toggleOverlay('options'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget navItem(String id, IconData icon, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: TingyuTokens.space / 4),
    child: Pressable(
      key: ValueKey('mac-nav-$id'),
      label: label,
      selected: page == id,
      selectionFill: false,
      color: page == id ? context.tokens.selectionSurface : Colors.transparent,
      radius: TingyuTokens.radius,
      onPressed: () => navigate(id),
      child: Row(
        children: [
          TingyuIcon(
            icon,
            color: page == id ? context.tokens.accentInk : context.tokens.muted,
          ),
          const SizedBox(width: TingyuTokens.space * 1.5),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: TingyuTokens.macTrackTitle,
                fontWeight: page == id ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    ),
  );
  Widget sidebar(LibraryController p) => ColoredBox(
    color: context.tokens.sidebar,
    child: Padding(
      padding: const EdgeInsets.all(TingyuTokens.space * 1.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(TingyuTokens.space * 2),
            child: Text(
              'tingyu',
              style: TextStyle(
                fontSize: TingyuTokens.macBrand,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  navItem('search', Icons.search, '搜索'),
                  Padding(
                    padding: const EdgeInsets.all(TingyuTokens.space),
                    child: Text(
                      '资料库',
                      style: TextStyle(
                        color: context.tokens.muted,
                        fontSize: TingyuTokens.macCaption,
                      ),
                    ),
                  ),
                  navItem('recent', Icons.history, '最近播放'),
                  navItem('songs', Icons.music_note, '歌曲'),
                  navItem('likes', Icons.favorite_border, '喜欢'),
                  navItem('downloads', Icons.download_outlined, '下载'),
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(TingyuTokens.space),
                          child: Text(
                            '我的歌单',
                            style: TextStyle(
                              color: context.tokens.muted,
                              fontSize: TingyuTokens.macCaption,
                            ),
                          ),
                        ),
                      ),
                      action(Icons.add, '新建歌单', createPlaylist),
                    ],
                  ),
                  navItem('playlists', Icons.folder_outlined, '全部歌单'),
                  for (final list in p.playlists)
                    navItem(
                      list.id,
                      Icons.featured_play_list_outlined,
                      list.name,
                    ),
                ],
              ),
            ),
          ),
          accountEntry(p),
          labelButton('设置', () => openSettings(), icon: Icons.tune),
        ],
      ),
    ),
  );
  Widget accountEntry(LibraryController p) {
    final name = p.profile?['uname']?.toString().trim() ?? '';
    final label = name.isNotEmpty
        ? name
        : p.api.hasSession
        ? '已登录'
        : '登录账号';
    return Pressable(
      key: const ValueKey('账号与收藏夹'),
      label: '$label，账号与收藏夹',
      onPressed: openAccount,
      radius: TingyuTokens.radius,
      padding: const EdgeInsets.symmetric(
        horizontal: TingyuTokens.space,
        vertical: TingyuTokens.space,
      ),
      child: Row(
        children: [
          AccountAvatar(profile: p.profile, size: TingyuTokens.macPlayerArt),
          const SizedBox(width: TingyuTokens.space * 1.5),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: TingyuTokens.macTrackTitle),
            ),
          ),
        ],
      ),
    );
  }

  Widget content(LibraryController p) {
    if (page == 'details') {
      return MacSongDetails(p);
    }
    if (page == 'downloads') {
      return DownloadsWorkspace(
        p,
        tasks: downloadTasks,
        memory: downloadsMemory,
        desktop: true,
        onSectionChanged: (tasks) => setState(() => downloadTasks = tasks),
      );
    }
    if (page == 'playlists') {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(TingyuTokens.macPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [heading('我的歌单'), playlistGrid(p)],
        ),
      );
    }
    if (page == 'search') {
      return searchPage(p);
    }
    return collectionPage(p);
  }

  bool downloadTasks = false;
  Widget heading(String label) => Padding(
    padding: const EdgeInsets.only(bottom: TingyuTokens.space * 3),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: TingyuTokens.macTitle,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
  Widget playlistGrid(LibraryController p) => LayoutBuilder(
    builder: (context, box) {
      if (p.playlists.isEmpty) {
        return EmptyView('还没有歌单', '把喜欢的声音整理在一起。');
      }
      final columns = math.max(
        2,
        (box.maxWidth / (TingyuTokens.macCard + TingyuTokens.space * 3))
            .floor(),
      );
      final width =
          (box.maxWidth - (columns - 1) * TingyuTokens.space * 3) / columns;
      return Wrap(
        spacing: TingyuTokens.space * 3,
        runSpacing: TingyuTokens.space * 3,
        children: [
          for (final list in p.playlists)
            SizedBox(
              width: width,
              child: Pressable(
                key: ValueKey('mac-playlist-${list.id}'),
                label: '打开歌单 ${list.name}',
                padding: EdgeInsets.zero,
                onPressed: () => navigate(list.id),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (list.trackIds
                            .map((id) => p.library[id])
                            .whereType<Track>()
                            .firstOrNull
                        case final Track track)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(
                          TingyuTokens.radius,
                        ),
                        child: Artwork(track, size: width),
                      )
                    else
                      Container(
                        width: width,
                        height: width,
                        decoration: BoxDecoration(
                          color: context.tokens.tint,
                          borderRadius: BorderRadius.circular(
                            TingyuTokens.radius,
                          ),
                        ),
                        child: TingyuIcon(
                          Icons.music_note,
                          color: context.tokens.muted,
                          size: TingyuTokens.space * 5,
                        ),
                      ),
                    const SizedBox(height: TingyuTokens.space),
                    Text(
                      list.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${list.trackIds.length} 首歌曲',
                      style: TextStyle(
                        color: context.tokens.muted,
                        fontSize: TingyuTokens.macCaption,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
  Widget searchPage(LibraryController p) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(TingyuTokens.macPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading('搜索'),
            TextField(
              key: const ValueKey('mac-search'),
              controller: search,
              focusNode: searchFocus,
              decoration: const InputDecoration(
                prefixIcon: Padding(
                  padding: EdgeInsets.all(TingyuTokens.space * 1.5),
                  child: TingyuIcon(Icons.search, size: TingyuTokens.iconSize),
                ),
                hintText: '歌曲、UP 主、BV / AV 号或链接',
              ),
              onChanged: (value) {
                debounce?.cancel();
                debounce = Timer(
                  const Duration(milliseconds: 450),
                  () => p.search(value),
                );
              },
              onSubmitted: (value) {
                debounce?.cancel();
                unawaited(p.search(value));
              },
            ),
            if (p.searching) const LinearProgressIndicator(),
            if (p.searchError.isNotEmpty)
              errorBox(
                context,
                p.searchError,
                () => p.search(search.text, page: p.searchAttemptPage),
              ),
          ],
        ),
      ),
      Expanded(
        child: p.results.isEmpty
            ? EmptyView(
                search.text.isEmpty ? '听点新鲜的' : '没有找到相关内容',
                '搜索关键词，或直接粘贴 BV 号。',
              )
            : ListView.builder(
                itemCount: p.results.length + 1,
                padding: const EdgeInsets.symmetric(
                  horizontal: TingyuTokens.macPadding,
                ),
                itemBuilder: (_, i) => i == p.results.length
                    ? labelButton(
                        '加载更多',
                        p.searching
                            ? null
                            : () =>
                                  p.search(search.text, page: p.searchPage + 1),
                      )
                    : TrackRow(p.results[i]),
              ),
      ),
    ],
  );
  Widget recentPage(LibraryController p) {
    final tracks = p.history
        .map((id) => p.library[id])
        .whereType<Track>()
        .toList();
    return Padding(
      padding: const EdgeInsets.all(TingyuTokens.macPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading('最近播放'),
          const SizedBox(height: TingyuTokens.space * 2),
          Expanded(
            child: tracks.isEmpty
                ? const EmptyView('还没有播放记录', '播放过的歌曲会出现在这里。')
                : LayoutBuilder(
                    builder: (context, box) {
                      final columns = math.max(1, (box.maxWidth / 300).floor());
                      final width =
                          (box.maxWidth -
                              (columns - 1) * TingyuTokens.space * 3) /
                          columns;
                      final scale = MediaQuery.textScalerOf(context);
                      return GridView.builder(
                        key: const ValueKey('mac-recent-grid'),
                        controller: collection.scroll,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: TingyuTokens.space * 3,
                          mainAxisSpacing: TingyuTokens.space * 3,
                          mainAxisExtent:
                              width / TingyuTokens.heroRatio +
                              scale.scale(16) * 1.5 +
                              scale.scale(12) * 1.5 +
                              12,
                        ),
                        itemCount: tracks.length,
                        itemBuilder: (context, i) {
                          final track = tracks[i];
                          return Pressable(
                            key: ValueKey('mac-recent-${track.id}'),
                            label: '播放 ${track.title}',
                            padding: EdgeInsets.zero,
                            onPressed: () => p.playFromCollection(
                              track,
                              tracks.map((t) => t.id).toList(),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.tokens.muted,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      TingyuTokens.artworkRadius,
                                    ),
                                    child: SizedBox.expand(
                                      child: FittedBox(
                                        fit: BoxFit.cover,
                                        child: Artwork(track, size: 400),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget collectionPage(LibraryController p) {
    if (page == 'recent') return recentPage(p);
    final list = playlist(p), visible = ids(p), state = collection;
    state.selected.retainAll(p.library.keys);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            TingyuTokens.macPadding,
            TingyuTokens.macPadding,
            TingyuTokens.macPadding,
            TingyuTokens.space,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: heading(title(p))),
                  if (list != null)
                    action(
                      Icons.more_horiz,
                      '歌单操作',
                      () => showPlaylistActions(context, p, list),
                    ),
                ],
              ),
              TextField(
                controller: state.query,
                focusNode: localFocus,
                key: ValueKey('mac-local-$page'),
                decoration: const InputDecoration(
                  prefixIcon: Padding(
                    padding: EdgeInsets.all(TingyuTokens.space * 1.5),
                    child: TingyuIcon(
                      Icons.search,
                      size: TingyuTokens.iconSize,
                    ),
                  ),
                  hintText: '在当前列表查找',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: TingyuTokens.space),
              if (page == 'recent')
                const SizedBox.shrink()
              else if (!state.selecting)
                CollectionToolbar(
                  ids: visible,
                  list: list,
                  collectionKey: page,
                  compact: true,
                  selecting: false,
                  onSelect: () => setState(() => state.selecting = true),
                )
              else
                SelectionToolbar(
                  scope: page,
                  selectedIds: state.selected.where(visible.contains).toList(),
                  totalCount: visible.length,
                  allSelected:
                      visible.isNotEmpty && state.selected.containsAll(visible),
                  list: list,
                  onSelectAll: () => setState(() {
                    state.selected.containsAll(visible)
                        ? state.selected.removeAll(visible)
                        : state.selected.addAll(visible);
                  }),
                  onDone: () => setState(() {
                    state.selecting = false;
                    state.selected.clear();
                  }),
                ),
              if (list != null)
                labelButton(
                  '添加歌曲',
                  () => context.push('/playlist/${list.id}/add'),
                  icon: Icons.playlist_add,
                ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? EmptyView(
                  state.query.text.trim().isNotEmpty
                      ? '没有匹配的歌曲'
                      : page == 'recent'
                      ? '还没有播放记录'
                      : page == 'likes'
                      ? '还没有喜欢的歌曲'
                      : '还没有歌曲',
                  state.query.text.trim().isNotEmpty
                      ? '换个关键词试试。'
                      : page == 'recent'
                      ? '播放过的歌曲会出现在这里。'
                      : page == 'likes'
                      ? '喜欢的歌曲会出现在这里。'
                      : '搜索歌曲，或添加到歌单。',
                  child: state.query.text.trim().isEmpty && p.library.isEmpty
                      ? Wrap(
                          spacing: TingyuTokens.space,
                          children: [
                            labelButton('搜索歌曲', () => navigate('search')),
                            labelButton('导入收藏夹', openAccount),
                          ],
                        )
                      : null,
                )
              : ListView.builder(
                  controller: state.scroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: TingyuTokens.macPadding,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final track = p.library[visible[i]]!;
                    return TrackRow(
                      track,
                      key: ValueKey(track.id),
                      sourceIds: visible,
                      playlist: list,
                      selecting: state.selecting,
                      selected: state.selected.contains(track.id),
                      onSelect: () => setState(() {
                        state.selected.contains(track.id)
                            ? state.selected.remove(track.id)
                            : state.selected.add(track.id);
                      }),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget overlaySurface(LibraryController p) => ClipRRect(
    borderRadius: BorderRadius.circular(TingyuTokens.detailRadius),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.tokens.surface,
        border: Border.all(color: context.tokens.line),
        borderRadius: BorderRadius.circular(TingyuTokens.detailRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(TingyuTokens.space * 2),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    switch (overlay) {
                      'queue' => '待播清单',
                      'volume' => '音量',
                      _ => '播放选项',
                    },
                    style: const TextStyle(
                      fontSize: TingyuTokens.macMenuTitle,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                action(Icons.clear, '关闭辅助面板', closeOverlay),
              ],
            ),
            Expanded(
              child: overlay == 'queue'
                  ? queue(p)
                  : overlay == 'volume'
                  ? SingleChildScrollView(
                      child: PlayerVolumePanel(p, compact: true),
                    )
                  : options(p),
            ),
          ],
        ),
      ),
    ),
  );
  Widget queue(LibraryController p) {
    final index = p.queue.indexOf(p.current?.id ?? '');
    final next = p.queue
        .skip(index < 0 ? 0 : index + 1)
        .map((id) => p.library[id])
        .whereType<Track>()
        .toList();
    Widget queueRow(Track track, {bool current = false}) => Row(
      children: [
        Expanded(
          child: Pressable(
            label: '${current ? '当前歌曲' : '播放'} ${track.title}',
            selected: current,
            selectionFill: false,
            padding: const EdgeInsets.symmetric(vertical: TingyuTokens.space),
            onPressed: p.opening
                ? null
                : () => report(
                    context,
                    () => current ? p.toggle() : p.play(track),
                  ),
            child: Row(
              children: [
                Artwork(track, size: TingyuTokens.space * 5),
                const SizedBox(width: TingyuTokens.space),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: TingyuTokens.macTrackTitle,
                          color: current
                              ? context.tokens.accentInk
                              : context.tokens.text,
                        ),
                      ),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: TingyuTokens.macMetadata,
                          color: context.tokens.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (current) PlayingIndicator(playing: p.playing),
              ],
            ),
          ),
        ),
        action(
          Icons.more_horiz,
          '队列选项 ${track.id}',
          () => showQueueTrackActions(context, p, track.id),
        ),
      ],
    );
    return ListView(
      controller: queueScroll,
      children: [
        if (p.current case final Track current) ...[
          Text(
            '正在播放',
            style: TextStyle(
              color: context.tokens.muted,
              fontSize: TingyuTokens.macCaption,
            ),
          ),
          queueRow(current, current: true),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                '接下来 · ${next.length} 首',
                style: TextStyle(
                  color: context.tokens.muted,
                  fontSize: TingyuTokens.macCaption,
                ),
              ),
            ),
            labelButton(
              '清空',
              p.queue.isEmpty
                  ? null
                  : () async {
                      if (await confirm(context, '清空队列并停止播放？')) {
                        await p.clearQueue();
                      }
                    },
            ),
          ],
        ),
        if (next.isEmpty)
          const Padding(
            padding: EdgeInsets.all(TingyuTokens.macPadding),
            child: Text('本轮没有待播歌曲'),
          ),
        for (final track in next) queueRow(track),
      ],
    );
  }

  Widget options(LibraryController p) {
    final draft = timerDraft!;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('播放速度')),
              Text(
                rateLabel(p.speed),
                style: TextStyle(color: context.tokens.accentInk),
              ),
              action(Icons.refresh, '恢复倍速', () => p.setSpeed(1)),
            ],
          ),
          Slider(
            key: const ValueKey('mac-speed'),
            min: .5,
            max: 2,
            value: p.speed.clamp(.5, 2),
            onChanged: (value) => report(context, () => p.setSpeed(value)),
          ),
          Row(
            children: [
              for (final speed in [.75, 1.0, 1.25, 1.5, 2.0])
                Expanded(
                  child: Pressable(
                    label: rateLabel(speed),
                    padding: EdgeInsets.zero,
                    selected: p.speed == speed,
                    onPressed: () => p.setSpeed(speed),
                    key: ValueKey('mac-option-speed-$speed'),
                    child: Center(
                      child: Text(
                        rateLabel(speed),
                        style: const TextStyle(
                          fontSize: TingyuTokens.macCaption,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Divider(height: TingyuTokens.space * 2, color: context.tokens.line),
          Row(
            children: [
              const Expanded(child: Text('定时关闭')),
              Text(
                draft.minutes == null ? '已关闭' : '${draft.minutes} 分钟后',
                style: TextStyle(
                  fontSize: TingyuTokens.macCaption,
                  color: context.tokens.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: TingyuTokens.space),
          Row(
            children: [
              for (final minutes in [15, 30, 45, 60])
                Expanded(
                  child: Pressable(
                    label: '$minutes 分钟',
                    padding: EdgeInsets.zero,
                    selected: draft.minutes == minutes,
                    onPressed: () => setState(() {
                      draft.minutes = minutes;
                      draft.changed = true;
                      optionsMinutes.text = '$minutes';
                    }),
                    child: Center(
                      child: Text(
                        '$minutes 分钟',
                        style: const TextStyle(
                          fontSize: TingyuTokens.macCaption,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: TingyuTokens.space),
          Row(
            children: [
              for (final item in [(false, '到时暂停'), (true, '本首播完')])
                Expanded(
                  child: Pressable(
                    label: item.$2,
                    padding: EdgeInsets.zero,
                    selected: draft.finish == item.$1,
                    onPressed: () => setState(() {
                      draft.finish = item.$1;
                      draft.changed = true;
                    }),
                    child: Center(
                      child: Text(
                        item.$2,
                        style: const TextStyle(
                          fontSize: TingyuTokens.macCaption,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: TingyuTokens.space * 2),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('mac-timer-minutes'),
                  controller: optionsMinutes,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '自定义分钟',
                    isDense: true,
                    filled: false,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(TingyuTokens.radius),
                      borderSide: BorderSide(color: context.tokens.line),
                    ),
                  ),
                  onChanged: (value) {
                    final number = int.tryParse(value);
                    if (number != null && number > 0 && number <= 180) {
                      setState(() {
                        draft.minutes = number;
                        draft.changed = true;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: TingyuTokens.space),
              action(Icons.timer_off_outlined, '关闭定时', () {
                draft.minutes = null;
                draft.changed = true;
                closeOverlay();
              }),
            ],
          ),
          const SizedBox(height: TingyuTokens.space),
          Text(
            '收起后生效',
            style: TextStyle(
              color: context.tokens.muted,
              fontSize: TingyuTokens.macCaption,
            ),
          ),
        ],
      ),
    );
  }
}

class MacSongDetails extends StatelessWidget {
  const MacSongDetails(this.p, {super.key});
  final LibraryController p;
  @override
  Widget build(BuildContext context) {
    final track = p.current, t = context.tokens;
    if (track == null) return const EmptyView('还没有正在播放的歌曲', '从搜索或音乐库选择歌曲。');
    return LayoutBuilder(
      builder: (context, box) {
        final artSize = math.min(
          TingyuTokens.macDetailCover,
          (box.maxWidth - TingyuTokens.macPadding * 2) * .4,
        );
        return Padding(
          padding: const EdgeInsets.all(TingyuTokens.macPadding),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth:
                    TingyuTokens.macDetailCover +
                    TingyuTokens.macPadding +
                    TingyuTokens.macLyricWidth,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: artSize,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              TingyuTokens.macDockRadius,
                            ),
                            child: Artwork(track, size: artSize),
                          ),
                          const SizedBox(height: TingyuTokens.space * 3),
                          Text(
                            track.title,
                            key: const ValueKey('mac-detail-title'),
                            style: const TextStyle(
                              fontSize: TingyuTokens.macDetailTitle,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: TingyuTokens.space),
                          Text(track.artist, style: TextStyle(color: t.muted)),
                          if (p.parts.length > 1)
                            DropdownButton<String>(
                              isExpanded: true,
                              value: p.parts.any((t) => t.id == track.id)
                                  ? track.id
                                  : null,
                              items: [
                                for (final part in p.parts)
                                  DropdownMenuItem(
                                    value: part.id,
                                    child: Text(
                                      'P${part.part} · ${part.title}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (id) {
                                if (id != null) {
                                  unawaited(
                                    report(
                                      context,
                                      () => p.play(
                                        p.parts.firstWhere((t) => t.id == id),
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),

                          action(
                            Icons.more_horiz,
                            '歌曲操作',
                            () => showTrackActions(context, p, track, null),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: TingyuTokens.macPadding),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '歌词',
                                style: TextStyle(
                                  color: t.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            action(
                              Icons.more_horiz,
                              '歌词选项',
                              () => showLyrics(context, p),
                            ),
                          ],
                        ),
                        const SizedBox(height: TingyuTokens.space),
                        if (p.lines.isNotEmpty)
                          Expanded(child: LyricPanel(p))
                        else if (p.lyricText.trim().isNotEmpty)
                          Expanded(
                            child: SingleChildScrollView(
                              child: Text(
                                p.lyricText,
                                style: TextStyle(
                                  color: t.text,
                                  fontSize: p.lyricFontSize,
                                  height: 1.8,
                                ),
                              ),
                            ),
                          )
                        else
                          Flexible(
                            child: SingleChildScrollView(
                              child: Container(
                                key: const ValueKey('mac-lyrics-empty'),
                                padding: const EdgeInsets.all(
                                  TingyuTokens.space * 3,
                                ),
                                decoration: BoxDecoration(
                                  color: t.sidebar,
                                  borderRadius: BorderRadius.circular(
                                    TingyuTokens.macDockRadius,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (p.lyricLoading)
                                      const LinearProgressIndicator(),
                                    Text(
                                      p.lyricLoading
                                          ? '正在查找歌词…'
                                          : p.lyricError.isEmpty
                                          ? '暂无歌词'
                                          : '歌词暂不可用',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (p.lyricError.isNotEmpty) ...[
                                      const SizedBox(
                                        height: TingyuTokens.space,
                                      ),
                                      Text(
                                        p.lyricError,
                                        style: TextStyle(
                                          color: t.muted,
                                          height: 1.6,
                                        ),
                                      ),
                                    ],
                                    if (!p.lyricLoading) ...[
                                      const SizedBox(
                                        height: TingyuTokens.space,
                                      ),
                                      labelButton(
                                        '匹配或导入歌词',
                                        () => showLyrics(context, p),
                                        icon: Icons.search,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class MacPlaybackBar extends StatelessWidget {
  const MacPlaybackBar(
    this.p, {
    super.key,
    required this.compact,
    required this.onDetails,
    required this.onQueue,
    required this.onVolume,
    required this.onOptions,
  });
  final LibraryController p;
  final bool compact;
  final VoidCallback onDetails, onQueue, onVolume, onOptions;
  @override
  Widget build(BuildContext context) {
    final track = p.current, t = context.tokens;
    Widget transport(Widget child) => Transform.translate(
      offset: Offset(
        0,
        compact
            ? 0
            : -MediaQuery.textScalerOf(context).scale(TingyuTokens.macCaption) *
                  .7,
      ),
      child: child,
    );
    return Container(
      key: const ValueKey('mac-playback-bar'),
      padding: const EdgeInsets.all(TingyuTokens.space),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(TingyuTokens.macDockRadius),
        border: Border.all(color: t.line),
      ),
      child: Row(
        children: [
          Expanded(
            flex: compact ? 2 : 3,
            child: Pressable(
              key: const ValueKey('mac-open-details'),
              label: '打开歌曲详情',
              onPressed: track == null ? null : onDetails,
              padding: EdgeInsets.zero,
              child: Row(
                children: [
                  if (track != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                        TingyuTokens.artworkRadius,
                      ),
                      child: Artwork(track, size: TingyuTokens.macPlayerArt),
                    ),
                    const SizedBox(width: TingyuTokens.space),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track?.title ?? '选择歌曲',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: TingyuTokens.macTrackTitle,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          p.opening ? '正在解析…' : track?.artist ?? '开始收听',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.muted,
                            fontSize: TingyuTokens.macMetadata,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          transport(
            action(
              Icons.skip_previous,
              '上一首',
              track == null || p.opening ? null : () => p.next(-1),
            ),
          ),
          transport(
            Pressable(
              key: const ValueKey('mac-toggle-playback'),
              label: p.playing ? '暂停' : '播放',
              padding: const EdgeInsets.all(TingyuTokens.space),
              onPressed: track == null || p.opening
                  ? null
                  : () => report(context, p.toggle),
              child: TingyuIcon(
                p.playing ? Icons.pause : Icons.play_arrow,
                size: TingyuTokens.space * 3.5,
              ),
            ),
          ),
          transport(
            action(
              Icons.skip_next,
              '下一首',
              track == null || p.opening ? null : () => p.next(),
            ),
          ),
          Expanded(
            flex: compact ? 2 : 4,
            child: SeekBar(
              p,
              showTimes: !compact,
              timeFontSize: TingyuTokens.macCaption,
              enabled: track != null && !p.opening,
            ),
          ),
          transport(MacModeButton(p)),
          transport(action(Icons.volume_up, '播放音量', onVolume)),
          transport(action(Icons.queue_music, '待播清单', onQueue)),
          transport(action(Icons.more_horiz, '播放选项', onOptions)),
        ],
      ),
    );
  }
}

class MacModeButton extends StatelessWidget {
  const MacModeButton(this.p, {super.key});
  final LibraryController p;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: '${modeLabel(p.mode)}，点击切换',
    child: Pressable(
      key: const ValueKey('mac-cycle-mode'),
      label: '播放模式：${modeLabel(p.mode)}，点击切换',
      padding: const EdgeInsets.all(TingyuTokens.space),
      onPressed: () => report(context, () async {
        const modes = ['order', 'repeat', 'shuffle'];
        await p.setMode(modes[(modes.indexOf(p.mode) + 1) % modes.length]);
        p.announceMode(modeLabel(p.mode));
      }),
      child: TingyuIcon(modeIcon(p.mode), color: context.tokens.accentInk),
    ),
  );
}
