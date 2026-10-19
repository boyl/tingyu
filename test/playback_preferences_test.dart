import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/services/sleep_timer.dart';
import 'support/fakes.dart';

void main() {
  test('continuous lyric size persists and migrates legacy sizes', () async {
    final f = await TestLibrary.create();
    try {
      await f.db.writeState('library', {'lyricSize': 2});
      await f.controller.initialize();
      expect(f.controller.lyricFontSize, 28);
      await f.controller.setLyricDisplay(fontSize: 31, translation: false);
      final state = (await f.db.readState('library'))!;
      expect(state['lyricFontSize'], 31);
      await f.controller.setLyricDisplay(fontSize: 24);
      expect(f.controller.showLyricTranslation, false);
      await f.controller.initialize();
      expect(f.controller.lyricFontSize, 24);
      expect(f.controller.showLyricTranslation, false);
    } finally {
      await f.close();
    }
  });

  test(
    'deadline is real time, replacement cancels previous, expires only once',
    () async {
      var now = DateTime(2026);
      final timer = SleepTimer(now: () => now);
      var calls = 0;
      timer.onExpire = (finish) async {
        calls++;
        expect(finish, true);
      };
      expect(
        () => timer.start(Duration.zero, finishTrack: false),
        throwsArgumentError,
      );
      timer.start(const Duration(minutes: 1), finishTrack: false);
      timer.start(const Duration(minutes: 2), finishTrack: true);
      now = now.add(const Duration(seconds: 61));
      timer.check();
      expect(calls, 0);
      now = now.add(const Duration(minutes: 2));
      timer.check();
      timer.check();
      expect(calls, 1);
      expect(timer.active, false);
      timer.dispose();
    },
  );
  test(
    'once mode pauses completion, manual next still works; preferences persist',
    () async {
      final f = await TestLibrary.create();
      final p = f.controller;
      try {
        await p.remember(firstTrack);
        await p.remember(secondTrack);
        p.queue.addAll([firstTrack.id, secondTrack.id]);
        await p.play(firstTrack);
        await p.setMode('once');
        await p.setSpeed(.75);
        await p.setPlayerLyrics(false);
        f.playback.onCompleted!();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(p.current!.id, firstTrack.id);
        expect(p.playing, false);
        await p.next();
        expect(p.current!.id, secondTrack.id);
        expect(p.mode, 'once');
        expect(f.playback.player.speed, .75);
        final state = (await p.db.readState('library'))!;
        expect(state['speed'], .75);
        expect(state['showPlayerLyrics'], false);
        expect(() => p.setSleepTimer(Duration.zero), throwsArgumentError);
      } finally {
        await f.close();
      }
    },
  );
  test(
    'timer waits for the current track and manual next cannot restart after deadline',
    () async {
      final f = await TestLibrary.create();
      final p = f.controller;
      try {
        await p.remember(firstTrack);
        await p.remember(secondTrack);
        p.queue.addAll([firstTrack.id, secondTrack.id]);
        await p.play(firstTrack);
        p.setSleepTimer(const Duration(minutes: 1), finishTrack: true);
        p.sleepTimer.deadline = DateTime.now().subtract(
          const Duration(seconds: 1),
        );
        p.sleepTimer.check();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(p.waitingForTrack, true);
        await p.next();
        expect(p.playing, false);
        expect(p.current!.id, firstTrack.id);
        expect(p.waitingForTrack, false);
        p.setSleepTimer(const Duration(minutes: 1));
        p.sleepTimer.deadline = DateTime.now().subtract(
          const Duration(seconds: 1),
        );
        p.sleepTimer.check();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(p.playing, false);
        expect(p.sleepTimer.active, false);
      } finally {
        await f.close();
      }
    },
  );
}
