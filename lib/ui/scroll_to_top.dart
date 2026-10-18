import 'package:flutter/material.dart';
import 'theme.dart';
import 'icons.dart';

/// Only the small overlay rebuilds as the scroll threshold changes.
class ScrollToTop extends StatefulWidget {
  const ScrollToTop({super.key, this.controller, required this.builder});
  final ScrollController? controller;
  final Widget Function(ScrollController controller) builder;
  @override
  State<ScrollToTop> createState() => _ScrollToTopState();
}

class _ScrollToTopState extends State<ScrollToTop> {
  late final ScrollController scroll = widget.controller ?? ScrollController();
  final visible = ValueNotifier(false);
  @override
  void initState() {
    super.initState();
    scroll.addListener(update);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) update();
    });
  }

  void update() {
    final show =
        scroll.hasClients &&
        scroll.position.hasContentDimensions &&
        scroll.offset > scroll.position.viewportDimension;
    if (visible.value != show) visible.value = show;
  }

  @override
  void dispose() {
    scroll.removeListener(update);
    if (widget.controller == null) scroll.dispose();
    visible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) update();
            });
          }
          return false;
        },
        child: Stack(
          children: [
            Positioned.fill(child: widget.builder(scroll)),
            Positioned(
              right: TingyuTokens.space * 2,
              bottom: TingyuTokens.space * 2,
              child: ValueListenableBuilder<bool>(
                valueListenable: visible,
                builder: (context, show, _) => show
                    ? Tooltip(
                        message: '回到顶部',
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: context.tokens.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: context.tokens.line),
                            boxShadow: [
                              BoxShadow(
                                color: context.tokens.playerShadow,
                                blurRadius: TingyuTokens.space,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Pressable(
                            key: const ValueKey('scroll-to-top'),
                            label: '回到顶部',
                            radius: 48,
                            onPressed: () {
                              if (MediaQuery.disableAnimationsOf(context)) {
                                scroll.jumpTo(0);
                              } else {
                                scroll.animateTo(
                                  0,
                                  duration: TingyuTokens.scrollReturn,
                                  curve: Curves.easeOutCubic,
                                );
                              }
                            },
                            child: TingyuIcon(
                              Icons.vertical_align_top,
                              color: context.tokens.accent,
                              size: 20,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      );
}
