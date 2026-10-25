part of 'app.dart';

class GlassPreferencesScreen extends ConsumerStatefulWidget {
  const GlassPreferencesScreen({super.key});
  @override
  ConsumerState<GlassPreferencesScreen> createState() =>
      _GlassPreferencesState();
}

class _GlassPreferencesState extends ConsumerState<GlassPreferencesScreen>
    with WidgetsBindingObserver {
  bool preview = true;
  String? active;
  double? overall;
  bool mixed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void endPreview() {
    if (mounted && active != null) setState(() => active = null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) endPreview();
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(libraryProvider), t = context.tokens;
    overall ??= p.playerOpacity;
    Widget visible(Widget child, [String? id]) =>
        Opacity(opacity: active == null || active == id ? 1 : 0, child: child);
    Widget slider(String id, String title, double alpha, bool primary) =>
        visible(
          Container(
            key: ValueKey('glass-control-$id'),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: active == id
                  ? t.surface
                  : primary
                  ? t.tint
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      Expanded(child: Text(title)),
                      Text(
                        id == 'all' && mixed
                            ? '分别设置'
                            : '${((1 - alpha) * 100).round()}%',
                        style: TextStyle(
                          fontSize: id == 'all' && mixed
                              ? 13
                              : primary
                              ? 24
                              : 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Listener(
                  onPointerCancel: (_) => endPreview(),
                  child: Slider(
                    key: ValueKey('glass-slider-$id'),
                    min: 0,
                    max: 1,
                    value: 1 - alpha,
                    onChangeStart: (_) {
                      if (preview) setState(() => active = id);
                    },
                    onChangeEnd: (_) => endPreview(),
                    onChanged: (v) {
                      setState(() {
                        if (id == 'all') {
                          overall = 1 - v;
                          mixed = false;
                        } else {
                          mixed = true;
                        }
                      });
                      unawaited(
                        report(
                          context,
                          () => p.setGlass(
                            navigation: id == 'mini' ? null : 1 - v,
                            player: id == 'nav' ? null : 1 - v,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('不透明', style: TextStyle(fontSize: 10, color: t.muted)),
                    Text('透明', style: TextStyle(fontSize: 10, color: t.muted)),
                  ],
                ),
              ],
            ),
          ),
          id,
        );
    Widget previewDock() => IgnorePointer(
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: t.tint,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (p.current != null)
                MiniPlayer(p)
              else
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: GlassSurface(
                    opacity: p.glassAutomatic
                        ? p.autoGlassOpacity.value
                        : p.playerOpacity,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        children: [
                          TingyuIcon(Icons.music_note),
                          SizedBox(width: 12),
                          Expanded(child: Text('尚未播放')),
                          TingyuIcon(Icons.play_arrow),
                        ],
                      ),
                    ),
                  ),
                ),
              CompactNavigation(
                selected: 'library',
                onSelect: (_) {},
                controller: p,
              ),
            ],
          ),
        ),
      ),
    );
    return Stack(
      children: [
        if (active != null)
          Positioned.fill(
            child: ExcludeSemantics(
              child: IgnorePointer(child: AppShell(page: 'library')),
            ),
          ),
        Scaffold(
          key: const ValueKey('glass-settings-foreground'),
          backgroundColor: active == null ? t.background : Colors.transparent,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 608),
                child: Column(
                  children: [
                    visible(
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            action(
                              Icons.arrow_back,
                              '返回设置',
                              () => context.canPop()
                                  ? context.pop()
                                  : context.go('/settings'),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '玻璃透明度',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        key: const PageStorageKey('glass-settings'),
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            visible(
                              TingyuSegmented(
                                labels: const ['自动', '手动'],
                                index: p.glassAutomatic ? 0 : 1,
                                onChanged: (index) => report(context, () async {
                                  setState(() {
                                    overall = .26;
                                    mixed = false;
                                  });
                                  await p.setGlass(automatic: index == 0);
                                }),
                              ),
                            ),
                            if (!p.glassAutomatic) ...[
                              visible(
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text('按住预览'),
                                          Text(
                                            '拖动时查看实际页面，松开返回',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: t.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    TingyuToggle(
                                      label: '按住预览',
                                      value: preview,
                                      onChanged: (v) =>
                                          setState(() => preview = v),
                                    ),
                                  ],
                                ),
                              ),
                              slider('all', '两栏同步', overall!, true),
                              visible(
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        '单独微调',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    labelButton(
                                      '恢复默认',
                                      () => report(context, () async {
                                        setState(() {
                                          overall = .26;
                                          mixed = false;
                                        });
                                        await p.setGlass(
                                          navigation: .26,
                                          player: .26,
                                        );
                                      }),
                                      icon: Icons.refresh,
                                    ),
                                  ],
                                ),
                              ),
                              slider('nav', '导航栏', p.navigationOpacity, false),
                              visible(Divider(height: 1, color: t.line)),
                              slider('mini', '播放栏', p.playerOpacity, false),
                            ],
                          ],
                        ),
                      ),
                    ),
                    // Reserve the dock's measured layout before a drag starts.
                    // Hidden controls retain their position and pointer capture;
                    // the actual AppShell dock beneath is never covered.
                    visible(previewDock()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String storageSize(int bytes) => bytes < 1000000
    ? '${(bytes / 1000).round()} KB'
    : bytes >= 1000000000
    ? '${(bytes / 1000000000).toStringAsFixed(2)} GB'
    : '${(bytes / 1000000).toStringAsFixed(1)} MB';

class StoragePanel extends StatefulWidget {
  const StoragePanel(
    this.p, {
    super.key,
    this.fillViewport = false,
    this.desktop = false,
  });
  final LibraryController p;
  final bool fillViewport, desktop;
  @override
  State<StoragePanel> createState() => _StoragePanelState();
}

class _StoragePanelState extends State<StoragePanel> {
  late Future<StorageUsage> scan = StorageUsage.scanWithInstall(
    widget.p.downloads.directory.parent,
  );
  bool cleaning = false, choosing = false;
  void refresh() => setState(() {
    scan = StorageUsage.scanWithInstall(widget.p.downloads.directory.parent);
  });
  Future<void> choose(StorageUsage data) async {
    if (widget.desktop) {
      setState(() => choosing = true);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(TingyuTokens.space * 3),
          child: StorageCleanup(
            data: data,
            p: widget.p,
            onCancel: () => Navigator.pop(ctx),
            onDone: () {
              Navigator.pop(ctx);
              refresh();
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<StorageUsage>(
    future: scan,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return EmptyView(
          '暂时无法统计空间',
          '请检查存储是否可用',
          child: labelButton(
            '重试',
            () => setState(
              () => scan = StorageUsage.scanWithInstall(
                widget.p.downloads.directory.parent,
              ),
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.data!, t = context.tokens;
      if (choosing) {
        return StorageCleanup(
          data: data,
          p: widget.p,
          onCancel: () => setState(() => choosing = false),
          onDone: () {
            setState(() => choosing = false);
            refresh();
          },
        );
      }
      final colors = [
        t.accent,
        t.muted,
        t.accentInk,
        t.playerMuted,
        t.line,
        t.accentInk,
        t.playerMuted,
      ];
      final ring = Center(
        child: SizedBox.square(
          dimension: widget.desktop ? TingyuTokens.macStorageRing : 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: StorageRing(data.bytes.values.toList(), colors),
                ),
              ),
              StorageTotalLabel(
                total: data.total,
                diameter: widget.desktop ? TingyuTokens.macStorageRing : 160,
              ),
            ],
          ),
        ),
      );
      final categories = Column(
        children: [
          for (final item in data.bytes.entries.indexed)
            Padding(
              padding: EdgeInsets.symmetric(
                vertical: widget.desktop
                    ? TingyuTokens.space / 2
                    : TingyuTokens.space,
              ),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 8, color: colors[item.$1]),
                  const SizedBox(width: TingyuTokens.space),
                  Expanded(child: Text(item.$2.key)),
                  Text(storageSize(item.$2.value)),
                  const SizedBox(width: TingyuTokens.space * 2),
                  if (widget.desktop)
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${data.total == 0 ? 0 : (item.$2.value / data.total * 100).round()}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: t.muted),
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.desktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ring,
                const SizedBox(width: TingyuTokens.space * 3),
                Expanded(child: categories),
              ],
            )
          else ...[
            ring,
            const SizedBox(height: TingyuTokens.space * 2),
            categories,
          ],
          const Divider(height: TingyuTokens.space * 4),
          Row(
            children: [
              const Expanded(child: Text('自动缓存')),
              TingyuToggle(
                value: widget.p.autoCache,
                label: '自动缓存',
                onChanged: (value) async {
                  await report(context, () => widget.p.setAutoCache(value));
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
          Text(
            '播放时自动缓存，最多 2 GB',
            style: TextStyle(color: t.muted, fontSize: 12),
          ),
          Text(
            '达到上限时清理较早使用的缓存',
            style: TextStyle(color: t.muted, fontSize: 12),
          ),
          const SizedBox(height: TingyuTokens.space * 3),
          Pressable(
            key: const ValueKey('storage-clear-temporary'),
            label: '清理缓存与临时文件',
            color: t.tint,
            radius: TingyuTokens.space * 2,
            onPressed:
                (data.bytes['临时文件'] ?? 0) + (data.bytes['播放缓存'] ?? 0) == 0
                ? null
                : () => choose(data),
            child: Center(
              child: Text('清理缓存与临时文件', style: TextStyle(color: t.accentInk)),
            ),
          ),
          const SizedBox(height: TingyuTokens.space),
          Center(
            child: Text(
              '可清理 ${storageSize((data.bytes['临时文件'] ?? 0) + (data.bytes['播放缓存'] ?? 0))}',
              style: TextStyle(color: t.muted, fontSize: 12),
            ),
          ),
          if (data.installUnavailable)
            Text(
              '应用安装大小暂时无法获取',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.muted, fontSize: 11),
            ),
        ],
      );
    },
  );
}

class StorageCleanup extends StatefulWidget {
  const StorageCleanup({
    super.key,
    required this.data,
    required this.p,
    required this.onCancel,
    required this.onDone,
  });
  final StorageUsage data;
  final LibraryController p;
  final VoidCallback onCancel, onDone;
  @override
  State<StorageCleanup> createState() => _StorageCleanupState();
}

class _StorageCleanupState extends State<StorageCleanup> {
  bool temporary = true, cache = false, busy = false;
  String? error;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final amount =
        (temporary ? widget.data.bytes['临时文件'] ?? 0 : 0) +
        (cache ? widget.data.bytes['播放缓存'] ?? 0 : 0);
    Widget choice(
      String title,
      String subtitle,
      bool selected,
      int bytes,
      VoidCallback toggle,
    ) => Pressable(
      label: title,
      selected: selected,
      selectionFill: false,
      onPressed: busy || bytes == 0 ? null : toggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: TingyuTokens.space * 2),
        child: Row(
          children: [
            TingyuIcon(
              selected ? Icons.check_box : Icons.check_box_outline_blank,
              color: selected ? t.accentInk : t.muted,
            ),
            const SizedBox(width: TingyuTokens.space * 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title),
                  const SizedBox(height: TingyuTokens.space),
                  Text(
                    subtitle,
                    style: TextStyle(color: t.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(storageSize(bytes)),
          ],
        ),
      ),
    );
    return PopScope(
      canPop: !busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('清理缓存与临时文件', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: TingyuTokens.space),
          Text('选择本次要清理的内容', style: TextStyle(color: t.muted)),
          const SizedBox(height: TingyuTokens.space * 2),
          choice(
            '临时文件',
            '未完成或遗留的临时数据',
            temporary,
            widget.data.bytes['临时文件'] ?? 0,
            () => setState(() => temporary = !temporary),
          ),
          const Divider(),
          choice(
            '同时清理播放缓存',
            '清理后，再次播放需联网获取',
            cache,
            widget.data.bytes['播放缓存'] ?? 0,
            () => setState(() => cache = !cache),
          ),
          const Divider(),
          Text(
            '已下载歌曲和播放记录会保留\n正在使用的文件会跳过',
            style: TextStyle(color: t.muted, fontSize: 12),
          ),
          if (error != null) Text(error!, style: TextStyle(color: t.accentInk)),
          const SizedBox(height: TingyuTokens.space * 3),
          Row(
            children: [
              Expanded(child: labelButton('取消', busy ? null : widget.onCancel)),
              const SizedBox(width: TingyuTokens.space * 2),
              Expanded(
                child: Pressable(
                  label: busy ? '正在清理' : '清理 ${storageSize(amount)}',
                  color: t.accent,
                  radius: TingyuTokens.radius,
                  onPressed: busy || amount == 0
                      ? null
                      : () async {
                          setState(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            if (temporary) {
                              await widget.data.clearTemporary(
                                widget.p.downloads.directory.parent,
                                transferActive:
                                    widget.p.downloads.tasks.any(
                                      (x) =>
                                          x.status ==
                                              DownloadStatus.downloading ||
                                          x.status == DownloadStatus.waiting,
                                    ) ||
                                    (widget.p.downloads.cache?.transferring ??
                                        false),
                                skipActive: true,
                              );
                            }
                            if (cache) await widget.p.downloads.cache?.clear();
                            if (mounted) widget.onDone();
                          } on FileSystemException {
                            if (mounted) {
                              setState(() => error = '清理失败，请检查存储空间后重试');
                            }
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                  child: Center(
                    child: Text(
                      busy ? '正在清理…' : '清理 ${storageSize(amount)}',
                      style: const TextStyle(color: TingyuTokens.onArtwork),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class StorageTotalLabel extends StatelessWidget {
  const StorageTotalLabel({
    super.key,
    required this.total,
    required this.diameter,
  });
  final int total;
  final double diameter;
  @override
  Widget build(BuildContext context) {
    final parts = storageSize(total).split(' ');
    final inner =
        diameter -
        TingyuTokens.storageRingInset * 2 -
        TingyuTokens.storageRingStroke -
        TingyuTokens.space * 2;
    return Semantics(
      label: '占用 ${storageSize(total)}',
      child: SizedBox.square(
        key: const ValueKey('storage-total-label'),
        dimension: inner,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                parts.first,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                parts.skip(1).join(' '),
                style: TextStyle(fontSize: 12, color: context.tokens.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StorageRing extends CustomPainter {
  StorageRing(this.values, this.colors);
  final List<int> values;
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(TingyuTokens.storageRingInset);
    final total = values.fold(0, (a, b) => a + b);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = TingyuTokens.storageRingStroke;
    if (total == 0) {
      canvas.drawOval(rect, paint..color = colors.last);
      return;
    }
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      if (sweep > 0) {
        canvas.drawArc(rect, start, sweep, false, paint..color = colors[i]);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant StorageRing oldDelegate) =>
      !listEquals(values, oldDelegate.values) ||
      !listEquals(colors, oldDelegate.colors);
}

/// Samples only the body behind the dock, so the material never samples itself.
class GlassBackdrop extends StatefulWidget {
  const GlassBackdrop({super.key, required this.p, required this.child});
  final LibraryController p;
  final Widget child;
  @override
  State<GlassBackdrop> createState() => _GlassBackdropState();
}

class _GlassBackdropState extends State<GlassBackdrop>
    with WidgetsBindingObserver {
  final boundaryKey = GlobalKey();
  Timer? sampling;
  bool busy = false, resumed = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    sampling = Timer.periodic(const Duration(seconds: 2), (_) => sample());
    WidgetsBinding.instance.addPostFrameCallback((_) => sample());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    resumed = state == AppLifecycleState.resumed;
  }

  Future<void> sample() async {
    if (!mounted ||
        busy ||
        !resumed ||
        !widget.p.glassAutomatic ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    final boundary = boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderBackdropBoundary ||
        boundary.debugNeedsPaint ||
        boundary.size.isEmpty) {
      return;
    }
    busy = true;
    ui.Image? image;
    try {
      image = await boundary.capture();
      if (image == null) return;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (!mounted || data == null) return;
      final pixels = data.buffer.asUint8List();
      var sum = 0.0, squared = 0.0, count = 0;
      for (var y = (image.height * .65).floor(); y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final at = (y * image.width + x) * 4;
          final l =
              (.2126 * pixels[at] +
                  .7152 * pixels[at + 1] +
                  .0722 * pixels[at + 2]) /
              255;
          sum += l;
          squared += l * l;
          count++;
        }
      }
      if (count == 0) return;
      final mean = sum / count;
      final variance = (squared / count - mean * mean).clamp(0, 1);
      final value = (.24 + variance * 3 + (mean < .45 ? .12 : 0)).clamp(
        .24,
        .65,
      );
      if ((widget.p.autoGlassOpacity.value - value).abs() > .035) {
        widget.p.autoGlassOpacity.value = value;
      }
    } on Exception {
      // Preserve the last readable material when a frame is unavailable.
    } finally {
      image?.dispose();
      busy = false;
    }
  }

  @override
  void dispose() {
    sampling?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BackdropBoundary(key: boundaryKey, child: widget.child);
}

class AdaptiveGlass extends StatelessWidget {
  const AdaptiveGlass({
    super.key,
    required this.p,
    required this.navigation,
    required this.child,
  });
  final LibraryController p;
  final bool navigation;
  final Widget child;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: p.autoGlassOpacity,
    builder: (context, auto, _) => TweenAnimationBuilder<double>(
      tween: Tween(
        end: p.glassAutomatic
            ? auto
            : navigation
            ? p.navigationOpacity
            : p.playerOpacity,
      ),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : TingyuTokens.transition,
      builder: (context, opacity, _) =>
          GlassSurface(opacity: opacity, child: child),
    ),
  );
}

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: SafeArea(
      child: AccountPanel(ref.watch(libraryProvider), standalone: true),
    ),
  );
}

class BackdropBoundary extends SingleChildRenderObjectWidget {
  const BackdropBoundary({super.key, required super.child});
  @override
  RenderBackdropBoundary createRenderObject(BuildContext context) =>
      RenderBackdropBoundary();
}

class RenderBackdropBoundary extends RenderRepaintBoundary {
  Future<ui.Image?> capture() async {
    if (!attached || !hasSize || layer is! OffsetLayer) return null;
    return toImage(pixelRatio: .04);
  }
}
