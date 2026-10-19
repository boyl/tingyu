import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/services/desktop_session.dart';

void main() {
  for (final platform in ['macOS', 'Windows']) {
    test(
      '$platform close hides with tray, preserves playback and can restore',
      () async {
        bool visible = true, playing = true;
        String? saved;
        final session = DesktopSession(
          hideWindow: () async {
            visible = false;
          },
          showWindow: () async {
            visible = true;
          },
          persist: () async {
            saved = 'queue';
          },
          stopPlayback: () async {
            playing = false;
          },
          destroyWindow: () async {
            visible = false;
          },
        );
        session.trayAvailable = true;
        await session.requestClose();
        expect(visible, isFalse);
        expect(playing, isTrue);
        expect(saved, isNull);
        expect(session.phase, DesktopPhase.hidden);
        await session.restore();
        expect(visible, isTrue);
        expect(playing, isTrue);
        expect(session.phase, DesktopPhase.visible);
      },
    );
    test('$platform tray failure still permits a safe complete exit', () async {
      final events = <String>[];
      bool visible = true, playing = true;
      final session = DesktopSession(
        hideWindow: () async {
          events.add('hide');
        },
        showWindow: () async {
          visible = true;
        },
        persist: () async {
          events.add('save');
        },
        stopPlayback: () async {
          events.add('stop');
          playing = false;
        },
        destroyWindow: () async {
          events.add('destroy');
          visible = false;
        },
      );
      await session.requestClose();
      expect(events, ['save', 'stop', 'destroy']);
      expect(playing, isFalse);
      expect(visible, isFalse);
      expect(session.phase, DesktopPhase.closed);
    });
  }
  test(
    'repeated exit and late close callbacks perform teardown only once',
    () async {
      final gate = Completer<void>();
      int saves = 0, stops = 0, destroys = 0;
      final session = DesktopSession(
        hideWindow: () async {},
        showWindow: () async {},
        persist: () async {
          saves++;
          await gate.future;
        },
        stopPlayback: () async {
          stops++;
        },
        destroyWindow: () async {
          destroys++;
        },
      );
      final first = session.quit(), second = session.quit();
      await session.requestClose();
      gate.complete();
      await Future.wait([first, second]);
      await session.requestClose();
      await session.restore();
      expect([saves, stops, destroys], [1, 1, 1]);
      expect(session.phase, DesktopPhase.closed);
    },
  );
  test(
    'failed persistence keeps window and playback intact and allows retry',
    () async {
      var fail = true, playing = true, visible = true;
      final session = DesktopSession(
        hideWindow: () async {
          visible = false;
        },
        showWindow: () async {
          visible = true;
        },
        persist: () async {
          if (fail) throw Exception('disk full');
        },
        stopPlayback: () async {
          playing = false;
        },
        destroyWindow: () async {
          visible = false;
        },
      );
      await expectLater(session.quit(), throwsException);
      expect(playing, isTrue);
      expect(visible, isTrue);
      expect(session.phase, DesktopPhase.visible);
      fail = false;
      await session.quit();
      expect(playing, isFalse);
      expect(visible, isFalse);
      expect(session.phase, DesktopPhase.closed);
    },
  );
}
