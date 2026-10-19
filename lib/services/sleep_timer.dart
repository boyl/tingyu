import 'dart:async';
import 'package:flutter/foundation.dart';

/// Wall-clock deadline; never restores playback or survives a process restart.
class SleepTimer extends ChangeNotifier {
  SleepTimer({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  DateTime? deadline;
  Timer? _ticker;
  bool finishTrack = false;
  Future<void> Function(bool finishTrack)? onExpire;
  Duration get remaining {
    final value = deadline?.difference(_now()) ?? Duration.zero;
    return value.isNegative ? Duration.zero : value;
  }

  bool get active => deadline != null;
  void start(Duration duration, {required bool finishTrack}) {
    if (duration < const Duration(minutes: 1) ||
        duration > const Duration(minutes: 180)) {
      throw ArgumentError.value(duration, 'duration', '1–180 minutes');
    }
    _ticker?.cancel();
    this.finishTrack = finishTrack;
    deadline = _now().add(duration);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => check());
    notifyListeners();
  }

  void check() {
    if (!active) return;
    if (remaining == Duration.zero) {
      final finish = finishTrack;
      cancel();
      final callback = onExpire;
      if (callback != null) unawaited(callback(finish));
    } else {
      notifyListeners();
    }
  }

  void cancel() {
    _ticker?.cancel();
    _ticker = null;
    deadline = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    onExpire = null;
    super.dispose();
  }
}
