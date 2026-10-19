import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'support/fakes.dart';

void main() {
  late TestLibrary fixture;
  var providerOwnsController = false;
  setUp(() async {
    providerOwnsController = false;
    fixture = await TestLibrary.create();
  });
  tearDown(() => fixture.close(disposeController: !providerOwnsController));

  testWidgets(
    'mid-song lyrics center the current line and gaps keep the last readable line',
    (tester) async {
      fixture.controller.lyricText = [
        '[00:00.00]第一句',
        '[00:02.00] ',
        '[00:04.00]第二句',
        '[00:06.00] ',
        '[00:08.00]第三句',
        '[00:10.00]第四句',
        '[00:12.00]第五句',
        '[00:14.00]第六句',
        '[00:16.00]第七句',
        '[00:18.00]第八句',
      ].join('\n');
      fixture.controller.position = const Duration(seconds: 9);
      await tester.pumpWidget(
        MaterialApp(
          theme: tingyuTheme('bili'),
          home: Scaffold(
            body: SizedBox(
              height: 150,
              width: 360,
              child: LyricPanel(fixture.controller),
            ),
          ),
        ),
      );
      await tester.pump();

      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      final viewport = scroll.position.viewportDimension;
      final maxScroll = scroll.position.maxScrollExtent;
      final centered = (12 + 4 * 64 - (viewport - 64) / 2).clamp(
        0.0,
        maxScroll,
      );
      expect(scroll.position.pixels, closeTo(centered, 0.5));
      expect(scroll.position.pixels, greaterThan(100));
      final active = tester
          .widgetList<Text>(find.byType(Text))
          .where((text) => text.style?.fontWeight == FontWeight.w600)
          .map((text) => text.data)
          .toList();
      expect(active, ['第三句']);

      fixture.controller.position = const Duration(seconds: 3);
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .where((text) => text.style?.fontWeight == FontWeight.w600)
            .map((text) => text.data)
            .toList(),
        ['第一句'],
      );
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        0,
      );

      fixture.controller.position = const Duration(seconds: 10);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      final arrived = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      final next = (12 + 5 * 64 - (arrived.viewportDimension - 64) / 2).clamp(
        0.0,
        arrived.maxScrollExtent,
      );
      expect(arrived.pixels, closeTo(next, 1));
      expect(
        tester.widget<Text>(find.text('第四句')).style?.fontWeight,
        FontWeight.w600,
      );
    },
  );

  testWidgets(
    'current player line shows words, translation and romaji inside the row',
    (tester) async {
      fixture.controller.lyricText = '[00:01.00]你[00:02.00]好[00:03.00]';
      fixture.controller.lyricTranslation = '[00:01.00]hello';
      fixture.controller.lyricRomaji = '[00:01.00]ni hao';
      fixture.controller.position = const Duration(milliseconds: 1500);
      await tester.pumpWidget(
        MaterialApp(
          theme: tingyuTheme('bili'),
          home: Scaffold(
            body: SizedBox(
              height: 150,
              width: 360,
              child: LyricPanel(fixture.controller),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('你'), findsOneWidget);
      expect(find.text('好'), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
      expect(find.text('ni hao'), findsOneWidget);
      expect(tester.takeException(), isNull);

      fixture.controller.showLyricTranslation = false;
      fixture.controller.showLyricRomaji = false;
      fixture.controller.position = const Duration(milliseconds: 1501);
      await tester.pump();
      expect(find.text('hello'), findsNothing);
      expect(find.text('ni hao'), findsNothing);
      expect(find.text('你'), findsOneWidget);
    },
  );

  testWidgets('subtitle gaps do not leave a tall blank row', (tester) async {
    fixture.controller.lyricText = '[00:01.00]第一句\n[00:02.00] \n[00:04.00]第二句';
    fixture.controller.position = const Duration(seconds: 1);
    await tester.pumpWidget(
      MaterialApp(
        theme: tingyuTheme('bili'),
        home: Scaffold(
          body: SizedBox(
            height: 480,
            width: 360,
            child: RichLyricTimeline(fixture.controller),
          ),
        ),
      ),
    );
    await tester.pump();
    final above = tester.getRect(find.text('第一句'));
    final below = tester.getRect(find.text('第二句'));
    expect(below.top - above.bottom, lessThan(48));
  });

  testWidgets('reduced motion keeps a timed line as one readable sentence', (
    tester,
  ) async {
    fixture.controller.lyricText = '[00:01.00]你[00:02.00]好[00:03.00]';
    fixture.controller.position = const Duration(milliseconds: 1500);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: tingyuTheme('bili'),
          home: Scaffold(
            body: SizedBox(
              height: 150,
              width: 360,
              child: LyricPanel(fixture.controller),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('你好'), findsOneWidget);
    expect(find.text('你'), findsNothing);
  });

  testWidgets('phone player keeps the current lyric fully above the seek bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    providerOwnsController = true;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    fixture.controller.current = firstTrack;
    fixture.controller.lyricSource = 'bilibili-ai-subtitle';
    fixture.controller.lyricText = [
      '[00:00.00]第一句完整歌词',
      '[00:10.00]第二句完整歌词',
      '[00:20.00]第三句完整歌词',
    ].join('\n');
    fixture.controller.position = const Duration(seconds: 10);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryProvider.overrideWith((_) => fixture.controller)],
        child: MaterialApp(
          theme: tingyuTheme('bili'),
          home: const PlayerScreen(),
        ),
      ),
    );
    await tester.pump();
    final line = tester.getRect(find.text('第二句完整歌词'));
    final panel = tester.getRect(find.byType(LyricPanel));
    final seek = tester.getTopLeft(find.text('00:10')).dy;
    expect(line.height, greaterThan(15));
    expect(line.top, greaterThanOrEqualTo(panel.top));
    expect(line.bottom, lessThanOrEqualTo(panel.bottom));
    expect(line.bottom, lessThan(seek));
  });

  testWidgets(
    'record keeps turning while playing and holds still when paused',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      providerOwnsController = true;
      fixture.controller.current = firstTrack;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryProvider.overrideWith((_) => fixture.controller)],
          child: MaterialApp(
            theme: tingyuTheme('bili'),
            home: const PlayerScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(RecordDisc), findsOneWidget);
      final turns = tester
          .widget<RotationTransition>(
            find.descendant(
              of: find.byType(RecordDisc),
              matching: find.byType(RotationTransition),
            ),
          )
          .turns;
      expect(turns.value, 0);
      await fixture.playback.play();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(turns.value, greaterThan(0));
      final held = turns.value;
      await fixture.playback.pause();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(turns.value, held);
    },
  );
}
