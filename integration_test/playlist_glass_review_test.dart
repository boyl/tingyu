import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tingyu/main.dart' as app;
import 'package:tingyu/models/music.dart';
import 'package:tingyu/ui/app.dart';
import '../test/support/export_fixture.dart' show testCover;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native cover directory and unobscured current-track dock preview',
    (tester) async {
      Future<void> settle() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
      }

      Future<void> capture(String name) async {
        await settle();
        final client = HttpClient();
        try {
          final request = await client.postUrl(
            Uri.parse('http://127.0.0.1:47935/capture/$name'),
          );
          final response = await request.close();
          await response.drain<void>();
          expect(response.statusCode, HttpStatus.ok);
        } finally {
          client.close(force: true);
        }
      }

      final startup = app.main();
      await tester.pump();
      await startup;
      await settle();
      final p = ProviderScope.containerOf(
        tester.element(find.byType(app.TingyuApp)),
      ).read(app.libraryProvider);
      await p.setTheme('moon');
      const track = Track(
        bvid: 'review-local-cover',
        cid: 1,
        title: '本地封面验证曲目',
        artist: '验收夹具',
        cover: '',
        duration: 30,
      );
      await p.remember(track);
      await p.downloads.coverFile(track).writeAsBytes(testCover());
      await p.downloads.artworkFile(track);
      p.current = track;
      await p.addPlaylist('有封面的歌单', track: track);
      final covered = p.playlists.last;
      await p.addPlaylist('空歌单');
      final empty = p.playlists.last;
      await p.addPlaylist('适合睡前安静收听的歌单', track: track);
      final long = p.playlists.last;
      final router = GoRouter.of(tester.element(find.byType(AppShell).first));
      await settle();
      final entry = find.byKey(const ValueKey('all-playlists'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await settle();
      final row = find.byKey(ValueKey('playlist-list-${covered.id}'));
      expect(
        find.descendant(of: row, matching: find.byType(Image)),
        findsOneWidget,
      );
      await capture('playlist-directory-verified');
      await tester.tap(row);
      await settle();
      expect(find.byKey(const ValueKey('返回我的歌单')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('返回我的歌单')));
      await settle();
      await tester.binding.handlePopRoute();
      await settle();
      await p.setGlass(automatic: false);
      unawaited(router.push('/settings/glass'));
      await settle();
      await capture('glass-settings-verified');
      final slider = find.byKey(const ValueKey('glass-slider-mini'));
      await tester.ensureVisible(slider);
      await settle();
      final before = tester.getRect(slider);
      final gesture = await tester.startGesture(before.center);
      await gesture.moveBy(const Offset(25, 0));
      await settle();
      final shell = find.byType(AppShell).last;
      final mini = find.descendant(
        of: shell,
        matching: find.byType(MiniPlayer),
      );
      final nav = find.descendant(
        of: shell,
        matching: find.byType(CompactNavigation),
      );
      expect(p.current, isNotNull);
      expect(tester.getSize(mini).height, greaterThan(0));
      expect(tester.getRect(slider), before);
      final control = tester.getRect(
        find.byKey(const ValueKey('glass-control-mini')),
      );
      expect(control.bottom, lessThanOrEqualTo(tester.getRect(mini).top));
      expect(control.bottom, lessThanOrEqualTo(tester.getRect(nav).top));
      await capture('glass-preview-verified');
      await gesture.up();
      await settle();
      router.pop();
      await settle();
      for (final list in [covered, empty, long]) {
        await p.editPlaylist(list, delete: true);
      }
      expect(tester.takeException(), isNull);
    },
  );
}
