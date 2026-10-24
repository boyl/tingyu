part of 'app.dart';

/// Optional owner for desktop navigation; mobile owns the same state internally.
class DownloadsViewMemory {
  final scrolls = [ScrollController(), ScrollController()];
  final searches = [TextEditingController(), TextEditingController()];
  bool searchOpen = false;
  void dispose() {
    for (final value in scrolls) {
      value.dispose();
    }
    for (final value in searches) {
      value.dispose();
    }
  }
}

/// Tab navigation is routed on mobile, callback-based inside the Mac workspace.
class DownloadsWorkspace extends StatefulWidget {
  const DownloadsWorkspace(
    this.p, {
    super.key,
    required this.tasks,
    required this.desktop,
    this.dockInset = 0,
    this.onSectionChanged,
    this.memory,
  });
  final LibraryController p;
  final bool tasks, desktop;
  final double dockInset;
  final ValueChanged<bool>? onSectionChanged;
  final DownloadsViewMemory? memory;
  @override
  State<DownloadsWorkspace> createState() => _DownloadsWorkspaceState();
}

class _DownloadsWorkspaceState extends State<DownloadsWorkspace> {
  late final memory = widget.memory ?? DownloadsViewMemory();
  List<ScrollController> get scrolls => memory.scrolls;
  List<TextEditingController> get searches => memory.searches;
  bool selecting = false;
  final selected = <String>{};
  bool get searchOpen => memory.searchOpen;
  set searchOpen(bool value) => memory.searchOpen = value;
  int get index => widget.tasks ? 1 : 0;
  @override
  void dispose() {
    if (widget.memory == null) memory.dispose();
    super.dispose();
  }

  Widget tab(bool tasks) {
    final selected = tasks == widget.tasks;
    final t = context.tokens;
    final count = widget.p.downloads.incompleteTasks.length;
    return Pressable(
      key: ValueKey(tasks ? 'downloads-tab-tasks' : 'downloads-tab-completed'),
      label: tasks ? '下载任务，共 $count 项' : '已下载',
      selected: selected,
      selectionFill: false,
      padding: EdgeInsets.zero,
      onPressed: () {
        if (selected) return;
        setState(() {
          selecting = false;
          this.selected.clear();
        });
        if (widget.onSectionChanged case final onChange?) {
          onChange(tasks);
        } else {
          context.go('/downloads?section=${tasks ? 'tasks' : 'completed'}');
        }
      },
      child: SizedBox(
        width: TingyuTokens.downloadTabWidth,
        height: TingyuTokens.downloadTabHeight,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: TingyuTokens.space * 2,
              child: Row(
                children: [
                  Text(
                    tasks ? '下载任务' : '已下载',
                    style: TextStyle(
                      color: selected ? t.accentInk : t.muted,
                      fontSize: 16,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (tasks && count > 0) ...[
                    const SizedBox(width: TingyuTokens.space),
                    Text(
                      '$count',
                      style: TextStyle(fontSize: 11, color: t.muted),
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              left: 0,
              bottom: 0,
              child: Container(
                width: TingyuTokens.space * 3,
                height: TingyuTokens.tabIndicatorHeight,
                decoration: BoxDecoration(
                  color: selected ? t.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                    TingyuTokens.tabIndicatorHeight,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p, t = context.tokens;
    final visible = p.downloads.completedTasks
        .where((d) => matchesLocal(d.track, searches[0].text))
        .map((d) => d.track.id)
        .toList();
    selected.retainAll(visible);
    final inset = widget.desktop ? 36.0 : 20.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, inset, inset, TingyuTokens.space * 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '离线随行',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              action(
                Icons.search,
                '搜索本地歌曲',
                () => setState(() {
                  searchOpen = !searchOpen;
                  if (!searchOpen) searches[index].clear();
                }),
              ),
            ],
          ),
          if (p.error.isNotEmpty) errorBox(context, p.error, p.clearError),
          if (searchOpen) ...[
            const SizedBox(height: TingyuTokens.space * 2),
            TextField(
              key: const ValueKey('downloads-search'),
              controller: searches[index],
              decoration: InputDecoration(
                hintText: widget.tasks ? '搜索下载任务' : '搜索已下载歌曲',
                prefixIcon: const TingyuIcon(Icons.search),
                suffixIcon: action(
                  Icons.clear_all,
                  '清除本地搜索',
                  () => setState(searches[index].clear),
                ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: TingyuTokens.space * 3),
          Row(children: [tab(false), tab(true)]),
          Divider(height: 1, color: t.line),
          if (!widget.tasks)
            SizedBox(
              height:
                  measuredSelectionToolbar(
                    context,
                    MediaQuery.sizeOf(context).width - inset * 2,
                    visible.length,
                    true,
                  ).compact
                  ? TingyuTokens.controlSize * 2
                  : TingyuTokens.controlSize,
              child: selecting
                  ? SelectionToolbar(
                      scope: 'downloads',
                      selectedIds: selected.toList(),
                      totalCount: visible.length,
                      allSelected:
                          visible.isNotEmpty && selected.containsAll(visible),
                      onSelectAll: () => setState(() {
                        selected.containsAll(visible)
                            ? selected.clear()
                            : selected.addAll(visible);
                      }),
                      onDone: () => setState(() {
                        selecting = false;
                        selected.clear();
                      }),
                    )
                  : Align(
                      alignment: Alignment.centerRight,
                      child: action(
                        Icons.checklist,
                        '批量选择',
                        visible.isEmpty
                            ? null
                            : () => setState(() {
                                selecting = true;
                                selected.clear();
                              }),
                      ),
                    ),
            ),
          Expanded(
            child: IndexedStack(
              index: index,
              children: [
                for (var i = 0; i < 2; i++)
                  ScrollToTop(
                    enabled: false,
                    key: ValueKey('downloads-scroll-$i'),
                    controller: scrolls[i],
                    builder: (scroll) => CustomScrollView(
                      key: PageStorageKey('downloads-list-$i'),
                      controller: scroll,
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.only(
                            top: TingyuTokens.space * 2,
                            bottom: TingyuTokens.space * 10 + widget.dockInset,
                          ),
                          sliver: DownloadsPanel(
                            p,
                            sliver: true,
                            showTasks: i == 1,
                            query: searches[i].text,
                            selected: i == 0 && selecting ? selected : null,
                            onToggle: (id) => setState(() {
                              selected.contains(id)
                                  ? selected.remove(id)
                                  : selected.add(id);
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
