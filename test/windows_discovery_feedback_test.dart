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
  for (final size in [const Size(800, 600), const Size(1280, 800)]) {
    testWidgets('Windows feedback and clear preserve library at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = (await tester.runAsync(TestLibrary.create))!;
      final router = createRouter(windows: true);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        await tester.runAsync(() => f.close(disposeController: false));
      });
      var calls = 0;
      f.api.searchAnswer = (query, page) async {
        calls++;
        return List.generate(
          60,
          (i) => Track(
            bvid: 'BVfeedback$i',
            cid: i,
            title: '推荐音乐 $i',
            artist: '创作者 $i',
            cover: '',
            duration: 180,
          ),
        );
      };
      await tester.runAsync(() async {
        await f.controller.setLiked(firstTrack, true);
        await f.controller.play(firstTrack);
        await f.controller.toggle();
      });
      final likes = Set<String>.of(f.controller.likes);
      final history = List<String>.of(f.controller.history);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryProvider.overrideWith((_) => f.controller)],
          child: TingyuApp(router: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mac-nav-search')));
      await tester.pumpAndSettle();
      final beforeDrag = calls;
      final tops = ['全部', '轻音乐', '翻唱', '现场', '纯音乐']
          .map(
            (tag) => tester
                .getTopLeft(find.byKey(ValueKey('discovery-tag-$tag')))
                .dy,
          )
          .toSet();
      expect(tops, hasLength(1));
      await tester.drag(
        find.byKey(const PageStorageKey('discovery-tags')),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();
      expect(
        calls,
        beforeDrag,
        reason: 'Horizontal tag scrolling must not load a vertical page',
      );
      await tester.tap(find.byKey(const ValueKey('discovery-tag-纯音乐')));
      await tester.pumpAndSettle();
      expect(f.controller.discovery.tag, '纯音乐');
      final track = f.controller.discovery.tracks.first;
      expect(find.byKey(ValueKey('推荐歌曲操作${track.title}')), findsNothing);
      final card = find.byKey(ValueKey('discovery-play-${track.id}'));
      await tester.tap(card, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(f.controller.current?.id, firstTrack.id);
      expect(f.controller.playing, isFalse);
      Navigator.of(tester.element(find.text('不感兴趣'))).pop();
      await tester.pumpAndSettle();
      Focus.of(
        tester.element(
          find.descendant(of: card, matching: find.byType(Text)).first,
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.text('不感兴趣'), findsOneWidget);
      expect(f.controller.current?.id, firstTrack.id);
      expect(f.controller.playing, isFalse);
      Navigator.of(tester.element(find.text('不感兴趣'))).pop();
      await tester.pumpAndSettle();
      Focus.of(
        tester.element(
          find.descendant(of: card, matching: find.byType(Text)).first,
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(find.text('不感兴趣'), findsOneWidget);
      expect(f.controller.current?.id, firstTrack.id);
      expect(f.controller.playing, isFalse);
      await tester.runAsync(() async {
        await tester.tap(find.text('不感兴趣'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(f.controller.discoveryPreferences.blocked, contains(track.bvid));
      expect(find.byKey(ValueKey('discovery-card-${track.id}')), findsNothing);
      expect(f.controller.likes, likes);
      await tester.runAsync(() async {
        await tester.tap(find.text('撤销不感兴趣'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(f.controller.discoveryPreferences.blocked, isEmpty);
      Navigator.of(tester.element(find.text('不感兴趣'))).pop();
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => f.controller.setDiscoveryBlocked(track.bvid, true),
      );
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mac-settings-playback')));
      await tester.pumpAndSettle();
      final clearEntry = find.text('清除推荐偏好');
      await tester.ensureVisible(clearEntry);
      await tester.pumpAndSettle();
      await tester.tap(clearEntry);
      await tester.pumpAndSettle();
      expect(find.text('清除推荐偏好？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(f.controller.discoveryPreferences.blocked, contains(track.bvid));
      expect(find.byType(MacSettingsPanel), findsOneWidget);
      await tester.tap(clearEntry);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('清除'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('清除推荐偏好？'), findsNothing);
      expect(f.controller.discoveryPreferences.blocked, isEmpty);
      expect(f.controller.discoveryPreferences.exposures, isEmpty);
      expect(f.controller.discoveryPreferences.behavior, isEmpty);
      expect(f.controller.likes, likes);
      expect(f.controller.history, history);
      expect(f.controller.current?.id, firstTrack.id);
      expect(f.controller.playing, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
  for (final windows in [false, true]) {
    testWidgets('desktop queue context preserves playback windows=$windows', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = (await tester.runAsync(TestLibrary.create))!;
      final router = createRouter(windows: windows, macOS: !windows);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        await tester.runAsync(() => f.close(disposeController: false));
      });
      await tester.runAsync(() async {
        await f.controller.play(firstTrack);
        await f.controller.toggle();
        await f.controller.enqueue(secondTrack);
      });
      final queue = List<String>.of(f.controller.queue);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryProvider.overrideWith((_) => f.controller)],
          child: TingyuApp(router: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('待播清单')));
      await tester.pumpAndSettle();
      final row = find.byWidgetPredicate(
        (widget) =>
            widget is Pressable && widget.label == '播放 ${secondTrack.title}',
      );
      await tester.tap(row, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('从队列移除')), findsOneWidget);
      expect(find.byType(SimpleDialog), findsNothing);
      await tester.tap(row, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('从队列移除')), findsOneWidget);
      expect(f.controller.queue, queue);
      expect(f.controller.current?.id, firstTrack.id);
      expect(f.controller.playing, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
