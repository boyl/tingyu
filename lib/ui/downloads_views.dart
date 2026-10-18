part of 'app.dart';

/// Tab navigation is routed; search and scroll remain local to each tab.
class DownloadsWorkspace extends StatefulWidget {
  const DownloadsWorkspace(
    this.p, {
    super.key,
    required this.tasks,
    required this.desktop,
  });
  final LibraryController p;
  final bool tasks, desktop;
  @override
  State<DownloadsWorkspace> createState() => _DownloadsWorkspaceState();
}

class _DownloadsWorkspaceState extends State<DownloadsWorkspace> {
  final scrolls = [ScrollController(), ScrollController()];
  final searches = [TextEditingController(), TextEditingController()];
  final searchOpen = [false, false];
  int get index => widget.tasks ? 1 : 0;
  @override
  void dispose() {
    for (final scroll in scrolls) {
      scroll.dispose();
    }
    for (final search in searches) {
      search.dispose();
    }
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
        FocusManager.instance.primaryFocus?.unfocus();
        context.go('/downloads?section=${tasks ? 'tasks' : 'completed'}');
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
                      color: selected ? t.accent : t.muted,
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
                  searchOpen[index] = !searchOpen[index];
                  if (!searchOpen[index]) searches[index].clear();
                }),
              ),
            ],
          ),
          if (p.error.isNotEmpty) errorBox(context, p.error, p.clearError),
          if (searchOpen[index]) ...[
            const SizedBox(height: TingyuTokens.space * 2),
            TextField(
              key: ValueKey('downloads-search-$index'),
              controller: searches[index],
              decoration: InputDecoration(
                hintText: widget.tasks ? '搜索下载任务' : '搜索已下载歌曲',
                prefixIcon: const TingyuIcon(Icons.search),
                suffixIcon: action(
                  Icons.close,
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
          Expanded(
            child: IndexedStack(
              index: index,
              children: [
                for (var i = 0; i < 2; i++)
                  ScrollToTop(
                    key: ValueKey('downloads-scroll-$i'),
                    controller: scrolls[i],
                    builder: (scroll) => CustomScrollView(
                      key: PageStorageKey('downloads-list-$i'),
                      controller: scroll,
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.only(
                            top: TingyuTokens.space * 2,
                            bottom: TingyuTokens.space * 10,
                          ),
                          sliver: DownloadsPanel(
                            p,
                            sliver: true,
                            showTasks: i == 1,
                            query: searches[i].text,
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
