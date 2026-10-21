part of 'app.dart';

const tingyuVersion = '0.1.24';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingsPageFrame(
    title: '设置',
    child: SettingsPanel(ref.watch(libraryProvider)),
  );
}

class SettingsStorageScreen extends ConsumerWidget {
  const SettingsStorageScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingsPageFrame(
    title: '存储空间',
    fillViewport: true,
    backLabel: '返回设置',
    fallback: '/settings',
    child: StoragePanel(ref.watch(libraryProvider), fillViewport: true),
  );
}

class SettingsPageFrame extends StatelessWidget {
  const SettingsPageFrame({
    super.key,
    required this.title,
    required this.child,
    this.backLabel = '返回',
    this.fallback = '/',
    this.fillViewport = false,
  });
  final String title, backLabel, fallback;
  final bool fillViewport;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();
    void back() => canPop ? context.pop() : context.go(fallback);
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !canPop) context.go(fallback);
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 608),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        action(Icons.arrow_back, backLabel, back),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        key: PageStorageKey('settings-$title'),
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                        child: fillViewport
                            ? ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: math.max(0, box.maxHeight - 40),
                                ),
                                child: IntrinsicHeight(child: child),
                              )
                            : child,
                      ),
                    ),
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

class SettingsPanel extends StatelessWidget {
  const SettingsPanel(this.p, {super.key});
  final LibraryController p;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final connected = p.profile != null || p.api.hasSession;
    final bytes = p.downloads.tasks
        .where((x) => x.status == DownloadStatus.completed)
        .fold<int>(0, (sum, task) => sum + task.received);
    final usage = bytes >= 1024 * 1024 * 1024
        ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
        : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    Widget heading(String title) => Padding(
      padding: const EdgeInsets.only(
        top: TingyuTokens.space * 3,
        bottom: TingyuTokens.space * 2,
      ),
      child: Text(
        title,
        style: TextStyle(
          color: t.text,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Pressable(
          key: const ValueKey('settings-account'),
          label: '账号',
          onPressed: () => context.push('/settings/account'),
          padding: const EdgeInsets.symmetric(vertical: TingyuTokens.space * 2),
          child: Row(
            children: [
              AccountAvatar(
                profile: p.profile,
                size: TingyuTokens.profileAvatarSize,
              ),
              const SizedBox(width: TingyuTokens.space * 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p.profile?['uname'] ?? (connected ? '已连接' : '登录 tingyu')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.text,
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: TingyuTokens.space),
                    Text(
                      connected ? 'B 站账号已连接' : '连接 B 站，收藏喜欢的声音',
                      style: TextStyle(color: t.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SettingsChevron(),
            ],
          ),
        ),
        Divider(height: TingyuTokens.space * 2, color: t.line),
        heading('外观'),
        ThemeShelf(p),
        const SizedBox(height: TingyuTokens.space * 3),
        Divider(height: 1, color: t.line),
        SettingsRow(
          icon: Icons.blur_on,
          title: '玻璃透明度',
          value: p.glassAutomatic ? '自动' : '手动',
          keyName: 'settings-glass',
          onPressed: () => context.push('/settings/glass'),
        ),
        heading('播放与存储'),
        SettingsRow(
          icon: Icons.speed,
          title: '默认倍速',
          value: rateLabel(p.speed),
          keyName: 'settings-speed',
          onPressed: () => showPlaybackSettings(context, p, timer: false),
        ),
        SettingsRow(
          icon: Icons.schedule,
          title: '定时关闭',
          value: p.sleepTimer.active ? timerLabel(p) : '未开启',
          keyName: 'settings-timer',
          onPressed: () => showPlaybackSettings(context, p, timer: true),
        ),
        SettingsRow(
          icon: Icons.graphic_eq,
          title: '音质偏好',
          value: p.standard ? '标准' : '高音质',
          keyName: 'settings-quality',
          onPressed: () => showContentActions(
            context,
            (ctx) => SimpleDialog(
              title: const Text('音质'),
              children: [
                for (final item in [(false, '高音质'), (true, '标准')])
                  Pressable(
                    key: ValueKey('quality-${item.$1}'),
                    selected: p.standard == item.$1,
                    onPressed: () => report(ctx, () async {
                      await p.setStandard(item.$1);
                    }),
                    child: Row(
                      children: [
                        Expanded(child: Text(item.$2)),
                        if (p.standard == item.$1)
                          TingyuIcon(Icons.check, color: t.accent),
                      ],
                    ),
                  ),
              ],
            ),
            listenable: p,
          ),
        ),
        Divider(height: 1, color: t.line),
        SettingsRow(
          icon: Icons.download_outlined,
          title: '存储空间',
          value: usage,
          keyName: 'settings-storage',
          onPressed: () => context.push('/settings/downloads'),
        ),
        Divider(height: TingyuTokens.space * 3, color: t.line),
        SettingsRow(
          icon: Icons.info_outline,
          title: '关于 tingyu',
          keyName: 'settings-about',
          onPressed: () => showAboutTingyu(context),
        ),
      ],
    );
  }
}

/// Reveal only the selected theme; vertical settings scroll is untouched.
class ThemeShelf extends StatefulWidget {
  const ThemeShelf(this.p, {super.key});
  final LibraryController p;
  @override
  State<ThemeShelf> createState() => _ThemeShelfState();
}

class _ThemeShelfState extends State<ThemeShelf> {
  final scroll = ScrollController();
  String? revealed;
  double? lastWidth;
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = shelfCardWidth(constraints.maxWidth).clamp(110.0, 184.0);
      if (revealed != widget.p.theme || lastWidth != constraints.maxWidth) {
        final initial = revealed == null;
        revealed = widget.p.theme;
        lastWidth = constraints.maxWidth;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !scroll.hasClients) return;
          final index = TingyuTokens.themes.indexWhere(
            (item) => item.$1 == widget.p.theme,
          );
          final target =
              (index * (width + TingyuTokens.space * 1.5) -
                      (constraints.maxWidth - width) / 2)
                  .clamp(0.0, scroll.position.maxScrollExtent);
          if (initial || MediaQuery.disableAnimationsOf(context)) {
            scroll.jumpTo(target);
          } else {
            scroll.animateTo(
              target,
              duration: TingyuTokens.transition,
              curve: Curves.easeOutCubic,
            );
          }
        });
      }
      return SingleChildScrollView(
        key: const ValueKey('theme-shelf'),
        controller: scroll,
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in TingyuTokens.themes)
              Padding(
                padding: const EdgeInsets.only(right: TingyuTokens.space * 1.5),
                child: SizedBox(
                  width: width,
                  child: ThemePreview(
                    name: item.$2,
                    tokens: item.$3,
                    selected: widget.p.theme == item.$1,
                    themeId: item.$1,
                    onPressed: () async {
                      await report(context, () => widget.p.setTheme(item.$1));
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class SettingsChevron extends StatelessWidget {
  const SettingsChevron({super.key});
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: TingyuTokens.iconSize,
    child: Center(
      child: TingyuIcon(
        Icons.chevron_right,
        size: 18,
        color: context.tokens.muted,
      ),
    ),
  );
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.keyName,
    required this.onPressed,
    this.value,
  });
  final IconData icon;
  final String title, keyName;
  final String? value;
  final FutureOr<void> Function()? onPressed;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Pressable(
      key: ValueKey(keyName),
      label: value == null ? title : '$title，$value',
      onPressed: onPressed == null ? null : () => report(context, onPressed!),
      padding: const EdgeInsets.symmetric(vertical: TingyuTokens.space * 1.5),
      child: Row(
        children: [
          Container(
            width: TingyuTokens.space * 4,
            height: TingyuTokens.space * 4,
            decoration: BoxDecoration(
              color: t.tint,
              borderRadius: BorderRadius.circular(TingyuTokens.radius),
            ),
            alignment: Alignment.center,
            child: TingyuIcon(icon, size: 18, color: t.accent),
          ),
          const SizedBox(width: TingyuTokens.space * 1.5),
          Expanded(
            child: Text(title, style: TextStyle(color: t.text, fontSize: 14)),
          ),
          if (value != null) ...[
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width / 3,
              ),
              child: Text(
                value!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(color: t.muted, fontSize: 12),
              ),
            ),
            const SizedBox(width: TingyuTokens.space),
          ],
          const SettingsChevron(),
        ],
      ),
    );
  }
}

