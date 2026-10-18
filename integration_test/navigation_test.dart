import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tingyu/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android tabs preserve input, dismiss keyboard and survive repeated switching',
    (tester) async {
      await app.main();
      await tester.pumpAndSettle();
      expect(find.text('音乐库'), findsWidgets);
      expect(tester.getTopLeft(find.text('随心听').first).dy, lessThan(80));

      final controller = ProviderScope.containerOf(
        tester.element(find.byType(app.TingyuApp)),
      ).read(app.libraryProvider);
      // Deterministic navigation acceptance: no live API or account dependency.
      controller.api.http.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                error: 'Acceptance offline fixture',
              ),
            );
          },
        ),
      );
      for (var i = 0; i < 40; i++) {
        final track = Track(
          bvid: 'acceptance-$i',
          cid: i + 1,
          title: '滚动验收 $i',
          artist: '本地测试',
          cover: '',
          duration: 30,
        );
        controller.library[track.id] = track;
      }
      controller.clearError();
      await tester.pumpAndSettle();
      final libraryScroll = find.byType(CustomScrollView).first;
      await tester.drag(libraryScroll, const Offset(0, -500));
      await tester.pumpAndSettle();
      final scrollState = tester.state<ScrollableState>(
        find
            .descendant(of: libraryScroll, matching: find.byType(Scrollable))
            .first,
      );
      final offset = scrollState.position.pixels;
      expect(offset, greaterThan(0));

      await tester.tap(find.byKey(const ValueKey('tab-search')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '验收保留输入');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('tab-downloads')));
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<EditableText>()),
      );
      for (var i = 0; i < 5; i++) {
        for (final tab in ['likes', 'library', 'downloads', 'search']) {
          final target = find.byKey(ValueKey('tab-$tab'));
          expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
          await tester.tap(target);
          await tester.pump(const Duration(milliseconds: 200));
          expect(tester.takeException(), isNull);
        }
      }
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '验收保留输入',
      );
      for (final theme in ['bili', 'sunrise', 'moon', 'night']) {
        await controller.setTheme(theme);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await binding.convertFlutterSurfaceToImage();
      for (final theme in ['night', 'moon', 'bili', 'sunrise']) {
        await controller.setTheme(theme);
        await tester.pumpAndSettle();
        for (final tab in ['likes', 'library', 'downloads', 'search']) {
          await tester.tap(find.byKey(ValueKey('tab-$tab')));
          for (final milliseconds in [0, 16, 100, 200]) {
            await tester.pump(Duration(milliseconds: milliseconds));
            final nav = find.byType(CompactNavigation);
            expect(
              Theme.of(
                tester.element(nav),
              ).extension<TingyuTokens>()!.background,
              tingyuTheme(theme).extension<TingyuTokens>()!.background,
            );
            expect(
              find.descendant(
                of: nav,
                matching: find.byType(AnimatedContainer),
              ),
              findsNothing,
            );
          }
          await binding.takeScreenshot('theme-first-visit-$theme-$tab');
        }
      }
      await controller.setTheme('sunrise');
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.byKey(const ValueKey('tab-library')));
      await tester.pumpAndSettle();
      expect(scrollState.position.pixels, closeTo(offset, 1));
      // Real local WAV decoding verifies that returning never pauses playback.
      final audioDirectory = await Directory.systemTemp.createTemp(
        'tingyu-back-test-',
      );
      final audioFile = File('${audioDirectory.path}/silence.wav');
      final pcmBytes = 44100 * 30 * 2;
      final wav = Uint8List(44 + pcmBytes), header = ByteData(44);
      header.setUint32(4, 36 + pcmBytes, Endian.little);
      header.setUint32(16, 16, Endian.little);
      header.setUint16(20, 1, Endian.little);
      header.setUint16(22, 1, Endian.little);
      header.setUint32(24, 44100, Endian.little);
      header.setUint32(28, 88200, Endian.little);
      header.setUint16(32, 2, Endian.little);
      header.setUint16(34, 16, Endian.little);
      header.setUint32(40, pcmBytes, Endian.little);
      wav.setRange(0, 44, header.buffer.asUint8List());
      for (final chunk in [
        (0, 'RIFF'),
        (8, 'WAVE'),
        (12, 'fmt '),
        (36, 'data'),
      ]) {
        wav.setRange(chunk.$1, chunk.$1 + 4, chunk.$2.codeUnits);
      }
      await audioFile.writeAsBytes(wav);
      controller.current = controller.library.values.firstWhere(
        (t) => t.bvid.startsWith('acceptance-'),
      );
      await controller.playback.open(controller.current!, file: audioFile.path);
      unawaited(controller.playback.play());
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.playing, isTrue);
      await tester.tap(find.byKey(const ValueKey('展开播放器')));
      await tester.pumpAndSettle();
      final playerScroll = find.byKey(const ValueKey('player-content'));
      await tester.drag(playerScroll, const Offset(0, -650));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('返回')).hitTestable(), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('返回'))).dy,
        lessThan(80),
      );
      await tester.tap(find.byKey(const ValueKey('返回')));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);
      expect(scrollState.position.pixels, closeTo(offset, 1));
      expect(controller.playing, isTrue);
      final lastPosition = controller.position;
      await tester.tap(find.byKey(const ValueKey('展开播放器')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);
      expect(controller.playing, isTrue);
      expect(controller.position, greaterThanOrEqualTo(lastPosition));
      await controller.playback.pause();
      await controller.playback.player.stop();
      controller.current = null;
      controller.clearError();
      await audioDirectory.delete(recursive: true);
      controller.library.removeWhere(
        (_, track) => track.bvid.startsWith('acceptance-'),
      );
      await controller.save();
      expect(find.text('音乐库'), findsWidgets);
      controller.clearError();
      scrollState.position.jumpTo(0);
      for (final theme in ['bili', 'sunrise', 'moon', 'night']) {
        await controller.setTheme(theme);
        await tester.pumpAndSettle();
        await binding.takeScreenshot('android-$theme-library');
      }
      await controller.setTheme('sunrise');
      // Logged-in layout fixture; never logs into or reads a real account.
      controller.api.http.interceptors.clear();
      controller.api.http.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final data = options.path.contains('created/list-all')
                ? {
                    'list': [
                      for (var i = 1; i <= 25; i++)
                        {
                          'id': i,
                          'title': '收藏夹 $i 这是用于验证长标题换行和选择操作的本地示例',
                          'media_count': 1,
                        },
                    ],
                  }
                : options.path.contains('resource/list')
                ? {
                    'has_more': false,
                    'medias': [
                      {
                        'bvid': 'BV1xx411c7mD',
                        'title': '本地导入验收示例',
                        'upper': {'name': '本地测试'},
                        'cover': '',
                        'duration': 30,
                      },
                    ],
                  }
                : {'mid': 1, 'uname': '本地验收账号'};
            handler.resolve(
              Response(
                requestOptions: options,
                data: {'code': 0, 'data': data},
                statusCode: 200,
              ),
            );
          },
        ),
      );
      controller.profile = {'mid': 1, 'uname': '本地验收账号'};
      await tester.tap(find.byKey(const ValueKey('打开设置')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-account')));
      await tester.pumpAndSettle();
      expect(find.text('请先选择收藏夹'), findsOneWidget);
      final accountScroll = find
          .descendant(
            of: find.byKey(const ValueKey('account-content')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('folder-25')),
        300,
        scrollable: accountScroll,
      );
      await tester.tap(find.byKey(const ValueKey('folder-25')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FolderChoice>(find.byType(FolderChoice).last).selected,
        isTrue,
      );
      final importButton = find.text('导入所选收藏夹');
      expect(
        tester.getBottomRight(importButton).dy,
        lessThan(
          tester.view.physicalSize.height / tester.view.devicePixelRatio,
        ),
      );
      await binding.takeScreenshot('android-account-selected');
      final playlistCount = controller.playlists.length;
      await tester.tap(importButton);
      await tester.pumpAndSettle();
      expect(find.text('查看已导入歌单'), findsOneWidget);
      expect(controller.playlists.length, playlistCount + 1);
      final imported = controller.playlists.last;
      expect(imported.trackIds.length, 1);
      await binding.takeScreenshot('android-account-imported');
      await tester.tap(find.text('查看已导入歌单'));
      await tester.pumpAndSettle();
      expect(find.text('本地导入验收示例'), findsOneWidget);
      await controller.editPlaylist(imported, delete: true);
      for (final id in imported.trackIds) {
        controller.library.remove(id);
        await controller.db.deleteTrack(id);
      }
      controller.profile = null;
      await controller.save();
      expect(tester.takeException(), isNull);
    },
  );
}
