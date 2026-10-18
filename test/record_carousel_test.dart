import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tingyu/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'support/fakes.dart';

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
}