class ThemePreview extends StatelessWidget {
  const ThemePreview({
    super.key,
    required this.name,
    required this.tokens,
    required this.selected,
    required this.themeId,
    required this.onPressed,
  });
  final String name, themeId;
  final TingyuTokens tokens;
  final bool selected;
  final FutureOr<void> Function() onPressed;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Tooltip(
      message: name,
      child: Pressable(
        key: ValueKey('theme-$themeId'),
        label: '$name主题',
        selected: selected,
        selectionFill: false,
        onPressed: onPressed,
        padding: const EdgeInsets.all(TingyuTokens.space / 2),
        child: Column(
          children: [
            Container(
              height: TingyuTokens.themePreviewHeight,
              padding: const EdgeInsets.all(TingyuTokens.space),
              decoration: BoxDecoration(
                color: tokens.background,
                borderRadius: BorderRadius.circular(TingyuTokens.radius),
                border: Border.all(
                  color: selected ? t.playerButton : t.line,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: TingyuTokens.space * 2,
                    height: 3,
                    color: tokens.text,
                  ),
                  const SizedBox(height: TingyuTokens.space),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          TingyuTokens.space / 2,
                        ),
                        gradient: LinearGradient(
                          colors: [tokens.tint, tokens.playerButton],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: TingyuTokens.space / 2),
                  SizedBox(
                    height: TingyuTokens.space * 2,
                    child: Row(
                      children: [
                        for (var i = 0; i < 3; i++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 3),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: i == 1 ? tokens.tint : tokens.surface,
                                  border: Border.all(color: tokens.line),
                                  borderRadius: BorderRadius.circular(
                                    TingyuTokens.space / 2,
                                  ),
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: TingyuTokens.space / 2),
                  Container(
                    height: TingyuTokens.space * 1.5,
                    decoration: BoxDecoration(
                      color: tokens.playerSurface,
                      borderRadius: BorderRadius.circular(
                        TingyuTokens.space / 2,
                      ),
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.all(3),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: tokens.playerButton,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: TingyuTokens.space),
            Text(
              name,
              style: TextStyle(
                color: selected ? t.accentInk : t.muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: TingyuTokens.space / 2),
            SizedBox(
              height: TingyuTokens.space * 2,
              child: selected
                  ? TingyuIcon(
                      Icons.check_circle_outline,
                      size: TingyuTokens.space * 2,
                      color: t.accent,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
