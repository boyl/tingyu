import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/models/music.dart';
import 'support/fakes.dart';

void main() => batchRemovalTests();

void batchRemovalTests({bool includeMac = true, bool nativeSize = false}) {
  for (final mac in [false, if (includeMac) true]) {
    testWidgets(
      '${mac ? "Mac" : "Android"} direct batch removal scopes and cancellation',
      (tester) async {
        final f = (await tester.runAsync(TestLibrary.create))!;
        final p = f.controller;
        await tester.runAsync(() async {
          await p.setLiked(firstTrack, true);
          await p.setLiked(secondTrack, true);
          await p.addPlaylist('保留', track: firstTrack);
        });
        f.downloads.tasks.addAll([
          DownloadTask(firstTrack, status: DownloadStatus.completed),
          DownloadTask(secondTrack, status: DownloadStatus.completed),
        ]);
        final router = createRouter(macOS: mac);
        if (!nativeSize) {
          tester.view.physicalSize = mac
              ? const Size(1024, 768)
              : const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
        }
        await tester.pumpWidget(
          ProviderScope(
            overrides: [libraryProvider.overrideWith((_) => p)],
            child: TingyuApp(router: router),
          ),
        );
        Future<void> settle() async {
          for (var i = 0; i < 8; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
        }

        Future<void> tap(String key) async {
          final finder = find.byKey(ValueKey(key));
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await settle();
        }

        await settle();
        await tap('批量选择');
        await tap('select-${firstTrack.id}');
        await tap('批量删除歌曲');
        await tap('取消');
        expect(p.library.length, 2);
        await tap('退出多选');
        if (mac) {
          await tap('mac-nav-likes');
        } else {
          router.go('/likes');
          await settle();
        }
        await tap('批量选择');
        await tap('全选');
        await tap('批量取消喜欢');
        await tap('确认');
        expect(p.likes, isEmpty);
        expect(p.library.length, 2);
        expect(p.playlists.single.trackIds, [firstTrack.id]);
        if (mac) {
          await tap('mac-nav-downloads');
        } else {
          router.go('/downloads');
          await settle();
        }
        await tap('批量选择');
        await tap('select-${firstTrack.id}');
        await tap('批量移除下载');
        await tap('取消');
        expect(f.downloads.completedTasks.length, 2);
        await tap('批量移除下载');
        await tap('确认');
        expect(f.downloads.completedTasks.single.track.id, secondTrack.id);
        expect(p.library.length, 2);
        expect(p.playlists.single.trackIds, [firstTrack.id]);
        if (mac) {
          await tap('mac-nav-songs');
        } else {
          router.go('/');
          await settle();
        }
        await tap('批量选择');
        await tap('select-${firstTrack.id}');
        await tap('批量删除歌曲');
        await tap('确认');
        expect(p.library.keys, [secondTrack.id]);
        expect(p.playlists.single.trackIds, isEmpty);
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        await tester.runAsync(() => f.close(disposeController: false));
      },
    );
  }
}
