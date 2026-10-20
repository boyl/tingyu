part of 'app.dart';

class _PlayerHeaderStatusState extends State<PlayerHeaderStatus>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final motion = AnimationController(vsync: this);
  double span = 0;
  bool get running =>
      mounted &&
      !widget.hold &&
      widget.status.startsWith('正在播放') &&
      !MediaQuery.disableAnimationsOf(context) &&
      TickerMode.valuesOf(context).enabled &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void sync() {
    if (running && span > 0) {
      if (!motion.isAnimating) motion.repeat();
    } else {
      motion.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) sync();
    });
  }

  @override
  void didUpdateWidget(covariant PlayerHeaderStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status ||
        oldWidget.mode != widget.mode ||
        oldWidget.hold != widget.hold) {
      motion.stop();
      motion.value = 0;
      span = 0;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => sync();
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = switch (widget.mode) {
      'shuffle' => '随机播放',
      'repeat' => '单曲循环',
      'once' => '播完暂停',
      _ => '列表循环',
    };
    final text = widget.hold || !widget.status.startsWith('正在播放')
        ? widget.status
        : '${widget.status}　｜　$mode';
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(TextStyle(color: context.tokens.muted, fontSize: 13));
    final animate =
        !widget.hold &&
        widget.status.startsWith('正在播放') &&
        !MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: SizedBox(
          height: TingyuTokens.controlSize,
          child: LayoutBuilder(
            builder: (context, box) {
              if (!animate) {
                return Center(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                );
              }
              final painter = TextPainter(
                text: TextSpan(text: text, style: style),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final nextSpan =
                  math.max(box.maxWidth, painter.width) +
                  TingyuTokens.marqueeGap;
              painter.dispose();
              if (span != nextSpan) {
                span = nextSpan;
                motion.stop();
                motion.duration = Duration(
                  milliseconds: (span / TingyuTokens.marqueeSpeed * 1000)
                      .round(),
                );
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) sync();
                });
              }
              Widget copy() => SizedBox(
                width: span,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(text, maxLines: 1, softWrap: false, style: style),
                ),
              );
              return ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: span * 2,
                  maxWidth: span * 2,
                  child: AnimatedBuilder(
                    animation: motion,
                    child: Row(children: [copy(), copy()]),
                    builder: (context, child) => Transform.translate(
                      key: const ValueKey('player-status-marquee'),
                      offset: Offset(-motion.value * span, 0),
                      child: child,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
