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
  bool cleaning = false;
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
      final colors = [
        t.accent,
        t.muted,
        t.accentInk,
        t.playerMuted,
        t.line,
        t.accentInk,
      ];
      final ring = Center(
        child: SizedBox.square(
          dimension: widget.desktop ? TingyuTokens.macStorageRing : 228,
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
                diameter: widget.desktop ? TingyuTokens.macStorageRing : 228,
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
                    ? TingyuTokens.space
                    : TingyuTokens.space * 2,
              ),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 8, color: colors[item.$1]),
                  const SizedBox(width: TingyuTokens.space),
                  Expanded(child: Text(item.$2.key)),
                  Text(storageSize(item.$2.value)),
                  const SizedBox(width: TingyuTokens.space * 2),
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
          if (widget.fillViewport) const Spacer(),
          const SizedBox(height: TingyuTokens.space * 3),
          Center(
            child: Pressable(
              key: const ValueKey('storage-clear-temporary'),
              label: cleaning ? '正在清理' : '清理临时文件',
              color: t.tint,
              radius: TingyuTokens.space * 2,
              padding: const EdgeInsets.symmetric(
                horizontal: TingyuTokens.space * 2,
                vertical: TingyuTokens.space * 2,
              ),
              onPressed: cleaning || data.temporary.isEmpty
                  ? null
                  : () async {
                      if (!await confirm(
                        context,
                        '清理非活动临时文件？已下载歌曲、歌单和喜欢会保留。',
                      )) {
                        return;
                      }
                      setState(() => cleaning = true);
                      try {
                        await data.clearTemporary(
                          widget.p.downloads.directory.parent,
                          transferActive: widget.p.downloads.tasks.any(
                            (x) => [
                              DownloadStatus.waiting,
                              DownloadStatus.downloading,
                            ].contains(x.status),
                          ),
                        );
                        if (mounted) {
                          setState(
                            () => scan = StorageUsage.scanWithInstall(
                              widget.p.downloads.directory.parent,
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => cleaning = false);
                      }
                    },
              child: SizedBox(
                width: double.infinity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TingyuIcon(Icons.clear_all, color: t.accentInk),
                    const SizedBox(width: TingyuTokens.space * 1.5),
                    Text(
                      cleaning ? '正在清理…' : '清理临时文件',
                      style: TextStyle(color: t.accentInk),
                    ),
                    const SizedBox(width: TingyuTokens.space * 1.5),
                    Text(
                      storageSize(data.bytes['临时文件'] ?? 0),
                      style: TextStyle(color: t.accentInk, fontSize: 12),
                    ),
                  ],
                ),
              ),
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
