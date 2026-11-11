import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'support/fakes.dart';

void main() {
  testWidgets(
    'long press gives one haptic, suppresses tap and guards pending actions',
    (tester) async {
      var taps = 0, holds = 0, haptics = 0;
      final pending = Completer<void>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics++;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: tingyuTheme('bili'),
          home: Scaffold(
            body: Pressable(
              onPressed: () {
                taps++;
              },
              onLongPress: () {
                holds++;
                return pending.future;
              },
              child: const Text('target'),
            ),
          ),
        ),
      );
      await tester.longPress(find.text('target'));
      await tester.pump();
      expect(holds, 1);
      expect(haptics, 1);
      expect(taps, 0);
      await tester.longPress(find.text('target'));
      expect(holds, 1);
      pending.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.text('target'));
      expect(taps, 1);
    },
  );

  testWidgets('desktop secondary and keyboard menu never activate playback', (
    tester,
  ) async {
    var taps = 0, menus = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        theme: tingyuTheme('bili').copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Pressable(
            onPressed: () {
              taps++;
            },
            onSecondaryPressed: () {
              menus++;
              return pending.future;
            },
            child: const Text('menu target'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('menu target'), buttons: kSecondaryMouseButton);
    await tester.pump();
    await tester.tap(find.text('menu target'), buttons: kSecondaryMouseButton);
    expect(menus, 1);
    expect(taps, 0);
    pending.complete();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(menus, 2);
    expect(taps, 0);
  });

  for (final direction in [Axis.horizontal, Axis.vertical]) {
    testWidgets('$direction scroll cancels long press and playback', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: tingyuTheme('bili'),
          home: Scaffold(
            body: SingleChildScrollView(
              scrollDirection: direction,
              child: SizedBox(
                width: direction == Axis.horizontal ? 1800 : 300,
                height: direction == Axis.vertical ? 1800 : 200,
                child: Pressable(
                  onPressed: () {
                    calls++;
                  },
                  onLongPress: () {
                    calls++;
                  },
                  child: const Text('scroll target'),
                ),
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(const Offset(100, 100));
      await gesture.moveBy(
        direction == Axis.horizontal
            ? const Offset(-70, 0)
            : const Offset(0, -70),
      );
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, 0);
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    for (final discovery in [false, true]) {
      testWidgets(
        'shared row long press uses existing menu discovery=$discovery $platform',
        (tester) async {
          final f = (await tester.runAsync(TestLibrary.create))!;
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            await tester.runAsync(() => f.close(disposeController: false));
          });
          await tester.pumpWidget(
            ProviderScope(
              overrides: [libraryProvider.overrideWith((_) => f.controller)],
              child: MaterialApp(
                theme: tingyuTheme('bili').copyWith(platform: platform),
                home: Scaffold(
                  body: TrackRow(firstTrack, discovery: discovery),
                ),
              ),
            ),
          );
          final row = find.byKey(ValueKey('play-${firstTrack.id}'));
          if (platform == TargetPlatform.android) {
            await tester.longPress(row);
          } else {
            await tester.tap(row, buttons: kSecondaryMouseButton);
          }
          await tester.pumpAndSettle();
          expect(f.controller.current, isNull);
          expect(find.text('下一首播放'), findsOneWidget);
          expect(find.text('不感兴趣'), discovery ? findsOneWidget : findsNothing);
          Navigator.of(tester.element(find.text('下一首播放'))).pop();
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey('更多 ${firstTrack.title}')));
          await tester.pumpAndSettle();
          expect(find.text('下一首播放'), findsOneWidget);
          Navigator.of(tester.element(find.text('下一首播放'))).pop();
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            await tester.tap(row);
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await tester.pumpAndSettle();
          expect(f.controller.current?.bvid, firstTrack.bvid);
        },
      );
    }

    for (final source in ['downloads', 'queue', 'history']) {
      testWidgets(
        '$source context gesture opens menu without playback $platform',
        (tester) async {
          final f = (await tester.runAsync(TestLibrary.create))!;
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            await tester.runAsync(() => f.close(disposeController: false));
          });
          f.controller.library[firstTrack.id] = firstTrack;
          f.controller.library[secondTrack.id] = secondTrack;
          f.controller.queue.addAll([firstTrack.id, secondTrack.id]);
          f.controller.history.add(firstTrack.id);
          f.downloads.tasks.add(
            DownloadTask(firstTrack, status: DownloadStatus.completed),
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: [libraryProvider.overrideWith((_) => f.controller)],
              child: MaterialApp(
                theme: tingyuTheme('bili').copyWith(platform: platform),
                home: Scaffold(
                  body: source == 'downloads'
                      ? DownloadsPanel(f.controller)
                      : source == 'queue'
                      ? const QueuePanel()
                      : SingleChildScrollView(
                          child: HomeShelves(
                            f.controller,
                            onCreate: () async {},
                          ),
                        ),
                ),
              ),
            ),
          );
          final key = source == 'downloads'
              ? 'play-downloaded-${firstTrack.id}'
              : source == 'queue'
              ? 'queue-track-${firstTrack.id}'
              : 'continue-${firstTrack.id}';
          if (platform == TargetPlatform.android) {
            await tester.longPress(find.byKey(ValueKey(key)));
          } else {
            await tester.tap(
              find.byKey(ValueKey(key)),
              buttons: kSecondaryMouseButton,
            );
          }
          await tester.pumpAndSettle();
          final item = find.text(
            source == 'downloads'
                ? '导出歌曲'
                : source == 'queue'
                ? '移至下一首'
                : '下一首播放',
          );
          expect(item, findsOneWidget);
          expect(find.text('不感兴趣'), findsNothing);
          expect(f.controller.current, isNull);
          Navigator.of(tester.element(item)).pop();
          await tester.pumpAndSettle();
          if (source == 'queue') {
            final handle = find.byKey(ValueKey('queue-drag-${firstTrack.id}'));
            await tester.timedDrag(
              handle,
              const Offset(0, 144),
              const Duration(seconds: 1),
            );
            await tester.pumpAndSettle();
            expect(f.controller.queue, [secondTrack.id, firstTrack.id]);
            expect(find.text('移至下一首'), findsNothing);
          }
        },
      );
    }
  }
  testWidgets('selection rows preserve selection without action menu', (
    tester,
  ) async {
    final f = (await tester.runAsync(TestLibrary.create))!;
    var selections = 0;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => f.close(disposeController: false));
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryProvider.overrideWith((_) => f.controller)],
        child: MaterialApp(
          theme: tingyuTheme('bili'),
          home: Scaffold(
            body: TrackRow(
              firstTrack,
              selecting: true,
              onSelect: () {
                selections++;
              },
            ),
          ),
        ),
      ),
    );
    final row = find.byKey(ValueKey('select-${firstTrack.id}'));
    expect(tester.widget<Pressable>(row).onLongPress, isNull);
    await tester.tap(row);
    expect(selections, 1);
    expect(find.text('下一首播放'), findsNothing);
    expect(f.controller.current, isNull);
  });
}
