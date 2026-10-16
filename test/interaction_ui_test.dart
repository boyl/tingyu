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
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
    }
    await tester.pumpAndSettle();
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
      await tap(tester, '重命名');
      await tester.enterText(find.byType(TextField), '新的歌单');
      await tap(tester, '保存');
      expect(fixture.controller.playlists.single.name, '新的歌单');
      await tap(tester, '更多 ${firstTrack.title}');
      await tap(tester, '移出歌单');
      expect(fixture.controller.playlists.single.trackIds, isEmpty);
      await tap(tester, '删除歌单');
      await tap(tester, '取消');
      expect(fixture.controller.playlists.length, 1);
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
      await tap(tester, '列表循环 · 切换模式');
      await tap(tester, '单曲循环');
      expect(fixture.controller.mode, 'repeat');
      await tap(tester, '下一首');
      expect(fixture.controller.current!.id, secondTrack.id);
      await tap(tester, '单曲循环 · 切换模式');
      await tap(tester, '随机播放');
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
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pending')));
      await tester.pumpAndSettle();
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
      await tap(tester, '账号与设置');
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
      expect(find.text('测试账号'), findsOneWidget);
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
              expect(find.text('列表循环 · 切换模式').hitTestable(), findsOneWidget);
            }
          }
        }
      }
      await unmount(tester);
    },
  );
}
