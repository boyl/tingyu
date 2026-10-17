part of 'app.dart';

const tingyuVersion = '0.1.10';

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
    title: '下载管理',
    backLabel: '返回设置',
    fallback: '/settings',
    child: DownloadsPanel(ref.watch(libraryProvider)),
  );
}

class SettingsPageFrame extends StatelessWidget {
  const SettingsPageFrame({
    super.key,
    required this.title,
    required this.child,
    this.backLabel = '返回',
    this.fallback = '/',
  });
  final String title, backLabel, fallback;
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
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      key: PageStorageKey('settings-$title'),
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      child: child,
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
    Widget heading(String label) => Padding(
      padding: const EdgeInsets.only(left: 4, top: 32, bottom: 16),
      child: Text(label, style: TextStyle(color: t.muted, fontSize: 13)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Pressable(
                key: const ValueKey('settings-account'),
                label: '账号',
                onPressed: () => showAccount(context, p),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: t.tint,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.person_outline, color: t.accent),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${p.profile?['uname'] ?? (connected ? '已连接' : '未登录')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            connected ? '管理 B 站账号' : '连接 B 站账号',
                            style: TextStyle(color: t.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: t.muted),
                  ],
                ),
              ),
              Divider(height: 1, color: t.line),
              Pressable(
                key: const ValueKey('settings-import'),
                label: connected ? '导入收藏夹' : '登录后可导入收藏夹',
                onPressed: connected ? () => showAccount(context, p) : null,
                child: Row(
                  children: [
                    Icon(Icons.playlist_add, size: 20, color: t.muted),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('导入收藏夹')),
                    if (!connected)
                      Text(
                        '登录后',
                        style: TextStyle(color: t.muted, fontSize: 11),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        heading('外观'),
        SettingsSurface(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('主题'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (final item in [
                      ('a', '暖白', TingyuTokens.light),
                      ('b', '深色', TingyuTokens.dark),
                      ('c', '冷白', TingyuTokens.pink),
                    ]) ...[
                      if (item.$1 != 'a') const SizedBox(width: 12),
                      Expanded(
                        child: Tooltip(
                          message: item.$2,
                          child: Pressable(
                            key: ValueKey('theme-${item.$1}'),
                            label: '${item.$2}主题',
                            selected: p.theme == item.$1,
                            onPressed: () =>
                                report(context, () => p.setTheme(item.$1)),
                            padding: EdgeInsets.zero,
                            child: Container(
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: item.$3.background,
                                borderRadius: BorderRadius.circular(
                                  TingyuTokens.radius,
                                ),
                                border: Border.all(
                                  color: p.theme == item.$1 ? t.accent : t.line,
                                  width: p.theme == item.$1 ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (p.theme == item.$1) ...[
                                    Icon(
                                      Icons.check,
                                      size: 16,
                                      color: item.$3.accent,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    item.$2,
                                    style: TextStyle(
                                      color: item.$3.text,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        heading('播放'),
        SettingsSurface(
          child: SettingsRow(
            icon: Icons.graphic_eq,
            title: '音质',
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
                        if (ctx.mounted) Navigator.pop(ctx);
                      }),
                      child: Row(
                        children: [
                          Expanded(child: Text(item.$2)),
                          if (p.standard == item.$1)
                            Icon(Icons.check, color: t.accent),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        heading('存储'),
        SettingsSurface(
          child: SettingsRow(
            icon: Icons.download_outlined,
            title: '下载管理',
            value: usage,
            keyName: 'settings-storage',
            onPressed: () => context.push('/settings/downloads'),
          ),
        ),
        const SizedBox(height: 40),
        SettingsSurface(
          child: SettingsRow(
            icon: Icons.info_outline,
            title: '关于听屿',
            keyName: 'settings-about',
            onPressed: () => showAboutTingyu(context),
          ),
        ),
        const SizedBox(height: 48),
        Center(
          child: Text(
            '听屿  $tingyuVersion',
            style: TextStyle(color: t.muted, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class SettingsSurface extends StatelessWidget {
  const SettingsSurface({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.tokens.surface,
      borderRadius: BorderRadius.circular(TingyuTokens.radius),
      border: Border.all(color: context.tokens.line),
    ),
    child: child,
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
  final FutureOr<void> Function() onPressed;
  @override
  Widget build(BuildContext context) => Pressable(
    key: ValueKey(keyName),
    onPressed: () => report(context, onPressed),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
    child: Row(
      children: [
        Icon(icon, size: 22, color: context.tokens.muted),
        const SizedBox(width: 16),
        Expanded(child: Text(title)),
        if (value != null) ...[
          Text(
            value!,
            style: TextStyle(color: context.tokens.muted, fontSize: 13),
          ),
          const SizedBox(width: 8),
        ],
        Icon(Icons.chevron_right, size: 22, color: context.tokens.muted),
      ],
    ),
  );
}
