import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';

/// Paint-only animation, isolated from queue layout and playback position.
class PlayingIndicator extends StatefulWidget {
  const PlayingIndicator({super.key});
  @override
  State<PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final phase = AnimationController(
    vsync: this,
    duration: TingyuTokens.playingPeriod,
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      phase.stop();
      phase.value = .25;
    } else if (!phase.isAnimating) {
      phase.repeat();
    }
  }

  @override
  void dispose() {
    phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '正在播放',
    child: RepaintBoundary(
      child: CustomPaint(
        size: const Size(18, 18),
        painter: _PlayingBars(phase, context.tokens.accent),
      ),
    ),
  );
}

class _PlayingBars extends CustomPainter {
  _PlayingBars(this.phase, this.color) : super(repaint: phase);
  final Animation<double> phase;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var i = 0; i < 3; i++) {
      final height = 5 + (math.sin(phase.value * math.pi * 2 + i * 2) + 1) * 6;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1 + i * 6, (size.height - height) / 2, 3, height),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlayingBars old) =>
      old.color != color || old.phase != phase;
}
