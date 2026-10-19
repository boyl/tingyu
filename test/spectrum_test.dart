import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/ui/playback_spectrum.dart';

void main() {
  test('spectrum follows ready playback and rests in the other states', () {
    bool live({
      bool playing = true,
      bool ready = true,
      bool opening = false,
      bool seeking = false,
      bool reducedMotion = false,
    }) => spectrumIsLive(
      playing: playing,
      ready: ready,
      opening: opening,
      seeking: seeking,
      reducedMotion: reducedMotion,
    );
    expect(live(), isTrue);
    expect(live(playing: false), isFalse);
    expect(live(ready: false), isFalse);
    expect(live(opening: true), isFalse);
    expect(live(seeking: true), isFalse);
    expect(live(reducedMotion: true), isFalse);
  });

  test('bar heights follow this frame and drop to the baseline when idle', () {
    final live = spectrumBarHeights([1, 0], 40, live: true);
    expect(live.first, 40);
    expect(live[1], 3);
    expect(live.length, spectrumBands);
    expect(spectrumBarHeights([1], 40, live: false), everyElement(3));
  });
}
