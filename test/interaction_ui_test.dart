import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'package:tingyu/ui/playing_indicator.dart';
import 'support/fakes.dart';

void main() {
  late TestLibrary fixture;
  late GoRouter router;
  bool mountedController = false;
  setUp(() async {
    mountedController = false;
    fixture = await TestLibrary.create();
    await fixture.controller.remember(firstTrack);
    await fixture.controller.remember(secondTrack);
    router = createRouter();
  });
  tearDown(() async {
    router.dispose();
    await fixture.close(disposeController: !mountedController);
  });
  Future<void> settleFrames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    if (find.byType(QueuePanel).evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
    } else {
      await tester.pumpAndSettle();
    }
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    for (var i = 0; i < 10; i++) {
      await settleFrames(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
    }
    await settleFrames(tester);
    expect(tester.takeException(), isNull);
  }

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(360, 800),
  }) async {
    mountedController = true;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryProvider.overrideWith((_) => fixture.controller)],
        child: TingyuApp(router: router),
      ),
    );
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final target = find.byKey(ValueKey(label)).last;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  }

  test(
    'batch adding existing songs commits once, deduplicates and recovers after save failure',
    () async {
      final p = fixture.controller;
      await p.addPlaylist('批量添加', track: firstTrack);
      final id = p.playlists.last.id;
      await fixture.db.customStatement('DROP TABLE app_state');
      try {
        await expectLater(
          p.addLibraryTracks(id, [secondTrack.id]),
          throwsA(isA<Exception>()),
        );
        expect(p.playlists.last.trackIds, [firstTrack.id]);
      } finally {
        await fixture.db.customStatement(
          'CREATE TABLE app_state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
      }
      await p.addLibraryTracks(id, [
        secondTrack.id,
        secondTrack.id,
        firstTrack.id,
      ]);
      expect(p.playlists.last.trackIds, [firstTrack.id, secondTrack.id]);
      await expectLater(p.addLibraryTracks(id, ['removed']), throwsException);
      expect(p.playlists.last.trackIds, [firstTrack.id, secondTrack.id]);
      final stored = await fixture.db.readState('library');
      expect((stored!['playlists'] as List).last['tracks'], [
        firstTrack.id,
        secondTrack.id,
      ]);
    },
  );

  testWidgets('collection transitions are brief and respect reduced motion', (
    tester,
  ) async {
    await fixture.controller.addPlaylist('过渡歌单', track: firstTrack);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await mount(tester);
    router.go('/playlist/${fixture.controller.playlists.last.id}');
    await settle(tester);
    final route = ModalRoute.of(tester.element(find.byType(AppShell).last))!;
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    await unmount(tester);
  });

  testWidgets(
    '500-song library is virtualized and playhead ticks do not rebuild rows',
    (tester) async {
      final p = fixture.controller;
      for (var i = 0; i < 498; i++) {
        await p.remember(
          Track(
            bvid: 'BVperf$i',
            cid: 5000 + i,
            title: '滚动歌曲 $i',
            artist: 'UP',
            cover: '',
            duration: 30,
          ),
        );
      }
      await mount(tester);
      expect(find.byType(TrackRow).evaluate().length, lessThan(30));
      await p.play(firstTrack);
      await settle(tester);
      final row = tester.element(find.byType(TrackRow).first);
      final oldWidget = row.widget;
      var globalNotifications = 0;
      void count() => globalNotifications++;
      p.addListener(count);
      for (var i = 1; i <= 100; i++) {
        fixture.playback.player.positions.add(Duration(milliseconds: i * 20));
        await tester.pump();
      }
      expect(p.position, const Duration(seconds: 2));
      expect(globalNotifications, 0, reason: '进度变化只刷新进度和歌词，不能刷新曲库');
      expect(identical(row.widget, oldWidget), isTrue);
      p.removeListener(count);
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -2000),
      );
      await settle(tester);
      expect(find.byType(TrackRow).evaluate().length, lessThan(30));
      await unmount(tester);
    },
  );

  testWidgets(
    'lazy rows retain their snapshot while canonical track replacement awaits notification',
    (tester) async {
      final p = fixture.controller;
      final originals = <Track>[];
      for (var i = 0; i < 80; i++) {
        final track = Track(
          bvid: 'BVsnapshot$i',
          cid: 0,
          title: '快照歌曲 $i',
          artist: 'UP',
          cover: '',
          duration: 30,
        );
        p.library[track.id] = track;
        originals.add(track);
      }
      await mount(tester);
      // Reproduce the interval after canonical() replaces IDs and before save()
      // completes and the controller publishes its next notification.
      for (final old in originals.skip(15).take(30)) {
        p.library.remove(old.id);
        final resolved = Track(
          bvid: old.bvid,
          cid: 7000,
          title: old.title,
          artist: old.artist,
          cover: '',
          duration: 30,
        );
        p.library[resolved.id] = resolved;
      }
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -1900),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      p.clearError();
      await settle(tester);
      expect(find.byType(TrackRow).evaluate().length, lessThan(30));
      await unmount(tester);
    },
  );

  testWidgets(
    'add songs is scoped, supports cancel/local commit/online add, and tabs do not flash old playlist',
    (tester) async {
      final p = fixture.controller;
      await p.addPlaylist('导航歌单', track: firstTrack);
      final list = p.playlists.last;
      Future<void> openPicker() async {
        await tap(tester, '歌单更多');
        await tester.tap(find.text('添加歌曲').last);
        await settle(tester);
        expect(find.byType(PlaylistAddScreen), findsOneWidget);
        expect(find.byType(CompactNavigation), findsNothing);
      }

      await mount(tester);
      router.go('/playlist/${list.id}');
      await settle(tester);
      await openPicker();
      expect(
        tester
            .widget<Pressable>(find.byKey(const ValueKey('commit-add-tracks')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<Pressable>(
              find.byKey(ValueKey('select-add-${firstTrack.id}')),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, 'select-add-${secondTrack.id}');
      await tap(tester, '取消添加歌曲');
      expect(p.playlists.last.trackIds, [firstTrack.id]);
      await openPicker();
      expect(find.text('添加 0 首'), findsOneWidget);
      await tap(tester, 'select-add-${secondTrack.id}');
      await tap(tester, '在线搜索');
      expect(
        GoRouterState.of(tester.element(find.byType(AppShell).last)).uri.path,
        '/playlist/${list.id}/add/search',
      );
      expect(find.byType(CompactNavigation), findsNothing);
      final remote = Track(
        bvid: 'BVremote',
        cid: 333,
        title: '新歌',
        artist: '新 UP',
        cover: '',
        duration: 30,
      );
      final placeholder = Track(
        bvid: firstTrack.bvid,
        cid: 0,
        title: '已有歌曲',
        artist: firstTrack.artist,
        cover: '',
        duration: 30,
      );
      fixture.api.searchAnswer = (_, _) async => [placeholder, remote];
      await tester.enterText(find.byType(TextField).last, '新歌');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(
        tester
            .widget<Pressable>(find.byKey(ValueKey('已添加 ${placeholder.title}')))
            .onPressed,
        isNull,
      );
      await tap(tester, '添加到歌单 ${remote.title}');
      expect(p.playlists.last.trackIds, [firstTrack.id, remote.id]);
      expect(find.byKey(ValueKey('已添加 ${remote.title}')), findsOneWidget);
      await tap(tester, '返回选歌');
      expect(find.text('添加 1 首'), findsOneWidget, reason: '在线搜索返回保留本地待选');
      await tap(tester, 'commit-add-tracks');
      expect(
        router.routeInformationProvider.value.uri.path,
        '/playlist/${list.id}',
      );
      expect(p.playlists.last.trackIds, [
        firstTrack.id,
        remote.id,
        secondTrack.id,
      ]);
      await openPicker();
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(
        router.routeInformationProvider.value.uri.path,
        '/playlist/${list.id}',
      );
      await tap(tester, 'tab-search');
      await tester.tap(find.byKey(const ValueKey('tab-library')));
      for (final time in [
        Duration.zero,
        const Duration(milliseconds: 16),
        const Duration(milliseconds: 80),
      ]) {
        await tester.pump(time);
        expect(
          find.byKey(const ValueKey('返回音乐库')),
          findsOneWidget,
          reason: '跨分类返回应直接恢复歌单，不能闪成首页',
        );
      }
      expect(
        router.routeInformationProvider.value.uri.path,
        '/playlist/${list.id}',
      );
      await tap(tester, 'tab-library');
      expect(find.byKey(const ValueKey('返回音乐库')), findsNothing);
      expect(router.routeInformationProvider.value.uri.path, '/');
      await unmount(tester);
    },
  );

  testWidgets(
    'clicking a row queues its entire 51-track library and respects the likes scope',
    (tester) async {
      final p = fixture.controller;
      for (var i = 0; i < 49; i++) {
        await p.remember(
          Track(
            bvid: 'BVlibrary$i',
            cid: 100 + i,
            title: '歌曲$i',
            artist: 'UP',
            cover: '',
            duration: 30,
          ),
        );
      }
      await p.enqueue(firstTrack);
      await p.enqueue(secondTrack);
      await mount(tester);
      await tap(tester, 'play-${firstTrack.id}');
      expect(p.queue.length, 51);
      await p.toggleLike(secondTrack);
      router.go('/likes');
      await settle(tester);
      await tap(tester, 'play-${secondTrack.id}');
      expect(p.queue, [secondTrack.id]);
      await unmount(tester);
    },
  );

  testWidgets(
    'queue locates and marks a late current track, supports locate and updates after removal',
    (tester) async {
      final p = fixture.controller;
      for (var i = 0; i < 80; i++) {
        await p.remember(
          Track(
            bvid: 'BVqueue$i',
            cid: i + 100,
            title: '队列歌曲$i',
            artist: 'UP',
            cover: '',
            duration: 30,
          ),
        );
      }
      final ids = p.library.keys.toList();
      final current = p.library[ids[65]]!;
      await p.playFromCollection(current, ids);
      await mount(tester);
      await tap(tester, '播放队列');
      final row = find.byKey(ValueKey('queue-track-${current.id}'));
      expect(row, findsOneWidget);
      expect(tester.widget<Pressable>(row).selected, isTrue);
      expect(find.byType(PlayingIndicator), findsOneWidget);
      await p.toggle();
      await settle(tester);
      expect(find.byType(PlayingIndicator), findsNothing);
      await p.toggle();
      await settle(tester);
      expect(find.byType(PlayingIndicator), findsOneWidget);
      final queue = find.byKey(const ValueKey('queue-list'));
      final scrollable = find.descendant(
        of: queue,
        matching: find.byType(Scrollable),
      );
      final state = tester.state<ScrollableState>(scrollable);
      expect(state.position.pixels, greaterThan(3000));
      state.position.jumpTo(0);
      await settleFrames(tester);
      await tap(tester, '定位当前歌曲');
      expect(state.position.pixels, greaterThan(3000));
      await tap(tester, '上移第 66 首');
      expect(p.queue[64], current.id);
      expect(tester.widget<Pressable>(row).selected, isTrue);
      await tap(tester, '关闭队列');
      await unmount(tester);
    },
  );

  testWidgets(
    'local search filters offline library and likes, clears without deleting songs',
    (tester) async {
      final p = fixture.controller;
      fixture.api.offline = true;
      await mount(tester);
      await tap(tester, '搜索本地歌曲');
      await tester.enterText(
        find.byKey(const ValueKey('local-search')),
        firstTrack.title,
      );
      await settle(tester);
      expect(find.byKey(ValueKey('play-${firstTrack.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('play-${secondTrack.id}')), findsNothing);
      await tap(tester, 'play-${firstTrack.id}');
      expect(p.queue, [firstTrack.id]);
      await tester.enterText(
        find.byKey(const ValueKey('local-search')),
        '没有这样的歌',
      );
      await settle(tester);
      expect(find.text('没有匹配的歌曲'), findsOneWidget);
      await tap(tester, '清除搜索');
      expect(find.byKey(ValueKey('play-${secondTrack.id}')), findsOneWidget);
      expect(p.library.length, 2);
      await p.toggleLike(secondTrack);
      router.go('/likes');
      await settle(tester);
      await tap(tester, '搜索本地歌曲');
      await tester.enterText(
        find.byKey(const ValueKey('local-search')),
        firstTrack.title,
      );
      await settle(tester);
      expect(find.text('没有匹配的歌曲'), findsOneWidget);
      await unmount(tester);
    },
  );

  testWidgets(
    'first visits after theme changes use new colors on every frame and retain branch state',
    (tester) async {
      await mount(tester);
      for (final theme in ['b', 'c', 'a']) {
        await tester.runAsync(() => fixture.controller.setTheme(theme));
        for (final tab in ['search', 'downloads', 'likes', 'library']) {
          await tester.tap(find.byKey(ValueKey('tab-$tab')));
          for (final delta in [0, 16, 100, 200]) {
            await tester.pump(Duration(milliseconds: delta));
            final nav = find.byType(CompactNavigation);
            expect(
              Theme.of(
                tester.element(nav),
              ).extension<TingyuTokens>()!.background,
              tingyuTheme(theme).extension<TingyuTokens>()!.background,
            );
            expect(
              find.descendant(
                of: nav,
                matching: find.byType(AnimatedContainer),
              ),
              findsNothing,
            );
            expect(tester.takeException(), isNull);
          }
        }
      }
      await unmount(tester);
    },
  );

  testWidgets(
    'settings returns to its source with search input and playback preserved',
    (tester) async {
      await fixture.controller.play(firstTrack);
      await mount(tester);
      router.go('/search');
      await settle(tester);
      await tester.enterText(find.byType(TextField), '保留搜索');
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      router.push('/settings');
      await settle(tester);
      expect(fixture.controller.playing, isTrue);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '保留搜索',
      );
      expect(fixture.controller.playing, isTrue);
      router.go('/settings');
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byKey(const ValueKey('打开设置')), findsOneWidget);
      await unmount(tester);
    },
  );

  testWidgets(
    'collection detail sorting and batch remove confirm cancellation preserves data',
    (tester) async {
      final p = fixture.controller;
      await p.addPlaylist('夜航', track: firstTrack);
      await p.addToPlaylist(p.playlists.single, secondTrack);
      await mount(tester);
      await tap(tester, '夜航');
      expect(find.byKey(const ValueKey('返回音乐库')), findsOneWidget);
      expect(find.byType(PlaylistSummary), findsOneWidget);
      await tap(tester, '歌曲排序');
      await tap(tester, 'sort-recent');
      expect(p.collectionSort[p.playlists.single.id], 'recent');
      await tap(tester, '批量选择');
      await tap(tester, 'select-${firstTrack.id}');
      expect(find.text('已选 1 首'), findsOneWidget);
      await tap(tester, '批量移出歌单');
      await tap(tester, '取消');
      expect(p.playlists.single.trackIds.length, 2);
      await tap(tester, '批量移出歌单');
      await tap(tester, '确认');
      expect(p.playlists.single.trackIds, [secondTrack.id]);
      expect(find.byKey(const ValueKey('批量选择')), findsOneWidget);
      await tap(tester, '批量选择');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byKey(const ValueKey('退出多选')), findsNothing);
      expect(find.byType(PlaylistSummary), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byKey(const ValueKey('打开设置')), findsOneWidget);
      await unmount(tester);
    },
  );

  testWidgets(
    'playlist create, blank validation, add, rename, remove and delete confirmation',
    (tester) async {
      await mount(tester);
      await tap(tester, '新建歌单');
      await tap(tester, '保存');
      expect(find.text('请输入歌单名称'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '晨间');
      await tap(tester, '保存');
      expect(fixture.controller.playlists.length, 1);
      await tap(tester, '更多 ${firstTrack.title}');
      await tap(tester, '加入歌单');
      await tap(tester, '晨间');
      expect(fixture.controller.playlists.single.trackIds, [firstTrack.id]);
      await tap(tester, '晨间');
      await tap(tester, '歌单更多');
      await tap(tester, '编辑歌单');
      await tester.enterText(
        find.byKey(const ValueKey('playlist-name')),
        '新的歌单',
      );
      final descriptionField = tester.widget<TextField>(
        find.byKey(const ValueKey('playlist-description')),
      );
      expect(descriptionField.minLines, 1);
      expect(descriptionField.maxLines, 4);
      expect(descriptionField.decoration!.isDense, isTrue);
      await tester.enterText(
        find.byKey(const ValueKey('playlist-description')),
        '夜晚听的歌',
      );
      await tap(tester, '保存');
      expect(fixture.controller.playlists.single.name, '新的歌单');
      expect(fixture.controller.playlists.single.description, '夜晚听的歌');
      await tap(tester, '更多 ${firstTrack.title}');
      await tap(tester, '移出歌单');
      await tap(tester, '确认');
      expect(fixture.controller.playlists.single.trackIds, isEmpty);
      await tap(tester, '歌单更多');
      await tap(tester, '删除歌单');
      await tap(tester, '取消');
      expect(fixture.controller.playlists.length, 1);
      await tap(tester, '歌单更多');
      await tap(tester, '删除歌单');
      await tap(tester, '确认');
      expect(fixture.controller.playlists, isEmpty);
      expect(
        fixture.controller.library.keys,
        containsAll([firstTrack.id, secondTrack.id]),
      );
      await unmount(tester);
    },
  );
  testWidgets(
    'likes and queue actions are reversible and clearing stops playback',
    (tester) async {
      await mount(tester);
      await tap(tester, '更多 ${firstTrack.title}');
      await tap(tester, '喜欢');
      await tap(tester, 'tab-likes');
      expect(fixture.controller.likes, [firstTrack.id]);
      expect(find.byKey(ValueKey('play-${secondTrack.id}')), findsNothing);
      await tap(tester, '更多 ${firstTrack.title}');
      await tap(tester, '取消喜欢');
      expect(find.text('这里还很安静'), findsOneWidget);
      await tap(tester, 'tab-library');
      await tap(tester, 'play-${firstTrack.id}');
      await tap(tester, '更多 ${secondTrack.title}');
      await tap(tester, '加入队列');
      await tap(tester, '播放队列');
      await tap(tester, '上移第 2 首');
      expect(fixture.controller.queue, [secondTrack.id, firstTrack.id]);
      await tap(tester, '清空');
      await tap(tester, '取消');
      expect(fixture.controller.queue.length, 2);
      await tap(tester, '清空');
      await tap(tester, '确认');
      expect(fixture.controller.queue, isEmpty);
      expect(fixture.controller.playing, isFalse);
      expect(find.text('队列是空的'), findsOneWidget);
      await tap(tester, '关闭队列');
      await unmount(tester);
    },
  );
  testWidgets(
    'visible playback modes, manual skip and lyric cancel/save keep their contracts',
    (tester) async {
      await fixture.controller.enqueue(firstTrack);
      await fixture.controller.enqueue(secondTrack);
      await mount(tester);
      await tap(tester, 'play-${firstTrack.id}');
      await tap(tester, '展开播放器');
      await tap(tester, 'cycle-mode');
      expect(find.byType(SimpleDialog), findsNothing);
      expect(fixture.controller.mode, 'repeat');
      await tap(tester, '下一首');
      expect(fixture.controller.current!.id, secondTrack.id);
      await tap(tester, 'cycle-mode');
      expect(fixture.controller.mode, 'shuffle');
      await tap(tester, '下一首');
      expect(fixture.controller.current!.id, firstTrack.id);
      await tap(tester, '歌词');
      await tester.drag(find.byType(Slider).last, const Offset(70, 0));
      await settle(tester);
      expect(fixture.controller.lyricOffset, 0);
      await tap(tester, '取消');
      expect(fixture.controller.lyricOffset, 0);
      await tap(tester, '歌词');
      await tester.enterText(find.byType(TextField).last, '[00:01.00]测试歌词');
      await tester.drag(find.byType(Slider).last, const Offset(60, 0));
      await tap(tester, '保存歌词');
      expect(fixture.controller.lyricText, '[00:01.00]测试歌词');
      expect(fixture.controller.lyricOffset, isNot(0));
      await tap(tester, '返回');
      expect(find.byType(PlayerScreen), findsNothing);
      await unmount(tester);
    },
  );
  testWidgets(
    'search failures retry the same page and never skip or duplicate results',
    (tester) async {
      final pages = <int>[];
      var failed = false;
      fixture.api.searchAnswer = (query, page) async {
        pages.add(page);
        if (query == '空') return [];
        if (page == 2 && !failed) {
          failed = true;
          throw const AppFailure('分页暂时失败，请重试');
        }
        return page == 1 ? [firstTrack] : [secondTrack];
      };
      await mount(tester);
      await tap(tester, 'tab-search');
      await tester.enterText(find.byType(TextField), '音乐');
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      await tap(tester, '加载更多');
      expect(find.text('分页暂时失败，请重试'), findsOneWidget);
      await tap(tester, '重试或关闭提示');
      await tap(tester, '加载更多');
      expect(pages, [1, 2, 2, 3]);
      expect(fixture.controller.results.length, 2);
      await tester.enterText(find.byType(TextField), '空');
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      expect(find.text('没有找到相关内容'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settle(tester);
      expect(fixture.controller.playing, isFalse);
      await unmount(tester);
    },
  );
  testWidgets(
    'async pressable suppresses repeated pointer and keyboard activation until completion',
    (tester) async {
      final done = Completer<void>();
      var count = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: tingyuTheme('a'),
          home: Scaffold(
            body: Pressable(
              key: const ValueKey('pending'),
              onPressed: () async {
                count++;
                await done.future;
              },
              child: const Text('保存'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('pending')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pending')));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(count, 1);
      done.complete();
      await settleFrames(tester);
      await tester.tap(find.byKey(const ValueKey('pending')));
      await settleFrames(tester);
      expect(count, 2);
      await unmount(tester);
    },
  );
  testWidgets(
    'desktop volume slider responds while paused and gain persists across track changes',
    (tester) async {
      await fixture.controller.play(firstTrack);
      await fixture.controller.toggle();
      await mount(tester, size: const Size(1440, 900));
      final slider = find.byType(Slider).last;
      await tester.drag(slider, const Offset(-35, 0));
      await settle(tester);
      final gain = fixture.playback.player.volume;
      expect(gain, lessThan(1));
      expect(tester.widget<Slider>(slider).value, gain);
      await fixture.controller.play(secondTrack);
      await settle(tester);
      expect(fixture.playback.player.volume, gain);
      await unmount(tester);
    },
  );
  testWidgets(
    'QR expiry, refresh, scan confirmation, expired session and logout recover visibly',
    (tester) async {
      await mount(tester);
      await tap(tester, '打开设置');
      await tap(tester, 'settings-account');
      await tap(tester, '生成登录二维码');
      fixture.api.qrCode = 86038;
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(find.text('二维码已过期，请刷新'), findsOneWidget);
      await tap(tester, '刷新二维码');
      expect(fixture.api.qrRequests, 2);
      fixture.api.qrCode = 86090;
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(find.text('已扫码，请在 B 站 App 确认'), findsOneWidget);
      fixture.api.qrCode = 0;
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(
        find.descendant(
          of: find.byType(AccountPanel),
          matching: find.text('测试账号'),
        ),
        findsOneWidget,
      );
      expect(find.text('暂无可导入的收藏夹。'), findsOneWidget);
      final disabled = tester.widget<Pressable>(
        find.byKey(const ValueKey('请先选择收藏夹')),
      );
      expect(disabled.onPressed, isNull);
      fixture.api.loggedIn = false;
      await tap(tester, '刷新收藏夹');
      expect(
        find.descendant(
          of: find.byType(AccountPanel),
          matching: find.text('登录已过期，请重新扫码'),
        ),
        findsOneWidget,
      );
      await tap(tester, '生成登录二维码');
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      await tap(tester, '退出账号');
      expect(fixture.controller.profile, isNull);
      expect(fixture.controller.library.length, 2);
      await tap(tester, '关闭账号窗口');
      await unmount(tester);
    },
  );
  testWidgets(
    'standalone settings consolidates account and preferences without drawer or player chrome',
    (tester) async {
      await mount(tester);
      expect(find.byKey(const ValueKey('打开设置')), findsOneWidget);
      expect(find.byKey(const ValueKey('账号与设置')), findsNothing);
      for (final page in ['/search', '/downloads', '/likes', '/settings']) {
        router.go(page);
        await settle(tester);
        expect(find.byKey(const ValueKey('打开设置')), findsNothing);
        expect(find.text('YOUR PERSONAL SOUNDTRACK'), findsNothing);
      }
      router.go('/');
      await settle(tester);
      await tap(tester, '打开设置');
      expect(find.byType(SettingsPanel), findsOneWidget);
      expect(find.text('暖白'), findsOneWidget);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(CompactNavigation), findsNothing);
      expect(find.byType(MiniPlayer), findsNothing);
      expect(find.text('收藏夹导入'), findsNothing);
      final disabledImport = tester.widget<Pressable>(
        find.byKey(const ValueKey('settings-import')),
      );
      expect(disabledImport.onPressed, isNull);
      await tap(tester, 'theme-b');
      expect(fixture.controller.theme, 'b');
      await tap(tester, 'theme-c');
      expect(fixture.controller.theme, 'c');
      await tap(tester, 'theme-a');
      await tap(tester, 'settings-quality');
      await tap(tester, 'quality-true');
      expect(fixture.controller.standard, isTrue);
      await tap(tester, 'settings-storage');
      expect(find.byType(DownloadsPanel), findsOneWidget);
      await tap(tester, '返回设置');
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tap(tester, 'settings-about');
      await tap(tester, '关闭');
      await tap(tester, '返回');
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.textContaining('账号凭据保存在'), findsNothing);
      await unmount(tester);
    },
  );

  testWidgets(
    'download icons expose waiting progress completion pause and failure without visible text',
    (tester) async {
      await fixture.controller.play(firstTrack);
      await mount(tester);
      await tap(tester, '展开播放器');
      final task = DownloadTask(firstTrack);
      fixture.downloads.tasks.add(task);
      for (final status in DownloadStatus.values) {
        task.status = status;
        task.received = 25;
        task.total = 100;
        fixture.controller.clearError();
        await tester.pump();
        final button = find.byKey(ValueKey('download-${firstTrack.id}'));
        expect(button.hitTestable(), findsOneWidget);
        expect(
          find.descendant(of: button, matching: find.byType(Text)),
          findsNothing,
        );
        final control = tester.widget<Pressable>(button);
        if (status == DownloadStatus.downloading) {
          expect(control.label, contains('25%'));
          expect(
            find.descendant(
              of: button,
              matching: find.byType(CircularProgressIndicator),
            ),
            findsOneWidget,
          );
        }
        if (status == DownloadStatus.completed) {
          expect(control.selected, isTrue);
          expect(control.label, contains('已下载'));
        }
        if (status == DownloadStatus.failed) {
          expect(control.label, contains('点击重试'));
        }
        if (status == DownloadStatus.paused) {
          expect(control.label, contains('点击继续'));
        }
      }
      task.status = DownloadStatus.completed;
      fixture.controller.clearError();
      await tester.pump();
      await tap(tester, 'download-${firstTrack.id}');
      expect(find.byType(DownloadsPanel), findsOneWidget);
      await unmount(tester);
    },
  );

  test(
    'download icon resolves placeholder IDs to the canonical first-part download',
    () async {
      fixture.downloads.tasks.add(
        DownloadTask(firstTrack, status: DownloadStatus.completed),
      );
      const placeholder = Track(
        bvid: 'BV1xx411c7mD',
        cid: 0,
        title: '占位',
        artist: '',
        cover: '',
        duration: 30,
      );
      expect(
        trackDownload(fixture.controller, placeholder)?.status,
        DownloadStatus.completed,
      );
    },
  );
  testWidgets(
    'all themes render full shared pages at four target sizes without exceptions',
    (tester) async {
      final p = fixture.controller;
      await p.play(firstTrack);
      await p.toggleLike(firstTrack);
      await p.addPlaylist('一个名字较长的收藏歌单用于页面布局检查', track: firstTrack);
      await mount(tester);
      for (final size in [
        const Size(360, 800),
        const Size(412, 915),
        const Size(1024, 768),
        const Size(1440, 900),
      ]) {
        tester.view.physicalSize = size;
        for (final theme in ['a', 'b', 'c']) {
          await p.setTheme(theme);
          for (final page in [
            '/',
            '/search',
            '/likes',
            '/downloads',
            '/settings',
            '/playlist/${p.playlists.single.id}',
            '/player',
          ]) {
            router.go(page);
            await settle(tester);
            if (page == '/player') {
              expect(
                find.byKey(const ValueKey('返回')).hitTestable(),
                findsOneWidget,
              );
              expect(
                find.byKey(const ValueKey('cycle-mode')).hitTestable(),
                findsOneWidget,
              );
              expect(find.text('返回'), findsNothing);
              expect(find.text('下载'), findsNothing);
            }
          }
        }
      }
      await unmount(tester);
    },
  );
}
