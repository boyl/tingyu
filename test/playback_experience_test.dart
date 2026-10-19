import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tingyu/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'support/fakes.dart';

void main() {
  late TestLibrary f;
  var owned = false;
  setUp(() async {
    owned = false;
    f = await TestLibrary.create();
  });
  tearDown(() async {
    await f.close(disposeController: !owned);
  });
  test(
    'lyrics visibility preserves the audio source, position, gain and speed',
    () async {
      await f.controller.play(firstTrack);
      await f.playback.player.seek(const Duration(seconds: 12));
      await f.playback.player.setVolume(.7);
      await f.controller.setSpeed(1.25);
      final opened = List<String>.of(f.playback.opened);
      for (final visible in [false, true, false, true]) {
        await f.controller.setPlayerLyrics(visible);
        expect(f.playback.opened, opened);
        expect(f.playback.player.playing, isTrue);
        expect(f.playback.player.position, const Duration(seconds: 12));
        expect(f.playback.player.volume, .7);
        expect(f.playback.player.speed, 1.25);
      }
    },
  );

  testWidgets(
    'changing mode preserves the active record state when previews change',
    (tester) async {
      final p = f.controller;
      for (final t in [firstTrack, secondTrack]) {
        await p.remember(t);
      }
      p.queue.addAll([firstTrack.id, secondTrack.id]);
      await p.play(firstTrack);
      owned = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryProvider.overrideWith((_) => p)],
          child: MaterialApp(
            theme: tingyuTheme('bili'),
            home: Scaffold(
              body: ListenableBuilder(
                listenable: p,
                builder: (_, _) => RecordCarousel(p, size: 246),
              ),
            ),
          ),
        ),
      );
      Finder current() =>
          find.byWidgetPredicate((w) => w is RecordDisc && w.playing);
      final original = tester.state(current());
      await tester.runAsync(() => p.setMode('shuffle'));
      await tester.pump();
      expect(tester.state(current()), same(original));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('detail lyric does not ellipsize long current sentences', (
    tester,
  ) async {
    f.controller.lyricText =
        '[00:00.00]这是一句需要完整显示而不能被裁切的很长很长的歌词，它应当按实际可用宽度换行并保持可读';
    await tester.pumpWidget(
      MaterialApp(
        theme: tingyuTheme('bili'),
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 160,
            child: LyricPanel(f.controller),
          ),
        ),
      ),
    );
    await tester.pump();
    final line = tester.widget<LyricWordLine>(find.byType(LyricWordLine).first);
    expect(line.maxLines, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('detail controls remain usable at 320 wide and 1.6 text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    owned = true;
    f.controller.current = firstTrack;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryProvider.overrideWith((_) => f.controller)],
        child: MaterialApp(
          theme: tingyuTheme('bili'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: const PlayerScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('player-lyrics-toggle')).hitTestable(),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
