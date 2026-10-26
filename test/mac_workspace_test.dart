import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'support/fakes.dart';

void main() {
  const windows = bool.fromEnvironment('WINDOWS_WORKSPACE');
  const capture =
      bool.fromEnvironment('CAPTURE_MAC_PREVIEW') ||
      bool.fromEnvironment('CAPTURE_WINDOWS_PREVIEW');
  createWorkspaceRouter() => createRouter(macOS: !windows, windows: windows);
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!capture) return;
    final font = await File(
      windows
          ? '${Platform.environment['SystemRoot']}/Fonts/msyh.ttc'
          : '/System/Library/Fonts/STHeiti Light.ttc',
    ).readAsBytes();
    for (final family in ['Roboto', '.SF UI Text', '.SF UI Display']) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(font)))).load();
    }
    final material = await File(
      'resources/icons/material/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(material)))).load();
  });
  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!capture) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('mac-preview-boundary')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final folder = windows
          ? 'artifacts/windows-flat-controls'
          : 'artifacts/mac-flat-controls';
      await Directory(folder).create(recursive: true);
      await File('$folder/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('Mac empty library starts in songs with search and import', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(TestLibrary.create))!;
    final router = createWorkspaceRouter();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('mac-preview-boundary'),
        child: ProviderScope(
          overrides: [libraryProvider.overrideWith((_) => fixture.controller)],
          child: TingyuApp(router: router),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyView), findsOneWidget);
    expect(find.text('还没有歌曲'), findsOneWidget);
    expect(find.text('登录账号'), findsOneWidget);
    expect(find.byType(AccountAvatar), findsOneWidget);
    expect(
      tester.getSize(find.byType(AccountAvatar)).width,
      TingyuTokens.macPlayerArt,
    );
    expect(
      tester
          .widget<Slider>(
            find.descendant(
              of: find.byKey(const ValueKey('mac-playback-bar')),
              matching: find.byType(Slider),
            ),
          )
          .onChanged,
      isNull,
    );
    expect(find.byKey(const ValueKey('mac-nav-library')), findsNothing);
    expect(find.text('还没有歌单'), findsNothing);
    expect(find.byKey(const ValueKey('新建歌单')), findsOneWidget);
    expect(find.byKey(const ValueKey('返回来源')), findsNothing);
    await screenshot(tester, '1280-empty-library');
    await tester.tap(find.byKey(const ValueKey('mac-nav-recent')));
    await tester.pumpAndSettle();
    expect(find.text('还没有播放记录'), findsOneWidget);
    await screenshot(tester, '1280-empty-recent');
    expect(find.byKey(const ValueKey('mac-local-recent')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mac-nav-playlists')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('新建歌单')), findsOneWidget);
    expect(find.byKey(const ValueKey('返回来源')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('账号与收藏夹')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mac-login-qr')), findsOneWidget);
    expect(fixture.api.qrRequests, 1);
    expect(find.text('刷新二维码'), findsNothing);
    final loginRect = tester.getRect(
      find.byKey(const ValueKey('mac-account-task')),
    );
    fixture.api.qrCode = 86038;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('刷新二维码'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('mac-account-task'))),
      loginRect,
    );
    fixture.api.qrCode = 86101;
    await tester.tap(find.text('刷新二维码'));
    await tester.pumpAndSettle();
    expect(fixture.api.qrRequests, 2);
    expect(find.text('刷新二维码'), findsNothing);
    fixture.api.qrFailure = const AppFailure('连接失败，请重试');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('连接失败，请重试'), findsOneWidget);
    expect(find.text('刷新二维码'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('mac-account-task'))),
      loginRect,
    );
    await screenshot(tester, '1280-account-error');
    fixture.api.qrFailure = null;
    await tester.tap(find.text('刷新二维码'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    fixture.api.qrCode = 0;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(fixture.controller.profile, isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.text('测试账号'), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('账号与收藏夹')),
        matching: find.text('测试账号'),
      ),
      findsOneWidget,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.tap(find.byKey(const ValueKey('关闭账号窗口')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    await tester.runAsync(() => fixture.close(disposeController: false));
  });

  testWidgets(
    'Mac storage stays in preferences and cancelling cleanup keeps files',
    (tester) async {
      final outer = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('tingyu-preferences-'),
      ))!;
      final data = (await tester.runAsync(
        () => Directory('${outer.path}/downloads').create(),
      ))!;
      final temporary = File('${data.path}/fixture.tmp');
      await tester.runAsync(
        () => temporary.writeAsString('fixture temporary file'),
      );
      final fixture = (await tester.runAsync(
        () => TestLibrary.create(dataDirectory: data),
      ))!;
      final router = createWorkspaceRouter();
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('mac-preview-boundary'),
          child: ProviderScope(
            overrides: [
              libraryProvider.overrideWith((_) => fixture.controller),
            ],
            child: TingyuApp(router: router),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('设置')));
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.byKey(const ValueKey('mac-settings')));
      await tester.tap(find.byKey(const ValueKey('mac-settings-storage')));
      await tester.pump();
      // Disk enumeration is real async I/O; wait for the statistics before settling.
      for (
        var i = 0;
        i < 100 &&
            find
                .byKey(const ValueKey('storage-clear-temporary'))
                .evaluate()
                .isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('mac-settings'))),
        bounds,
      );
      expect(router.routeInformationProvider.value.uri.path, '/');
      await screenshot(tester, '1024-settings-storage');
      await tester.ensureVisible(
        find.byKey(const ValueKey('storage-clear-temporary')),
      );
      await tester.tap(find.byKey(const ValueKey('storage-clear-temporary')));
      await tester.pumpAndSettle();
      expect(find.text('选择本次要清理的内容'), findsOneWidget);
      await tester.ensureVisible(find.text('取消'));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('选择本次要清理的内容'), findsNothing);
      expect(await tester.runAsync(temporary.exists), isTrue);
      expect(find.byType(MacSettingsPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await tester.runAsync(() async {
        await fixture.close(disposeController: false);
        await outer.delete(recursive: true);
      });
    },
  );

  for (final theme in ['bili', 'sunrise', 'moon', 'night']) {
    for (final size in [
      const Size(800, 600),
      const Size(1024, 768),
      const Size(1280, 800),
    ]) {
      testWidgets('Mac $theme large text and long title at $size', (
        tester,
      ) async {
        const longTrack = Track(
          bvid: 'BV1xx411c7mD',
          cid: 303,
          title: '这是一首标题非常长的歌曲，用来检查桌面播放器与详情文字的布局',
          artist: '一个名称同样比较长的创作者',
          cover: '',
          duration: 30,
        );
        final fixture = (await tester.runAsync(() async {
          final fixture = await TestLibrary.create();
          await fixture.controller.remember(longTrack);
          await fixture.controller.playCollection([longTrack.id]);
          await fixture.controller.toggle();
          await fixture.controller.setLyrics(
            '[00:00.00]第一行歌词\n[00:04.00]第二行歌词\n[00:08.00]第三行歌词',
          );
          await fixture.controller.setTheme(theme);
          return fixture;
        }))!;
        final router = createWorkspaceRouter();
        final dpi = windows
            ? (size.width == 800
                  ? 1.25
                  : size.width == 1024
                  ? 1.5
                  : 2.0)
            : 1.0;
        tester.view.physicalSize = size * dpi;
        tester.view.devicePixelRatio = dpi;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('mac-preview-boundary'),
            child: ProviderScope(
              overrides: [
                libraryProvider.overrideWith((_) => fixture.controller),
              ],
              child: TingyuApp(router: router),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byKey(const ValueKey('mac-playback-bar'))).height,
          80,
        );
        await tester.tap(find.byKey(const ValueKey('mac-open-details')));
        await tester.pumpAndSettle();
        expect(find.byType(LyricPanel), findsOneWidget);
        await screenshot(tester, '${size.width.toInt()}-$theme-large-details');
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('账号与收藏夹')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('mac-account-task')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await screenshot(tester, '${size.width.toInt()}-$theme-large-account');
        await tester.tap(find.byKey(const ValueKey('关闭账号窗口')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('设置')));
        await tester.pumpAndSettle();
        await screenshot(
          tester,
          '${size.width.toInt()}-$theme-large-settings-appearance',
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('mac-settings-playback')));
        await tester.pumpAndSettle();
        await screenshot(
          tester,
          '${size.width.toInt()}-$theme-large-settings-playback',
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
        router.dispose();
        await tester.runAsync(() => fixture.close(disposeController: false));
      });
    }
  }

  for (final size in [
    const Size(800, 600),
    const Size(1024, 768),
    const Size(1280, 800),
  ]) {
    testWidgets('Mac import flow and populated songs at $size', (tester) async {
      final fixture = (await tester.runAsync(TestLibrary.create))!;
      fixture.api.importAnswer = (_) async => [firstTrack, secondTrack];
      await tester.runAsync(
        () => fixture.controller.importFolder({'id': 7, 'title': '导入的收藏'}),
      );
      final router = createWorkspaceRouter();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('mac-preview-boundary'),
          child: ProviderScope(
            overrides: [
              libraryProvider.overrideWith((_) => fixture.controller),
            ],
            child: TingyuApp(router: router),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(fixture.controller.history, isEmpty);
      expect(find.byKey(const ValueKey('mac-local-songs')), findsOneWidget);
      expect(find.text('从喜欢的一首歌开始'), findsNothing);
      expect(find.byType(EmptyView), findsNothing);
      expect(find.byType(TrackRow), findsNWidgets(2));
      await screenshot(tester, '${size.width.toInt()}-imported-home');
      fixture.api.loggedIn = true;
      fixture.api.folderResults = [
        {'id': 8, 'title': '新的收藏夹与很长的名字，检查窄窗口仍能选择并完成导入', 'media_count': 2},
        {'id': 9, 'title': '第二个收藏夹', 'media_count': 0},
      ];
      await tester.tap(find.byKey(const ValueKey('账号与收藏夹')));
      await tester.pumpAndSettle();
      expect(find.text('测试账号'), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('账号与收藏夹')),
          matching: find.text('测试账号'),
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('mac-folder-search')),
        '新的收藏',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('folder-9')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('folder-8')));
      await tester.pumpAndSettle();
      final importHeight = tester
          .getSize(find.byKey(const ValueKey('mac-account-task')))
          .height;
      await screenshot(tester, '${size.width.toInt()}-account-import');
      fixture.api.importAnswer = (_) async =>
          throw const AppFailure('收藏夹暂时无法导入，请重试');
      await tester.runAsync(() async {
        await tester
            .widget<Pressable>(find.byKey(const ValueKey('import-folders')))
            .onPressed!();
      });
      await tester.pumpAndSettle();
      expect(find.text('收藏夹暂时无法导入，请重试'), findsOneWidget);
      expect(fixture.controller.playlists.length, 1);
      fixture.api.importAnswer = (_) async => [firstTrack, secondTrack];
      await tester.runAsync(() async {
        await tester
            .widget<Pressable>(find.byKey(const ValueKey('import-folders')))
            .onPressed!();
      });
      await tester.pumpAndSettle();
      expect(find.text('已导入 1 个收藏夹'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('mac-account-task'))).height,
        lessThan(importHeight),
      );
      await screenshot(tester, '${size.width.toInt()}-account-success');
      final imported = fixture.controller.playlists.last;
      await tester.tap(find.byKey(const ValueKey('mac-open-imported')));
      await tester.pumpAndSettle();
      expect(find.byType(AccountPanel), findsNothing);
      expect(
        find.byType(windows ? WindowsWorkspace : MacWorkspace),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('mac-local-${imported.id}')), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/');
      await tester.tap(find.byKey(const ValueKey('mac-nav-songs')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mac-local-songs')), findsOneWidget);
      expect(fixture.controller.history, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await tester.runAsync(() => fixture.close(disposeController: false));
    });
  }

  for (final size in [
    const Size(800, 600),
    const Size(1024, 768),
    const Size(1280, 800),
  ]) {
    testWidgets('Mac shell/details/queue keep layout at $size', (tester) async {
      final fixture = (await tester.runAsync(() async {
        final fixture = await TestLibrary.create();
        await fixture.controller.remember(firstTrack);
        await fixture.controller.remember(secondTrack);
        await fixture.controller.playCollection([
          firstTrack.id,
          secondTrack.id,
        ]);
        await fixture.controller.toggle();
        // Lyrics read from disk in another isolate; wait for fixture I/O before
        // asking pumpAndSettle to settle the newly visible loading indicator.
        for (var i = 0; fixture.controller.lyricLoading && i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(fixture.controller.lyricLoading, isFalse);
        return fixture;
      }))!;
      fixture.controller.history.add(secondTrack.id);
      final router = createWorkspaceRouter();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('mac-preview-boundary'),
          child: ProviderScope(
            overrides: [
              libraryProvider.overrideWith((_) => fixture.controller),
            ],
            child: TingyuApp(router: router),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(windows ? WindowsWorkspace : MacWorkspace),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('返回来源')), findsNothing);
      expect(find.text('主页'), findsNothing);
      expect(find.byKey(const ValueKey('mac-recent-grid')), findsOneWidget);
      await screenshot(tester, '${size.width.toInt()}-recent');
      expect(find.byKey(const ValueKey('mac-local-recent')), findsNothing);
      final recentCard = find.byKey(ValueKey('mac-recent-${firstTrack.id}'));
      expect(recentCard, findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(recentCard);
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          if (!fixture.controller.opening && !fixture.controller.lyricLoading) {
            break;
          }
        }
      });
      await tester.pumpAndSettle();
      expect(fixture.controller.current?.id, firstTrack.id);
      await tester.tap(find.byKey(const ValueKey('mac-toggle-playback')));
      await tester.pumpAndSettle();

      expect(find.text('我的歌单'), findsOneWidget);
      expect(find.byKey(const ValueKey('新建歌单')), findsOneWidget);
      expect(find.byType(TrackRow), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mac-nav-recent')));
      await tester.pumpAndSettle();
      expect(find.text('最近播放'), findsNWidgets(2));
      expect(find.byType(TrackRow), findsNothing);
      expect(find.byType(CollectionToolbar), findsNothing);
      expect(find.byKey(const ValueKey('返回来源')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mac-open-details')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('返回来源')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mac-recent-grid')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mac-nav-songs')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('返回来源')), findsNothing);
      final songNav = find.byKey(const ValueKey('mac-nav-songs'));
      final selectedNav = tester.widget<Pressable>(songNav);
      expect(selectedNav.selected, isTrue);
      final restingFill = tester
          .widget<AnimatedContainer>(
            find
                .descendant(
                  of: songNav,
                  matching: find.byType(AnimatedContainer),
                )
                .first,
          )
          .decoration;
      final pointer = await tester.startGesture(tester.getCenter(songNav));
      await tester.pump(TingyuTokens.pressDuration);
      final scales = tester.widgetList<AnimatedScale>(
        find.descendant(of: songNav, matching: find.byType(AnimatedScale)),
      );
      expect(scales.single.scale, 1);
      final pressedFill = tester
          .widget<AnimatedContainer>(
            find
                .descendant(
                  of: songNav,
                  matching: find.byType(AnimatedContainer),
                )
                .first,
          )
          .decoration;
      expect(pressedFill, isNot(restingFill));
      await pointer.up();
      await tester.pumpAndSettle();
      await screenshot(tester, '${size.width.toInt()}-home');
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(
        find.byKey(const ValueKey('mac-main-content')),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('mac-playback-bar'))).height,
        80,
      );
      final bar = tester.element(
        find.byKey(const ValueKey('mac-playback-bar')),
      );
      await tester.tap(find.byKey(const ValueKey('待播清单')));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('mac-main-content'))),
        rect,
      );
      expect(find.text('队列 · 2 首'), findsOneWidget);
      await screenshot(tester, '${size.width.toInt()}-queue');
      await tester.tap(find.byKey(ValueKey('队列选项 ${secondTrack.id}')));
      await tester.pumpAndSettle();
      expect(find.byType(SimpleDialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byKey(const ValueKey('从队列移除')), findsOneWidget);
      await screenshot(tester, '${size.width.toInt()}-queue-actions');
      await tester.tap(find.byKey(ValueKey('队列选项 ${secondTrack.id}')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('关闭辅助面板')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mac-open-details')));
      await tester.pumpAndSettle();
      expect(find.byType(MacSongDetails), findsOneWidget);
      expect(find.byKey(const ValueKey('mac-lyrics-empty')), findsOneWidget);
      await screenshot(tester, '${size.width.toInt()}-details');
      await tester.runAsync(
        () => fixture.controller.setLyrics(
          '[00:00.00]第一行歌词\n[00:03.00]第二行歌词\n[00:06.00]第三行歌词',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LyricPanel), findsOneWidget);
      await screenshot(tester, '${size.width.toInt()}-lyrics');
      expect(
        tester.element(find.byKey(const ValueKey('mac-playback-bar'))),
        same(bar),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('返回来源')));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('mac-main-content'))),
        rect,
      );
      for (final mode in ['repeat', 'shuffle', 'once', 'order']) {
        await tester.tap(find.byKey(const ValueKey('mac-cycle-mode')));
        await tester.pumpAndSettle();
        expect(fixture.controller.mode, mode);
        expect(
          tester.element(find.byKey(const ValueKey('mac-playback-bar'))),
          same(bar),
        );
      }
      final seek = find.descendant(
        of: find.byKey(const ValueKey('mac-playback-bar')),
        matching: find.byType(Slider),
      );
      await tester.tapAt(tester.getCenter(seek) + const Offset(12, 0));
      await tester.pumpAndSettle();
      expect(fixture.controller.position, greaterThan(Duration.zero));
      await tester.tap(find.byKey(const ValueKey('播放音量')));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerVolumePanel), findsOneWidget);
      expect(find.text('播放音量'), findsNothing);
      await screenshot(tester, '${size.width.toInt()}-volume');
      await tester.tap(find.byKey(const ValueKey('关闭辅助面板')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('播放选项')));
      await tester.pumpAndSettle();
      await screenshot(tester, '${size.width.toInt()}-options');
      await tester.enterText(
        find.byKey(const ValueKey('mac-timer-minutes')),
        '45',
      );
      await tester.pump();
      expect(fixture.controller.sleepTimer.active, isFalse);
      await tester.tap(find.byKey(const ValueKey('关闭辅助面板')));
      await tester.pumpAndSettle();
      expect(fixture.controller.sleepTimer.active, isTrue);
      await tester.tap(find.byKey(const ValueKey('mac-nav-downloads')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('downloads-tab-tasks')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('搜索本地歌曲')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('downloads-search')),
        '保留查询',
      );
      await tester.tap(find.byKey(const ValueKey('mac-nav-songs')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mac-local-songs')));
      await tester.enterText(
        find.byKey(const ValueKey('mac-local-songs')),
        '第一首',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(fixture.controller.playing, isFalse);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('mac-nav-downloads')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('downloads-search')))
            .controller!
            .text,
        '保留查询',
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('账号与收藏夹')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AccountPanel), findsOneWidget);
      expect(find.byKey(const ValueKey('mac-login-qr')), findsOneWidget);
      expect(find.text('登录哔哩哔哩'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('mac-account-task'))).width,
        420,
      );
      expect(find.text('刷新二维码'), findsNothing);
      await screenshot(tester, '${size.width.toInt()}-account');
      await tester.tap(find.byKey(const ValueKey('关闭账号窗口')));
      await tester.pumpAndSettle();
      expect(find.byType(AccountPanel), findsNothing);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mac-settings')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-account')), findsNothing);
      expect(find.text('玻璃透明度'), findsNothing);
      expect(find.text('定时关闭'), findsNothing);
      final settingsRect = tester.getRect(
        find.byKey(const ValueKey('mac-settings')),
      );
      await tester.tap(find.byKey(const ValueKey('mac-settings-playback')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mac-quality-standard')));
      await tester.pumpAndSettle();
      expect(fixture.controller.standard, isTrue);
      await tester.tap(find.byKey(const ValueKey('mac-speed-1.5')));
      await tester.pumpAndSettle();
      expect(fixture.controller.speed, 1.5);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(
        tester.getRect(find.byKey(const ValueKey('mac-settings'))),
        settingsRect,
      );
      await screenshot(tester, '${size.width.toInt()}-settings-playback');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await tester.runAsync(() => fixture.close(disposeController: false));
    });
  }
  testWidgets('Storage totals fit inside Mac ring with large text', (
    tester,
  ) async {
    for (final total in [456025702, 9999999999999]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: tingyuTheme('bili'),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: Scaffold(
              body: Center(
                child: StorageTotalLabel(total: total, diameter: 156),
              ),
            ),
          ),
        ),
      );
      final label = tester.getRect(
        find.byKey(const ValueKey('storage-total-label')),
      );
      expect(label.width, 62);
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        final rect = tester.getRect(find.byWidget(text));
        expect(rect.left, greaterThanOrEqualTo(label.left - .1));
        expect(rect.right, lessThanOrEqualTo(label.right + .1));
      }
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('Mac action dialog bounds long titles at narrow widths', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: tingyuTheme('bili'),
        home: PressableStyle(
          desktop: true,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showContentActions(
                  context,
                  (ctx) => SimpleDialog(
                    title: const Text('长歌曲标题长歌曲标题长歌曲标题长歌曲标题长歌曲标题', maxLines: 2),
                    children: [labelButton('完成', () => Navigator.pop(ctx))],
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    final content = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(SingleChildScrollView),
    );
    expect(tester.getSize(content).width, lessThanOrEqualTo(420));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
}
