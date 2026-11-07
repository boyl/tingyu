import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'support/fakes.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_DISCOVERY');
  setUpAll(() async {
    if (!capture) return;
    final bytes = await File(
      '/System/Library/Fonts/STHeiti Light.ttc',
    ).readAsBytes();
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });
  testWidgets(
    'initial discovery uses card placeholders instead of a progress bar',
    (tester) async {
      final f = (await tester.runAsync(TestLibrary.create))!;
      final response = Completer<List<Track>>();
      f.api.searchAnswer = (_, _) => response.future;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => f.close(disposeController: false));
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryProvider.overrideWith((_) => f.controller)],
          child: MaterialApp(
            theme: tingyuTheme('bili'),
            home: Scaffold(
              body: Consumer(
                builder: (_, ref, _) => DiscoveryPagination(
                  controller: ref.watch(libraryProvider).discovery,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SearchDiscovery(ref.watch(libraryProvider)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.byKey(const ValueKey('discovery-placeholder-0')),
        findsOneWidget,
      );
      expect(find.text('暂时没有推荐内容'), findsNothing);
      expect(
        tester
            .widget<Pressable>(find.byKey(const ValueKey('discovery-refresh')))
            .onPressed,
        isNull,
      );
      response.complete(
        List.generate(
          30,
          (i) => Track(
            bvid: 'BVslow$i',
            cid: i,
            title: '歌曲$i',
            artist: 'UP$i',
            cover: '',
            duration: 60,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('discovery-placeholder-0')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('discovery-shelf')), findsOneWidget);
      expect(f.controller.discovery.moreTracks.length, 10);
      expect(find.byKey(const ValueKey('discovery-load-more')), findsNothing);
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scroll.position.jumpTo(scroll.position.maxScrollExtent - 350);
      await tester.pumpAndSettle();
      expect(f.controller.discovery.moreTracks.length, 10);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      final offset = scroll.position.pixels;
      await tester.pumpAndSettle();
      expect(f.controller.discovery.tracks.first.bvid, 'BVslow0');
      expect(f.controller.discovery.moreTracks.length, 20);
      expect(scroll.position.pixels, offset);
      f.api.searchAnswer = (_, _) async => throw const AppFailure('推荐暂时离线');
      scroll.position.jumpTo(scroll.position.maxScrollExtent - 350);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(f.controller.discovery.moreTracks.length, 20);
      expect(find.text('推荐暂时离线'), findsOneWidget);
      expect(
        tester.getRect(find.text('推荐暂时离线')).top,
        greaterThan(tester.getRect(find.text('继续发现')).bottom),
      );

      expect(tester.takeException(), isNull);
    },
  );
  List<Track> tracks(int start, int count) => List.generate(
    count,
    (i) => Track(
      bvid: 'BVauto${start + i}',
      cid: start + i,
      title: '歌曲${start + i}',
      artist: 'UP${start + i}',
      cover: '',
      duration: 60,
    ),
  );

  for (final platform in ['mobile', 'macOS', 'windows']) {
    final desktop = platform != 'mobile';
    testWidgets(
      'real search page auto paginates and stops on failure platform=$platform',
      (tester) async {
        final f = (await tester.runAsync(TestLibrary.create))!;
        final pending = Completer<List<Track>>();
        var calls = 0;
        f.api.searchAnswer = (_, _) {
          calls++;
          return calls == 1 ? Future.value(tracks(0, 16)) : pending.future;
        };
        await f.controller.discovery.ensureLoaded();
        final router = createRouter();
        if (!desktop) router.go('/search');
        tester.view.physicalSize = Size(desktop ? 1024 : 412, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          router.dispose();
          await tester.runAsync(() => f.close(disposeController: false));
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [libraryProvider.overrideWith((_) => f.controller)],
            child: desktop
                ? MaterialApp(
                    theme: tingyuTheme('bili'),
                    home: platform == 'windows'
                        ? const WindowsWorkspace(initialPage: 'search')
                        : const MacWorkspace(initialPage: 'search'),
                  )
                : TingyuApp(router: router),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('discovery-load-more')), findsNothing);
        await tester.drag(
          find.byKey(const ValueKey('discovery-shelf')),
          const Offset(-180, 0),
        );
        await tester.pumpAndSettle();
        expect(calls, 1);
        final viewport = find.byType(DiscoveryPagination).last;
        final scroll = tester.state<ScrollableState>(
          find
              .descendant(of: viewport, matching: find.byType(Scrollable))
              .first,
        );
        scroll.position.jumpTo(
          scroll.position.maxScrollExtent -
              scroll.position.viewportDimension / 2 -
              100,
        );
        await tester.pumpAndSettle();
        await tester.drag(viewport, const Offset(0, -150));
        await tester.pump();
        await tester.pump();
        expect(calls, 2);
        expect(
          find.byKey(const ValueKey('discovery-loading-more')),
          findsOneWidget,
        );
        await tester.drag(viewport, const Offset(0, -100));
        await tester.pump();
        expect(calls, 2);
        pending.completeError(const AppFailure('推荐暂时离线'));
        await tester.pumpAndSettle();
        expect(f.controller.discovery.moreTracks.length, 10);
        await tester.drag(viewport, const Offset(0, -250));
        await tester.pumpAndSettle();
        expect(calls, 2);
        expect(find.text('推荐暂时离线'), findsOneWidget);
        f.api.searchAnswer = (_, _) async {
          calls++;
          return tracks(16, 10);
        };
        final retry = find.byTooltip('重试或关闭提示');
        await tester.ensureVisible(retry);
        await tester.pumpAndSettle();
        final offset = scroll.position.pixels;
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(calls, 3);
        expect(f.controller.discovery.moreTracks.length, 20);
        expect(f.controller.discovery.tracks.first.bvid, 'BVauto0');
        expect(scroll.position.pixels, offset);
        f.api.searchAnswer = (_, _) async {
          calls++;
          return [];
        };
        scroll.position.jumpTo(
          scroll.position.maxScrollExtent -
              scroll.position.viewportDimension / 2 -
              100,
        );
        await tester.pumpAndSettle();
        await tester.drag(viewport, const Offset(0, -150));
        await tester.pumpAndSettle();
        expect(f.controller.discovery.exhausted, isTrue);
        final exhaustedCalls = calls;
        await tester.drag(viewport, const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(calls, exhaustedCalls);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('short discovery page loads on overscroll without a button', (
    tester,
  ) async {
    final f = (await tester.runAsync(TestLibrary.create))!;
    var calls = 0;
    f.api.searchAnswer = (_, _) async {
      calls++;
      return calls <= 2 ? tracks((calls - 1) * 3, 3) : tracks(6, 10);
    };
    await f.controller.discovery.selectTag('纯音乐');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => f.close(disposeController: false));
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryProvider.overrideWith((_) => f.controller)],
        child: MaterialApp(
          theme: tingyuTheme('bili'),
          home: Scaffold(
            body: DiscoveryPagination(
              controller: f.controller.discovery,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SearchDiscovery(f.controller),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(f.controller.discovery.moreTracks, isEmpty);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(calls, 3);
    expect(f.controller.discovery.moreTracks.length, 10);
    expect(tester.takeException(), isNull);
  });

  for (final theme in ['bili', 'sunrise', 'moon', 'night']) {
    for (final width in [320.0, 360.0, 412.0, 1024.0, 1440.0]) {
      testWidgets(
        'discovery $theme width $width keeps search handoff and fits large text',
        (tester) async {
          final f = (await tester.runAsync(TestLibrary.create))!;
          f.api.searchAnswer = (_, page) async => List.generate(
            60,
            (i) => Track(
              bvid: 'BVdiscovery$i',
              cid: 100 + i,
              title: [
                '把晚风留在耳机里',
                '晴天 · 木吉他翻唱',
                '日落之前，再听一遍',
                '雨落琴键｜安静的钢琴时光',
                '城市慢下来 · 爵士片段',
                '和你一起等风来',
              ][i % 6],
              artist: '音乐创作者$i',
              cover: '',
              duration: 60,
            ),
          );
          await f.controller.discovery.ensureLoaded();
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [libraryProvider.overrideWith((_) => f.controller)],
              child: MaterialApp(
                theme: tingyuTheme(theme),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 1000),
                    textScaler: TextScaler.linear(width == 320 ? 1.6 : 1),
                  ),
                  child: Scaffold(
                    body: RepaintBoundary(
                      key: const ValueKey('capture'),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '搜索',
                              style: tingyuTheme(theme).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 24),
                            const TextField(
                              decoration: InputDecoration(
                                hintText: '歌曲、UP 主、BV / AV 号或链接',
                              ),
                            ),
                            const Align(
                              alignment: Alignment.centerRight,
                              child: BilibiliExternalLink(compact: true),
                            ),
                            SearchDiscovery(f.controller),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('为你发现'), findsOneWidget);
          expect(find.text('继续发现'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('discovery-more-BVdiscovery6:106')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('discovery-more-BVdiscovery0:100')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('open-bilibili-external')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          final shelf = tester.getRect(
            find.byKey(const ValueKey('discovery-shelf')),
          );
          final first = tester.getRect(
            find.byKey(const ValueKey('discovery-card-BVdiscovery0:100')),
          );
          final second = tester.getRect(
            find.byKey(const ValueKey('discovery-card-BVdiscovery1:101')),
          );
          expect(first.top, second.top);
          if (width <= 412) {
            final third = tester.getRect(
              find.byKey(const ValueKey('discovery-card-BVdiscovery2:102')),
            );
            expect(second.right, lessThan(shelf.right));
            expect(third.left, lessThan(shelf.right));
            expect(third.right, greaterThan(shelf.right));
          }
          expect(find.byType(LinearProgressIndicator), findsNothing);
          if (width <= 412) {
            await tester.drag(
              find.byKey(const ValueKey('discovery-shelf')),
              const Offset(-200, 0),
            );
            await tester.pumpAndSettle();
          }
          final before = f.controller.discovery.tracks.first.bvid;
          await tester.tap(find.byKey(const ValueKey('discovery-refresh')));
          await tester.pumpAndSettle();
          expect(f.controller.discovery.tracks.first.bvid, isNot(before));
          expect(
            tester
                .getRect(
                  find.byKey(
                    const ValueKey('discovery-card-BVdiscovery16:116'),
                  ),
                )
                .left,
            closeTo(shelf.left, .01),
          );
          await tester.tap(find.byKey(const ValueKey('discovery-tag-纯音乐')));
          await tester.pumpAndSettle();
          expect(f.controller.query, isEmpty);
          expect(f.controller.discovery.tag, '纯音乐');
          expect(tester.takeException(), isNull);
          if (capture && theme == 'bili' && width == 412) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('capture')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory('artifacts/discovery').create(recursive: true);
              await File(
                'artifacts/discovery/phone-widget.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() => f.close(disposeController: false));
        },
      );
    }
  }
}
