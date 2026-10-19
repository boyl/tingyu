import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'support/fakes.dart';

void main() {
  late TestLibrary f;
  setUp(() async {
    f = await TestLibrary.create();
  });
  tearDown(() => f.close(disposeController: false));
  testWidgets(
    'speed and timer apply real controller changes and icon controls',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryProvider.overrideWith((ref) => f.controller)],
          child: MaterialApp(
            theme: tingyuTheme('bili'),
            home: Scaffold(
              body: PlaybackSettingsPanel(f.controller, timer: false),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('speed-0.5')));
      await tester.pump();
      expect(f.playback.player.speed, .5);
      await tester.tap(find.byKey(const ValueKey('恢复正常倍速')));
      await tester.pump();
      expect(f.playback.player.speed, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'glass ranges cover endpoints and hold preview preserves exact slider position',
    (tester) async {
      final p = f.controller;
      await p.setGlass(automatic: false);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryProvider.overrideWith((ref) => p)],
          child: MaterialApp(
            theme: tingyuTheme('bili'),
            home: const GlassPreferencesScreen(),
          ),
        ),
      );
      await tester.pump();
      final slider = find.byKey(const ValueKey('glass-slider-nav'));
      await tester.ensureVisible(slider);
      await tester.pump();
      final rect = tester.getRect(slider);
      final gesture = await tester.startGesture(rect.center);
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump();
      expect(tester.getRect(slider), rect);
      expect(find.byType(AppShell), findsOneWidget);
      await gesture.up();
      await tester.pump();
      expect(find.byType(AppShell), findsNothing);
      expect(tester.takeException(), isNull);
      await p.setGlass(navigation: 0, player: 1);
      await tester.pump();
      expect(p.navigationOpacity, 0);
      expect(p.playerOpacity, 1);
      expect(tester.widget<Slider>(slider).value, 1);
      await p.setGlass(automatic: true);
      await tester.pump();
      expect(p.navigationOpacity, .26);
      expect(p.playerOpacity, .26);
      expect(find.byKey(const ValueKey('glass-slider-nav')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('toggle track stays compact inside accessible touch target', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: tingyuTheme('bili'),
        home: Scaffold(
          body: Center(
            child: TingyuToggle(value: true, label: '歌词', onChanged: (_) {}),
          ),
        ),
      ),
    );
    final toggle = find.byType(TingyuToggle);
    final track = find.descendant(
      of: toggle,
      matching: find.byType(AnimatedContainer),
    );
    expect(tester.getSize(track), const Size(36, 22));
    expect(tester.getSize(toggle).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('speed fine slider is continuous without discrete ticks', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: tingyuTheme('bili'),
        home: Scaffold(body: PlaybackSettingsPanel(f.controller, timer: false)),
      ),
    );
    expect(tester.widget<Slider>(find.byType(Slider)).divisions, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'lyric toggle preserves large disc geometry and playback control positions',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      f.controller.current = firstTrack;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryProvider.overrideWith((ref) => f.controller)],
          child: MaterialApp(
            theme: tingyuTheme('bili'),
            home: const PlayerScreen(),
          ),
        ),
      );
      final disc = find.byType(RecordDisc).last;
      final size = tester.widget<RecordDisc>(disc).size;
      final before = tester.getRect(disc);
      final playBefore = tester.getRect(find.byType(ModeButton));
      await f.controller.setPlayerLyrics(false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<RecordDisc>(disc).size, size);
      expect(tester.getRect(disc), before);
      expect(tester.getRect(find.byType(ModeButton)), playBefore);
      expect(size, greaterThanOrEqualTo(240));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'font size drag changes preview to 32 instead of nearest legacy preset',
    (tester) async {
      f.controller.current = firstTrack;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryProvider.overrideWith((ref) => f.controller)],
          child: MaterialApp(
            theme: tingyuTheme('bili'),
            home: LyricsPreferencesPage(
              f.controller,
              firstTrack,
              section: 'display',
            ),
          ),
        ),
      );
      await tester.drag(find.byType(Slider), const Offset(500, 0));
      await tester.pump();
      final preview = find.text('歌词显示预览');
      expect(tester.widget<Text>(preview).style!.fontSize, 32);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'folder search matches casefolded non adjacent keywords and keeps selected items',
    (tester) async {
      f.api.loggedIn = true;
      f.controller.profile = {'mid': 1, 'uname': '测试账号'};
      f.api.folderResults = [
        {'id': 1, 'title': 'BGM 夜间电台', 'media_count': 2},
        {'id': 2, 'title': '通勤 Bgm', 'media_count': 3},
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: tingyuTheme('bili'),
          home: Scaffold(body: AccountPanel(f.controller)),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), ' 夜间 bgm ');
      await tester.pump();
      expect(find.byType(FolderChoice), findsOneWidget);
      await tester.tap(find.byType(FolderChoice));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'BGM');
      await tester.pump();
      expect(find.byType(FolderChoice), findsNWidgets(2));
      expect(
        tester.widget<FolderChoice>(find.byType(FolderChoice).first).selected,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
