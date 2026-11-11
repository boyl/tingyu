/// Counts only continuous ready playback, never seek jumps or buffering time.
class DiscoveryListening {
  String? bvid;
  double seconds = 0;
  bool rewarded = false, failed = false;
  Duration? _position;
  DateTime? _time;
  bool _active = false;
  void start(String id) {
    bvid = id;
    seconds = 0;
    rewarded = false;
    failed = false;
    resetSample();
  }

  void resetSample() {
    _position = null;
    _time = null;
    _active = false;
  }

  void sample(
    Duration position,
    DateTime now, {
    required bool active,
    double speed = 1,
  }) {
    if (active && _active && _position != null && _time != null) {
      final elapsed = now.difference(_time!).inMicroseconds / 1000000;
      final delta = (position - _position!).inMicroseconds / 1000000;
      if (elapsed > 0 &&
          elapsed <= 2 &&
          delta > 0 &&
          (delta - elapsed * speed).abs() <= .4) {
        seconds += elapsed;
      }
    }
    _position = position;
    _time = now;
    _active = active;
  }

  bool get earlySkip => !failed && seconds > 0 && seconds < 10;
  bool qualifies(int duration) =>
      !failed &&
      !rewarded &&
      seconds >= (duration > 0 && duration < 120 ? duration / 2 : 60);
}
