import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'support/fakes.dart';

void main() {
  late TestLibrary f;
  setUp(() async => f = await TestLibrary.create());
  tearDown(() => f.close(disposeController: false));
  Future<void> mountTimer(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: tingyuTheme('bili'),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showPlaybackSettings(context, f.controller, timer: true),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'inactive timer has no preset and selecting waits for dismissal',
    (tester) async {
      await mountTimer(tester);
      expect(find.text('定时已关闭'), findsOneWidget);
      expect(find.byKey(const ValueKey('timer-off')), findsNothing);
      expect(find.text('15 分钟'), findsOneWidget);
      final panelBefore = tester.getSize(find.byType(PlaybackSettingsPanel));
      await tester.tap(find.byKey(const ValueKey('timer-30')));
      await tester.pump(const Duration(seconds: 10));
      expect(tester.getSize(find.byType(PlaybackSettingsPanel)), panelBefore);
      expect(find.text('收起后生效'), findsNothing);
      expect(find.text('关闭定时'), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('timer-status')))
            .style!
            .fontSize,
        16,
      );
      expect(f.controller.sleepTimer.active, isFalse);
      Navigator.of(tester.element(find.byType(PlaybackSettingsPanel))).pop();
      await tester.pumpAndSettle();
      expect(f.controller.sleepTimer.active, isTrue);
      expect(f.controller.sleepTimer.remaining.inSeconds, greaterThan(1795));
      f.controller.setSleepTimer(null);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('opening and dismissing an active timer preserves deadline', (
    tester,
  ) async {
    f.controller.setSleepTimer(const Duration(minutes: 15));
    final deadline = f.controller.sleepTimer.deadline;
    await mountTimer(tester);
    Navigator.of(tester.element(find.byType(PlaybackSettingsPanel))).pop();
    await tester.pumpAndSettle();
    expect(f.controller.sleepTimer.deadline, deadline);
    f.controller.setSleepTimer(null);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'timer compact layout fits narrow large text and reflects cancellation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: tingyuTheme('bili'),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
              body: PlaybackSettingsPanel(f.controller, timer: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('timer-45'))).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const ValueKey('timer-15'))).dy,
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('timer-15'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      f.controller.setSleepTimer(const Duration(minutes: 30));
      await mountTimer(tester);
      expect(find.text('剩余时间'), findsOneWidget);
      f.controller.setSleepTimer(null);
      await tester.pumpAndSettle();
      expect(find.text('定时已关闭'), findsOneWidget);
      expect(find.byKey(const ValueKey('timer-off')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'waiting for current track remains readable in narrow large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await f.controller.play(firstTrack);
      await f.controller.sleepTimer.onExpire!(true);
      expect(f.controller.waitingForTrack, isTrue);
      await tester.pumpWidget(
        MaterialApp(
          theme: tingyuTheme('bili'),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
              body: PlaybackSettingsPanel(f.controller, timer: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('本首结束后暂停'), findsOneWidget);
      expect(find.byKey(const ValueKey('timer-off')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('selection toolbar completion is centered with action icons', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryProvider.overrideWith((ref) => f.controller)],
        child: MaterialApp(
          theme: tingyuTheme('bili'),
          home: Scaffold(
            body: SizedBox(
              height: TingyuTokens.controlSize,
              child: SelectionToolbar(
                totalCount: 1000,
                selectedIds: const [],
                allSelected: false,
                onSelectAll: () {},
                onDone: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('完成')).dy,
      closeTo(tester.getCenter(find.byType(SelectionToolbar)).dy, 1),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('custom wheels preview forty and eighty without starting timer', (
    tester,
  ) async {
    await mountTimer(tester);
    await tester.tap(find.byKey(const ValueKey('timer-custom')));
    await tester.pumpAndSettle();
    FixedExtentScrollController wheel(String key) =>
        tester
                .widget<ListWheelScrollView>(find.byKey(ValueKey(key)))
                .controller!
            as FixedExtentScrollController;
    wheel('timer-minutes').jumpToItem(40);
    await tester.pumpAndSettle();
    expect(find.text('40 分钟后'), findsOneWidget);
    expect(find.text('40 分钟'), findsWidgets);
    expect(wheel('timer-minutes').selectedItem, 40);
    wheel('timer-hours').jumpToItem(1);
    await tester.pumpAndSettle();
    wheel('timer-minutes').jumpToItem(20);
    await tester.pumpAndSettle();
    expect(find.text('80 分钟后'), findsOneWidget);
    expect(find.text('1 小时 20 分钟'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('timer-minutes')),
      const Offset(0, -48),
    );
    await tester.pumpAndSettle();
    final draggedMinutes = 60 + wheel('timer-minutes').selectedItem;
    expect(find.text('$draggedMinutes 分钟后'), findsOneWidget);
    expect(wheel('timer-hours').selectedItem, 1);
    expect(f.controller.sleepTimer.active, isFalse);
    wheel('timer-hours').jumpToItem(0);
    await tester.pumpAndSettle();
    wheel('timer-minutes').jumpToItem(30);
    await tester.pumpAndSettle();
    expect(find.text('30 分钟后'), findsOneWidget);
    expect(find.text('30 分钟'), findsWidgets);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.byType(PlaybackSettingsPanel))).pop();
    await tester.pumpAndSettle();
    expect(f.controller.sleepTimer.active, isTrue);
    f.controller.setSleepTimer(null);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'collection sort and selection align to trailing edge at phone widths',
    (tester) async {
      for (final width in [320.0, 390.0]) {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [libraryProvider.overrideWith((ref) => f.controller)],
            child: MaterialApp(
              theme: tingyuTheme('bili'),
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(20),
                  child: CollectionToolbar(
                    ids: const [],
                    collectionKey: 'likes',
                    selecting: false,
                    onSelect: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const ValueKey('批量选择'))).right,
          closeTo(width - 20, .1),
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('歌曲排序'))).right,
          closeTo(tester.getRect(find.byKey(const ValueKey('批量选择'))).left, .1),
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets(
    'header marquee moves continuously and pauses with lifecycle or reduced motion',
    (tester) async {
      Widget header({
        bool reduced = false,
        bool hold = false,
        String status = '正在播放 · 51 / 52',
      }) => MaterialApp(
        theme: tingyuTheme('bili'),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Scaffold(
            body: SizedBox(
              width: 180,
              child: PlayerHeaderStatus(
                status: status,
                mode: 'shuffle',
                hold: hold,
              ),
            ),
          ),
        ),
      );
      double offset() => tester
          .widget<Transform>(
            find.byKey(const ValueKey('player-status-marquee')),
          )
          .transform
          .storage[12];
      await tester.pumpWidget(header());
      await tester.pump();
      final start = offset();
      await tester.pump(const Duration(seconds: 1));
      expect(offset(), lessThan(start));
      final beforeBackground = offset();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 5));
      expect(offset(), beforeBackground);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(offset(), lessThan(beforeBackground));
      await tester.pumpWidget(header(hold: true, status: '随机播放'));
      expect(find.byKey(const ValueKey('player-status-marquee')), findsNothing);
      await tester.pumpWidget(header(reduced: true));
      expect(find.byKey(const ValueKey('player-status-marquee')), findsNothing);
      await tester.pumpWidget(header(status: '正在加载…'));
      expect(find.text('正在加载…'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'selection count is bounded by measured total and does not shift actions',
    (tester) async {
      int count = 0;
      late StateSetter update;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryProvider.overrideWith((ref) => f.controller)],
          child: MaterialApp(
            theme: tingyuTheme('bili'),
            home: Scaffold(
              body: SizedBox(
                width: 390,
                height: 48,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return SelectionToolbar(
                      totalCount: 1000,
                      selectedIds: List.generate(count, (i) => '$i'),
                      allSelected: count == 1000,
                      onSelectAll: () {},
                      onDone: () {},
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final all = tester.getRect(find.byKey(const ValueKey('全选')));
      final download = tester.getRect(find.byKey(const ValueKey('批量下载')));
      for (final next in [9, 10, 99, 100, 999, 1000]) {
        update(() => count = next);
        await tester.pump();
        expect(tester.getRect(find.byKey(const ValueKey('全选'))), all);
        expect(tester.getRect(find.byKey(const ValueKey('批量下载'))), download);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'application volume works while paused and persists across track changes',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: tingyuTheme('bili'),
          home: Scaffold(body: PlayerVolumePanel(f.controller)),
        ),
      );
      tester
          .widget<Slider>(find.byKey(const ValueKey('player-volume-slider')))
          .onChanged!(.4);
      await tester.pump();
      expect(f.playback.player.volume, .4);
      expect(find.text('40%'), findsOneWidget);
      expect(find.textContaining('仅调节'), findsNothing);
      await f.controller.play(firstTrack);
      await f.controller.play(secondTrack);
      expect(f.playback.player.volume, .4);
      await f.playback.pause();
      tester
          .widget<Slider>(find.byKey(const ValueKey('player-volume-slider')))
          .onChanged!(0);
      await tester.pump();
      expect(f.playback.player.volume, 0);
      await tester.tap(find.byKey(const ValueKey('恢复正常音量')));
      await tester.pump();
      expect(f.playback.player.volume, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('select all remains text and toggles twice', (tester) async {
    bool all = false;
    late StateSetter update;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryProvider.overrideWith((ref) => f.controller)],
        child: MaterialApp(
          theme: tingyuTheme('bili'),
          home: Scaffold(
            body: SizedBox(
              height: 48,
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return SelectionToolbar(
                    totalCount: 1000,
                    selectedIds: all ? const ['one'] : const [],
                    allSelected: all,
                    onSelectAll: () => update(() => all = !all),
                    onDone: () {},
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('全选'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('全选')));
    await tester.pump();
    expect(all, isTrue);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('取消全选'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('全选')));
    await tester.pump();
    expect(all, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('timer finish control is compact and both labels centered', (
    tester,
  ) async {
    await mountTimer(tester);
    expect(find.byType(Divider), findsNothing);
    for (final finish in [false, true]) {
      final button = find.byKey(ValueKey('timer-finish-$finish'));
      expect(tester.getSize(button).height, 48);
      final label = find.text(finish ? '播完本首' : '到时暂停');
      expect(
        tester.getCenter(label).dx,
        closeTo(tester.getCenter(button).dx, .1),
      );
      expect(
        tester.getCenter(label).dy,
        closeTo(tester.getCenter(button).dy, .1),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('normal phone record is enlarged and remains fully visible', (
    tester,
  ) async {
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
    await tester.pump();
    final disc = tester.getRect(find.byType(RecordDisc).last);
    expect(disc.width, closeTo(390 * .74, 1));
    final viewport = tester.getRect(find.byType(PlayerContentViewport));
    expect(disc.top, greaterThanOrEqualTo(viewport.top));
    expect(disc.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(find.byKey(const ValueKey('播放音量')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('歌曲操作')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('播放音量'), findsOneWidget);
    await tester.tap(find.text('播放音量'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PlayerVolumePanel), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('player opens with whole current disc inside content viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
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
    await tester.pump();
    final disc = tester.getRect(find.byType(RecordDisc).last);
    final viewport = tester.getRect(find.byType(PlayerContentViewport));
    expect(disc.top, greaterThanOrEqualTo(viewport.top));
    expect(disc.bottom, lessThanOrEqualTo(viewport.bottom));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('selection moves control left while keeping row bounds', (
    tester,
  ) async {
    await f.controller.remember(firstTrack);
    bool selecting = false;
    bool selected = false;
    f.controller.current = firstTrack;
    await f.controller.toggleLike(firstTrack);
    late StateSetter update;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryProvider.overrideWith((ref) => f.controller)],
        child: MaterialApp(
          theme: tingyuTheme('bili'),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return TrackRow(
                  firstTrack,
                  selecting: selecting,
                  selected: selected,
                  onSelect: () {},
                );
              },
            ),
          ),
        ),
      ),
    );
    final before = tester.getRect(find.byType(Artwork));
    final row = tester.getRect(find.byType(TrackRow));
    update(() => selecting = true);
    await tester.pumpAndSettle();
    final after = tester.getRect(find.byType(Artwork));
    expect(after.left, before.left + TingyuTokens.controlSize);
    expect(after.top, before.top);
    expect(tester.getRect(find.byType(TrackRow)), row);
    expect(find.bySemanticsLabel('已喜欢'), findsNothing);
    BoxDecoration rowDecoration() =>
        tester
                .widget<Container>(
                  find
                      .descendant(
                        of: find.byType(TrackRow),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(rowDecoration().color, isNull, reason: '播放状态不能冒充已选背景');
    update(() => selected = true);
    await tester.pumpAndSettle();
    expect(rowDecoration().color, isNull);
    expect(
      tester.widget<Text>(find.text(firstTrack.title)).style!.color,
      tingyuTheme('bili').extension<TingyuTokens>()!.text,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('off is a draft until dismissal and background never commits', (
    tester,
  ) async {
    f.controller.setSleepTimer(const Duration(minutes: 15));
    final deadline = f.controller.sleepTimer.deadline;
    await mountTimer(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('timer-off')));
    await tester.tap(find.byKey(const ValueKey('timer-off')));
    await tester.pump();
    expect(f.controller.sleepTimer.deadline, deadline);
    Navigator.of(tester.element(find.byType(PlaybackSettingsPanel))).pop();
    await tester.pumpAndSettle();
    expect(f.controller.sleepTimer.active, isFalse);
    await mountTimer(tester);
    await tester.tap(find.byKey(const ValueKey('timer-30')));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    Navigator.of(tester.element(find.byType(PlaybackSettingsPanel))).pop();
    await tester.pumpAndSettle();
    expect(f.controller.sleepTimer.active, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('home multi-select leaves header dock and song region in place', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await f.controller.remember(firstTrack);
    f.controller.current = firstTrack;
    final router = createRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryProvider.overrideWith((ref) => f.controller)],
        child: TingyuApp(router: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('批量选择')));
    await tester.pumpAndSettle();
    final row = tester.getRect(find.byType(TrackRow));
    final dock = tester.getRect(find.byType(MiniPlayer));
    final nav = tester.getRect(find.byType(CompactNavigation));
    await tester.tap(find.byKey(const ValueKey('批量选择')));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(TrackRow)), row);
    expect(tester.getRect(find.byType(MiniPlayer)), dock);
    expect(tester.getRect(find.byType(CompactNavigation)), nav);
    expect(find.text('随心听'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });
}
