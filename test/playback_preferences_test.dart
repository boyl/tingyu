import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/services/sleep_timer.dart';
import 'support/fakes.dart';

void main() {
  test('stored volume restores in a fresh player', () async {
    for (final volume in [.37, 0.0, 1.0]) {
      var f = await TestLibrary.create();
      final directory = f.directory;
      await f.controller.setVolume(volume);
      expect((await f.db.readState('library'))!['volume'], volume);
      await f.close(deleteData: false);
      f = await TestLibrary.create(dataDirectory: directory);
      try {
        expect(f.playback.player.volume, volume);
        expect(f.controller.playing, false);
      } finally {
        await f.close();
      }
    }
  });

  test(
    'finish-track choice applies while timer is off and survives restart',
    () async {
      var f = await TestLibrary.create();
      try {
        await f.controller.setSleepTimer(null, finishTrack: true);
        expect(f.controller.sleepTimer.finishTrack, true);

        final directory = f.directory;
        await f.close(deleteData: false);
        f = await TestLibrary.create(dataDirectory: directory);
        expect(f.controller.sleepTimer.finishTrack, true);
        expect(f.controller.sleepTimer.active, false);
        expect(f.controller.waitingForTrack, false);
        expect(f.controller.playing, false);
      } finally {
        await f.close();
      }
    },
  );

  test('legacy defaults and stored volume bounds are restored', () async {
    var f = await TestLibrary.create();
    try {
      expect(f.playback.player.volume, 1);
      expect(f.controller.sleepTimer.finishTrack, false);
      for (final pair in [(-1.0, 0.0), (2.0, 1.0)]) {
        await f.db.writeState('library', {'volume': pair.$1});
        final directory = f.directory;
        await f.close(deleteData: false);
        f = await TestLibrary.create(dataDirectory: directory);
        expect(f.playback.player.volume, pair.$2);
      }
      for (final invalid in [-.1, 1.1, double.nan, double.infinity]) {
        await expectLater(
          f.controller.setVolume(invalid),
          throwsA(isA<Exception>()),
        );
      }
    } finally {
      await f.close();
    }
  });

  test(
    'cancel and expiry preserve preference without restoring timer',
    () async {
      var f = await TestLibrary.create();
      try {
        await f.controller.setSleepTimer(
          const Duration(minutes: 1),
          finishTrack: true,
        );
        await f.controller.setSleepTimer(null);
        expect(f.controller.sleepTimer.finishTrack, true);
        await f.controller.setSleepTimer(const Duration(minutes: 1));
        f.controller.sleepTimer.deadline = DateTime.now().subtract(
          const Duration(seconds: 1),
        );
        f.controller.sleepTimer.check();
        expect(f.controller.sleepTimer.finishTrack, true);
        expect(f.controller.sleepTimer.active, false);
        await f.controller.setSleepTimer(const Duration(minutes: 1));
        final directory = f.directory;
        await f.close(deleteData: false);
        f = await TestLibrary.create(dataDirectory: directory);
        expect(f.controller.sleepTimer.finishTrack, true);
        expect(f.controller.sleepTimer.active, false);
        expect(f.controller.waitingForTrack, false);
        expect(f.controller.playing, false);
        await f.controller.setSleepTimer(null, finishTrack: false);
        expect((await f.db.readState('library'))!['sleepFinishTrack'], false);
      } finally {
        await f.close();
      }
    },
  );

  test('continuous lyric size persists and migrates legacy sizes', () async {
    var f = await TestLibrary.create();
    try {
      await f.db.writeState('library', {'lyricSize': 2});
      final directory = f.directory;
      await f.close(deleteData: false);
      f = await TestLibrary.create(dataDirectory: directory);
      expect(f.controller.lyricFontSize, 28);
      await f.controller.setLyricDisplay(fontSize: 31, translation: false);
      final state = (await f.db.readState('library'))!;
      expect(state['lyricFontSize'], 31);
      await f.controller.setLyricDisplay(fontSize: 24);
      expect(f.controller.showLyricTranslation, false);
      await f.close(deleteData: false);
      f = await TestLibrary.create(dataDirectory: directory);
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
