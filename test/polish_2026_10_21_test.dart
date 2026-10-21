import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'support/fakes.dart';

void main() {
  testWidgets(
    'record diameter stays fixed when lyrics arrive and tracks change',
    (tester) async {
      final f = (await tester.runAsync(() => TestLibrary.create()))!;
      addTearDown(() => f.close(disposeController: false));
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p = f.controller;
      p.current = firstTrack;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryProvider.overrideWith((_) => p)],
          child: MaterialApp(
            theme: tingyuTheme('bili'),
            home: const PlayerScreen(),
          ),
        ),
      );
      await tester.pump();
      double diameter() =>
          tester.widget<RecordCarousel>(find.byType(RecordCarousel)).size;
      final initial = diameter();
      p.lyricText = '[00:00.00]这是一句很长很长、需要完整显示的歌词，下面半截也不能被播放器遮挡，这是回归测试';
      p.notifyListeners();
      await tester.pump();
      expect(diameter(), initial);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      final textRect = tester.getRect(find.text(p.lines.first.text));
      final panelRect = tester.getRect(find.byType(LyricPanel));
      expect(textRect.bottom, lessThanOrEqualTo(panelRect.bottom + .1));
      expect(textRect.top, greaterThanOrEqualTo(panelRect.top - .1));
      p.current = secondTrack;
      p.lyricText = '[00:00.00]短句';
      p.notifyListeners();
      await tester.pump();
      expect(diameter(), initial);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('cancel like keeps the menu even for the last liked track', (
    tester,
  ) async {
    final f = (await tester.runAsync(() => TestLibrary.create()))!;
    addTearDown(() => f.close(disposeController: false));
    final p = f.controller;
    await tester.runAsync(() => p.toggleLike(firstTrack));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryProvider.overrideWith((_) => p)],
        child: MaterialApp(
          theme: tingyuTheme('bili'),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: p,
              builder: (context, _) => p.likes.isEmpty
                  ? const SizedBox.shrink()
                  : Builder(
                      builder: (context) => TextButton(
                        onPressed: () =>
                            showTrackActions(context, p, firstTrack, null),
                        child: const Text('open'),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('取消喜欢')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pumpAndSettle();
    expect(p.likes, isEmpty);
    expect(find.text('下一首播放'), findsOneWidget);
    expect(find.byKey(const ValueKey('喜欢')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('撤销'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'batch download reports resolution failure and keeps retry in place',
    (tester) async {
      final f = (await tester.runAsync(() => TestLibrary.create()))!;
      addTearDown(() => f.close(disposeController: false));
      const track = Track(
        bvid: 'BVmissing',
        cid: 0,
        title: '无效曲目',
        artist: '',
        cover: '',
        duration: 0,
      );
      final p = f.controller;
      p.library[track.id] = track;
      f.api.offline = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryProvider.overrideWith((_) => p)],
          child: MaterialApp(
            theme: tingyuTheme('bili'),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showBatchTransfer(
                    context,
                    p,
                    [track.id],
                    () {},
                    download: true,
                  ),
                  child: const Text('batch'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('batch'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('失败 1 首'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.textContaining('已加入下载任务 1'), findsNothing);
      expect(p.downloads.tasks, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
