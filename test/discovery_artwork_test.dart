import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/controllers/library_controller.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/services/downloads.dart';
import 'package:tingyu/services/storage.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'support/fakes.dart';

class _Images implements HttpClientAdapter {
  _Images(this.bytes);
  final List<int> bytes;
  final ready = Completer<void>();
  final updatedReady = Completer<void>();
  final requests = <String, int>{};
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.update(options.path, (n) => n + 1, ifAbsent: () => 1);
    await ready.future;
    if (options.uri.queryParameters.containsKey('updated')) {
      await updatedReady.future;
    }
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        'content-length': ['${bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Results extends FixtureApi {
  final candidates = List.generate(
    60,
    (i) => Track(
      bvid: 'BVcover$i',
      cid: 0,
      title: '推荐音乐 $i',
      artist: '创作者 $i',
      cover: 'https://images.test/$i.png',
      duration: 60,
    ),
  );
  @override
  Future<List<Track>> search(String text, {int page = 1}) async => candidates;
  @override
  Future<List<Track>> details(String bvid) async {
    final t = candidates.firstWhere((t) => t.bvid == bvid);
    return [
      Track(
        bvid: t.bvid,
        cid: 101,
        title: t.title,
        artist: t.artist,
        cover: t.cover,
        duration: t.duration,
      ),
    ];
  }
}

void main() {
  for (final platform in ['mobile', 'macOS', 'windows']) {
    for (final section in ['featured', 'more']) {
      testWidgets('$platform $section retains loaded artwork while playing', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final api = _Results();
          final directory = await Directory.systemTemp.createTemp(
            'tingyu-image-',
          );
          final images = _Images(await File('assets/tray.png').readAsBytes());
          final db = AppDatabase(NativeDatabase.memory());
          final playback = FakePlayback();
          final downloads = DownloadManager(
            api,
            db,
            directory,
            dio: Dio()..httpClientAdapter = images,
            lyricsClient: FixtureLyrics(),
          );
          final controller = LibraryController(
            api,
            db,
            downloads,
            playback,
            lyricsClient: FixtureLyrics(),
          );
          await controller.initialize();
          final selected = api.candidates[section == 'featured' ? 0 : 6];
          tester.view.physicalSize = const Size(1280, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(() async {
            if (!images.ready.isCompleted) {
              images.ready.complete();
            }
            if (!images.updatedReady.isCompleted) {
              images.updatedReady.complete();
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.runAsync(() async {
              await downloads.prepareForExit();
              downloads.dispose();
              await downloads.covers.close();
              await playback.close();
              await db.close();
              await directory.delete(recursive: true);
            });
          });
          await tester.pumpWidget(
            ProviderScope(
              overrides: [libraryProvider.overrideWith((_) => controller)],
              child: MaterialApp(
                theme: tingyuTheme('bili'),
                home: switch (platform) {
                  'windows' => const WindowsWorkspace(initialPage: 'search'),
                  'macOS' => const MacWorkspace(initialPage: 'search'),
                  _ => Scaffold(
                    body: SingleChildScrollView(
                      child: SearchDiscovery(controller),
                    ),
                  ),
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          Finder artwork() => find.descendant(
            of: find.byType(SearchDiscovery),
            matching: find.byWidgetPredicate(
              (w) => w is Artwork && w.track.bvid == selected.bvid,
            ),
          );
          expect(
            find.descendant(of: artwork(), matching: find.byType(Image)),
            findsNothing,
          );
          images.ready.complete();
          for (var i = 0; i < 100; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await tester.pump();
            final rendered = find.descendant(
              of: artwork(),
              matching: find.byType(RawImage),
            );
            if (rendered.evaluate().isNotEmpty &&
                tester.renderObject<RenderImage>(rendered).image != null) {
              break;
            }
          }
          final initialState = tester.state(artwork());
          final rendered = find.descendant(
            of: artwork(),
            matching: find.byType(RawImage),
          );
          expect(tester.renderObject<RenderImage>(rendered).image, isNotNull);
          final imageState = tester.state(
            find.descendant(of: artwork(), matching: find.byType(Image)),
          );
          final requests = images.requests[selected.cover];
          expect(requests, 1);
          for (var repeat = 0; repeat < 2; repeat++) {
            final button = find
                .byWidgetPredicate(
                  (w) =>
                      w is Pressable &&
                      (w.label?.startsWith('播放') ?? false) &&
                      (w.label?.contains(selected.title) ?? false),
                )
                .first;
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            await tester.tap(button);
            await tester.pump();
            for (var i = 0; i < 100 && controller.opening; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            await tester.pump();
            expect(controller.current?.id, '${selected.bvid}:101');
            expect(tester.state(artwork()), same(initialState));
            expect(
              tester.state(
                find.descendant(of: artwork(), matching: find.byType(Image)),
              ),
              same(imageState),
            );
            expect(
              tester
                  .renderObject<RenderImage>(
                    find.descendant(
                      of: artwork(),
                      matching: find.byType(RawImage),
                    ),
                  )
                  .image,
              isNotNull,
            );
            expect(images.requests[selected.cover], requests);
            expect(tester.takeException(), isNull);
          }
          File shownFile() {
            final image = tester
                .widget<Image>(
                  find.descendant(of: artwork(), matching: find.byType(Image)),
                )
                .image;
            final provider = image is ResizeImage ? image.imageProvider : image;
            return (provider as FileImage).file;
          }

          final originalFile = shownFile().path;
          final updatedUrl = '${selected.cover}?updated=1';
          await controller.toggleLike(
            Track(
              bvid: selected.bvid,
              cid: 101,
              title: selected.title,
              artist: selected.artist,
              cover: updatedUrl,
              duration: 60,
            ),
          );
          await tester.pump();
          expect(controller.likes, contains('${selected.bvid}:101'));
          expect(controller.likes, isNot(contains(selected.id)));
          expect(tester.state(artwork()), same(initialState));
          expect(shownFile().path, originalFile);
          images.updatedReady.complete();
          for (var i = 0; i < 100 && shownFile().path == originalFile; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await tester.pump();
          }
          expect(images.requests[updatedUrl], 1);
          expect(shownFile().path, isNot(originalFile));
          await controller.discovery.nextBatch();
          await tester.pumpAndSettle();
          expect(artwork(), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });
    }
  }
}
