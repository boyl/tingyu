import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tingyu/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'support/fakes.dart';
import 'package:tingyu/models/music.dart';

void main() {
  late TestLibrary fixture;
  setUp(() async {
    fixture = await TestLibrary.create();
  });
  tearDown(() async {
    await fixture.close(disposeController: false);
  });
  testWidgets(
    'record swipe matches previews and original next in repeat and shuffle',
    (tester) async {
      final p = fixture.controller;
      await p.remember(firstTrack);
      await p.remember(secondTrack);
      p.queue.addAll([firstTrack.id, secondTrack.id]);
      await p.play(firstTrack);
      await p.setMode('repeat');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryProvider.overrideWith((_) => p)],
          child: MaterialApp(
            theme: tingyuTheme('bili'),
            home: Scaffold(
              body: SizedBox(height: 300, child: RecordCarousel(p, size: 240)),
            ),
          ),
        ),
      );
      expect(p.adjacentTrack(1)?.id, secondTrack.id);
      await tester.drag(
        find.byKey(const ValueKey('record-carousel')),
        const Offset(-120, 0),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(p.current?.id, secondTrack.id);
      await p.next(-1);
      expect(p.current?.id, firstTrack.id);
      await p.setMode('shuffle');
      final preview = p.adjacentTrack(1)?.id;
      expect(p.adjacentTrack(1)?.id, preview);
      await p.next();
      expect(p.current?.id, preview);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'both adjacent records expose equal small edges at different central sizes',
    (tester) async {
      final p = fixture.controller;
      const third = Track(
        bvid: 'BVedgefixture',
        cid: 303,
        title: '第三首',
        artist: 'UP',
        cover: '',
        duration: 30,
      );
      for (final t in [firstTrack, secondTrack, third]) {
        await p.remember(t);
      }
      p.queue.addAll([firstTrack.id, secondTrack.id, third.id]);
      await p.play(secondTrack);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final size in [100.0, 240.0]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [libraryProvider.overrideWith((ref) => p)],
            child: MaterialApp(
              theme: tingyuTheme('bili'),
              home: Scaffold(body: RecordCarousel(p, size: size)),
            ),
          ),
        );
        final left = tester.getRect(
          find.byWidgetPredicate(
            (w) => w is RecordDisc && w.track.id == firstTrack.id,
          ),
        );
        final right = tester.getRect(
          find.byWidgetPredicate(
            (w) => w is RecordDisc && w.track.id == third.id,
          ),
        );
        expect(left.right, closeTo(size * .1, .01));
        expect(right.left, closeTo(390 - size * .1, .01));
        expect(left.right, greaterThan(0));
        expect(right.left, lessThan(390));
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
