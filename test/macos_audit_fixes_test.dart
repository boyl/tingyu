// 2026-10-25 Mac 审查问题的正式回归。
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/controllers/library_controller.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'support/fakes.dart';

class DelayedSessionApi extends FixtureApi {
  final gate = Completer<void>();
  @override
  Future<void> initialize() => gate.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('直接退出账号与重开数据库应保留历史', () async {
    final f = await TestLibrary.create();
    await f.controller.remember(firstTrack);
    f.controller.history.add(firstTrack.id);
    f.api.loggedIn = true;
    await f.controller.save();
    await f.controller.logout();
    expect(f.controller.history, [firstTrack.id]);
    final directory = f.directory;
    await f.close(deleteData: false);
    final restored = await TestLibrary.create(dataDirectory: directory);
    try {
      expect(restored.controller.history, [firstTrack.id]);
    } finally {
      await restored.close();
    }
  });

  test('慢登录恢复不能覆盖已保存历史与歌单', () async {
    final f = await TestLibrary.create();
    await f.controller.remember(firstTrack);
    f.controller.history.add(firstTrack.id);
    f.controller.playlists.add(Playlist('audit', '审查歌单', [firstTrack.id]));
    await f.controller.save();
    f.controller.dispose();
    final api = DelayedSessionApi();
    final restored = LibraryController(
      api,
      f.db,
      f.downloads,
      f.playback,
      lyricsClient: FixtureLyrics(),
    );
    try {
      final initializing = restored.initialize();
      await expectLater(restored.save(), throwsStateError);
      await Future<void>.delayed(const Duration(milliseconds: 5200));
      final storedBeforeRestore = await f.db.readState('library');
      api.gate.complete();
      await initializing;
      expect(storedBeforeRestore!['history'], [
        firstTrack.id,
      ], reason: '本地恢复完成前不允许自动保存空状态');
      expect(restored.history, [firstTrack.id]);
      expect(restored.playlists, hasLength(1));
    } finally {
      if (!api.gate.isCompleted) api.gate.complete();
      restored.dispose();
      await f.close(disposeController: false);
    }
  });

  test('初始化失败后仍不能覆盖原状态', () async {
    final f = await TestLibrary.create();
    await f.controller.remember(firstTrack);
    f.controller.history.add(firstTrack.id);
    await f.controller.save();
    f.controller.dispose();
    final api = DelayedSessionApi();
    final restored = LibraryController(
      api,
      f.db,
      f.downloads,
      f.playback,
      lyricsClient: FixtureLyrics(),
    );
    try {
      final init = restored.initialize();
      final failure = expectLater(init, throwsStateError);
      api.gate.completeError(StateError('无法恢复'));
      await failure;
      await expectLater(restored.save(), throwsStateError);
      expect((await f.db.readState('library'))!['history'], [firstTrack.id]);
    } finally {
      restored.dispose();
      await f.close(disposeController: false);
    }
  });

  test('搜索空页、重复页停止继续加载，失败保留重试页', () async {
    final f = await TestLibrary.create();
    try {
      var calls = 0;
      f.api.searchAnswer = (_, page) async {
        calls++;
        return page == 1 ? [firstTrack] : [];
      };
      await f.controller.search('声音');
      await f.controller.search('声音', page: 2);
      await f.controller.search('声音', page: 3);
      expect(calls, 2);
      expect(f.controller.searchHasMore, isFalse);
      f.api.searchAnswer = (_, page) async => [firstTrack];
      await f.controller.search('声音');
      await f.controller.search('声音', page: 2);
      expect(f.controller.searchHasMore, isFalse);
      f.api.searchAnswer = (_, page) async =>
          page == 1 ? [firstTrack] : throw const AppFailure('离线');
      await f.controller.search('声音');
      await f.controller.search('声音', page: 2);
      expect(f.controller.searchAttemptPage, 2);
      expect(f.controller.searchHasMore, isTrue);
      expect(f.controller.results, [firstTrack]);
    } finally {
      await f.close();
    }
  });

