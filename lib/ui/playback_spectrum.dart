import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import '../controllers/library_controller.dart';
import 'theme.dart';

const spectrumBands = 32;
const spectrumRest = 3.0;

bool spectrumIsLive({
  required bool playing,
  required bool ready,
  required bool opening,
  required bool seeking,
  required bool reducedMotion,
}) => playing && ready && !opening && !seeking && !reducedMotion;

List<double> spectrumBarHeights(
  List<double> levels,
  double span, {
  required bool live,
}) {
  final rest = math.min(spectrumRest, span);
  if (!live) return List<double>.filled(spectrumBands, rest);
  return List<double>.generate(spectrumBands, (index) {
    final level = index < levels.length ? levels[index].clamp(0.0, 1.0) : 0.0;
    return rest + (span - rest) * level;
  });
}

class LiveSpectrum {
  static const _control = MethodChannel('app.tingyu/spectrum');
  static const _events = EventChannel('app.tingyu/spectrum/events');
  static Stream<List<double>>? _cached;

  static Stream<List<double>> get events =>
      _cached ??= _events.receiveBroadcastStream().map((event) {
        final values = event as List;
        return [
          for (final value in values)
            (value as num).toDouble().clamp(0.0, 1.0).toDouble(),
        ];
      });

  static Future<void> start(int sessionId) =>
      _control.invokeMethod('start', {'sessionId': sessionId});

  static Future<void> stop() => _control.invokeMethod('stop');
}

class PlaybackSpectrum extends StatefulWidget {
  const PlaybackSpectrum(this.controller, {super.key, this.seeking = false});
  final LibraryController controller;
  final bool seeking;
  @override
  State<PlaybackSpectrum> createState() => _PlaybackSpectrumState();
}

class _PlaybackSpectrumState extends State<PlaybackSpectrum>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  StreamSubscription<List<double>>? _levels;
  StreamSubscription<PlayerState>? _state;
  StreamSubscription<int?>? _session;
  List<double> _shown = List<double>.filled(spectrumBands, 0);
  List<double> _target = List<double>.filled(spectrumBands, 0);
  int? _sessionId;
  bool _live = false;
  bool _capturing = false;
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    if (!Platform.isAndroid) return;
    final player = widget.controller.playback.player;
    _levels = LiveSpectrum.events.listen((levels) {
      if (!_live) return;
      _target = List<double>.generate(
        spectrumBands,
        (index) => index < levels.length ? levels[index] : 0,
      );
    }, onError: (_, _) {});
    _state = player.playerStateStream.listen((_) => _sync());
    _session = player.androidAudioSessionIdStream.listen((_) => _sync());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync(rebuild: _armed);
    _armed = true;
  }

  @override
  void didUpdateWidget(covariant PlaybackSpectrum oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync({bool rebuild = true}) {
    if (!mounted) return;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final player = widget.controller.playback.player;
    final live =
        Platform.isAndroid &&
        spectrumIsLive(
          playing: player.playing,
          ready: player.processingState == ProcessingState.ready,
          opening: widget.controller.opening,
          seeking: widget.seeking,
          reducedMotion: reduced,
        );
    final changed = live != _live;
    _live = live;
    if (!live && _capturing) {
      _capturing = false;
      _sessionId = null;
      unawaited(LiveSpectrum.stop());
    } else if (live) {
      final id = player.androidAudioSessionId;
      if (id != null && id > 0 && id != _sessionId) {
        _sessionId = id;
        _capturing = true;
        unawaited(LiveSpectrum.start(id));
      }
    }
    if (reduced) {
      _shown = List<double>.filled(spectrumBands, 0);
      _target = List<double>.filled(spectrumBands, 0);
      _ticker.stop();
    } else if ((_live || _shown.any((value) => value > 0.01)) &&
        !_ticker.isActive) {
      _ticker.start();
    }
    if (rebuild && changed) setState(() {});
  }

  void _tick(Duration _) {
    if (!mounted) return;
    var moving = false;
    final next = List<double>.generate(spectrumBands, (index) {
      final goal = _live
          ? (_target.length > index ? _target[index] : 0.0)
          : 0.0;
      final current = _shown[index];
      final value = goal >= current ? goal : current * .82 + goal * .18;
      if ((value - goal).abs() > .01) moving = true;
      return value;
    });
    _shown = next;
    if (!_live && !moving) {
      _shown = List<double>.filled(spectrumBands, 0);
      _ticker.stop();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    unawaited(_levels?.cancel());
    unawaited(_state?.cancel());
    unawaited(_session?.cancel());
    if (_capturing) unawaited(LiveSpectrum.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final moving = _shown.any((value) => value > .02);
    final span = TingyuTokens.space * 5;
    return Semantics(
      label: _live || moving ? '实时频谱' : '频谱已落下',
      child: SizedBox(
        height: span,
        width: double.infinity,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _SpectrumPainter(
              spectrumBarHeights(_shown, span, live: _live || moving),
              (_live || moving)
                  ? context.tokens.accent
                  : context.tokens.playerTrack,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter(this.heights, this.color);
  final List<double> heights;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (heights.isEmpty || size.width <= 0 || size.height <= 0) return;
    final paint = Paint()..color = color;
    const gap = 2.0;
    final width = math.max(
      1.0,
      (size.width - gap * (heights.length - 1)) / heights.length,
    );
    for (var i = 0; i < heights.length; i++) {
      final bar = heights[i].clamp(0.0, size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * (width + gap), size.height - bar, width, bar),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.heights != heights;
}