  Future<TestLibrary> mount(WidgetTester tester) async {
    final f = (await tester.runAsync(TestLibrary.create))!;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryProvider.overrideWith((_) => f.controller)],
        child: TingyuApp(router: createRouter(macOS: true)),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => f.close(disposeController: false));
    return f;
  }

  testWidgets('Mac 应显示播放失败原因', (tester) async {
    final f = await mount(tester);
    f.api.offline = true;
    await tester.runAsync(() => f.controller.play(firstTrack));
    await tester.pumpAndSettle();
    expect(f.controller.error, isNotEmpty);
    expect(find.text(f.controller.error), findsOneWidget);
  });

  testWidgets('无效自定义定时不能静默提交上一个值', (tester) async {
    final f = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('播放选项')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mac-timer-minutes')),
      '15',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mac-timer-minutes')),
      '999',
    );
    await tester.tap(find.byKey(const ValueKey('关闭辅助面板')));
    await tester.pumpAndSettle();
    expect(
      f.controller.sleepTimer.active,
      isFalse,
      reason: '输入 999 不能实际开始 15 分钟定时',
    );
  });

  testWidgets('Mac 添加歌曲应保留桌面工作区', (tester) async {
    final f = await mount(tester);
    await tester.runAsync(() => f.controller.addPlaylist('审查歌单'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('mac-nav-${f.controller.playlists.single.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加歌曲'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mac-playback-bar')), findsOneWidget);
  });

  testWidgets('最近播放 Cmd F 应打开可用搜索', (tester) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('mac-nav-recent')));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
  });

  testWidgets('列表循环末曲的待播不能显示没有待播歌曲', (tester) async {
    final f = await mount(tester);
    await tester.runAsync(() async {
      await f.controller.remember(firstTrack);
      await f.controller.remember(secondTrack);
    });
    f.controller.queue.addAll([firstTrack.id, secondTrack.id]);
    f.controller.current = secondTrack;
    await tester.tap(find.byKey(const ValueKey('待播清单')));
    await tester.pumpAndSettle();
    expect(find.text('本轮没有待播歌曲'), findsNothing);
  });
  testWidgets('搜索进行中和失败不伪装为空结果', (tester) async {
    final f = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('mac-nav-search')));
    await tester.pumpAndSettle();
    final response = Completer<List<Track>>();
    f.api.searchAnswer = (_, _) => response.future;
    await tester.enterText(find.byKey(const ValueKey('mac-search')), '声音');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('正在搜索…'), findsOneWidget);
    expect(find.text('没有找到相关内容'), findsNothing);
    response.completeError(const AppFailure('测试断网'));
    await tester.pumpAndSettle();
    expect(find.text('测试断网'), findsOneWidget);
    expect(find.text('没有找到相关内容'), findsNothing);
  });

  testWidgets('定时无效值保持输入，修正后提交，未修改不重置', (tester) async {
    final f = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('播放选项')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('mac-timer-minutes'));
    await tester.enterText(field, '15');
    for (final value in ['', '0', '-1', '181', 'abc']) {
      await tester.enterText(field, value);
      await tester.tap(find.byKey(const ValueKey('关闭辅助面板')));
      await tester.pumpAndSettle();
      expect(find.text('请输入 1–180 分钟'), findsOneWidget);
      expect(f.controller.sleepTimer.active, isFalse);
    }
    await tester.enterText(field, '180');
    await tester.tap(find.byKey(const ValueKey('关闭辅助面板')));
    await tester.pumpAndSettle();
    expect(f.controller.sleepTimer.active, isTrue);
    final deadline = f.controller.sleepTimer.deadline;
    await tester.tap(find.byKey(const ValueKey('播放选项')));
    await tester.pumpAndSettle();
    expect(find.textContaining('剩余 '), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('关闭辅助面板')));
    await tester.pumpAndSettle();
    expect(f.controller.sleepTimer.deadline, deadline);
  });

  testWidgets('桌面在线选歌可取消且提交不离开工作区', (tester) async {
    final f = await mount(tester);
    await tester.runAsync(() => f.controller.addPlaylist('选歌测试'));
    await tester.pumpAndSettle();
    final id = f.controller.playlists.single.id;
    await tester.tap(find.byKey(ValueKey('mac-nav-$id')));
    await tester.pumpAndSettle();
    Future<void> choose() async {
      await tester.tap(find.text('添加歌曲'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('在线搜索')));
      await tester.enterText(
        find.byKey(const ValueKey('playlist-add-query')),
        '声音',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('select-add-${firstTrack.id}')));
      await tester.pumpAndSettle();
    }

    await choose();
    await tester.tap(find.byKey(const ValueKey('取消添加歌曲')));
    await tester.pumpAndSettle();
    expect(f.controller.library, isEmpty);
    expect(f.controller.playlists.single.trackIds, isEmpty);
    await choose();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('commit-add-tracks')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(f.controller.playlists.single.trackIds, [firstTrack.id]);
    expect(find.byType(PlaylistAddScreen), findsNothing);
    expect(find.byKey(const ValueKey('mac-playback-bar')), findsOneWidget);
  });

  testWidgets('歌词空态直接匹配，默认恢复按钮禁用', (tester) async {
    final f = await mount(tester);
    await tester.runAsync(() => f.controller.remember(firstTrack));
    f.controller.current = firstTrack;
    f.controller.showError('测试刷新');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('关闭错误提示')));
    await tester.tap(find.byKey(const ValueKey('mac-open-details')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('匹配或导入歌词'));
    await tester.pumpAndSettle();
    expect(find.byType(LyricsPreferencesPage), findsOneWidget);
    expect(find.text('显示与排版'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('返回')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('播放选项')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Pressable>(find.byKey(const ValueKey('恢复倍速'))).onPressed,
      isNull,
    );
  });
}
